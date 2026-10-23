import Foundation
import Darwin

extension NoteStore {
    enum HomeMigrationPathStatus: Equatable {
        case missing, directory, other, inaccessible
    }

    static func homeMigrationPathStatus(_ path: String, _ followsSymlinks: Bool) -> HomeMigrationPathStatus {
        var info = stat()
        let result = path.withCString { pointer in
            followsSymlinks ? stat(pointer, &info) : lstat(pointer, &info)
        }
        guard result == 0 else { return errno == ENOENT ? .missing : .inaccessible }
        return (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) ? .directory : .other
    }

    /// Migration Assistant preserves absolute preferences even when the account's
    /// home changes. Reuse only an existing directory at the identical home-relative
    /// path; a missing or inaccessible library must never become a new empty one.
    static func recoverMigratedHomeDirectories(
        defaults: UserDefaults,
        fileManager: FileManager,
        currentAccountName: String = NSUserName(),
        readPathStatus: (String, Bool) -> HomeMigrationPathStatus = NoteStore.homeMigrationPathStatus
    ) {
        let currentHome = fileManager.homeDirectoryForCurrentUser.standardizedFileURL
        guard currentHome.deletingLastPathComponent().path == "/Users",
              !["Shared", "Guest"].contains(currentAccountName) else { return }

        func recoveredPath(_ rawPath: String) -> String {
            guard rawPath.hasPrefix("/Users/") else { return rawPath }
            let original = URL(fileURLWithPath: rawPath, isDirectory: true).standardizedFileURL
            let components = original.pathComponents
            guard components.count > 3,
                  components[1] == "Users",
                  components[2] == currentAccountName,
                  components[2] != currentHome.lastPathComponent else { return rawPath }
            // Foundation's full attributes include extended attributes, which can
            // wait indefinitely on an iCloud provider. Only basic path type is needed.
            guard readPathStatus(original.path, false) == .missing else { return rawPath }

            let candidate = components.dropFirst(3).reduce(currentHome) {
                $0.appendingPathComponent($1, isDirectory: true)
            }
            guard readPathStatus(candidate.path, true) == .directory,
                  fileManager.isReadableFile(atPath: candidate.path) else { return rawPath }
            return candidate.path
        }

        if let original = defaults.string(forKey: NoteStoreDefaultsKey.notesDirectory) {
            let recovered = recoveredPath(original)
            if recovered != original {
                defaults.set(recovered, forKey: NoteStoreDefaultsKey.notesDirectory)
            }
        }
        if let originals = defaults.stringArray(forKey: NoteStoreDefaultsKey.extraDirectories) {
            let recovered = originals.map(recoveredPath)
            if recovered != originals {
                defaults.set(recovered, forKey: NoteStoreDefaultsKey.extraDirectories)
            }
        }
    }

    enum LegacyDefaultsKey {
        static let hotKey = "quickmarkdown.hotkey"
        static let floatingHotKey = "quickmarkdown.floatingHotKey"
        static let saveShortcut = "quickmarkdown.saveShortcut"
        static let notesDirectory = "quickmarkdown.notesDirectory"
        static let extraDirectories = "quickmarkdown.extraDirectories"
        static let panelOpacity = "quickmarkdown.panelOpacity"
        static let recentFiles = "quickmarkdown.recentFiles"
        static let quickCaptureFrameX = "quickmarkdown.quickCaptureFrameX"
        static let quickCaptureFrameY = "quickmarkdown.quickCaptureFrameY"
        static let quickCaptureFrameWidth = "quickmarkdown.quickCaptureFrameWidth"
        static let quickCaptureFrameHeight = "quickmarkdown.quickCaptureFrameHeight"
        static let floatingFrameX = "quickmarkdown.floatingFrameX"
        static let floatingFrameY = "quickmarkdown.floatingFrameY"
        static let floatingFrameWidth = "quickmarkdown.floatingFrameWidth"
        static let floatingFrameHeight = "quickmarkdown.floatingFrameHeight"
    }

    enum MigrationKey {
        static let didMigrateQuickMarkdownDefaults = "mudsnote.didMigrateQuickMarkdownDefaults"
    }

