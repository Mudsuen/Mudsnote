import Foundation

public struct NoteOverview: Codable, Equatable, Sendable {
    public struct MapPosition: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var scope: String
        public init(x: Double, y: Double, scope: String) { self.x = x; self.y = y; self.scope = scope }
    }
    public struct Area: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var title: String
        public var parentID: UUID?
        public var details: String?
        public var mapPosition: MapPosition?
        public init(title: String, parentID: UUID? = nil) { id = UUID(); self.title = title; self.parentID = parentID }
    }
    public struct Card: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var url: URL
        public var areaID: UUID?
        public var mapPosition: MapPosition?
        public init(url: URL, areaID: UUID? = nil) { id = UUID(); self.url = url.standardizedFileURL; self.areaID = areaID }
    }
    public struct Connection: Codable, Equatable, Sendable {
        public var from: UUID
        public var to: UUID
        public init(from: UUID, to: UUID) { self.from = from; self.to = to }
    }
    public var seeded: Bool?
    public var title: String?
    public var principles = "AI Native · 长期主义 · 身体优先"
    public var areas = [Area(title: "搞钱"), Area(title: "健康"), Area(title: "关系"), Area(title: "内在世界")]
    public var cards: [Card] = []
    public var connections: [Connection] = []
    public init() {}

    @discardableResult public mutating func add(_ url: URL, areaID: UUID? = nil) -> UUID {
        if let index = cards.firstIndex(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            if let areaID { cards[index].areaID = areaID }
            return cards[index].id
        }
        let card = Card(url: url, areaID: areaID)
        cards.append(card)
        return card.id
    }
    public mutating func connect(_ from: UUID, _ to: UUID) {
        guard from != to, cards.contains(where: { $0.id == from }), cards.contains(where: { $0.id == to }),
              !connections.contains(where: { ($0.from == from && $0.to == to) || ($0.from == to && $0.to == from) }) else { return }
        connections.append(Connection(from: from, to: to))
    }
    public mutating func removeCard(_ id: UUID) {
        cards.removeAll { $0.id == id }
        connections.removeAll { $0.from == id || $0.to == id }
    }
    public mutating func remap(_ old: URL, to new: URL) {
        for index in cards.indices where cards[index].url.standardizedFileURL == old.standardizedFileURL { cards[index].url = new }
    }
}

extension NoteStore {
    public func loadOverview() throws -> NoteOverview {
        let file = appSupportDirectory.appendingPathComponent("Overview-v1.json")
        guard fileManager.fileExists(atPath: file.path) else { return NoteOverview() }
        return try JSONDecoder().decode(NoteOverview.self, from: Data(contentsOf: file))
    }
    public func saveOverview(_ overview: NoteOverview) throws {
        overviewPersistenceLock.lock()
        defer { overviewPersistenceLock.unlock() }
        try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(overview)
        // Older builds ignore new optional metadata when re-encoding. Keep the
        // latest full snapshot independently; never silently replace canonical
        // metadata with it on load, including after malformed writes.
        try data.write(to: appSupportDirectory.appendingPathComponent("Overview-recovery.json"), options: .atomic)
        try data.write(to: appSupportDirectory.appendingPathComponent("Overview-v1.json"), options: .atomic)
    }
}
