import Foundation
import Testing
@testable import MudsnoteCore

private final class CreationCollisionFileManager: FileManager, @unchecked Sendable {
    var collisionPath: String?
    override func fileExists(atPath path: String) -> Bool {
        if path == collisionPath {
            collisionPath = nil
            // A second writer wins after our name check, before our creation.
            try! Data("# Concurrent writer\n\nKeep this body".utf8).write(to: URL(fileURLWithPath: path))
            return false
        }
        return super.fileExists(atPath: path)
    }
}

struct NoteCreationCollisionTests {
    @Test func creationRetriesWhenAnotherWriterClaimsTheChosenName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "creation-collision-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        let manager = CreationCollisionFileManager()
        let store = NoteStore(defaults: defaults, legacyDefaults: nil, fileManager: manager,
                              appSupportDirectory: root.appendingPathComponent("Support"))
        let notes = root.appendingPathComponent("Notes")
        try manager.createDirectory(at: notes, withIntermediateDirectories: true)
        let occupied = try store.saveNewNote(title: "Collision", body: "Naming probe", in: notes)
        try manager.removeItem(at: occupied)
        manager.collisionPath = occupied.path
        let created = try store.saveNewNote(title: "Collision", body: "Second body", in: notes)
        #expect(created != occupied)
        #expect(try String(contentsOf: occupied, encoding: .utf8) == "# Concurrent writer\n\nKeep this body")
        #expect(try store.loadNote(at: created).body == "Second body")
    }
}