    static func migrateLegacyDefaultsIfNeeded(defaults: UserDefaults, legacyDefaults: UserDefaults?) {
        guard !defaults.bool(forKey: MigrationKey.didMigrateQuickMarkdownDefaults) else { return }
        defer { defaults.set(true, forKey: MigrationKey.didMigrateQuickMarkdownDefaults) }
        guard let legacyDefaults else { return }

        let stringMigrations: [(legacy: String, current: String)] = [
            (LegacyDefaultsKey.hotKey, NoteStoreDefaultsKey.hotKey),
            (LegacyDefaultsKey.floatingHotKey, NoteStoreDefaultsKey.floatingHotKey),
            (LegacyDefaultsKey.saveShortcut, NoteStoreDefaultsKey.saveShortcut)
        ]
        for migration in stringMigrations {
            migrateString(from: migration.legacy, to: migration.current, defaults: defaults, legacyDefaults: legacyDefaults)
        }

        migratePathString(
            from: LegacyDefaultsKey.notesDirectory,
            to: NoteStoreDefaultsKey.notesDirectory,
            defaults: defaults,
            legacyDefaults: legacyDefaults
        )

        let pathArrayMigrations: [(legacy: String, current: String)] = [
            (LegacyDefaultsKey.extraDirectories, NoteStoreDefaultsKey.extraDirectories),
            (LegacyDefaultsKey.recentFiles, NoteStoreDefaultsKey.recentFiles)
        ]
        for migration in pathArrayMigrations {
            migratePathArray(from: migration.legacy, to: migration.current, defaults: defaults, legacyDefaults: legacyDefaults)
        }

        let numberMigrations: [(legacy: String, current: String)] = [
            (LegacyDefaultsKey.panelOpacity, NoteStoreDefaultsKey.panelOpacity),
            (LegacyDefaultsKey.quickCaptureFrameX, NoteStoreDefaultsKey.quickCaptureFrameX),
            (LegacyDefaultsKey.quickCaptureFrameY, NoteStoreDefaultsKey.quickCaptureFrameY),
            (LegacyDefaultsKey.quickCaptureFrameWidth, NoteStoreDefaultsKey.quickCaptureFrameWidth),
            (LegacyDefaultsKey.quickCaptureFrameHeight, NoteStoreDefaultsKey.quickCaptureFrameHeight),
            (LegacyDefaultsKey.floatingFrameX, NoteStoreDefaultsKey.floatingFrameX),
            (LegacyDefaultsKey.floatingFrameY, NoteStoreDefaultsKey.floatingFrameY),
            (LegacyDefaultsKey.floatingFrameWidth, NoteStoreDefaultsKey.floatingFrameWidth),
            (LegacyDefaultsKey.floatingFrameHeight, NoteStoreDefaultsKey.floatingFrameHeight)
        ]
        for migration in numberMigrations {
            migrateNumber(from: migration.legacy, to: migration.current, defaults: defaults, legacyDefaults: legacyDefaults)
        }
    }

    private static func migrateString(from legacyKey: String, to currentKey: String, defaults: UserDefaults, legacyDefaults: UserDefaults) {
        guard defaults.object(forKey: currentKey) == nil,
              let value = legacyDefaults.string(forKey: legacyKey),
              !value.isEmpty else { return }
        defaults.set(value, forKey: currentKey)
    }

    private static func migratePathString(from legacyKey: String, to currentKey: String, defaults: UserDefaults, legacyDefaults: UserDefaults) {
        guard defaults.object(forKey: currentKey) == nil,
              let value = legacyDefaults.string(forKey: legacyKey),
              !value.isEmpty else { return }
        defaults.set(rewrittenLegacyPath(value), forKey: currentKey)
    }

    private static func migratePathArray(from legacyKey: String, to currentKey: String, defaults: UserDefaults, legacyDefaults: UserDefaults) {
        guard defaults.object(forKey: currentKey) == nil,
              let values = legacyDefaults.array(forKey: legacyKey) as? [String] else { return }
        defaults.set(values.map(rewrittenLegacyPath), forKey: currentKey)
    }

    private static func migrateNumber(from legacyKey: String, to currentKey: String, defaults: UserDefaults, legacyDefaults: UserDefaults) {
        guard defaults.object(forKey: currentKey) == nil,
              let value = legacyDefaults.object(forKey: legacyKey) as? NSNumber else { return }
        defaults.set(value, forKey: currentKey)
    }

    private static func rewrittenLegacyPath(_ value: String) -> String {
        value
            .replacingOccurrences(of: "/QuickMarkdown/", with: "/Mudsnote/")
            .replacingOccurrences(of: "/QuickMarkdown", with: "/Mudsnote")
    }
}
