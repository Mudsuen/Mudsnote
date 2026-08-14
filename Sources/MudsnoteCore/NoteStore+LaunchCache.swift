import Foundation

private struct LibraryLaunchNoteDiskCache: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let url: URL
    let title: String
    let body: String
    let tags: [String]
    let sourceContents: String
    let modifiedAt: Date
    let createdAt: Date?

    var snapshot: LibraryLaunchNoteSnapshot {
        LibraryLaunchNoteSnapshot(
            url: url.standardizedFileURL,
            document: LoadedNoteDocument(
                title: title,
                body: body,
                tags: tags,
                sourceContents: sourceContents
            ),
            modifiedAt: modifiedAt,
            createdAt: createdAt
        )
    }
}

private struct LibraryPresentationDiskCache: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let notes: [Note]

    struct Note: Codable {
        let url: URL
        let title: String
        let snippet: String
        let modifiedAt: Date
        let createdAt: Date
        let tags: [String]
        let hasAttachments: Bool
        let thumbnailURL: URL?

        init(_ note: NoteSearchResult) {
            url = note.url.standardizedFileURL
            title = note.title
            snippet = note.snippet
            modifiedAt = note.modifiedAt
            createdAt = note.createdAt
            tags = note.tags
            hasAttachments = note.hasAttachments
            thumbnailURL = note.thumbnailURL?.standardizedFileURL
        }

        var searchResult: NoteSearchResult {
            NoteSearchResult(
                url: url.standardizedFileURL,
                title: title,
                snippet: snippet,
                modifiedAt: modifiedAt,
                createdAt: createdAt,
                tags: tags,
                hasAttachments: hasAttachments,
                thumbnailURL: thumbnailURL?.standardizedFileURL
            )
        }
    }
}

extension NoteStore {
    static let maximumLibraryLaunchNoteCacheSize: UInt64 = 4 * 1_024 * 1_024
    static let maximumLibraryPresentationCacheSize = 12 * 1_024 * 1_024
    static let maximumLibraryPresentationNoteCount = 50_000

    public func cacheLibraryLaunchNote(
        _ document: LoadedNoteDocument,
        at url: URL,
        modifiedAt: Date,
        createdAt: Date? = nil
    ) {
        let cache = LibraryLaunchNoteDiskCache(
            schemaVersion: LibraryLaunchNoteDiskCache.currentSchemaVersion,
            url: url.standardizedFileURL,
            title: document.title,
            body: document.body,
            tags: document.tags,
            sourceContents: document.sourceContents,
            modifiedAt: modifiedAt,
            createdAt: createdAt
        )

        do {
            let data = try JSONEncoder().encode(cache)
            guard data.count <= Self.maximumLibraryLaunchNoteCacheSize else {
                try? fileManager.removeItem(at: libraryLaunchNoteCacheURL)
                return
            }
            try fileManager.createDirectory(
                at: libraryLaunchNoteCacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: libraryLaunchNoteCacheURL, options: .atomic)
        } catch {
            try? fileManager.removeItem(at: libraryLaunchNoteCacheURL)
        }
    }

    public func cachedLibraryLaunchNote() -> LibraryLaunchNoteSnapshot? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: libraryLaunchNoteCacheURL.path),
              let cacheSize = (attributes[.size] as? NSNumber)?.uint64Value,
              cacheSize <= Self.maximumLibraryLaunchNoteCacheSize,
              let data = try? Data(contentsOf: libraryLaunchNoteCacheURL),
              let cache = try? JSONDecoder().decode(LibraryLaunchNoteDiskCache.self, from: data),
              cache.schemaVersion == LibraryLaunchNoteDiskCache.currentSchemaVersion else {
            return nil
        }
        return cache.snapshot
    }

    public func cacheLibraryPresentationSnapshot(_ notes: [NoteSearchResult]) {
        var cachedNotes = Array(notes.prefix(Self.maximumLibraryPresentationNoteCount))
        let encoder = JSONEncoder()

        do {
            var data = try encoder.encode(LibraryPresentationDiskCache(
                schemaVersion: LibraryPresentationDiskCache.currentSchemaVersion,
                notes: cachedNotes.map(LibraryPresentationDiskCache.Note.init)
            ))
            while data.count > Self.maximumLibraryPresentationCacheSize, cachedNotes.count > 1 {
                cachedNotes.removeLast(max(cachedNotes.count / 4, 1))
                data = try encoder.encode(LibraryPresentationDiskCache(
                    schemaVersion: LibraryPresentationDiskCache.currentSchemaVersion,
                    notes: cachedNotes.map(LibraryPresentationDiskCache.Note.init)
                ))
            }
            guard data.count <= Self.maximumLibraryPresentationCacheSize else {
                try? fileManager.removeItem(at: libraryPresentationCacheURL)
                return
            }
            try fileManager.createDirectory(
                at: libraryPresentationCacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: libraryPresentationCacheURL, options: .atomic)
        } catch {
            try? fileManager.removeItem(at: libraryPresentationCacheURL)
        }
    }

    public func cachedLibraryPresentationSnapshot(limit: Int = .max) -> [NoteSearchResult] {
        guard let attributes = try? fileManager.attributesOfItem(
            atPath: libraryPresentationCacheURL.path
        ),
        let cacheSize = (attributes[.size] as? NSNumber)?.intValue,
        cacheSize <= Self.maximumLibraryPresentationCacheSize,
        let data = try? Data(contentsOf: libraryPresentationCacheURL),
        let cache = try? JSONDecoder().decode(LibraryPresentationDiskCache.self, from: data),
        cache.schemaVersion == LibraryPresentationDiskCache.currentSchemaVersion else {
            return []
        }
        return cache.notes.prefix(limit).map(\.searchResult)
    }

    private var libraryLaunchNoteCacheURL: URL {
        appSupportDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("launch-note-v1.json", isDirectory: false)
    }

    private var libraryPresentationCacheURL: URL {
        appSupportDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("presentation-v1.json", isDirectory: false)
    }
}
