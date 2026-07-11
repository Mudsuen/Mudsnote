import Foundation

extension NoteStore {
    public func knownSearchRoots() -> [URL] {
        let recentDirectories = listRecentFiles(limit: 50).map { $0.url.deletingLastPathComponent() }
        return deduplicatedDirectories(preferredDirectories + recentDirectories)
    }

    @discardableResult
    public func prewarmSearchIndex(roots: [URL]? = nil) -> Int {
        indexedEntries(roots: roots).count
    }

    public func knownTags(limit: Int = 200) -> [String] {
        var counts: [String: Int] = [:]

        for entry in indexedEntries() {
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

    public func searchNotes(query: String, limit: Int = 30, in directory: URL) -> [NoteSearchResult] {
        let directoryPath = directory.standardizedFileURL.path
        return scopedSearchResults(query: query, limit: limit) { entry in
            let noteDirectoryPath = entry.url.deletingLastPathComponent().standardizedFileURL.path
            return noteDirectoryPath == directoryPath || noteDirectoryPath.hasPrefix(directoryPath + "/")
        }
    }

    public func searchNotes(query: String, limit: Int = 30, tagged tag: String) -> [NoteSearchResult] {
        scopedSearchResults(query: query, limit: limit) { entry in
            entry.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
        }
    }

    public func searchInboxNotes(query: String, limit: Int = 30) -> [NoteSearchResult] {
        scopedSearchResults(query: query, limit: limit) { entry in
            entry.url.lastPathComponent.localizedCaseInsensitiveCompare("Inbox.md") == .orderedSame
                || entry.title.localizedCaseInsensitiveContains("Inbox")
        }
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

    private func rankedSearchResults(
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
        let occurrences = max(entry.bodyLower.components(separatedBy: loweredQuery).count - 1, 0)
        let bodyScore = min(occurrences * 15, 90)
        let tagScore = entry.tagsLower.contains(where: { $0 == loweredQuery }) ? 80 : (entry.tagsLower.contains(where: { $0.contains(loweredQuery) }) ? 40 : 0)
        let snippet = snippet(from: entry.body, query: loweredQuery)

        return (
            result: NoteSearchResult(
                url: entry.url,
                title: entry.title,
                snippet: snippet,
                modifiedAt: entry.modifiedAt,
                tags: entry.tags,
                hasAttachments: entry.hasAttachments,
                thumbnailURL: entry.thumbnailURL
            ),
            score: titleScore + bodyScore + tagScore
        )
    }

    private func indexedEntries(roots: [URL]? = nil) -> [NoteSearchIndexEntry] {
        searchIndexLock.lock()
        defer { searchIndexLock.unlock() }

        let searchRoots = roots ?? knownSearchRoots()
        let rootsKey = deduplicatedDirectories(searchRoots).map { $0.standardizedFileURL.path }
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

        let reusableSnapshot: NoteSearchIndexSnapshot?
        if let snapshot = searchIndexSnapshot, snapshot.rootsKey == rootsKey {
            reusableSnapshot = snapshot
        } else {
            reusableSnapshot = readSearchIndexSnapshotFromDisk(rootsKey: rootsKey)
        }

        if let reusableSnapshot, reusableSnapshot.fileSignatures == signatures {
            searchIndexSnapshot = reusableSnapshot
            return reusableSnapshot.entries
        }

        let reusableEntriesByPath = reusableSnapshot?.entries.reduce(into: [String: NoteSearchIndexEntry]()) {
            $0[$1.url.standardizedFileURL.path] = $1
        } ?? [:]
        let reusableSignatures = reusableSnapshot?.fileSignatures ?? [:]
        let entries = fileURLs.compactMap { fileURL -> NoteSearchIndexEntry? in
            let path = fileURL.path
            if reusableSignatures[path] == signatures[path], let entry = reusableEntriesByPath[path] {
                return entry
            }
            return indexedEntry(for: fileURL, signature: signatures[path])
        }
        let snapshot = NoteSearchIndexSnapshot(
            rootsKey: rootsKey,
            fileSignatures: signatures,
            entries: entries
        )
        searchIndexSnapshot = snapshot
        writeSearchIndexSnapshotToDisk(snapshot)
        return entries
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
        guard let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
              let modifiedAt = attrs[.modificationDate] as? Date else {
            return nil
        }

        let fileSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        return NoteSearchFileSignature(modifiedAt: modifiedAt, fileSize: fileSize)
    }

    private func indexedEntry(for fileURL: URL, signature: NoteSearchFileSignature?) -> NoteSearchIndexEntry? {
        searchIndexEntryReadCountForTesting += 1
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return nil
        }

        let modifiedAt = signature?.modifiedAt ?? Date()
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
