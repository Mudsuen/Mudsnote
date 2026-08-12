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
        searchNotes(query: query, limit: limit, cancellationCheck: { false })
    }

    public func searchNotes(
        query: String,
        limit: Int = 30,
        cancellationCheck: @Sendable () -> Bool
    ) -> [NoteSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return recentResults(limit: limit) }
        return noteStore.rankedSearchResults(
            query: trimmedQuery,
            limit: limit,
            entries: entries,
            cancellationCheck: cancellationCheck
        ) ?? []
    }

    public func searchRecentNotes(query: String, limit: Int = 30) -> [NoteSearchResult] {
        searchRecentNotes(query: query, limit: limit, cancellationCheck: { false })
    }

    public func searchRecentNotes(
        query: String,
        limit: Int = 30,
        cancellationCheck: @Sendable () -> Bool
    ) -> [NoteSearchResult] {
        let recentPaths = Set(noteStore.listRecentFiles(limit: .max).map { $0.url.standardizedFileURL.path })
        var recentEntries: [NoteSearchIndexEntry] = []
        for entry in entries {
            guard !cancellationCheck() else { return [] }
            if recentPaths.contains(entry.url.standardizedFileURL.path) {
                recentEntries.append(entry)
            }
        }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return recentResults(limit: limit) }
        return noteStore.rankedSearchResults(
            query: trimmedQuery,
            limit: limit,
            entries: recentEntries,
            cancellationCheck: cancellationCheck
        ) ?? []
    }

    public func searchNotes(
        query: String,
        limit: Int = 30,
        in directory: URL,
        includingDescendants: Bool = true
    ) -> [NoteSearchResult] {
        searchNotes(
            query: query,
            limit: limit,
            in: directory,
            includingDescendants: includingDescendants,
            cancellationCheck: { false }
        )
    }

    public func searchNotes(
        query: String,
        limit: Int = 30,
        in directory: URL,
        includingDescendants: Bool = true,
        cancellationCheck: @Sendable () -> Bool
    ) -> [NoteSearchResult] {
        let directoryPath = directory.standardizedFileURL.path
        return scopedSearchResults(
            query: query,
            limit: limit,
            cancellationCheck: cancellationCheck
        ) { entry in
            let noteDirectoryPath = entry.url.deletingLastPathComponent().standardizedFileURL.path
            return noteDirectoryPath == directoryPath
                || (includingDescendants && noteDirectoryPath.hasPrefix(directoryPath + "/"))
        }
    }

    public func searchNotes(query: String, limit: Int = 30, tagged tag: String) -> [NoteSearchResult] {
        searchNotes(
            query: query,
            limit: limit,
            tagged: tag,
            cancellationCheck: { false }
        )
    }

    public func searchNotes(
        query: String,
        limit: Int = 30,
        tagged tag: String,
        cancellationCheck: @Sendable () -> Bool
    ) -> [NoteSearchResult] {
        scopedSearchResults(
            query: query,
            limit: limit,
            cancellationCheck: cancellationCheck
        ) { entry in
            entry.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
        }
    }

    public func searchInboxNotes(query: String, limit: Int = 30) -> [NoteSearchResult] {
        searchInboxNotes(query: query, limit: limit, cancellationCheck: { false })
    }

    public func searchInboxNotes(
        query: String,
        limit: Int = 30,
        cancellationCheck: @Sendable () -> Bool
    ) -> [NoteSearchResult] {
        scopedSearchResults(
            query: query,
            limit: limit,
            cancellationCheck: cancellationCheck
        ) { entry in
            noteStore.isInboxNote(at: entry.url)
        }
    }

    private func scopedSearchResults(
        query: String,
        limit: Int,
        cancellationCheck: @Sendable () -> Bool,
        matching predicate: (NoteSearchIndexEntry) -> Bool
    ) -> [NoteSearchResult] {
        var scopedEntries: [NoteSearchIndexEntry] = []
        for entry in entries {
            guard !cancellationCheck() else { return [] }
            if predicate(entry) {
                scopedEntries.append(entry)
            }
        }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return scopedEntries
                .sorted { $0.modifiedAt > $1.modifiedAt }
                .prefix(limit)
                .map(\.result)
        }
        return noteStore.rankedSearchResults(
            query: trimmedQuery,
            limit: limit,
            entries: scopedEntries,
            cancellationCheck: cancellationCheck
        ) ?? []
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

    public func makeSearchSession(
        roots: [URL],
        cancellationCheck: @Sendable () -> Bool
    ) -> NoteSearchSession? {
        guard let entries = cancellableIndexedEntries(
            roots: roots,
            cancellationCheck: cancellationCheck
        ) else {
            return nil
        }
        return NoteSearchSession(noteStore: self, entries: entries)
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
        rankedSearchResults(
            query: query,
            limit: limit,
            entries: entries,
            cancellationCheck: { false }
        ) ?? []
    }

    private struct RankedSearchCandidate {
        let entry: NoteSearchIndexEntry
        let score: Int
    }

    fileprivate func rankedSearchResults(
        query: String,
        limit: Int,
        entries: [NoteSearchIndexEntry],
        cancellationCheck: @Sendable () -> Bool
    ) -> [NoteSearchResult]? {
        guard limit > 0, !cancellationCheck() else { return [] }
        let loweredQuery = query.lowercased()
        var candidates: [RankedSearchCandidate] = []
        candidates.reserveCapacity(min(limit, entries.count))

        for entry in entries {
            guard !cancellationCheck() else { return nil }
            searchIndexEntryWillMatchForTesting?()
            guard !cancellationCheck(),
                  let score = matchScore(for: entry, loweredQuery: loweredQuery) else {
                continue
            }
            let candidate = RankedSearchCandidate(entry: entry, score: score)
            if candidates.count < limit {
                candidates.append(candidate)
                siftWorstCandidateUp(in: &candidates, from: candidates.count - 1)
            } else if isHigherRanked(candidate, than: candidates[0]) {
                candidates[0] = candidate
                siftWorstCandidateDown(in: &candidates, from: 0)
            }
        }

        candidates.sort { isHigherRanked($0, than: $1) }
        var results: [NoteSearchResult] = []
        results.reserveCapacity(candidates.count)
        for candidate in candidates {
            guard !cancellationCheck() else { return nil }
            let entry = candidate.entry
            results.append(NoteSearchResult(
                url: entry.url,
                title: entry.title,
                snippet: snippet(from: entry.body, query: loweredQuery),
                modifiedAt: entry.modifiedAt,
                createdAt: entry.createdAt,
                tags: entry.tags,
                hasAttachments: entry.hasAttachments,
                thumbnailURL: entry.thumbnailURL
            ))
        }
        return results
    }

    private func isHigherRanked(
        _ lhs: RankedSearchCandidate,
        than rhs: RankedSearchCandidate
    ) -> Bool {
        if lhs.score == rhs.score {
            return lhs.entry.modifiedAt > rhs.entry.modifiedAt
        }
        return lhs.score > rhs.score
    }

    private func isWorseRanked(
        _ lhs: RankedSearchCandidate,
        than rhs: RankedSearchCandidate
    ) -> Bool {
        isHigherRanked(rhs, than: lhs)
    }

    private func siftWorstCandidateUp(
        in heap: inout [RankedSearchCandidate],
        from startIndex: Int
    ) {
        var index = startIndex
        while index > 0 {
            let parent = (index - 1) / 2
            guard isWorseRanked(heap[index], than: heap[parent]) else { return }
            heap.swapAt(index, parent)
            index = parent
        }
    }

    private func siftWorstCandidateDown(
        in heap: inout [RankedSearchCandidate],
        from startIndex: Int
    ) {
        var index = startIndex
        while true {
            let left = (index * 2) + 1
            guard left < heap.count else { return }
            let right = left + 1
            var worseChild = left
            if right < heap.count,
               isWorseRanked(heap[right], than: heap[left]) {
                worseChild = right
            }
            guard isWorseRanked(heap[worseChild], than: heap[index]) else { return }
            heap.swapAt(index, worseChild)
            index = worseChild
        }
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

    private func matchScore(for entry: NoteSearchIndexEntry, loweredQuery: String) -> Int? {
        let titleLower = entry.title.lowercased()
        guard titleLower.contains(loweredQuery) || entry.bodyLower.contains(loweredQuery) || entry.tagsLower.contains(where: { $0.contains(loweredQuery) }) else {
            return nil
        }

        let titleScore = titleLower.contains(loweredQuery) ? 100 : 0
        let occurrences = occurrenceCount(of: loweredQuery, in: entry.bodyLower, stoppingAt: 6)
        let bodyScore = min(occurrences * 15, 90)
        let tagScore = entry.tagsLower.contains(where: { $0 == loweredQuery }) ? 80 : (entry.tagsLower.contains(where: { $0.contains(loweredQuery) }) ? 40 : 0)
        return titleScore + bodyScore + tagScore
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
        cancellableIndexedEntries(
            roots: roots,
            validatesMemorySnapshot: validatesMemorySnapshot,
            cancellationCheck: { false }
        ) ?? []
    }

    private func cancellableIndexedEntries(
        roots: [URL]? = nil,
        validatesMemorySnapshot: Bool = false,
        cancellationCheck: @Sendable () -> Bool
    ) -> [NoteSearchIndexEntry]? {
        guard !cancellationCheck() else { return nil }
        let searchRoots = roots ?? knownSearchRoots()
        let rootsKey = deduplicatedDirectories(searchRoots).map { $0.standardizedFileURL.path }

        if !validatesMemorySnapshot {
            searchIndexLock.lock()
            let cleanSnapshot = !searchIndexRequiresFullRefresh
                && dirtySearchIndexPaths.isEmpty
                && searchIndexSnapshot?.rootsKey == rootsKey
                ? searchIndexSnapshot
                : nil
            searchIndexLock.unlock()
            if let cleanSnapshot {
                return cleanSnapshot.entries
            }
        }

        while !searchIndexBuildLock.try() {
            guard !cancellationCheck() else { return nil }
            Thread.sleep(forTimeInterval: 0.002)
        }
        defer { searchIndexBuildLock.unlock() }
        guard !cancellationCheck() else { return nil }

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
        guard !cancellationCheck() else { return nil }

        let reusableSnapshot = memorySnapshot ?? readSearchIndexSnapshotFromDisk(rootsKey: rootsKey)
        if !requiresFullRefresh,
           !dirtyPaths.isEmpty,
           let reusableSnapshot {
            guard let snapshot = incrementallyRefreshing(
                reusableSnapshot,
                dirtyPaths: dirtyPaths,
                rootsKey: rootsKey,
                cancellationCheck: cancellationCheck
            ) else {
                return nil
            }
            guard !cancellationCheck() else { return nil }
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
            guard let markdownURLs = markdownFiles(
                in: root,
                cancellationCheck: cancellationCheck
            ) else {
                return nil
            }
            for fileURL in markdownURLs {
                guard !cancellationCheck() else { return nil }
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
        var entries: [NoteSearchIndexEntry] = []
        entries.reserveCapacity(fileURLs.count)
        for fileURL in fileURLs {
            guard !cancellationCheck() else { return nil }
            let path = fileURL.path
            if !requiresFullRefresh,
               !dirtyPaths.contains(path),
               reusableSignatures[path] == signatures[path],
               let entry = reusableEntriesByPath[path] {
                entries.append(entry)
                continue
            }
            if let entry = indexedEntry(
                for: fileURL,
                signature: signatures[path],
                cancellationCheck: cancellationCheck
            ) {
                entries.append(entry)
            }
            guard !cancellationCheck() else { return nil }
        }
        guard !cancellationCheck() else { return nil }
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
        rootsKey: [String],
        cancellationCheck: @Sendable () -> Bool
    ) -> NoteSearchIndexSnapshot? {
        var signatures = reusableSnapshot.fileSignatures
        var entriesByPath = reusableSnapshot.entries.reduce(into: [String: NoteSearchIndexEntry]()) {
            $0[$1.url.standardizedFileURL.path] = $1
        }

        for path in dirtyPaths.sorted() {
            guard !cancellationCheck() else { return nil }
            signatures.removeValue(forKey: path)
            entriesByPath.removeValue(forKey: path)

            guard isSearchableMarkdownPath(path, rootsKey: rootsKey) else { continue }
            let fileURL = URL(fileURLWithPath: path).standardizedFileURL
            guard let signature = fileSignature(for: fileURL),
                  let entry = indexedEntry(
                    for: fileURL,
                    signature: signature,
                    cancellationCheck: cancellationCheck
                  ) else {
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
        guard let attributes = try? fileManager.attributesOfItem(atPath: searchIndexCacheURL.path),
              let cacheSize = (attributes[.size] as? NSNumber)?.uint64Value,
              cacheSize <= Self.maximumSearchIndexDiskCacheSize else {
            try? fileManager.removeItem(at: searchIndexCacheURL)
            return nil
        }
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
        guard estimatedDiskCacheSize(for: snapshot) <= Self.maximumSearchIndexDiskCacheSize else {
            try? fileManager.removeItem(at: searchIndexCacheURL)
            return
        }
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

    private func estimatedDiskCacheSize(for snapshot: NoteSearchIndexSnapshot) -> UInt64 {
        var size: UInt64 = 0
        for entry in snapshot.entries {
            size += UInt64(entry.url.path.utf8.count)
            size += UInt64(entry.title.utf8.count)
            size += UInt64(entry.body.utf8.count)
            size += UInt64(entry.bodyLower.utf8.count)
            size += UInt64(entry.snippet.utf8.count)
            size += UInt64(entry.tags.reduce(0) { $0 + $1.utf8.count })
            size += 256
            if size > Self.maximumSearchIndexDiskCacheSize {
                return size
            }
        }
        return size
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

    private func indexedEntry(
        for fileURL: URL,
        signature: NoteSearchFileSignature?,
        cancellationCheck: @Sendable () -> Bool = { false }
    ) -> NoteSearchIndexEntry? {
        guard !cancellationCheck(),
              let signature,
              signature.fileSize <= Self.maximumSearchIndexedFileSize,
              isLocallyAvailableForSearch(fileURL) else {
            return nil
        }
        searchIndexEntryReadCountForTesting += 1
        searchIndexEntryWillReadForTesting?()
        guard !cancellationCheck(),
              let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
              data.count <= Self.maximumSearchIndexedFileSize,
              let text = String(data: data, encoding: .utf8),
              !cancellationCheck() else {
            return nil
        }

        let modifiedAt = signature.modifiedAt
        let createdAt = signature.createdAt
        let note = loadedNote(from: text, at: fileURL)
        guard !cancellationCheck() else { return nil }
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

    private func isLocallyAvailableForSearch(_ fileURL: URL) -> Bool {
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        guard let values = try? fileURL.resourceValues(forKeys: keys),
              values.isUbiquitousItem == true else {
            return true
        }
        return values.ubiquitousItemDownloadingStatus == .current
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
