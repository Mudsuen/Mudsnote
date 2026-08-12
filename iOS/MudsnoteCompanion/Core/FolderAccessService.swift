import Foundation

enum FolderAccessError: LocalizedError, Equatable {
    case missingFolder
    case bookmarkResolutionFailed
    case folderUnavailable
    case notDirectory

    var errorDescription: String? {
        switch self {
        case .missingFolder:
            return String(localized: "Choose an iCloud Drive Markdown folder first.")
        case .bookmarkResolutionFailed:
            return String(localized: "The saved folder permission is no longer valid. Choose the folder again.")
        case .folderUnavailable:
            return String(localized: "The saved folder was moved, removed, or is not downloaded. Choose its current location.")
        case .notDirectory:
            return String(localized: "Choose a folder, not an individual file.")
        }
    }
}

final class FolderAccessService {
    enum DefaultsKey {
        static let bookmarkData = "mudsnote.ios.folderBookmarkData"
    }

    private(set) var currentRoot: URL?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func persistFolder(_ url: URL) throws {
        try validateFolder(url)
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(bookmark, forKey: DefaultsKey.bookmarkData)
        currentRoot = url
    }

    func resolvePersistedFolder() throws -> URL? {
        guard let data = defaults.data(forKey: DefaultsKey.bookmarkData) else {
            return nil
        }
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            currentRoot = nil
            throw FolderAccessError.bookmarkResolutionFailed
        }
        do {
            try validateFolder(url)
        } catch {
            currentRoot = nil
            throw error
        }
        if isStale {
            try persistFolder(url)
        }
        currentRoot = url
        return url
    }

    func withAccess<T>(to url: URL, _ work: () throws -> T) throws -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        return try work()
    }

    func forgetPersistedFolder() {
        defaults.removeObject(forKey: DefaultsKey.bookmarkData)
        currentRoot = nil
    }

    private func validateFolder(_ url: URL) throws {
        guard url.isFileURL else { throw FolderAccessError.folderUnavailable }
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        guard (try? url.checkResourceIsReachable()) == true else {
            throw FolderAccessError.folderUnavailable
        }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw FolderAccessError.notDirectory }
    }
}

enum FolderInitializer {
    static func initialize(_ root: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try ensureDirectory(root.appendingPathComponent("Attachments"))
        try ensureDirectory(root.appendingPathComponent("Inbox"))
        try ensureDirectory(root.appendingPathComponent(".mudsnote"))
        try ensureDirectory(root.appendingPathComponent(".mudsnote/Trash"))

        try ensureFile(
            root.appendingPathComponent("Inbox.md"),
            contents: "# Inbox\n\n"
        )
        try ensureFile(
            root.appendingPathComponent(".mudsnote/queue.json"),
            contents: "[]"
        )
        try ensureFile(
            root.appendingPathComponent(".mudsnote/pins.json"),
            contents: "[]"
        )
        try ensureFile(
            root.appendingPathComponent(".mudsnote/smart-folders.json"),
            contents: "{\"version\":1,\"folders\":[]}\n"
        )
    }

    private static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private static func ensureFile(_ url: URL, contents: String) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
