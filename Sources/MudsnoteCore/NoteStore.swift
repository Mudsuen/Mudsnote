import Foundation

/// `NoteStore` is the single public facade for all on-disk state that Mudsnote
/// persists: settings, drafts, notes, recent files, and search. Behavior is
/// split across focused extensions (Settings, Migration, Drafts, Notes, Search)
/// so that each responsibility lives in its own file.
public final class NoteStore: @unchecked Sendable {
    public static let minimumPanelOpacity = 0.62
    public static let maximumPanelOpacity = 0.96
    public static let defaultPanelOpacity = 0.78
    public static let attachmentDirectoryName = "Attachments"

    let defaults: UserDefaults
    let fileManager: FileManager
    let appSupportDirectory: URL
    let searchIndexLock = NSLock()
    var searchIndexSnapshot: NoteSearchIndexSnapshot?
    var searchIndexEntryReadCountForTesting = 0
    var searchIndexSignatureReadCountForTesting = 0
    var searchIndexCacheURL: URL {
        appSupportDirectory
            .appendingPathComponent("SearchIndex", isDirectory: true)
            .appendingPathComponent("index-v1.json", isDirectory: false)
    }

    public init(
        defaults: UserDefaults = .standard,
        legacyDefaults: UserDefaults? = UserDefaults(suiteName: "local.codex.quickmarkdown"),
        fileManager: FileManager = .default,
        appSupportDirectory: URL? = nil
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        Self.migrateLegacyDefaultsIfNeeded(defaults: defaults, legacyDefaults: legacyDefaults)
        self.appSupportDirectory = appSupportDirectory ?? Self.defaultAppSupportDirectory(fileManager: fileManager)
    }

    public static func defaultNotesDirectory(fileManager: FileManager = .default) -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents", isDirectory: true)
        return documents.appendingPathComponent("Mudsnote", isDirectory: true)
    }

    public static func defaultAppSupportDirectory(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport.appendingPathComponent("Mudsnote", isDirectory: true)
    }

    func deduplicatedDirectories(_ directories: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []

        for directory in directories {
            let standardized = directory.standardizedFileURL
            if seen.insert(standardized.path).inserted {
                result.append(standardized)
            }
        }

        return result
    }
}

struct NoteSearchIndexSnapshot: Codable {
    let rootsKey: [String]
    let fileSignatures: [String: NoteSearchFileSignature]
    let entries: [NoteSearchIndexEntry]
}

struct NoteSearchFileSignature: Equatable, Codable {
    let modifiedAt: Date
    let fileSize: UInt64
}

struct NoteSearchIndexEntry: Codable {
    let url: URL
    let title: String
    let body: String
    let bodyLower: String
    let snippet: String
    let modifiedAt: Date
    let tags: [String]
    let tagsLower: [String]
    let hasAttachments: Bool
    let thumbnailURL: URL?

    var result: NoteSearchResult {
        NoteSearchResult(
            url: url,
            title: title,
            snippet: snippet,
            modifiedAt: modifiedAt,
            tags: tags,
            hasAttachments: hasAttachments,
            thumbnailURL: thumbnailURL
        )
    }
}

struct NoteSearchIndexDiskCache: Codable {
    static let currentSchemaVersion = 4

    let schemaVersion: Int
    let snapshot: NoteSearchIndexSnapshot
}

enum NoteStoreDefaultsKey {
    static let hotKey = "mudsnote.hotkey"
    static let floatingHotKey = "mudsnote.floatingHotKey"
    static let saveShortcut = "mudsnote.saveShortcut"
    static let notesDirectory = "mudsnote.notesDirectory"
    static let extraDirectories = "mudsnote.extraDirectories"
    static let panelOpacity = "mudsnote.panelOpacity"
    static let revealSavedNoteInFinder = "mudsnote.revealSavedNoteInFinder"
    static let floatingNoteStaysOnTop = "mudsnote.floatingNoteStaysOnTop"
    static let spellCheckingEnabled = "mudsnote.spellCheckingEnabled"
    static let libraryNoteSortOrder = "mudsnote.library.noteSortOrder"
    static let libraryGroupsNotesByDate = "mudsnote.library.groupsNotesByDate"
    static let libraryPinnedNotePaths = "mudsnote.library.pinnedNotePaths"
    static let libraryCollapsedFolderPaths = "mudsnote.library.collapsedFolderPaths"
    static let libraryExpandedFolderPaths = "mudsnote.library.expandedFolderPaths"
    static let libraryFoldersSectionCollapsed = "mudsnote.library.foldersSectionCollapsed"
    static let libraryTagsSectionCollapsed = "mudsnote.library.tagsSectionCollapsed"
    static let librarySourceColumnWidth = "mudsnote.library.sourceColumnWidth"
    static let libraryNoteColumnWidth = "mudsnote.library.noteColumnWidth"
    static let librarySourceListVisible = "mudsnote.library.sourceListVisible"
    static let aiEnabled = "mudsnote.ai.enabled"
    static let aiOllamaBaseURL = "mudsnote.ai.ollamaBaseURL"
    static let aiOllamaModel = "mudsnote.ai.ollamaModel"
    static let recentFiles = "mudsnote.recentFiles"
    static let recentFileMetadata = "mudsnote.recentFileMetadata"
    static let trashedNotesMetadata = "mudsnote.trashedNotesMetadata"
    static let quickCaptureFrameX = "mudsnote.quickCaptureFrameX"
    static let quickCaptureFrameY = "mudsnote.quickCaptureFrameY"
    static let quickCaptureFrameWidth = "mudsnote.quickCaptureFrameWidth"
    static let quickCaptureFrameHeight = "mudsnote.quickCaptureFrameHeight"
    static let floatingFrameX = "mudsnote.floatingFrameX"
    static let floatingFrameY = "mudsnote.floatingFrameY"
    static let floatingFrameWidth = "mudsnote.floatingFrameWidth"
    static let floatingFrameHeight = "mudsnote.floatingFrameHeight"
}
