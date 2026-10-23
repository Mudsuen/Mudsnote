import Foundation
import Testing
@testable import MudsnoteCore

private final class MigratedHomeFileManager: FileManager, @unchecked Sendable {
    let fixtureRoot: URL
    var inaccessiblePaths: Set<String> = []
    var fullAttributeReadCount = 0

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
        fullAttributeReadCount += 1
        throw CocoaError(.fileReadUnknown)
    }

    func migrationPathStatus(_ path: String, _ followsSymlinks: Bool) -> NoteStore.HomeMigrationPathStatus {
        if inaccessiblePaths.contains(path) { return .inaccessible }
        return NoteStore.homeMigrationPathStatus(fixtureURL(for: path).path, followsSymlinks)
    }

    override func isReadableFile(atPath path: String) -> Bool {
        !inaccessiblePaths.contains(path) && super.isReadableFile(atPath: fixtureURL(for: path).path)
    }
}

private final class LaunchPreparationFileManager: FileManager, @unchecked Sendable {
    private let lock = NSLock()
    private var usedMainThread = false

    override func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool,
                                  attributes: [FileAttributeKey: Any]? = nil) throws {
        lock.lock()
        usedMainThread = usedMainThread || Thread.isMainThread
        lock.unlock()
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }

    func observedMainThread() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return usedMainThread
    }
}

struct MigratedHomeDirectoryTests {
    @MainActor
    @Test func launchPreparationPerformsFilesystemWorkOffMainActor() async throws {
        let suite = "mudsnote.launch-preparation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let manager = LaunchPreparationFileManager()
        let store = NoteStore(defaults: defaults, legacyDefaults: nil, fileManager: manager,
                              appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")

        try await store.prepareNotesDirectoryForLaunch()

        #expect(!manager.observedMainThread())
        #expect(FileManager.default.fileExists(atPath: store.notesDirectory.path))
    }

    @Test func storeInitializationDoesNotProbeConfiguredCloudDirectories() throws {
        let suite = "mudsnote.launch-no-cloud-probe.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manager = MigratedHomeFileManager(fixtureRoot: root)
        let oldPath = "/Users/\(NSUserName())/Library/Mobile Documents/Test/Notes"
        defaults.set(oldPath, forKey: NoteStoreDefaultsKey.notesDirectory)

        let store = NoteStore(defaults: defaults, legacyDefaults: nil, fileManager: manager,
                              appSupportDirectory: root.appendingPathComponent("Support"))

        #expect(manager.fullAttributeReadCount == 0)
        #expect(store.notesDirectory.path == oldPath)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

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
            defaults: defaults, fileManager: manager, currentAccountName: "previous",
            readPathStatus: manager.migrationPathStatus
        )

        let store = NoteStore(defaults: defaults, legacyDefaults: nil, fileManager: manager,
                              appSupportDirectory: root.appendingPathComponent("Support"))

        #expect(store.notesDirectory.path == currentRoot + "/Input")
        #expect(store.preferredDirectories.map(\.path) == [currentRoot + "/Input", currentRoot, "/Volumes/Offline/Notes"])
        NoteStore.recoverMigratedHomeDirectories(defaults: defaults, fileManager: manager,
                                               currentAccountName: "previous", readPathStatus: manager.migrationPathStatus)
        #expect(defaults.string(forKey: NoteStoreDefaultsKey.notesDirectory) == currentRoot + "/Input")
        #expect(!FileManager.default.fileExists(atPath: manager.fixtureURL(for: oldRoot).path))
        #expect(manager.fullAttributeReadCount == 0)
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

        NoteStore.recoverMigratedHomeDirectories(defaults: defaults, fileManager: manager,
                                               currentAccountName: "previous", readPathStatus: manager.migrationPathStatus)

        #expect(defaults.string(forKey: NoteStoreDefaultsKey.notesDirectory) == preservedPaths[2])
        #expect(defaults.stringArray(forKey: NoteStoreDefaultsKey.extraDirectories) == preservedPaths)
        #expect(!FileManager.default.fileExists(atPath: manager.fixtureURL(for: "/Users/current/Missing").path))
        #expect(manager.fullAttributeReadCount == 0)
    }
}
