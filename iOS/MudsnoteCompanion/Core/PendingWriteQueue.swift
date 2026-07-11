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
                try persistUnlocked()
                return
            }
            let data = try Data(contentsOf: queueURL)
            items = try JSONDecoder.pendingWrites.decode([PendingWrite].self, from: data)
        }
    }

    func pendingCount() -> Int {
        items.count
    }

    func enqueue(_ item: PendingWrite) throws {
        if !items.contains(where: { $0.id == item.id }) {
            try PendingWriteQueuePolicy.validate(existing: items, appending: item)
            items.append(item)
            try persist()
        }
    }

    func remove(id: UUID) throws {
        items.removeAll { $0.id == id }
        try persist()
    }

    func replay(_ writer: (PendingWrite) async throws -> Void) async throws {
        for item in items {
            try await writer(item)
            try remove(id: item.id)
        }
    }

    private func persist() throws {
        try withRootAccess {
            try persistUnlocked()
        }
    }

    private func persistUnlocked() throws {
        let data = try JSONEncoder.pretty.encode(items)
        try data.write(to: queueURL, options: .atomic)
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
            return "Pending capture limit reached (\(maximum)). Reconnect the folder and retry."
        case .tooLarge:
            return "Pending attachments are full. Reconnect the folder before adding more."
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
