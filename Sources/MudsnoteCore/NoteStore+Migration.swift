import Foundation

extension NoteStore {
    /// Migration Assistant preserves absolute preferences even when the account's
    /// home changes. Reuse only an existing directory at the identical home-relative
    /// path; a missing or inaccessible library must never become a new empty one.
    static func recoverMigratedHomeDirectories(
        defaults: UserDefaults,
        fileManager: FileManager,
        currentAccountName: String = NSUserName()
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
            do {
                _ = try fileManager.attributesOfItem(atPath: original.path)
                return rawPath
            } catch {
                let error = error as NSError
                guard error.domain == NSCocoaErrorDomain,
                      [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) else {
                    return rawPath
                }
            }

            let candidate = components.dropFirst(3).reduce(currentHome) {
                $0.appendingPathComponent($1, isDirectory: true)
            }
            guard let attributes = try? fileManager.attributesOfItem(atPath: candidate.path),
                  attributes[.type] as? FileAttributeType == .typeDirectory,
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
