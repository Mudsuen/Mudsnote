import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

extension LibraryWindowController {
    func reloadNotes(
        selecting preferredURL: URL? = nil,
        loadFirstIfNeeded: Bool,
        allNotesSnapshot: [NoteSearchResult]? = nil,
        sourceCountIndex: LibrarySourceCountIndex? = nil,
        sourceRecentCount: Int? = nil,
        refreshCounts: Bool = true,
        mutationAnimation: LibraryNoteMutationAnimation? = nil
    ) {
        cancelSourceSnapshotValidation()
        cancelActiveSearchResultReload()
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let allNotes = allNotesSnapshot ?? sourceCountSnapshot
        searchScopeControl.isHidden = query.isEmpty
        let previousRows = listRows
        notes = query.isEmpty
            ? notesForSelectedScope(limit: Self.noteListResultLimit, allNotes: allNotes)
            : searchResultsForSelectedScope(query: query, limit: Self.noteListResultLimit)
        listRows = buildGroupedRows(for: notes, preservesInputOrder: !query.isEmpty)
        updateNoteListHeader(query: query)

        suppressSelectionChanges = true
        reloadNoteBrowserData(animation: mutationAnimation, previousRows: previousRows)
        updateNoteListEmptyState(query: query)

        let preferredPath = preferredURL?.standardizedFileURL.path
        var noteToLoad: NoteSearchResult?
        if let preferredPath,
           let row = rowIndex(for: preferredPath) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            noteToLoad = note(at: row)
        } else if loadFirstIfNeeded,
                  let firstNoteRow = listRows.firstIndex(where: { $0.note != nil }) {
            tableView.selectRowIndexes(IndexSet(integer: firstNoteRow), byExtendingSelection: false)
            noteToLoad = note(at: firstNoteRow)
        } else {
            tableView.deselectAll(nil)
        }

        suppressSelectionChanges = false
        synchronizeGallerySelectionFromTable()
        stabilizeVisualQASelectionIfNeeded()

