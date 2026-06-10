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
            items = try JSONDecoder().decode([PendingWrite].self, from: data)
        }
    }

    func enqueue(_ item: PendingWrite) throws {
        if !items.contains(where: { $0.id == item.id }) {
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

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
