import Foundation

public final class NoteSearchSession: @unchecked Sendable {
    private let noteStore: NoteStore
    private let entries: [NoteSearchIndexEntry]
    private let entriesByPath: [String: NoteSearchIndexEntry]

    fileprivate init(noteStore: NoteStore, entries: [NoteSearchIndexEntry]) {
        self.noteStore = noteStore
        self.entries = entries
        self.entriesByPath = entries.reduce(into: [:]) {
            $0[$1.url.standardizedFileURL.path] = $1
        }
    }

    public func searchNotes(query: String, limit: Int = 30) -> [NoteSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return recentResults(limit: limit) }
        return noteStore.rankedSearchResults(query: trimmedQuery, limit: limit, entries: entries)
    }

    public func searchRecentNotes(query: String, limit: Int = 30) -> [NoteSearchResult] {
        let recentPaths = Set(noteStore.listRecentFiles(limit: .max).map { $0.url.standardizedFileURL.path })
        let recentEntries = entries.filter { recentPaths.contains($0.url.standardizedFileURL.path) }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return recentResults(limit: limit) }
        return noteStore.rankedSearchResults(query: trimmedQuery, limit: limit, entries: recentEntries)
    }

    public func searchNotes(
        query: String,
        limit: Int = 30,
        in directory: URL,
        includingDescendants: Bool = true
    ) -> [NoteSearchResult] {
        let directoryPath = directory.standardizedFileURL.path
        return scopedSearchResults(query: query, limit: limit) { entry in
            let noteDirectoryPath = entry.url.deletingLastPathComponent().standardizedFileURL.path
            return noteDirectoryPath == directoryPath
                || (includingDescendants && noteDirectoryPath.hasPrefix(directoryPath + "/"))
        }
    }

    public func searchNotes(query: String, limit: Int = 30, tagged tag: String) -> [NoteSearchResult] {
        scopedSearchResults(query: query, limit: limit) { entry in
            entry.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
        }
    }

    public func searchInboxNotes(query: String, limit: Int = 30) -> [NoteSearchResult] {
        scopedSearchResults(query: query, limit: limit) { entry in
            noteStore.isInboxNote(at: entry.url)
        }
    }

    private func scopedSearchResults(
        query: String,
        limit: Int,
        matching predicate: (NoteSearchIndexEntry) -> Bool
    ) -> [NoteSearchResult] {
        let scopedEntries = entries.filter(predicate)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return scopedEntries
                .sorted { $0.modifiedAt > $1.modifiedAt }
                .prefix(limit)
                .map(\.result)
        }
        return noteStore.rankedSearchResults(query: trimmedQuery, limit: limit, entries: scopedEntries)
    }

    private func recentResults(limit: Int) -> [NoteSearchResult] {
        noteStore.listRecentFiles(limit: limit).compactMap {
            entriesByPath[$0.url.standardizedFileURL.path]?.result
        }
    }
}

extension NoteStore {
    public func knownSearchRoots() -> [URL] {
        let recentDirectories = listRecentFiles(limit: 50).map { $0.url.deletingLastPathComponent() }
        return deduplicatedDirectories(preferredDirectories + recentDirectories)
    }

    @discardableResult
    public func prewarmSearchIndex(roots: [URL]? = nil) -> Int {
        indexedEntries(roots: roots).count
    }

    public func makeSearchSession() -> NoteSearchSession {
        NoteSearchSession(noteStore: self, entries: indexedEntries())
    }

    public func makeSearchSession(roots: [URL]) -> NoteSearchSession {
        NoteSearchSession(noteStore: self, entries: indexedEntries(roots: roots))
    }

    public func knownTags(limit: Int = 200) -> [String] {
        knownTags(limit: limit, roots: nil)
    }

    public func knownTags(limit: Int = 200, roots: [URL]) -> [String] {
        knownTags(limit: limit, roots: Optional(roots))
    }

