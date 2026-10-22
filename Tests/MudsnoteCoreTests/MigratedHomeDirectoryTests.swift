import Foundation
import Testing
@testable import MudsnoteCore

private final class MigratedHomeFileManager: FileManager, @unchecked Sendable {
    let fixtureRoot: URL
    var inaccessiblePaths: Set<String> = []

    init(fixtureRoot: URL) {
        self.fixtureRoot = fixtureRoot
        super.init()
    }

    override var homeDirectoryForCurrentUser: URL {
        URL(fileURLWithPath: "/Users/current", isDirectory: true)
    }

    func fixtureURL(for path: String) -> URL {
        fixtureRoot.appendingPathComponent(String(path.dropFirst()))
    }

    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        if inaccessiblePaths.contains(path) { throw CocoaError(.fileReadNoPermission) }
        return try super.attributesOfItem(atPath: fixtureURL(for: path).path)
    }

    override func isReadableFile(atPath path: String) -> Bool {
        !inaccessiblePaths.contains(path) && super.isReadableFile(atPath: fixtureURL(for: path).path)
    }
}

struct MigratedHomeDirectoryTests {
    @Test func migratedAccountReusesOnlyExistingEquivalentLibraryDirectories() throws {
        let suite = "mudsnote.home-migration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let manager = MigratedHomeFileManager(fixtureRoot: root)
        let relativePath = "Library/Mobile Documents/iCloud~md~obsidian/Documents/Mudsbuild"
        let oldRoot = "/Users/previous/\(relativePath)"
        let currentRoot = "/Users/current/\(relativePath)"
        try FileManager.default.createDirectory(
            at: manager.fixtureURL(for: currentRoot + "/Input"), withIntermediateDirectories: true
        )
        // Migration Assistant can leave an empty old-home stub behind.
        try FileManager.default.createDirectory(
            at: manager.fixtureURL(for: "/Users/previous"), withIntermediateDirectories: true
        )
        defaults.set(oldRoot + "/Input", forKey: NoteStoreDefaultsKey.notesDirectory)
        defaults.set([oldRoot, "/Volumes/Offline/Notes"], forKey: NoteStoreDefaultsKey.extraDirectories)
        NoteStore.recoverMigratedHomeDirectories(
            defaults: defaults, fileManager: manager, currentAccountName: "previous"
        )

        let store = NoteStore(defaults: defaults, legacyDefaults: nil, fileManager: manager,
                              appSupportDirectory: root.appendingPathComponent("Support"))

        #expect(store.notesDirectory.path == currentRoot + "/Input")
        #expect(store.preferredDirectories.map(\.path) == [currentRoot + "/Input", currentRoot, "/Volumes/Offline/Notes"])
        NoteStore.recoverMigratedHomeDirectories(defaults: defaults, fileManager: manager, currentAccountName: "previous")
        #expect(defaults.string(forKey: NoteStoreDefaultsKey.notesDirectory) == currentRoot + "/Input")
        #expect(!FileManager.default.fileExists(atPath: manager.fixtureURL(for: oldRoot).path))
    }

    @Test func homeRecoveryPreservesValidUnavailableAndNonEquivalentLocations() throws {
        let suite = "mudsnote.home-migration-boundaries.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let manager = MigratedHomeFileManager(fixtureRoot: root)
        let preservedPaths = [
            "/Users/previous/Existing", "/Users/previous/PermissionDenied",
            "/Users/previous/Missing", "/Users/previous/FileInsteadOfDirectory",
            "/Users/previous/UnreadableCandidate", "/Users/current/CurrentMissing",
            "/Volumes/Offline/Notes", "/Users/previous", "relative/Notes",
            "/Users/Shared/Existing", "/Users/Guest/Existing", "/Users/another/Existing",
            "/Users/missing-account/Existing"
        ]
        for name in ["Existing", "PermissionDenied", "UnreadableCandidate"] {
            try FileManager.default.createDirectory(
                at: manager.fixtureURL(for: "/Users/current/\(name)"), withIntermediateDirectories: true
            )
        }
        try FileManager.default.createDirectory(
            at: manager.fixtureURL(for: preservedPaths[0]), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: manager.fixtureURL(for: "/Users/another"), withIntermediateDirectories: true
        )
        try Data("Not a library".utf8).write(to: manager.fixtureURL(for: "/Users/current/FileInsteadOfDirectory"))
        manager.inaccessiblePaths = [preservedPaths[1], "/Users/current/UnreadableCandidate"]
        defaults.set(preservedPaths[2], forKey: NoteStoreDefaultsKey.notesDirectory)
        defaults.set(preservedPaths, forKey: NoteStoreDefaultsKey.extraDirectories)

        NoteStore.recoverMigratedHomeDirectories(defaults: defaults, fileManager: manager, currentAccountName: "previous")

        #expect(defaults.string(forKey: NoteStoreDefaultsKey.notesDirectory) == preservedPaths[2])
        #expect(defaults.stringArray(forKey: NoteStoreDefaultsKey.extraDirectories) == preservedPaths)
        #expect(!FileManager.default.fileExists(atPath: manager.fixtureURL(for: "/Users/current/Missing").path))
    }
}
