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

    var snapshot: LibraryLaunchNoteSnapshot {
        LibraryLaunchNoteSnapshot(
            url: url.standardizedFileURL,
            document: LoadedNoteDocument(
                title: title,
                body: body,
                tags: tags,
                sourceContents: sourceContents
            ),
            modifiedAt: modifiedAt
        )
    }
}

extension NoteStore {
    static let maximumLibraryLaunchNoteCacheSize: UInt64 = 4 * 1_024 * 1_024

    public func cacheLibraryLaunchNote(
        _ document: LoadedNoteDocument,
        at url: URL,
        modifiedAt: Date
    ) {
        let cache = LibraryLaunchNoteDiskCache(
            schemaVersion: LibraryLaunchNoteDiskCache.currentSchemaVersion,
            url: url.standardizedFileURL,
            title: document.title,
            body: document.body,
            tags: document.tags,
            sourceContents: document.sourceContents,
            modifiedAt: modifiedAt
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

    private var libraryLaunchNoteCacheURL: URL {
        appSupportDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("launch-note-v1.json", isDirectory: false)
    }
}