    private func knownTags(limit: Int, roots: [URL]?) -> [String] {
        var counts: [String: Int] = [:]

        for entry in indexedEntries(roots: roots) {
            for tag in entry.tags {
                counts[tag, default: 0] += 1
            }
        }

        return counts
            .sorted {
                if $0.value == $1.value {
                    return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
                }
                return $0.value > $1.value
            }
            .prefix(limit)
            .map(\.key)
    }

    public func listNotes(limit: Int = 200, roots: [URL]? = nil) -> [NoteSearchResult] {
        indexedEntries(roots: roots)
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(limit)
            .map(\.result)
    }

    public func listNotesRefreshingIndex(limit: Int = 200, roots: [URL]? = nil) -> [NoteSearchResult] {
        indexedEntries(roots: roots, validatesMemorySnapshot: true)
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(limit)
            .map(\.result)
    }

    public func searchNotes(query: String, limit: Int = 30, roots: [URL]? = nil) -> [NoteSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return recentSearchResults(limit: limit)
        }

        return rankedSearchResults(
            query: trimmedQuery,
            limit: limit,
            entries: indexedEntries(roots: roots)
        )
    }

    public func searchNotes(
        query: String,
        limit: Int = 30,
        in directory: URL,
        includingDescendants: Bool = true
    ) -> [NoteSearchResult] {
        let directoryPath = directory.standardizedFileURL.path
        return scopedSearchResults(query: query, limit: limit) { entry in
            let noteDirectoryPath = entry.url.deletingLastPathComponent().standardizedFileURL.path
            return noteDirectoryPath == directoryPath
                || (includingDescendants && noteDirectoryPath.hasPrefix(directoryPath + "/"))
        }
    }

    public func searchNotes(query: String, limit: Int = 30, tagged tag: String) -> [NoteSearchResult] {
        scopedSearchResults(query: query, limit: limit) { entry in
            entry.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
        }
    }

    public func searchInboxNotes(query: String, limit: Int = 30) -> [NoteSearchResult] {
        scopedSearchResults(query: query, limit: limit) { entry in
            isInboxNote(at: entry.url)
        }
    }

    public func markSearchIndexDirty(at urls: some Sequence<URL>) {
        searchIndexLock.lock()
        dirtySearchIndexPaths.formUnion(urls.map { $0.standardizedFileURL.path })
        searchIndexRevision &+= 1
        searchIndexLock.unlock()
    }

    public func invalidateSearchIndexContents() {
        searchIndexLock.lock()
        searchIndexRequiresFullRefresh = true
        searchIndexRevision &+= 1
        searchIndexLock.unlock()
    }

    public func searchRecentNotes(query: String, limit: Int = 30) -> [NoteSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return recentSearchResults(limit: limit)
        }

        let recentPaths = Set(listRecentFiles(limit: .max).map { $0.url.standardizedFileURL.path })
        let recentEntries = indexedEntries().filter { recentPaths.contains($0.url.standardizedFileURL.path) }
        return rankedSearchResults(query: trimmedQuery, limit: limit, entries: recentEntries)
    }

    private func recentSearchResults(limit: Int) -> [NoteSearchResult] {
        listRecentFiles(limit: limit).map { note in
            let loaded = try? loadNote(at: note.url)
            return NoteSearchResult(
                url: note.url,
                title: loaded.map { displayTitle(for: note.url, loadedTitle: $0.title) } ?? note.title,
                snippet: loaded.flatMap { MarkdownEditorDocument.firstPreviewLine(in: $0.body) } ?? "",
                modifiedAt: note.modifiedAt,
                tags: loaded?.tags ?? [],
                hasAttachments: loaded.map { MarkdownEditorDocument.containsAttachmentReference(in: $0.body) } ?? false,
                thumbnailURL: loaded.flatMap { MarkdownEditorDocument.firstLocalImageURL(in: $0.body, relativeTo: note.url) }
            )
        }
    }

    fileprivate func rankedSearchResults(
        query: String,
        limit: Int,
        entries: [NoteSearchIndexEntry]
    ) -> [NoteSearchResult] {
        let loweredQuery = query.lowercased()
        var scoredResults: [(result: NoteSearchResult, score: Int)] = []

        for entry in entries {
            guard let scored = scoredMatch(for: entry, loweredQuery: loweredQuery) else { continue }
            scoredResults.append(scored)
        }

        return scoredResults
            .sorted {
                if $0.score == $1.score {
                    return $0.result.modifiedAt > $1.result.modifiedAt
                }
                return $0.score > $1.score
            }
            .prefix(limit)
            .map(\.result)
    }

    private func scopedSearchResults(
        query: String,
        limit: Int,
        matching predicate: (NoteSearchIndexEntry) -> Bool
    ) -> [NoteSearchResult] {
        let entries = indexedEntries().filter(predicate)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return entries
                .sorted { $0.modifiedAt > $1.modifiedAt }
                .prefix(limit)
                .map(\.result)
        }
        return rankedSearchResults(query: trimmedQuery, limit: limit, entries: entries)
    }

    private func scoredMatch(for entry: NoteSearchIndexEntry, loweredQuery: String) -> (result: NoteSearchResult, score: Int)? {
        let titleLower = entry.title.lowercased()
        guard titleLower.contains(loweredQuery) || entry.bodyLower.contains(loweredQuery) || entry.tagsLower.contains(where: { $0.contains(loweredQuery) }) else {
            return nil
        }

        let titleScore = titleLower.contains(loweredQuery) ? 100 : 0
        let occurrences = occurrenceCount(of: loweredQuery, in: entry.bodyLower, stoppingAt: 6)
        let bodyScore = min(occurrences * 15, 90)
        let tagScore = entry.tagsLower.contains(where: { $0 == loweredQuery }) ? 80 : (entry.tagsLower.contains(where: { $0.contains(loweredQuery) }) ? 40 : 0)
        let snippet = snippet(from: entry.body, query: loweredQuery)

        return (
            result: NoteSearchResult(
                url: entry.url,
                title: entry.title,
                snippet: snippet,
                modifiedAt: entry.modifiedAt,
                createdAt: entry.createdAt,
                tags: entry.tags,
                hasAttachments: entry.hasAttachments,
                thumbnailURL: entry.thumbnailURL
            ),
            score: titleScore + bodyScore + tagScore
        )
    }

    private func occurrenceCount(of needle: String, in haystack: String, stoppingAt limit: Int) -> Int {
        guard !needle.isEmpty, limit > 0 else { return 0 }
        var count = 0
        var searchStart = haystack.startIndex
        while searchStart < haystack.endIndex,
              let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            count += 1
            if count == limit { break }
            searchStart = range.upperBound
        }
        return count
    }

    func indexedEntries(
        roots: [URL]? = nil,
        validatesMemorySnapshot: Bool = false
    ) -> [NoteSearchIndexEntry] {
        searchIndexBuildLock.lock()
        defer { searchIndexBuildLock.unlock() }

        let searchRoots = roots ?? knownSearchRoots()
        let rootsKey = deduplicatedDirectories(searchRoots).map { $0.standardizedFileURL.path }

        searchIndexLock.lock()
        let stateRevision = searchIndexRevision
        let dirtyPaths = dirtySearchIndexPaths
        let requiresFullRefresh = searchIndexRequiresFullRefresh
        let memorySnapshot = searchIndexSnapshot?.rootsKey == rootsKey ? searchIndexSnapshot : nil
        let buildWillRead = searchIndexBuildWillReadForTesting
        searchIndexLock.unlock()

        if !validatesMemorySnapshot,
           !requiresFullRefresh,
           dirtyPaths.isEmpty,
           let memorySnapshot {
            return memorySnapshot.entries
        }

        buildWillRead?()

        let reusableSnapshot = memorySnapshot ?? readSearchIndexSnapshotFromDisk(rootsKey: rootsKey)
        if !requiresFullRefresh,
           !dirtyPaths.isEmpty,
           let reusableSnapshot {
            let snapshot = incrementallyRefreshing(
                reusableSnapshot,
                dirtyPaths: dirtyPaths,
                rootsKey: rootsKey
            )
            publishSearchIndexSnapshot(
                snapshot,
                consuming: dirtyPaths,
                fullRefresh: false,
                stateRevision: stateRevision
            )
            return snapshot.entries
        }

        var signatures: [String: NoteSearchFileSignature] = [:]
        var fileURLs: [URL] = []
        var seenPaths = Set<String>()

        for root in searchRoots {
            for fileURL in markdownFiles(in: root) {
                let standardizedURL = fileURL.standardizedFileURL
                let path = standardizedURL.path
                guard seenPaths.insert(path).inserted,
                      let signature = fileSignature(for: standardizedURL) else {
                    continue
                }
                signatures[path] = signature
                fileURLs.append(standardizedURL)
            }
        }

        if !requiresFullRefresh,
           dirtyPaths.isEmpty,
           let reusableSnapshot,
           reusableSnapshot.fileSignatures == signatures {
            publishSearchIndexSnapshot(
                reusableSnapshot,
                consuming: [],
                fullRefresh: false,
                stateRevision: stateRevision,
                writesDiskCache: false
            )
            return reusableSnapshot.entries
        }

        let reusableEntriesByPath = reusableSnapshot?.entries.reduce(into: [String: NoteSearchIndexEntry]()) {
            $0[$1.url.standardizedFileURL.path] = $1
        } ?? [:]
        let reusableSignatures = reusableSnapshot?.fileSignatures ?? [:]
        let entries = fileURLs.compactMap { fileURL -> NoteSearchIndexEntry? in
            let path = fileURL.path
            if !requiresFullRefresh,
               !dirtyPaths.contains(path),
               reusableSignatures[path] == signatures[path],
               let entry = reusableEntriesByPath[path] {
                return entry
            }
            return indexedEntry(for: fileURL, signature: signatures[path])
        }
        let snapshot = NoteSearchIndexSnapshot(
            rootsKey: rootsKey,
            fileSignatures: signatures,
            entries: entries
        )
        publishSearchIndexSnapshot(
            snapshot,
            consuming: dirtyPaths,
            fullRefresh: requiresFullRefresh,
            stateRevision: stateRevision
        )
        return entries
    }

    private func incrementallyRefreshing(
        _ reusableSnapshot: NoteSearchIndexSnapshot,
        dirtyPaths: Set<String>,
        rootsKey: [String]
    ) -> NoteSearchIndexSnapshot {
        var signatures = reusableSnapshot.fileSignatures
        var entriesByPath = reusableSnapshot.entries.reduce(into: [String: NoteSearchIndexEntry]()) {
            $0[$1.url.standardizedFileURL.path] = $1
        }

        for path in dirtyPaths.sorted() {
            signatures.removeValue(forKey: path)
            entriesByPath.removeValue(forKey: path)

            guard isSearchableMarkdownPath(path, rootsKey: rootsKey) else { continue }
            let fileURL = URL(fileURLWithPath: path).standardizedFileURL
            guard let signature = fileSignature(for: fileURL),
                  let entry = indexedEntry(for: fileURL, signature: signature) else {
                continue
            }
            signatures[path] = signature
            entriesByPath[path] = entry
        }

        let existingPaths = reusableSnapshot.entries.map { $0.url.standardizedFileURL.path }
        let existingPathSet = Set(existingPaths)
        let orderedEntries = existingPaths.compactMap { entriesByPath[$0] }
        let insertedEntries = entriesByPath
            .filter { !existingPathSet.contains($0.key) }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map(\.value)

        return NoteSearchIndexSnapshot(
            rootsKey: rootsKey,
            fileSignatures: signatures,
            entries: orderedEntries + insertedEntries
        )
    }

    private func isSearchableMarkdownPath(_ path: String, rootsKey: [String]) -> Bool {
        let fileExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        guard ["md", "markdown", "txt"].contains(fileExtension) else { return false }

        guard let rootPath = rootsKey.first(where: {
            path == $0 || $0 == "/" || path.hasPrefix($0 + "/")
        }) else {
            return false
        }

        let relativePath = String(path.dropFirst(rootPath == "/" ? 1 : rootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parentComponents = relativePath.split(separator: "/").dropLast()
        return !parentComponents.contains {
            $0.caseInsensitiveCompare(Self.attachmentDirectoryName) == .orderedSame
        }
    }

    private func publishSearchIndexSnapshot(
        _ snapshot: NoteSearchIndexSnapshot,
        consuming dirtyPaths: Set<String>,
        fullRefresh: Bool,
        stateRevision: UInt64,
        writesDiskCache: Bool = true
    ) {
        searchIndexLock.lock()
        let stateIsCurrent = searchIndexRevision == stateRevision
        if stateIsCurrent {
            searchIndexSnapshot = snapshot
            dirtySearchIndexPaths.subtract(dirtyPaths)
            if fullRefresh {
                searchIndexRequiresFullRefresh = false
            }
        }
        searchIndexLock.unlock()

        if stateIsCurrent, writesDiskCache {
            writeSearchIndexSnapshotToDisk(snapshot)
        }
    }

    func readSearchIndexSnapshotFromDisk(rootsKey: [String]) -> NoteSearchIndexSnapshot? {
        guard let data = try? Data(contentsOf: searchIndexCacheURL) else {
            return nil
        }

        do {
            let cache = try JSONDecoder().decode(NoteSearchIndexDiskCache.self, from: data)
            guard cache.schemaVersion == NoteSearchIndexDiskCache.currentSchemaVersion,
                  cache.snapshot.rootsKey == rootsKey else {
                return nil
            }
            return cache.snapshot
        } catch {
            try? fileManager.removeItem(at: searchIndexCacheURL)
            return nil
        }
    }

    func writeSearchIndexSnapshotToDisk(_ snapshot: NoteSearchIndexSnapshot) {
        let cache = NoteSearchIndexDiskCache(
            schemaVersion: NoteSearchIndexDiskCache.currentSchemaVersion,
            snapshot: snapshot
        )

        do {
            try fileManager.createDirectory(
                at: searchIndexCacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(cache)
            try data.write(to: searchIndexCacheURL, options: .atomic)
        } catch {
            try? fileManager.removeItem(at: searchIndexCacheURL)
        }
    }

    private func fileSignature(for fileURL: URL) -> NoteSearchFileSignature? {
        searchIndexSignatureReadCountForTesting += 1
        guard let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let modifiedAt = attrs[.modificationDate] as? Date else {
            return nil
        }

        let fileSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let createdAt = (attrs[.creationDate] as? Date) ?? modifiedAt
        return NoteSearchFileSignature(modifiedAt: modifiedAt, createdAt: createdAt, fileSize: fileSize)
    }

    private func indexedEntry(for fileURL: URL, signature: NoteSearchFileSignature?) -> NoteSearchIndexEntry? {
        searchIndexEntryReadCountForTesting += 1
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        let modifiedAt = signature?.modifiedAt ?? Date()
        let createdAt = signature?.createdAt ?? modifiedAt
        let note = loadedNote(from: text, at: fileURL)
        let title = displayTitle(for: fileURL, loadedTitle: note.title)
        let snippet = MarkdownEditorDocument.firstPreviewLine(in: note.body) ?? ""

        return NoteSearchIndexEntry(
            url: fileURL,
            title: title,
            body: note.body,
            bodyLower: note.body.lowercased(),
            snippet: snippet,
            modifiedAt: modifiedAt,
            createdAt: createdAt,
            tags: note.tags,
            tagsLower: note.tags.map { $0.lowercased() },
            hasAttachments: MarkdownEditorDocument.containsAttachmentReference(in: note.body),
            thumbnailURL: MarkdownEditorDocument.firstLocalImageURL(in: note.body, relativeTo: fileURL)
        )
    }

    private func snippet(from body: String, query: String) -> String {
        let lines = body.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let match = lines.first(where: { $0.lowercased().contains(query) }) {
            return MarkdownEditorDocument.previewText(fromMarkdownLine: match) ?? ""
        }

        return MarkdownEditorDocument.firstPreviewLine(in: body) ?? ""
    }
}
