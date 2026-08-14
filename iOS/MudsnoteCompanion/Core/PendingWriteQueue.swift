import Foundation

struct PendingWrite: Codable, Identifiable, Equatable {
    var id: UUID
    var createdAt: Date
    var libraryID: String
    var targetRelativePath: String
    var markdownBlock: String
    var attachments: [PendingAttachment]

    init(
        id: UUID,
        createdAt: Date,
        libraryID: String = "",
        targetRelativePath: String,
        markdownBlock: String,
        attachments: [PendingAttachment]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.libraryID = libraryID
        self.targetRelativePath = targetRelativePath
        self.markdownBlock = markdownBlock
        self.attachments = attachments
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case libraryID
        case targetRelativePath
        case markdownBlock
        case attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        libraryID = try container.decodeIfPresent(String.self, forKey: .libraryID) ?? ""
        targetRelativePath = try container.decode(String.self, forKey: .targetRelativePath)
        markdownBlock = try container.decode(String.self, forKey: .markdownBlock)
        attachments = try container.decode([PendingAttachment].self, forKey: .attachments)
    }
}

struct PendingAttachment: Codable, Equatable {
    var relativePath: String
    var base64Data: String
}

actor PendingWriteQueue {
    private static let maximumQueueFileBytes = 128 * 1_024 * 1_024
    private let root: URL
    private let queueURL: URL
    private let libraryID: String
    private var items: [PendingWrite] = []

    init(root: URL) {
        self.root = root
        self.queueURL = root.appendingPathComponent(".mudsnote/queue.json")
        self.libraryID = LibraryIdentity.identifier(for: root)
    }

    @discardableResult
    func load(now: Date = Date()) throws -> PendingWriteQueueLoadResult {
        try withRootAccess {
            let coordinator = NSFileCoordinator()
            var coordinationError: NSError?
            var operationError: Error?
            var loadedItems: [PendingWrite]?
            var loadResult: PendingWriteQueueLoadResult?

            coordinator.coordinate(
                writingItemAt: queueURL,
                options: .forMerging,
                error: &coordinationError
            ) { coordinatedURL in
                do {
                    guard FileManager.default.fileExists(atPath: coordinatedURL.path) else {
                        let emptyItems: [PendingWrite] = []
                        try persistUnlocked(emptyItems, to: coordinatedURL)
                        loadedItems = emptyItems
                        loadResult = .ready
                        return
                    }

                    do {
                        let byteCount = try coordinatedURL.resourceValues(
                            forKeys: [.fileSizeKey]
                        ).fileSize ?? 0
                        guard byteCount <= Self.maximumQueueFileBytes else {
                            throw PendingWriteQueueLoadError.fileTooLarge
                        }
                        var persisted = try loadItemsUnlocked(from: coordinatedURL)
                        let needsMigration = persisted.contains { $0.libraryID.isEmpty }
                        if needsMigration {
                            for index in persisted.indices where persisted[index].libraryID.isEmpty {
                                persisted[index].libraryID = libraryID
                            }
                            try persistUnlocked(persisted, to: coordinatedURL)
                        }
                        loadedItems = persisted
                        loadResult = .ready
                    } catch {
                        guard error is DecodingError
                                || (error as? PendingWriteQueueLoadError) == .fileTooLarge
                        else {
                            throw error
                        }

                        let quarantineURL = uniqueQuarantineURL(now: now)
                        try FileManager.default.moveItem(at: coordinatedURL, to: quarantineURL)
                        do {
                            let emptyItems: [PendingWrite] = []
                            try persistUnlocked(emptyItems, to: coordinatedURL)
                            loadedItems = emptyItems
                            loadResult = .quarantined(filename: quarantineURL.lastPathComponent)
                        } catch {
                            let replacementError = error
                            do {
                                try FileManager.default.moveItem(
                                    at: quarantineURL,
                                    to: coordinatedURL
                                )
                            } catch {
                                throw PendingWriteQueueLoadError.recoveryFailed(
                                    replacement: replacementError.localizedDescription,
                                    rollback: error.localizedDescription
                                )
                            }
                            throw replacementError
                        }
                    }
                } catch {
                    operationError = error
                }
            }

            if let coordinationError { throw coordinationError }
            if let operationError { throw operationError }
            guard let loadedItems, let loadResult else {
                throw PendingWriteQueueLoadError.missingResult
            }
            items = loadedItems
            return loadResult
        }
    }

    func pendingCount() -> Int {
        items.count
    }

    func allItems() -> [PendingWrite] {
        items
    }

    func preservedFailureFilenames() throws -> [String] {
        try withRootAccess {
            let directory = queueURL.deletingLastPathComponent()
            return try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            .map(\.lastPathComponent)
            .filter { $0.hasPrefix("queue-failed-") && $0.hasSuffix(".json") }
            .sorted()
        }
    }

    func enqueue(_ item: PendingWrite) throws {
        try mutatePersistedItems { persisted in
            guard !persisted.contains(where: { $0.id == item.id }) else { return }
            try PendingWriteQueuePolicy.validate(existing: persisted, appending: item)
            persisted.append(item)
        }
    }

    func remove(id: UUID) throws {
        try mutatePersistedItems { persisted in
            persisted.removeAll { $0.id == id }
        }
    }

    @discardableResult
    func replay(
        _ writer: (PendingWrite) async throws -> Void
    ) async throws -> PendingWriteReplayResult {
        var result = PendingWriteReplayResult()
        for item in items {
            do {
                try await writer(item)
                result.replayedCount += 1
            } catch {
                guard let validationError = error as? any IrrecoverablePendingWriteError,
                      validationError.shouldPreserveOutsideActiveQueue else {
                    throw error
                }
                let filename = try preserveIrrecoverable(item)
                result.preservedFailureFilenames.append(filename)
            }
            try await removeAfterReplay(id: item.id)
        }
        return result
    }

    private func removeAfterReplay(id: UUID) async throws {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                try remove(id: id)
                return
            } catch {
                lastError = error
                guard attempt < 2 else { break }
                try await Task.sleep(for: .milliseconds(100 * (attempt + 1)))
            }
        }
        if let lastError { throw lastError }
    }

    private func preserveIrrecoverable(_ item: PendingWrite) throws -> String {
        try withRootAccess {
            let directory = queueURL.deletingLastPathComponent()
            let stem = "queue-failed-\(item.id.uuidString.lowercased())"
            var candidate = directory.appendingPathComponent("\(stem).json")
            var suffix = 2

            while FileManager.default.fileExists(atPath: candidate.path) {
                if (try? loadItemsUnlocked(from: candidate)) == [item] {
                    return candidate.lastPathComponent
                }
                candidate = directory.appendingPathComponent("\(stem)-\(suffix).json")
                suffix += 1
            }

            try persistUnlocked([item], to: candidate)
            return candidate.lastPathComponent
        }
    }

    private func mutatePersistedItems(
        _ mutation: (inout [PendingWrite]) throws -> Void
    ) throws {
        try withRootAccess {
            let coordinator = NSFileCoordinator()
            var coordinationError: NSError?
            var operationError: Error?
            var updatedItems: [PendingWrite]?
            coordinator.coordinate(
                writingItemAt: queueURL,
                options: .forMerging,
                error: &coordinationError
            ) { coordinatedURL in
                do {
                    var persisted = try loadItemsUnlocked(from: coordinatedURL)
                    try mutation(&persisted)
                    try persistUnlocked(persisted, to: coordinatedURL)
                    updatedItems = persisted
                } catch {
                    operationError = error
                }
            }

            if let coordinationError { throw coordinationError }
            if let operationError { throw operationError }
            if let updatedItems { items = updatedItems }
        }
    }

    private func loadItemsUnlocked(from url: URL) throws -> [PendingWrite] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder.pendingWrites.decode([PendingWrite].self, from: data)
    }

    private func persistUnlocked(_ items: [PendingWrite], to url: URL) throws {
        let data = try JSONEncoder.pretty.encode(items)
        try data.write(to: url, options: .atomic)
    }

    private func uniqueQuarantineURL(now: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stem = "queue-damaged-\(formatter.string(from: now))"
        var candidate = queueURL.deletingLastPathComponent()
            .appendingPathComponent("\(stem).json")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = queueURL.deletingLastPathComponent()
                .appendingPathComponent("\(stem)-\(suffix).json")
            suffix += 1
        }
        return candidate
    }

    private func withRootAccess<T>(_ work: () throws -> T) throws -> T {
        let accessed = root.startAccessingSecurityScopedResource()
        defer {
            if accessed { root.stopAccessingSecurityScopedResource() }
        }
        return try work()
    }
}

