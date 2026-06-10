import Foundation

enum FolderAccessError: LocalizedError {
    case missingFolder
    case bookmarkResolutionFailed

    var errorDescription: String? {
        switch self {
        case .missingFolder:
            return "Choose an iCloud Drive Markdown folder first."
        case .bookmarkResolutionFailed:
            return "The folder bookmark could not be restored."
        }
    }
}

final class FolderAccessService {
    private enum DefaultsKey {
        static let bookmarkData = "mudsnote.ios.folderBookmarkData"
    }

    private(set) var currentRoot: URL?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func persistFolder(_ url: URL) throws {
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
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
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
}

enum FolderInitializer {
    static func initialize(_ root: URL, calendar: Calendar = .current, now: Date = Date()) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try ensureDirectory(root.appendingPathComponent("Daily"))
        try ensureDirectory(root.appendingPathComponent("Attachments"))
        try ensureDirectory(root.appendingPathComponent("Templates"))
        try ensureDirectory(root.appendingPathComponent(".mudsnote"))

        try ensureFile(
            root.appendingPathComponent("Inbox.md"),
            contents: "# Inbox\n\n"
        )
        try ensureFile(
            root.appendingPathComponent("Templates/quick-memo.md"),
            contents: "## {{datetime}}\n\n{{body}}\n\n{{tags}}\n"
        )
        try ensureFile(
            root.appendingPathComponent("Templates/reading.md"),
            contents: "## {{datetime}}\n\nSource: {{url}}\n\n{{body}}\n"
        )
        try ensureFile(
            root.appendingPathComponent("Templates/meeting.md"),
            contents: "## {{datetime}}\n\nParticipants:\n\nNotes:\n{{body}}\n"
        )
        try ensureFile(
            root.appendingPathComponent(".mudsnote/queue.json"),
            contents: "[]"
        )
        try ensureFile(
            root.appendingPathComponent(".mudsnote/settings.json"),
            contents: "{\n  \"markdownReferenceStyle\": \"wikilink\",\n  \"audioTranscription\": \"placeholder\"\n}\n"
        )

        let day = dayFormatter.string(from: now)
        try ensureFile(
            root.appendingPathComponent("Daily/\(day).md"),
            contents: "# \(day)\n\n"
        )
    }

    private static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private static func ensureFile(_ url: URL, contents: String) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