        if loadFirstIfNeeded, let noteToLoad {
            load(note: noteToLoad)
        }
        if refreshCounts {
            sourceCountSnapshot = allNotes
            rebuildSourceRows(includeTags: sourceTagsLoaded)
            refreshSourceCounts(
                using: allNotes,
                countIndex: sourceCountIndex,
                recentCount: sourceRecentCount
            )
        }
        refreshSourceSelection()
        updateToolbarActionState()
    }

    func reloadNotesForNavigation(
        selecting preferredURL: URL? = nil,
        loadFirstIfNeeded: Bool
    ) {
        reloadNotes(
            selecting: preferredURL,
            loadFirstIfNeeded: loadFirstIfNeeded,
            refreshCounts: false
        )
    }

    func scheduleSourceSnapshotValidation(loadFirstIfNeeded: Bool) {
        sourceSnapshotValidationTask?.cancel()
        sourceSnapshotValidationGeneration += 1
        let generation = sourceSnapshotValidationGeneration
        let scope = selectedScope
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteStore = noteStore
        let snapshotLimit = Self.sourceCountSnapshotLimit
        let preferredDirectories = noteStore.preferredDirectories
        let sourceFolderPaths = currentSourceFolderPaths()
        let externalDocumentPaths = Set(externallyOpenedDocumentsByPath.keys)

        sourceSnapshotValidationTask = Task.detached(priority: .userInitiated) { [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            let inboxDirectory = noteStore.preferredInboxDirectory
            let recentCount = Self.recentFilesVisibleInLibrary(
                noteStore: noteStore,
                preferredDirectories: preferredDirectories,
                externalDocumentPaths: externalDocumentPaths,
                limit: 80
            ).count
            let allNotes = noteStore.listNotesRefreshingIndex(
                limit: snapshotLimit,
                roots: preferredDirectories
            )
            guard !Task.isCancelled else { return }
            let trashedNotes = noteStore.listTrashedNotes(limit: snapshotLimit)
            guard !Task.isCancelled else { return }
            let countIndex = LibrarySourceCountIndex(
                notes: allNotes,
                folderPaths: sourceFolderPaths,
                inboxDirectory: inboxDirectory
            )
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self,
                      generation == self.sourceSnapshotValidationGeneration,
                      scope == self.selectedScope,
                      query == self.searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    return
                }

                self.sourceSnapshotValidationTask = nil
                self.sourceInboxDirectory = inboxDirectory
                let mergedAllNotes = self.includingExternallyOpenedDocuments(in: allNotes)
                let reusableCountIndex = self.currentSourceFolderPaths() == sourceFolderPaths
                    ? countIndex
                    : nil
                let trashChanged = trashedNotes != self.trashedNotesSnapshot
                self.trashedNotesSnapshot = trashedNotes
                guard mergedAllNotes != self.sourceCountSnapshot || trashChanged else {
                    self.refreshSourceCounts(
                        using: mergedAllNotes,
                        countIndex: reusableCountIndex,
                        recentCount: recentCount
                    )
                    return
                }

                let selectedURL = self.selectedURL
                let selectedPath = selectedURL?.standardizedFileURL.path
                let nextNotes = self.notesForSelectedScope(
                    limit: Self.noteListResultLimit,
                    allNotes: mergedAllNotes
                )
                let selectionStillExists = selectedPath.map { path in
                    nextNotes.contains { $0.url.standardizedFileURL.path == path }
                } ?? false
                self.reloadNotes(
                    selecting: selectionStillExists ? selectedURL : nil,
                    loadFirstIfNeeded: loadFirstIfNeeded && !selectionStillExists,
                    allNotesSnapshot: mergedAllNotes,
                    sourceCountIndex: reusableCountIndex,
                    sourceRecentCount: recentCount
                )
            }
        }
    }

    func cancelSourceSnapshotValidation() {
        sourceSnapshotValidationTask?.cancel()
        sourceSnapshotValidationTask = nil
        sourceSnapshotValidationGeneration += 1
    }

    func updateNoteListHeader(query: String) {
        updateSidebarScopeButton()
        // Search results must be visible even when the persisted presentation
        // is the file tree. Clearing the query restores that preference.
        if let tree = sidebarTreeView, tree.isHidden == isShowingSidebarTree {
            applySidebarPresentation(animated: false)
        }
        let title = query.isEmpty
            ? noteListTitle(for: selectedScope)
            : (searchScopeControl.selectedSegment == 1 ? noteListTitle(for: .all) : noteListTitle(for: selectedScope))
        noteListCountLabel.isHidden = query.isEmpty && selectedScope == .all
        noteListTitleLabel.stringValue = title
        noteListTitleLabel.isHidden = !query.isEmpty
        if query.isEmpty {
            noteListCountLabel.stringValue = notesCountText(notes.count)
        } else if hasPendingSearchReload || isSearchResultReloading {
            noteListCountLabel.stringValue = LibraryCopy.searching
        } else {
            noteListCountLabel.stringValue = resultsCountText(notes.count)
        }
    }

    func updateNoteListEmptyState(query: String) {
        let isEmpty = listRows.isEmpty
        noteListEmptyLabel.isHidden = !isEmpty
        galleryEmptyLabel.isHidden = !isEmpty || noteListViewMode != .gallery
        guard isEmpty else { return }

        let message: String
        if !query.isEmpty, hasPendingSearchReload || isSearchResultReloading {
            message = LibraryCopy.searching
        } else if !query.isEmpty {
            message = LibraryCopy.noResults
        } else if selectedScope == .trash {
            message = LibraryCopy.recentlyDeletedIsEmpty
        } else {
            message = LibraryCopy.noNotes
        }
        noteListEmptyLabel.stringValue = message
        galleryEmptyLabel.stringValue = message
    }

    func notesForSelectedScope(limit: Int, allNotes: [NoteSearchResult]) -> [NoteSearchResult] {
        let pinnedPaths = selectedScope == .trash
            ? Set<String>()
            : Set(noteStore.libraryPinnedNotePaths)
        if noteListSortOrder == .dateEdited, pinnedPaths.isEmpty {
            return notesForSelectedScopeByModifiedDate(limit: limit, allNotes: allNotes)
        }

        let candidates: [NoteSearchResult]
        let predicate: (NoteSearchResult) -> Bool
        switch selectedScope {
        case .all:
            candidates = allNotes
            predicate = { _ in true }
        case .recent:
            candidates = recentNoteResults(limit: 80, allNotes: allNotes)
            predicate = { _ in true }
        case .favorites:
            candidates = allNotes
            predicate = { pinnedPaths.contains($0.url.standardizedFileURL.path) }
        case .inbox:
            candidates = allNotes
            let inboxDirectory = inboxDirectoryForCurrentSourceSnapshot()
            predicate = { libraryIsInboxNote($0, inboxDirectory: inboxDirectory) }
        case .trash:
            candidates = trashedNotesSnapshot
            predicate = { _ in true }
        case .folder(let url):
            candidates = allNotes
            predicate = { note in
                libraryNote(
                    note,
                    isIn: url,
                    includingDescendants: self.noteStore.libraryIncludesSubfolderNotes
                )
            }
        case .tag(let tag):
            candidates = allNotes
            predicate = { note in
                note.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
            }
        }

        return LibraryNoteListProjection.rankedPrefix(
            candidates,
            limit: limit,
            sortOrder: noteListSortOrder,
            groupsByDate: groupsNoteListByDate,
            includesPinnedGroup: selectedScope != .trash,
            pinnedPaths: pinnedPaths,
            where: predicate
        )
    }

    func notesForSelectedScopeByModifiedDate(
        limit: Int,
        allNotes: [NoteSearchResult]
    ) -> [NoteSearchResult] {
        switch selectedScope {
        case .all:
            return Array(allNotes.prefix(limit))
        case .recent:
            return recentNoteResults(limit: min(limit, 80), allNotes: allNotes)
        case .favorites:
            let pinnedPaths = Set(noteStore.libraryPinnedNotePaths)
            return Array(allNotes.lazy.filter {
                pinnedPaths.contains($0.url.standardizedFileURL.path)
            }.prefix(limit))
        case .inbox:
            let inboxDirectory = inboxDirectoryForCurrentSourceSnapshot()
            return LibraryNoteListProjection.prefix(allNotes, limit: limit) { note in
                libraryIsInboxNote(note, inboxDirectory: inboxDirectory)
            }
        case .trash:
            return Array(trashedNotesSnapshot.prefix(limit))
        case .folder(let url):
            return LibraryNoteListProjection.prefix(allNotes, limit: limit) { note in
                libraryNote(
                    note,
                    isIn: url,
                    includingDescendants: self.noteStore.libraryIncludesSubfolderNotes
                )
            }
        case .tag(let tag):
            return LibraryNoteListProjection.prefix(allNotes, limit: limit) { note in
                note.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
            }
        }
    }

    func searchResultsForSelectedScope(query: String, limit: Int) -> [NoteSearchResult] {
        if selectedScope == .trash, searchScopeControl.selectedSegment != 1 {
            return cachedTrashSearchResults(query: query, limit: limit)
        }
        return searchResults(
            for: selectedScope,
            query: query,
            limit: limit,
            searchesAllNotes: searchScopeControl.selectedSegment == 1
        ).filter {
            !pendingDeletionPaths.contains($0.url.standardizedFileURL.path)
        }
    }

    func cachedTrashSearchResults(query: String, limit: Int) -> [NoteSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return Array(trashedNotesSnapshot.prefix(limit)) }
        return Array(trashedNotesSnapshot.lazy.filter { note in
            note.title.localizedCaseInsensitiveContains(trimmedQuery)
                || note.snippet.localizedCaseInsensitiveContains(trimmedQuery)
                || note.tags.contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
        }.prefix(limit))
    }

    func cachedSearchResultsForSelectedScope(query: String, limit: Int) -> [NoteSearchResult] {
        if selectedScope == .trash, searchScopeControl.selectedSegment != 1 {
            return cachedTrashSearchResults(query: query, limit: limit)
        }

        let candidates: [NoteSearchResult]
        if searchScopeControl.selectedSegment == 1 {
            candidates = sourceCountSnapshot
        } else {
            switch selectedScope {
            case .all:
                candidates = sourceCountSnapshot
            case .recent:
                candidates = recentNoteResults(limit: 80, allNotes: sourceCountSnapshot)
            case .favorites:
                let pinnedPaths = Set(noteStore.libraryPinnedNotePaths)
                candidates = sourceCountSnapshot.filter {
                    pinnedPaths.contains($0.url.standardizedFileURL.path)
                }
            case .inbox:
                let inboxDirectory = inboxDirectoryForCurrentSourceSnapshot()
                candidates = sourceCountSnapshot.filter {
                    libraryIsInboxNote($0, inboxDirectory: inboxDirectory)
                }
            case .trash:
                candidates = trashedNotesSnapshot
            case .folder(let folderURL):
                candidates = sourceCountSnapshot.filter { note in
                    libraryNote(
                        note,
                        isIn: folderURL,
                        includingDescendants: self.noteStore.libraryIncludesSubfolderNotes
                    )
                }
            case .tag(let tag):
                candidates = sourceCountSnapshot.filter { note in
                    note.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
                }
            }
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return Array(candidates.lazy.filter { note in
            note.title.localizedCaseInsensitiveContains(trimmedQuery)
                || note.snippet.localizedCaseInsensitiveContains(trimmedQuery)
                || note.tags.contains { $0.localizedCaseInsensitiveContains(trimmedQuery) }
        }.prefix(limit))
    }

    func searchResults(
        for scope: LibraryScope,
        query: String,
        limit: Int,
        searchesAllNotes: Bool
    ) -> [NoteSearchResult] {
        let searchSession = activeSearchSession
            ?? noteStore.makeSearchSession(roots: noteStore.preferredDirectories)
        activeSearchSession = searchSession
        return librarySearchResults(
            noteStore: noteStore,
            searchSession: searchSession,
            scope: scope,
            query: query,
            limit: limit,
            searchesAllNotes: searchesAllNotes,
            includesSubfolderNotes: noteStore.libraryIncludesSubfolderNotes,
            recentlyEditedPaths: Set(recentNoteResults(limit: 80, allNotes: sourceCountSnapshot).map { $0.url.standardizedFileURL.path })
        )
    }

    func allNoteResults(limit: Int) -> [NoteSearchResult] {
        noteStore.listNotes(limit: limit, roots: noteStore.preferredDirectories)
    }

    func recentShellNoteResults(limit: Int) -> [NoteSearchResult] {
        var results = recentFilesVisibleInLibrary(limit: limit).map { note in
            NoteSearchResult(
                url: note.url,
                title: note.title,
                snippet: "",
                modifiedAt: note.modifiedAt,
                tags: [],
                hasAttachments: false,
                thumbnailURL: nil
            )
        }
        if let cached = noteStore.cachedLibraryLaunchNote(),
           noteStore.preferredDirectories.contains(where: {
               let rootPath = $0.standardizedFileURL.path
               let notePath = cached.url.standardizedFileURL.path
               return notePath.hasPrefix(rootPath + "/")
           }),
           !results.contains(where: {
               $0.url.standardizedFileURL.path == cached.url.standardizedFileURL.path
           }) {
            results.insert(
                NoteSearchResult(
                    url: cached.url,
                    title: cached.document.title,
                    snippet: "",
                    modifiedAt: cached.modifiedAt,
                    tags: cached.document.tags,
                    hasAttachments: MarkdownEditorDocument.containsAttachmentReference(
                        in: cached.document.body
                    ),
                    thumbnailURL: nil
                ),
                at: 0
            )
            if results.count > limit {
                results.removeLast(results.count - limit)
            }
        }
        return results
    }

    func recentNoteResults(limit: Int, allNotes: [NoteSearchResult]) -> [NoteSearchResult] {
        Array(allNotes.prefix(limit))
    }

    func recentFilesVisibleInLibrary(limit: Int) -> [NoteFile] {
        Self.recentFilesVisibleInLibrary(
            noteStore: noteStore,
            preferredDirectories: noteStore.preferredDirectories,
            externalDocumentPaths: Set(externallyOpenedDocumentsByPath.keys),
            limit: limit
        )
    }

    nonisolated static func recentFilesVisibleInLibrary(
        noteStore: NoteStore,
        preferredDirectories: [URL],
        externalDocumentPaths: Set<String>,
        limit: Int
    ) -> [NoteFile] {
        Array(noteStore.listRecentFiles(limit: .max).lazy.filter { note in
            let path = note.url.standardizedFileURL.path
            let isInsideLibrary = preferredDirectories.contains { rootURL in
                let rootPath = rootURL.standardizedFileURL.path
                guard path.hasPrefix(rootPath + "/") else { return false }
                let relativePath = String(path.dropFirst(rootPath.count + 1))
                return !relativePath.split(separator: "/").contains {
                    $0.caseInsensitiveCompare(NoteStore.attachmentDirectoryName) == .orderedSame
                }
            }
            return isInsideLibrary || externalDocumentPaths.contains(path)
        }.prefix(limit))
    }

    func includingExternallyOpenedDocuments(in notes: [NoteSearchResult]) -> [NoteSearchResult] {
        externallyOpenedDocumentsByPath = externallyOpenedDocumentsByPath.filter {
            FileManager.default.fileExists(atPath: $0.key)
        }
        var merged = notes
        for note in externallyOpenedDocumentsByPath.values {
            LibraryNoteListProjection.upsertByModifiedDate(
                note,
                into: &merged,
                replacingPaths: Set([note.url.standardizedFileURL.path]),
                limit: Self.sourceCountSnapshotLimit
            )
        }
        return merged
    }

    func buildGroupedRows(
        for notes: [NoteSearchResult],
        now: Date = Date(),
        preservesInputOrder: Bool = false
    ) -> [LibraryNoteListRow] {
        LibraryNoteListProjection.rows(
            for: notes,
            sortOrder: noteListSortOrder,
            groupsByDate: groupsNoteListByDate,
            includesPinnedGroup: selectedScope != .trash,
            pinnedPaths: Set(noteStore.libraryPinnedNotePaths),
            now: now,
            preservesInputOrder: preservesInputOrder
        )
    }

    @discardableResult
    func togglePinnedStateForSelectedNotesForLibrary() -> Bool {
        let urls = selectedMarkdownFileURLsForLibrary()
        guard selectedScope != .trash, !urls.isEmpty else { return false }
        let shouldPin = !urls.allSatisfy { noteStore.isLibraryNotePinned(at: $0) }
        urls.forEach { noteStore.setLibraryNotePinned(shouldPin, at: $0) }
        rebuildNoteListRowsForDisplayOptions()
        sourceTreeNeedsScopeRebuild = true
        if isShowingSidebarTree {
            rebuildSourceRows(includeTags: sourceTagsLoaded)
        } else {
            let pinnedPaths = Set(noteStore.libraryPinnedNotePaths)
            sourceOutlineItemsByScopeIdentifier[sourceOutlineIdentifier(for: .favorites)]?.count =
                sourceCountSnapshot.lazy.filter { pinnedPaths.contains($0.url.standardizedFileURL.path) }.count
            updateSidebarScopeButton()
        }
        return shouldPin
    }

    func rebuildNoteListRowsForDisplayOptions(
        mutationAnimation: LibraryNoteMutationAnimation? = nil,
        refreshedNotePaths: Set<String> = []
    ) {
        let selectedPaths = Set(selectedMarkdownFileURLsForLibrary().map { $0.standardizedFileURL.path })
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousRows = listRows
        if query.isEmpty {
            notes = notesForSelectedScope(
                limit: Self.noteListResultLimit,
                allNotes: sourceCountSnapshot
            )
        }
        listRows = buildGroupedRows(for: notes, preservesInputOrder: !query.isEmpty)

        suppressSelectionChanges = true
        reloadNoteBrowserData(
            animation: mutationAnimation,
            previousRows: previousRows,
            refreshedNotePaths: refreshedNotePaths
        )
        let selectedRows = IndexSet(listRows.indices.filter { row in
            guard let note = listRows[row].note else { return false }
            return selectedPaths.contains(note.url.standardizedFileURL.path)
        })
        tableView.selectRowIndexes(selectedRows, byExtendingSelection: false)
        suppressSelectionChanges = false
        synchronizeGallerySelectionFromTable()
        updateNoteListEmptyState(query: query)
        updateToolbarActionState()
    }

    func rowIndex(for standardizedPath: String) -> Int? {
        listRows.firstIndex { row in
            row.note?.url.standardizedFileURL.path == standardizedPath
        }
    }

    func note(at row: Int) -> NoteSearchResult? {
        guard listRows.indices.contains(row) else { return nil }
        return listRows[row].note
    }
}
