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
    public struct Defaults: Equatable, Sendable {
        public var principles: String
        public var areaTitles: [String]

        public init(principles: String, areaTitles: [String]) {
            self.principles = principles
            self.areaTitles = areaTitles
        }

        public static let standard = Defaults(
            principles: "聚焦核心 · 持续积累 · 保持清晰",
            areaTitles: ["工作", "健康", "关系", "成长"]
        )
    }

    public var seeded: Bool?
    public var title: String?
    public var principles: String
    public var areas: [Area]
    public var cards: [Card] = []
    public var connections: [Connection] = []

    public init(defaults: Defaults = .standard) {
        self.principles = defaults.principles
        self.areas = defaults.areaTitles.map { Area(title: $0) }
    }

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
        let oldURL = old.standardizedFileURL
        let newURL = new.standardizedFileURL
        guard oldURL != newURL else { return }
        if let existingNewIndex = cards.firstIndex(where: { $0.url.standardizedFileURL == newURL }) {
            let duplicateIDs = Set(cards.filter { $0.url.standardizedFileURL == oldURL }.map(\.id))
            guard !duplicateIDs.isEmpty else { return }
            let targetID = cards[existingNewIndex].id
            cards.removeAll { duplicateIDs.contains($0.id) }
            var remappedConnections: [Connection] = []
            for edge in connections {
                let from = duplicateIDs.contains(edge.from) ? targetID : edge.from
                let to = duplicateIDs.contains(edge.to) ? targetID : edge.to
                guard from != to,
                      !remappedConnections.contains(where: {
                          ($0.from == from && $0.to == to) || ($0.from == to && $0.to == from)
                      }) else { continue }
                remappedConnections.append(Connection(from: from, to: to))
            }
            connections = remappedConnections
            return
        }
        for index in cards.indices where cards[index].url.standardizedFileURL == oldURL {
            cards[index].url = newURL
        }
    }
}

extension NoteStore {
    public func loadOverview() throws -> NoteOverview {
        overviewPersistenceLock.lock()
        defer { overviewPersistenceLock.unlock() }
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
