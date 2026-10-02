import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

struct LibraryBackgroundSaveSnapshot: Sendable {
    let generation: Int
    let editorRevision: Int
    let previousURL: URL?
    let title: String
    let body: String
    let tags: [String]
    let targetDirectory: URL
    let updatesInPlace: Bool
    let expectedContents: String?
}

final class LibraryBackgroundEditorSnapshot: @unchecked Sendable {
    private let sourceMarkdown: String?
    private let attributedMarkdown: NSAttributedString?
    private let theme: MarkdownEditorTheme

    init(sourceMarkdown: String, theme: MarkdownEditorTheme) {
        self.sourceMarkdown = sourceMarkdown
        self.attributedMarkdown = nil
        self.theme = theme
    }

    init(attributedMarkdown: NSAttributedString, theme: MarkdownEditorTheme) {
        self.sourceMarkdown = nil
        self.attributedMarkdown = NSAttributedString(attributedString: attributedMarkdown)
        self.theme = theme
    }

    func markdown() -> String {
        if let sourceMarkdown {
            return sourceMarkdown
        }
        guard let attributedMarkdown else { return "" }
        return MarkdownRichTextCodec.serialize(attributedMarkdown, theme: theme)
    }
}

struct LibraryBackgroundSaveSuccess: Sendable {
    let snapshot: LibraryBackgroundSaveSnapshot
    let savedURL: URL
    let savedAt: Date
    let snippet: String
    let hasAttachments: Bool
    let thumbnailURL: URL?
    let sourceContents: String
    let conflictedOriginalURL: URL?
}

final class LibraryBackgroundSaveResultBox: @unchecked Sendable {
    let result: Result<LibraryBackgroundSaveSuccess, Error>

    init(_ result: Result<LibraryBackgroundSaveSuccess, Error>) {
        self.result = result
    }
}

final class LibraryBackgroundSaveResultStore: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Int: LibraryBackgroundSaveResultBox] = [:]

    func insert(_ result: LibraryBackgroundSaveResultBox, for generation: Int) {
        lock.lock()
        results[generation] = result
        lock.unlock()
    }

    func remove(generation: Int) -> LibraryBackgroundSaveResultBox? {
        lock.lock()
        defer { lock.unlock() }
        return results.removeValue(forKey: generation)
    }

    func pendingGenerations() -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return results.keys.sorted()
    }
}

struct LibraryDeletedNote: Sendable {
    let sourceURL: URL
    let trashedURL: URL?
}

struct LibraryDeletionFailure: Sendable {
    let sourceURL: URL
    let message: String
}

struct LibraryDeletionPersistenceResult: Sendable {
    let deletedNotes: [LibraryDeletedNote]
    let failures: [LibraryDeletionFailure]
}

final class LoadedLibraryNoteCacheEntry: NSObject {
    let loaded: LoadedLibraryNote
    let fileModifiedAt: Date
    var renderedBody: NSAttributedString?

    init(loaded: LoadedLibraryNote, fileModifiedAt: Date) {
        self.loaded = loaded
        self.fileModifiedAt = fileModifiedAt
    }
}

final class LoadedLibraryNoteCache: @unchecked Sendable {
    private let storage: NSCache<NSString, LoadedLibraryNoteCacheEntry>

    init(countLimit: Int) {
        storage = NSCache<NSString, LoadedLibraryNoteCacheEntry>()
        storage.countLimit = countLimit
    }

    func entry(forKey key: NSString) -> LoadedLibraryNoteCacheEntry? {
        storage.object(forKey: key)
    }

    func insert(_ entry: LoadedLibraryNoteCacheEntry, forKey key: NSString) {
        storage.setObject(entry, forKey: key)
    }

    func removeEntry(forKey key: NSString) {
        storage.removeObject(forKey: key)
    }
}

final class LibraryThumbnailCacheEntry: NSObject {
    let image: NSImage?

    init(image: NSImage?) {
        self.image = image
    }
}

final class LibraryThumbnailDecodeResult: @unchecked Sendable {
    let image: CGImage?

    init(image: CGImage?) {
        self.image = image
    }
}
