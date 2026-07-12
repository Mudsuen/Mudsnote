import Foundation

struct PendingWrite: Codable, Identifiable, Equatable {
    var id: UUID
    var createdAt: Date
    var targetRelativePath: String
    var markdownBlock: String
    var attachments: [PendingAttachment]
}

struct PendingAttachment: Codable, Equatable {
    var relativePath: String
    var base64Data: String
}

actor PendingWriteQueue {
    private let root: URL
    private let queueURL: URL
    private var items: [PendingWrite] = []

    init(root: URL) {
        self.root = root
        self.queueURL = root.appendingPathComponent(".mudsnote/queue.json")
    }

    func load() throws {
        try withRootAccess {
            guard FileManager.default.fileExists(atPath: queueURL.path) else {
                items = []
                try persistUnlocked(items, to: queueURL)
                return
            }
            items = try loadItemsUnlocked(from: queueURL)
        }
    }

    func pendingCount() -> Int {
        items.count
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

    func replay(_ writer: (PendingWrite) async throws -> Void) async throws {
        for item in items {
            try await writer(item)
            try remove(id: item.id)
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

    private func withRootAccess<T>(_ work: () throws -> T) throws -> T {
        let accessed = root.startAccessingSecurityScopedResource()
        defer {
            if accessed { root.stopAccessingSecurityScopedResource() }
        }
        return try work()
    }
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
