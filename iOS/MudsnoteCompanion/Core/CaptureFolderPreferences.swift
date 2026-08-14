import Foundation

struct CaptureFolderPreferences {
    static let defaultFolderKey = "mudsnote.ios.capture.defaultFolder"
    static let recentFoldersKey = "mudsnote.ios.capture.recentFolders"
    static let maximumRecentFolderCount = 10

    private struct RecentFolder: Codable, Equatable {
        var relativePath: String
        var lastUsedAt: Date
    }

    private let defaults: UserDefaults
    private let fileManager: FileManager

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
    }

    var storedDefaultFolder: String? {
        normalizedPath(defaults.string(forKey: Self.defaultFolderKey))
    }

    func setDefaultFolder(_ relativePath: String) {
        guard let path = normalizedPath(relativePath) else { return }
        defaults.set(path, forKey: Self.defaultFolderKey)
    }

    func setDefaultFolder(_ relativePath: String, libraryRoot: URL?) {
        guard let path = normalizedPath(relativePath) else { return }
        guard let libraryRoot else {
            setDefaultFolder(path)
            return
        }
        defaults.set(path, forKey: defaultFolderKey(libraryRoot: libraryRoot))
    }

    func resolveDefaultFolder(in folders: [LibraryFolderNode]) -> String? {
        let available = folders.flatMap(\.captureFlattened)
        if let storedDefaultFolder,
           available.contains(where: { $0.relativePath == storedDefaultFolder }) {
            return storedDefaultFolder
        }
        if defaults.object(forKey: Self.defaultFolderKey) != nil {
            defaults.removeObject(forKey: Self.defaultFolderKey)
        }
        return available.first(where: \.isMergedInboxFolder)?.relativePath
    }

    func resolveDefaultFolder(libraryRoot: URL) -> String? {
        let accessed = libraryRoot.startAccessingSecurityScopedResource()
        defer {
            if accessed { libraryRoot.stopAccessingSecurityScopedResource() }
        }
        let key = defaultFolderKey(libraryRoot: libraryRoot)
        let stored = normalizedPath(defaults.string(forKey: key))
            ?? migrateLegacyDefaultFolder(to: key)
        if let stored,
           isExistingWritableFolder(stored, libraryRoot: libraryRoot) {
            return stored
        }
        if defaults.object(forKey: key) != nil {
            defaults.removeObject(forKey: key)
        }
        return isExistingWritableFolder("Inbox", libraryRoot: libraryRoot)
            ? "Inbox"
            : nil
    }

    func recordSuccessfulSave(to relativePath: String?, at date: Date = Date()) {
        recordSuccessfulSave(to: relativePath, at: date, libraryRoot: nil)
    }

    func recordSuccessfulSave(
        to relativePath: String?,
        at date: Date = Date(),
        libraryRoot: URL?
    ) {
        guard let relativePath = normalizedPath(relativePath) else { return }
        let key = recentFoldersKey(libraryRoot: libraryRoot)
        var records = loadRecentFolders(key: key, migratesLegacy: libraryRoot != nil)
        records.removeAll { $0.relativePath == relativePath }
        records.append(RecentFolder(relativePath: relativePath, lastUsedAt: date))
        records.sort {
            if $0.lastUsedAt == $1.lastUsedAt {
                return $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }
            return $0.lastUsedAt > $1.lastUsedAt
        }
        saveRecentFolders(Array(records.prefix(Self.maximumRecentFolderCount)), key: key)
    }

    func recentFolders(
        in folders: [LibraryFolderNode],
        libraryRoot: URL?
    ) -> [LibraryFolderNode] {
        let available = Dictionary(
            uniqueKeysWithValues: folders
                .flatMap(\.captureFlattened)
                .map { ($0.relativePath, $0) }
        )
        let accessed = libraryRoot?.startAccessingSecurityScopedResource() ?? false
        defer {
            if accessed { libraryRoot?.stopAccessingSecurityScopedResource() }
        }
        return loadRecentFolders(
            key: recentFoldersKey(libraryRoot: libraryRoot),
            migratesLegacy: libraryRoot != nil
        ).compactMap { record in
            guard let folder = available[record.relativePath] else { return nil }
            guard let libraryRoot else { return folder }
            guard isExistingWritableFolder(
                record.relativePath,
                libraryRoot: libraryRoot
            ) else {
                return nil
            }
            return folder
        }
    }

    private func loadRecentFolders(
        key: String = Self.recentFoldersKey,
        migratesLegacy: Bool = false
    ) -> [RecentFolder] {
        var data = defaults.data(forKey: key)
        if data == nil, migratesLegacy, let legacy = defaults.data(forKey: Self.recentFoldersKey) {
            data = legacy
            defaults.set(legacy, forKey: key)
            defaults.removeObject(forKey: Self.recentFoldersKey)
        }
        guard let data,
              let decoded = try? JSONDecoder().decode([RecentFolder].self, from: data) else {
            return []
        }
        var seen = Set<String>()
        return decoded
            .filter { seen.insert($0.relativePath).inserted }
            .sorted {
                if $0.lastUsedAt == $1.lastUsedAt {
                    return $0.relativePath.localizedStandardCompare($1.relativePath)
                        == .orderedAscending
                }
                return $0.lastUsedAt > $1.lastUsedAt
            }
    }

    private func saveRecentFolders(
        _ folders: [RecentFolder],
        key: String = Self.recentFoldersKey
    ) {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        defaults.set(data, forKey: key)
    }

    private func defaultFolderKey(libraryRoot: URL) -> String {
        "\(Self.defaultFolderKey).\(LibraryIdentity.identifier(for: libraryRoot))"
    }

    private func recentFoldersKey(libraryRoot: URL?) -> String {
        guard let libraryRoot else { return Self.recentFoldersKey }
        return "\(Self.recentFoldersKey).\(LibraryIdentity.identifier(for: libraryRoot))"
    }

    private func migrateLegacyDefaultFolder(to key: String) -> String? {
        guard let legacy = storedDefaultFolder else { return nil }
        defaults.set(legacy, forKey: key)
        defaults.removeObject(forKey: Self.defaultFolderKey)
        return legacy
    }

    private func normalizedPath(_ rawPath: String?) -> String? {
        guard let rawPath else { return nil }
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, !path.hasPrefix("/") else { return nil }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.isEmpty,
              !components.contains("."),
              !components.contains("..") else {
            return nil
        }
        return components.joined(separator: "/")
    }

    private func isExistingWritableFolder(
        _ relativePath: String,
        libraryRoot: URL
    ) -> Bool {
        guard let url = AuthorizedLibraryPath.resolve(relativePath, within: libraryRoot) else {
            return false
        }
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && fileManager.isWritableFile(atPath: url.path)
    }
}

private extension LibraryFolderNode {
    var captureFlattened: [LibraryFolderNode] {
        [self] + children.flatMap(\.captureFlattened)
    }
}
