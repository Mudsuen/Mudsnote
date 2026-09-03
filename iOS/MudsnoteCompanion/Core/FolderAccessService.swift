import CryptoKit
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
        static let bookmarkFormatVersion = "mudsnote.ios.folderBookmarkFormatVersion"
    }

    private static let currentBookmarkFormatVersion = 1
    private(set) var currentRoot: URL?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func persistFolder(_ url: URL) throws {
        let bookmark = try withValidatedAccess(to: url) {
            try url.bookmarkData(
                options: [.minimalBookmark],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        defaults.set(bookmark, forKey: DefaultsKey.bookmarkData)
        defaults.set(
            Self.currentBookmarkFormatVersion,
            forKey: DefaultsKey.bookmarkFormatVersion
        )
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
            try withValidatedAccess(to: url) {}
        } catch {
            currentRoot = nil
            throw error
        }
        if isStale
            || defaults.integer(forKey: DefaultsKey.bookmarkFormatVersion)
                != Self.currentBookmarkFormatVersion {
            try persistFolder(url)
        }
        currentRoot = url
        return url
    }

    func withAccess<T>(to url: URL, _ work: () throws -> T) throws -> T {
        try withValidatedAccess(to: url, validateFolder: false, work)
    }

    func validateCurrentFolder() throws {
        guard let currentRoot else { throw FolderAccessError.missingFolder }
        try withValidatedAccess(to: currentRoot) {}
    }

    func forgetPersistedFolder() {
        defaults.removeObject(forKey: DefaultsKey.bookmarkData)
        defaults.removeObject(forKey: DefaultsKey.bookmarkFormatVersion)
        currentRoot = nil
    }

    private func withValidatedAccess<T>(
        to url: URL,
        validateFolder: Bool = true,
        _ work: () throws -> T
    ) throws -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        guard accessed || Self.isAppOwnedURL(url) else {
            throw FolderAccessError.bookmarkResolutionFailed
        }
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        if validateFolder {
            try validateFolderWithinAccess(url)
        }
        return try work()
    }

    private func validateFolderWithinAccess(_ url: URL) throws {
        guard url.isFileURL else { throw FolderAccessError.folderUnavailable }
        guard (try? url.checkResourceIsReachable()) == true else {
            throw FolderAccessError.folderUnavailable
        }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw FolderAccessError.notDirectory }
    }

    private static func isAppOwnedURL(_ url: URL) -> Bool {
        let candidate = url.standardizedFileURL.path
        let fileManager = FileManager.default
        let ownedRoots = [
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first,
            fileManager.temporaryDirectory,
        ].compactMap { $0?.standardizedFileURL.path }

        return ownedRoots.contains { root in
            candidate == root || candidate.hasPrefix(root + "/")
        }
    }
}

enum LibraryIdentity {
    static func identifier(for root: URL) -> String {
        let canonicalPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let digest = SHA256.hash(data: Data(canonicalPath.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum FolderInitializer {
    static func initialize(_ root: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try ensureDirectory(root.appendingPathComponent("Attachments"))
        try ensureDirectory(root.appendingPathComponent(".mudsnote"))
        try ensureDirectory(root.appendingPathComponent(".mudsnote/Trash"))
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
        guard let data = contents.data(using: .utf8) else { return }
        do {
            try data.write(to: url, options: .withoutOverwriting)
        } catch let error as CocoaError where error.code == .fileWriteFileExists {
            // Initialization is idempotent across the app and App Intent
            // processes. Another writer winning exclusive creation is success.
        }
    }
}
