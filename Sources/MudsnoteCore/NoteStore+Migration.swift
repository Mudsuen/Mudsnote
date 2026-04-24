import Foundation

extension NoteStore {
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