enum PendingWriteQueueLoadResult: Equatable {
    case ready
    case quarantined(filename: String)
}

struct PendingWriteReplayResult: Equatable {
    var replayedCount = 0
    var preservedFailureFilenames: [String] = []
}

protocol IrrecoverablePendingWriteError: Error {
    var shouldPreserveOutsideActiveQueue: Bool { get }
}

private enum PendingWriteQueueLoadError: Error, Equatable {
    case fileTooLarge
    case recoveryFailed(replacement: String, rollback: String)
    case missingResult
}

enum PendingWriteQueuePolicy {
    static let maximumItemCount = 50
    static let maximumEncodedAttachmentBytes = 96 * 1_024 * 1_024

    static func validate(
        existing: [PendingWrite],
        appending item: PendingWrite,
        maximumItems: Int = maximumItemCount,
        maximumEncodedBytes: Int = maximumEncodedAttachmentBytes
    ) throws {
        guard existing.count < maximumItems else {
            throw PendingWriteQueueError.tooManyItems(maximum: maximumItems)
        }
        let encodedBytes = (existing + [item]).reduce(into: 0) { total, pending in
            total += pending.attachments.reduce(into: 0) { $0 += $1.base64Data.utf8.count }
        }
        guard encodedBytes <= maximumEncodedBytes else {
            throw PendingWriteQueueError.tooLarge
        }
    }
}

enum PendingWriteQueueError: LocalizedError, Equatable {
    case tooManyItems(maximum: Int)
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .tooManyItems(let maximum):
            return String(
                format: String(localized: "pending.maximum_count.format"),
                locale: .current,
                maximum
            )
        case .tooLarge:
            return String(localized: "Pending attachments are full. Reconnect the folder before adding more.")
        }
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var pendingWrites: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
