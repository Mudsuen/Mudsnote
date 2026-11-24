import Foundation
import MudsnoteSharedCore

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
        filter: NoteSearchFilter,
        cancellationCheck: @Sendable () -> Bool = { false }
    ) -> [NoteSearchResult] {
        guard limit > 0, !cancellationCheck() else { return [] }
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return entries.lazy
                .filter { filter != .attachments || $0.hasAttachments }
                .sorted { $0.modifiedAt > $1.modifiedAt }
                .prefix(limit)
                .map(\.result)
        }
        return noteStore.rankedSearchResults(
            query: query,
            limit: limit,
            entries: entries,
            filter: filter,
            cancellationCheck: cancellationCheck
        ) ?? []
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

    public func searchNotes(
        query: String,
        limit: Int,
        restrictedTo notePaths: Set<String>,
        cancellationCheck: @Sendable () -> Bool
    ) -> [NoteSearchResult] {
        var scopedEntries: [NoteSearchIndexEntry] = []
        for path in notePaths {
            guard !cancellationCheck() else { return [] }
            if let entry = entriesByPath[path] { scopedEntries.append(entry) }
        }
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 0, !cancellationCheck() else { return [] }
        if trimmedQuery.isEmpty {
            return scopedEntries.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(limit).map(\.result)
        }
        return noteStore.rankedSearchResults(
            query: trimmedQuery,
            limit: limit,
            entries: scopedEntries,
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
        let inboxDirectoryPath = noteStore.preferredInboxDirectory.standardizedFileURL.path
        return scopedSearchResults(
            query: query,
            limit: limit,
            cancellationCheck: cancellationCheck
        ) { entry in
            let noteDirectoryPath = entry.url.deletingLastPathComponent().standardizedFileURL.path
            return noteDirectoryPath == inboxDirectoryPath
                || noteDirectoryPath.hasPrefix(inboxDirectoryPath + "/")
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
        return canonicalSearchRoots(preferredDirectories + recentDirectories)
    }

    @discardableResult
    public func prewarmSearchIndex(roots: [URL]? = nil) -> Int {
        indexedEntries(roots: roots).count
    }

    public func makeSearchSession() -> NoteSearchSession {
        NoteSearchSession(noteStore: self, entries: searchEligibleEntries(indexedEntries()))
    }

    public func makeSearchSession(roots: [URL]) -> NoteSearchSession {
        NoteSearchSession(noteStore: self, entries: searchEligibleEntries(indexedEntries(roots: roots)))
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
        return NoteSearchSession(noteStore: self, entries: searchEligibleEntries(entries))
    }

    public func knownTags(limit: Int = 200) -> [String] {
        knownTags(limit: limit, roots: nil)
    }

    public func knownTags(limit: Int = 200, roots: [URL]) -> [String] {
        knownTags(limit: limit, roots: Optional(roots))
    }

    private func knownTags(limit: Int, roots: [URL]?) -> [String] {
        var summaries: [String: (name: String, count: Int)] = [:]
        let includesArchived = includesArchivedNotesInSearch
        let candidateRoots = includesArchived ? [] : knownSearchRoots().map(\.standardizedFileURL)

        for entry in indexedEntries(roots: roots) {
            guard includesArchived || !isArchivedNote(at: entry.url, candidateRoots: candidateRoots) else { continue }
            var countedInNote = Set<String>()
            for tag in entry.tags {
                let key = tag.folding(
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    locale: .current
                )
                guard countedInNote.insert(key).inserted else { continue }
                if let existing = summaries[key] {
                    summaries[key] = (existing.name, existing.count + 1)
                } else {
                    summaries[key] = (tag, 1)
                }
            }
        }

        return summaries.values
            .sorted {
                if $0.count == $1.count {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.count > $1.count
            }
            .prefix(limit)
            .map(\.name)
    }

    public func listNotes(limit: Int = 200, roots: [URL]? = nil) -> [NoteSearchResult] {
        indexedEntries(roots: roots)
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(limit)
            .map(\.result)
    }

    /// Returns the last persisted search snapshot without walking the note roots.
    ///
    /// The result is intentionally not installed as the live search index because
    /// callers must treat it as a fast, possibly stale launch placeholder until a
    /// normal validating read completes.
    public func cachedNotes(limit: Int = 200, roots: [URL]? = nil) -> [NoteSearchResult]? {
        let searchRoots = canonicalSearchRoots(roots ?? knownSearchRoots())
        let rootsKey = searchRoots.map {
            $0.standardizedFileURL.path
        }

        searchIndexLock.lock()
        let memorySnapshot = searchIndexSnapshot?.rootsKey == rootsKey
            ? searchIndexSnapshot
            : nil
        searchIndexLock.unlock()

        guard let snapshot = memorySnapshot ?? {
            guard let loaded = readSearchIndexSnapshotFromDisk(rootsKey: rootsKey) else { return nil }
            searchIndexLock.lock()
            lastDiskLoadedSearchIndexSnapshot = loaded
            searchIndexLock.unlock()
            return loaded
        }() else {
            return nil
        }
        return snapshot.entries
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
            let includesArchived = includesArchivedNotesInSearch
            let candidateRoots = includesArchived ? [] : knownSearchRoots().map(\.standardizedFileURL)
            return recentSearchResults(limit: limit)
                .filter { includesArchived || !isArchivedNote(at: $0.url, candidateRoots: candidateRoots) }
        }

        return rankedSearchResults(
            query: trimmedQuery,
            limit: limit,
            entries: searchEligibleEntries(indexedEntries(roots: roots))
        )
    }

    private func searchEligibleEntries(_ entries: [NoteSearchIndexEntry]) -> [NoteSearchIndexEntry] {
        guard !includesArchivedNotesInSearch else { return entries }
        let candidateRoots = knownSearchRoots().map(\.standardizedFileURL)
        return entries.filter { !isArchivedNote(at: $0.url, candidateRoots: candidateRoots) }
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
        let inboxDirectoryPath = preferredInboxDirectory.standardizedFileURL.path
        return scopedSearchResults(query: query, limit: limit) { entry in
            let noteDirectoryPath = entry.url.deletingLastPathComponent().standardizedFileURL.path
            return noteDirectoryPath == inboxDirectoryPath
                || noteDirectoryPath.hasPrefix(inboxDirectoryPath + "/")
        }
    }

    public var currentSearchIndexRevision: UInt64 {
        searchIndexLock.lock()
        defer { searchIndexLock.unlock() }
        return searchIndexRevision
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
            let includesArchived = includesArchivedNotesInSearch
            let candidateRoots = includesArchived ? [] : knownSearchRoots().map(\.standardizedFileURL)
            return recentSearchResults(limit: limit)
                .filter { includesArchived || !isArchivedNote(at: $0.url, candidateRoots: candidateRoots) }
        }

        let recentPaths = Set(listRecentFiles(limit: .max).map { $0.url.standardizedFileURL.path })
        let recentEntries = searchEligibleEntries(indexedEntries())
            .filter { recentPaths.contains($0.url.standardizedFileURL.path) }
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
        filter: NoteSearchFilter = .all,
        cancellationCheck: @Sendable () -> Bool
    ) -> [NoteSearchResult]? {
        guard limit > 0, !cancellationCheck() else { return [] }
        let parsedQuery = NoteSearchQuery(query)
        guard !parsedQuery.terms.isEmpty else { return [] }
        let retainsEveryEntry = limit >= entries.count
        var candidates: [RankedSearchCandidate] = []
        candidates.reserveCapacity(min(limit, entries.count))

        for entry in entries {
            guard !cancellationCheck() else { return nil }
            searchIndexEntryWillMatchForTesting?()
            guard !cancellationCheck(),
                  let score = matchScore(for: entry, query: parsedQuery, filter: filter) else {
                continue
            }
            let candidate = RankedSearchCandidate(entry: entry, score: score)
            if retainsEveryEntry {
                candidates.append(candidate)
            } else if candidates.count < limit {
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
                snippet: parsedQuery.snippet(in: entry.body, fallback: entry.snippet),
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
        let entries = searchEligibleEntries(indexedEntries()).filter(predicate)
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return entries
                .sorted { $0.modifiedAt > $1.modifiedAt }
                .prefix(limit)
                .map(\.result)
        }
        return rankedSearchResults(query: trimmedQuery, limit: limit, entries: entries)
    }

    private func matchScore(for entry: NoteSearchIndexEntry, query: NoteSearchQuery,
                            filter: NoteSearchFilter) -> Int? {
        guard filter != .attachments || entry.hasAttachments else { return nil }
        var score = 0
        for term in query.terms {
            let titleMatches = filter != .body && filter != .tags && entry.titleLower.contains(term)
            let tagScore: Int
            if filter == .title || filter == .body { tagScore = 0 }
            else if entry.tagsLower.contains(term) { tagScore = 80 }
            else { tagScore = entry.tagsLower.contains { $0.contains(term) } ? 40 : 0 }
            let occurrences = filter == .title || filter == .tags ? 0
                : occurrenceCount(of: term, in: entry.bodyLower, stoppingAt: 6)
            guard titleMatches || occurrences > 0 || tagScore > 0 else { return nil }
            score += (titleMatches ? 100 : 0) + occurrences * 15 + tagScore
        }
        return score
    }

    private func occurrenceCount(of needle: String, in haystack: String, stoppingAt limit: Int) -> Int {
        guard !needle.isEmpty, limit > 0 else { return 0 }
        var count = 0
        var searchStart = haystack.startIndex
        while searchStart < haystack.endIndex,
              let range = haystack.range(of: needle, options: .literal, range: searchStart..<haystack.endIndex) {
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

    func indexedEntries(
        roots: [URL]? = nil,
        cancellationCheck: @Sendable () -> Bool
    ) -> [NoteSearchIndexEntry]? {
        cancellableIndexedEntries(
            roots: roots,
            cancellationCheck: cancellationCheck
        )
    }

    func indexedReadView(
        roots: [URL]? = nil,
        cancellationCheck: @Sendable () -> Bool
    ) -> (entries: [NoteSearchIndexEntry], rootsKey: [String], revision: UInt64)? {
        guard indexedEntries(
            roots: roots,
            cancellationCheck: cancellationCheck
        ) != nil, !cancellationCheck() else {
            return nil
        }
        let searchRoots = canonicalSearchRoots(roots ?? knownSearchRoots())
        let rootsKey = searchRoots.map {
            $0.standardizedFileURL.path
        }
        searchIndexLock.lock()
        defer { searchIndexLock.unlock() }
        guard !searchIndexRequiresFullRefresh,
              dirtySearchIndexPaths.isEmpty,
              let snapshot = searchIndexSnapshot,
              snapshot.rootsKey == rootsKey else {
            return nil
        }
        return (snapshot.entries, rootsKey, searchIndexRevision)
    }

    func isCurrentIndexedReadView(rootsKey: [String], revision: UInt64) -> Bool {
        searchIndexLock.lock()
        defer { searchIndexLock.unlock() }
        return searchIndexRevision == revision
            && !searchIndexRequiresFullRefresh
            && dirtySearchIndexPaths.isEmpty
            && searchIndexSnapshot?.rootsKey == rootsKey
    }

    private func cancellableIndexedEntries(
        roots: [URL]? = nil,
        validatesMemorySnapshot: Bool = false,
        cancellationCheck: @Sendable () -> Bool
    ) -> [NoteSearchIndexEntry]? {
        guard !cancellationCheck() else { return nil }
        let searchRoots = canonicalSearchRoots(roots ?? knownSearchRoots())
        let rootsKey = searchRoots.map { $0.standardizedFileURL.path }

        if !validatesMemorySnapshot {
            searchIndexLock.lock()
            let snapshot = !searchIndexRequiresFullRefresh && dirtySearchIndexPaths.isEmpty
                ? searchIndexSnapshot
                : nil
            searchIndexLock.unlock()
            if let snapshot {
                if snapshot.rootsKey == rootsKey {
                    return snapshot.entries
                }
                if rootsCover(parentRoots: snapshot.rootsKey, childRoots: rootsKey) {
                    return filterEntries(snapshot.entries, within: rootsKey)
                }
            }
        }

        while !searchIndexBuildLock.try() {
            guard !cancellationCheck() else { return nil }
            Thread.sleep(forTimeInterval: 0.002)
        }
        defer { searchIndexBuildLock.unlock() }

        let canonicalPreferredRootsKey = canonicalSearchRoots(preferredDirectories).map { $0.standardizedFileURL.path }
        let isSubsetOfPreferred = roots != nil
            && rootsKey != canonicalPreferredRootsKey
            && rootsCover(parentRoots: canonicalPreferredRootsKey, childRoots: rootsKey)

        for attempt in 0..<4 {
            guard !cancellationCheck() else { return nil }

            searchIndexLock.lock()
            let stateRevision = searchIndexRevision
            let dirtyPaths = dirtySearchIndexPaths
            let requiresFullRefresh = searchIndexRequiresFullRefresh
            let currentSnapshot = searchIndexSnapshot
            let memorySnapshot = currentSnapshot?.rootsKey == rootsKey ? currentSnapshot : nil
            let coveringSnapshot: NoteSearchIndexSnapshot? = (memorySnapshot == nil
                && currentSnapshot.map { rootsCover(parentRoots: $0.rootsKey, childRoots: rootsKey) } == true)
                ? currentSnapshot
                : nil
            let cachedDiskSnapshot = lastDiskLoadedSearchIndexSnapshot?.rootsKey == rootsKey
                ? lastDiskLoadedSearchIndexSnapshot
                : nil
            let buildWillRead = attempt == 0 ? searchIndexBuildWillReadForTesting : nil
            searchIndexLock.unlock()

            if !validatesMemorySnapshot,
               !requiresFullRefresh,
               dirtyPaths.isEmpty {
                if let memorySnapshot {
                    return memorySnapshot.entries
                }
                if let coveringSnapshot {
                    return filterEntries(coveringSnapshot.entries, within: rootsKey)
                }
            }

            // Reuse and refresh the parent root snapshot when querying a strict subset root
            // so single-folder searches never wipe or duplicate the shared SQLite cache.
            if !validatesMemorySnapshot,
               let coveringSnapshot,
               !requiresFullRefresh,
               !dirtyPaths.isEmpty {
                guard let incremental = incrementallyRefreshing(
                    coveringSnapshot,
                    dirtyPaths: dirtyPaths,
                    rootsKey: coveringSnapshot.rootsKey,
                    cancellationCheck: cancellationCheck
                ) else {
                    return nil
                }
                guard !cancellationCheck() else { return nil }
                if publishSearchIndexSnapshot(
                    incremental.snapshot,
                    consuming: dirtyPaths,
                    fullRefresh: false,
                    stateRevision: stateRevision,
                    incrementalChanges: (incremental.upserts, incremental.deletes)
                ) {
                    return filterEntries(incremental.snapshot.entries, within: rootsKey)
                }
                continue
            }

            buildWillRead?()
            guard !cancellationCheck() else { return nil }

            let reusableSnapshot = memorySnapshot ?? cachedDiskSnapshot ?? readSearchIndexSnapshotFromDisk(rootsKey: rootsKey)
            let shouldPersistToSharedCache = !isSubsetOfPreferred
            if !requiresFullRefresh,
               !dirtyPaths.isEmpty,
               let reusableSnapshot {
                guard let incremental = incrementallyRefreshing(
                    reusableSnapshot,
                    dirtyPaths: dirtyPaths,
                    rootsKey: rootsKey,
                    cancellationCheck: cancellationCheck
                ) else {
                    return nil
                }
                guard !cancellationCheck() else { return nil }
                if !shouldPersistToSharedCache {
                    return incremental.snapshot.entries
                }
                if publishSearchIndexSnapshot(
                    incremental.snapshot,
                    consuming: dirtyPaths,
                    fullRefresh: false,
                    stateRevision: stateRevision,
                    incrementalChanges: (incremental.upserts, incremental.deletes)
                ) {
                    return incremental.snapshot.entries
                }
                continue
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
               reusableSnapshot.entries.allSatisfy(\.isContentIndexed),
               reusableSnapshot.fileSignatures == signatures {
                if !shouldPersistToSharedCache {
                    return reusableSnapshot.entries
                }
                if publishSearchIndexSnapshot(
                    reusableSnapshot,
                    consuming: [],
                    fullRefresh: false,
                    stateRevision: stateRevision,
                    writesDiskCache: false
                ) {
                    return reusableSnapshot.entries
                }
                continue
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
                   let entry = reusableEntriesByPath[path],
                   entry.isContentIndexed {
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
            if !shouldPersistToSharedCache {
                return entries
            }
            let snapshot = NoteSearchIndexSnapshot(
                rootsKey: rootsKey,
                fileSignatures: signatures,
                entries: entries
            )
            if publishSearchIndexSnapshot(
                snapshot,
                consuming: dirtyPaths,
                fullRefresh: requiresFullRefresh,
                stateRevision: stateRevision
            ) {
                return entries
            }
        }
        return nil
    }

    private func rootsCover(parentRoots: [String], childRoots: [String]) -> Bool {
        guard !parentRoots.isEmpty, !childRoots.isEmpty else { return false }
        return childRoots.allSatisfy { child in
            parentRoots.contains { parent in
                child == parent || child.hasPrefix(parent + "/")
            }
        }
    }

    private func filterEntries(_ entries: [NoteSearchIndexEntry], within rootsKey: [String]) -> [NoteSearchIndexEntry] {
        entries.filter { entry in
            let path = entry.url.standardizedFileURL.path
            return rootsKey.contains { root in
                path == root || path.hasPrefix(root + "/")
            }
        }
    }

    func canonicalSearchRoots(_ roots: [URL]) -> [URL] {
        let standardized = deduplicatedDirectories(roots)
        return standardized.filter { candidate in
            let candidatePath = candidate.standardizedFileURL.path
            return !standardized.contains { other in
                let otherPath = other.standardizedFileURL.path
                guard otherPath != candidatePath else { return false }
                return otherPath == "/"
                    || candidatePath.hasPrefix(otherPath + "/")
            }
        }
    }

    private func incrementallyRefreshing(
        _ reusableSnapshot: NoteSearchIndexSnapshot,
        dirtyPaths: Set<String>,
        rootsKey: [String],
        cancellationCheck: @Sendable () -> Bool
    ) -> (snapshot: NoteSearchIndexSnapshot, upserts: [NoteSearchIndexEntry], deletes: [String])? {
        var signatures = reusableSnapshot.fileSignatures
        var entriesByPath = reusableSnapshot.entries.reduce(into: [String: NoteSearchIndexEntry]()) {
            $0[$1.url.standardizedFileURL.path] = $1
        }
        var upserts: [NoteSearchIndexEntry] = []
        var deletes: [String] = []

        for path in dirtyPaths.sorted() {
            guard !cancellationCheck() else { return nil }
            signatures.removeValue(forKey: path)
            entriesByPath.removeValue(forKey: path)

            guard isSearchableMarkdownPath(path, rootsKey: rootsKey) else {
                deletes.append(path)
                continue
            }
            let fileURL = URL(fileURLWithPath: path).standardizedFileURL
            guard let signature = fileSignature(for: fileURL),
                  let entry = indexedEntry(
                    for: fileURL,
                    signature: signature,
                    cancellationCheck: cancellationCheck
                  ) else {
                deletes.append(path)
                continue
            }
            signatures[path] = signature
            entriesByPath[path] = entry
            upserts.append(entry)
        }

        let existingPaths = reusableSnapshot.entries.map { $0.url.standardizedFileURL.path }
        let existingPathSet = Set(existingPaths)
        let orderedEntries = existingPaths.compactMap { entriesByPath[$0] }
        let insertedEntries = entriesByPath
            .filter { !existingPathSet.contains($0.key) }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map(\.value)

        let snapshot = NoteSearchIndexSnapshot(
            rootsKey: rootsKey,
            fileSignatures: signatures,
            entries: orderedEntries + insertedEntries
        )
        return (snapshot, upserts, deletes)
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

    @discardableResult
    private func publishSearchIndexSnapshot(
        _ snapshot: NoteSearchIndexSnapshot,
        consuming dirtyPaths: Set<String>,
        fullRefresh: Bool,
        stateRevision: UInt64,
        writesDiskCache: Bool = true,
        incrementalChanges: (upserts: [NoteSearchIndexEntry], deletes: [String])? = nil
    ) -> Bool {
        searchIndexLock.lock()
        let stateIsCurrent = searchIndexRevision == stateRevision
        if stateIsCurrent {
            searchIndexSnapshot = snapshot
            lastDiskLoadedSearchIndexSnapshot = nil
            dirtySearchIndexPaths.subtract(dirtyPaths)
            if fullRefresh {
                searchIndexRequiresFullRefresh = false
            }
        }
        searchIndexLock.unlock()

        if stateIsCurrent {
            noteLinkIndexLock.lock()
            cachedNoteLinkIndex = nil
            noteLinkIndexLock.unlock()
        }

        if stateIsCurrent, writesDiskCache {
            if let incrementalChanges,
               estimatedDiskCacheSize(for: snapshot) <= Self.maximumSearchIndexDiskCacheSize {
                let encoder = JSONEncoder()
                let upsertRecords = incrementalChanges.upserts.map { entry in
                    sqliteRecord(
                        for: entry,
                        signature: snapshot.fileSignatures[entry.url.standardizedFileURL.path],
                        encoder: encoder
                    )
                }
                let updated = searchIndexSQLite.applyIncrementalChanges(
                    rootsKey: snapshot.rootsKey,
                    upserts: upsertRecords,
                    deletes: incrementalChanges.deletes,
                    schemaVersion: NoteSearchIndexDiskCache.currentSchemaVersion
                )
                if !updated {
                    writeSearchIndexSnapshotToDisk(snapshot)
                }
            } else {
                writeSearchIndexSnapshotToDisk(snapshot)
            }
        }
        return stateIsCurrent
    }

    private struct SQLiteSearchEntryExtra: Codable {
        let linkTargets: [NoteLinkTarget]
        let hasAttachments: Bool
        let thumbnailPath: String?
        let isContentIndexed: Bool
    }

    private func sqliteRecord(
        for entry: NoteSearchIndexEntry,
        signature: NoteSearchFileSignature?,
        encoder: JSONEncoder
    ) -> SQLiteNoteIndexRecord {
        let extra = SQLiteSearchEntryExtra(
            linkTargets: entry.linkTargets,
            hasAttachments: entry.hasAttachments,
            thumbnailPath: entry.thumbnailURL?.standardizedFileURL.path,
            isContentIndexed: entry.isContentIndexed
        )
        let extraData = try? encoder.encode(extra)
        return SQLiteNoteIndexRecord(
            path: entry.url.standardizedFileURL.path,
            modifiedAt: (signature?.modifiedAt ?? entry.modifiedAt).timeIntervalSinceReferenceDate,
            createdAt: (signature?.createdAt ?? entry.createdAt).timeIntervalSinceReferenceDate,
            fileSize: signature?.fileSize ?? UInt64(entry.body.utf8.count),
            title: entry.title,
            body: entry.body,
            snippet: entry.snippet,
            tags: entry.tags,
            extraJSON: extraData
        )
    }

    func readSearchIndexSnapshotFromDisk(rootsKey: [String]) -> NoteSearchIndexSnapshot? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: searchIndexCacheURL.path),
              let cacheSize = (attributes[.size] as? NSNumber)?.uint64Value,
              cacheSize <= Self.maximumSearchIndexDiskCacheSize else {
            searchIndexSQLite.removeDatabaseFiles()
            return nil
        }

        guard let records = searchIndexSQLite.loadAll(
            expectedRootsKey: rootsKey,
            expectedSchemaVersion: NoteSearchIndexDiskCache.currentSchemaVersion
        ) else {
            return nil
        }

        let decoder = JSONDecoder()
        var signatures: [String: NoteSearchFileSignature] = [:]
        var entries: [NoteSearchIndexEntry] = []
        signatures.reserveCapacity(records.count)
        entries.reserveCapacity(records.count)

        for record in records {
            let fileURL = URL(fileURLWithPath: record.path).standardizedFileURL
            let modifiedAt = Date(timeIntervalSinceReferenceDate: record.modifiedAt)
            let createdAt = Date(timeIntervalSinceReferenceDate: record.createdAt)
            signatures[fileURL.path] = NoteSearchFileSignature(
                modifiedAt: modifiedAt,
                createdAt: createdAt,
                fileSize: record.fileSize
            )
            let extra = record.extraJSON.flatMap { try? decoder.decode(SQLiteSearchEntryExtra.self, from: $0) }
            let entry = NoteSearchIndexEntry(
                url: fileURL,
                title: record.title,
                titleLower: NoteSearchQuery.normalized(record.title),
                body: record.body,
                bodyLower: NoteSearchQuery.normalized(record.body),
                snippet: record.snippet,
                modifiedAt: modifiedAt,
                createdAt: createdAt,
                tags: record.tags,
                tagsLower: record.tags.map(NoteSearchQuery.normalized),
                linkTargets: extra?.linkTargets ?? [],
                hasAttachments: extra?.hasAttachments ?? false,
                thumbnailURL: extra?.thumbnailPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
                isContentIndexed: extra?.isContentIndexed ?? true
            )
            entries.append(entry)
        }

        return NoteSearchIndexSnapshot(
            rootsKey: rootsKey,
            fileSignatures: signatures,
            entries: entries
        )
    }

    func writeSearchIndexSnapshotToDisk(_ snapshot: NoteSearchIndexSnapshot) {
        guard estimatedDiskCacheSize(for: snapshot) <= Self.maximumSearchIndexDiskCacheSize else {
            searchIndexSQLite.removeDatabaseFiles()
            return
        }

        let encoder = JSONEncoder()
        let records = snapshot.entries.map { entry in
            sqliteRecord(
                for: entry,
                signature: snapshot.fileSignatures[entry.url.standardizedFileURL.path],
                encoder: encoder
            )
        }
        let wrote = searchIndexSQLite.replaceAll(
            rootsKey: snapshot.rootsKey,
            records: records,
            schemaVersion: NoteSearchIndexDiskCache.currentSchemaVersion
        )
        if wrote {
            let legacyJSON = appSupportDirectory
                .appendingPathComponent("SearchIndex", isDirectory: true)
                .appendingPathComponent("index-v1.json", isDirectory: false)
            if fileManager.fileExists(atPath: legacyJSON.path) {
                try? fileManager.removeItem(at: legacyJSON)
            }
        } else {
            searchIndexSQLite.removeDatabaseFiles()
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
            size += UInt64(entry.linkTargets.reduce(0) {
                $0 + $1.value.utf8.count + 8
            })
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
        guard !cancellationCheck(), let signature else {
            return nil
        }
        guard isLocallyAvailableForSearch(fileURL) else {
            return unavailableSearchIndexEntry(for: fileURL, signature: signature)
        }
        guard signature.fileSize <= Self.maximumSearchIndexedFileSize else { return nil }
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
            titleLower: NoteSearchQuery.normalized(title),
            body: note.body,
            bodyLower: NoteSearchQuery.normalized(note.body),
            snippet: snippet,
            modifiedAt: modifiedAt,
            createdAt: createdAt,
            tags: note.tags,
            tagsLower: note.tags.map(NoteSearchQuery.normalized),
            linkTargets: noteLinkTargets(
                in: note.body,
                cancellationCheck: cancellationCheck
            ),
            hasAttachments: MarkdownEditorDocument.containsAttachmentReference(in: note.body),
            thumbnailURL: MarkdownEditorDocument.firstLocalImageURL(in: note.body, relativeTo: fileURL),
            isContentIndexed: true
        )
    }

    private func unavailableSearchIndexEntry(
        for fileURL: URL,
        signature: NoteSearchFileSignature
    ) -> NoteSearchIndexEntry {
        NoteSearchIndexEntry(
            url: fileURL,
            title: displayTitle(for: fileURL, loadedTitle: ""),
            titleLower: NoteSearchQuery.normalized(displayTitle(for: fileURL, loadedTitle: "")),
            body: "",
            bodyLower: "",
            snippet: "",
            modifiedAt: signature.modifiedAt,
            createdAt: signature.createdAt,
            tags: [],
            tagsLower: [],
            linkTargets: [],
            hasAttachments: false,
            thumbnailURL: nil,
            isContentIndexed: false
        )
    }

    private func isLocallyAvailableForSearch(_ fileURL: URL) -> Bool {
        if let availability = searchIndexEntryContentAvailabilityForTesting {
            return availability(fileURL)
        }
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

}
