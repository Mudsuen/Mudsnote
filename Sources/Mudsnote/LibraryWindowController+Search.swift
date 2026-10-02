import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

extension LibraryWindowController {
    func clearSearchFromKeyboard() -> Bool {
        guard !searchField.stringValue.isEmpty else { return false }
        searchField.stringValue = ""
        activeSearchSession = nil
        cancelPendingSearchReload()
        performSearchReload()
        removeEditorSearchHighlights()
        return true
    }

    func scheduleSearchReloadFromTyping() {
        searchReloadWorkItem?.cancel()
        cancelActiveSearchResultReload()

        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            activeSearchSession = nil
            hasPendingSearchReload = false
            performSearchReload(synchronously: true)
            removeEditorSearchHighlights()
            return
        }

        hasPendingSearchReload = true
        searchScopeControl.isHidden = false
        updateNoteListHeader(query: query)
        updateNoteListEmptyState(query: query)
        applyEditorSearchHighlightsForCurrentQuery()

        let workItem = DispatchWorkItem { [weak self] in
            self?.performSearchReload()
        }
        searchReloadWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(140), execute: workItem)
    }

    func flushPendingSearchReload() {
        guard hasPendingSearchReload else { return }
        cancelPendingSearchReload()
        performSearchReload(synchronously: true)
    }

    func cancelPendingSearchReload() {
        searchReloadWorkItem?.cancel()
        searchReloadWorkItem = nil
        hasPendingSearchReload = false
    }

    func cancelActiveSearchResultReload() {
        searchResultsTask?.cancel()
        searchResultsTask = nil
        isSearchResultReloading = false
        searchResultsGeneration += 1
    }

    func performSearchReload(synchronously: Bool = false) {
        cancelPendingSearchReload()
        let query = searchField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            activeSearchSession = nil
            reloadNotesForNavigation(selecting: selectedURL, loadFirstIfNeeded: false)
            applyEditorSearchHighlightsForCurrentQuery()
        } else if synchronously {
            if activeSearchSession == nil || (selectedScope == .trash && searchScopeControl.selectedSegment != 1) {
                let provisionalResults = cachedSearchResultsForSelectedScope(
                    query: query,
                    limit: Self.noteListResultLimit
                )
                applySearchResults(provisionalResults, query: query, selecting: selectedURL)
                scheduleSearchResultReload(query: query, selecting: selectedURL)
            } else {
                reloadNotes(selecting: selectedURL, loadFirstIfNeeded: false, refreshCounts: false)
            }
            applyEditorSearchHighlightsForCurrentQuery()
        } else {
            scheduleSearchResultReload(query: query, selecting: selectedURL)
        }
    }

    func scheduleSearchResultReload(query: String, selecting preferredURL: URL?) {
        cancelActiveSearchResultReload()
        let generation = searchResultsGeneration
        let scope = selectedScope
        let searchesAllNotes = searchScopeControl.selectedSegment == 1
        let noteStore = noteStore
        let existingSearchSession = activeSearchSession
        let preferredDirectories = noteStore.preferredDirectories
        let includesSubfolderNotes = noteStore.libraryIncludesSubfolderNotes
        let recentlyEditedPaths = Set(recentNoteResults(limit: 80, allNotes: sourceCountSnapshot).map { $0.url.standardizedFileURL.path })
        isSearchResultReloading = true
        searchScopeControl.isHidden = false
        updateNoteListHeader(query: query)
        updateNoteListEmptyState(query: query)

        let task = Task.detached(priority: .userInitiated) { [noteStore, existingSearchSession, preferredDirectories, scope, query, searchesAllNotes, includesSubfolderNotes, recentlyEditedPaths, generation, preferredURL] in
            guard !Task.isCancelled else { return }
            let searchSession: NoteSearchSession
            if let existingSearchSession {
                searchSession = existingSearchSession
            } else {
                guard let builtSession = noteStore.makeSearchSession(
                    roots: preferredDirectories,
                    cancellationCheck: { Task.isCancelled }
                ) else {
                    return
                }
                searchSession = builtSession
            }
            let results = librarySearchResults(
                noteStore: noteStore,
                searchSession: searchSession,
                scope: scope,
                query: query,
                limit: Self.noteListResultLimit,
                searchesAllNotes: searchesAllNotes,
                includesSubfolderNotes: includesSubfolderNotes,
                recentlyEditedPaths: recentlyEditedPaths
            )
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self,
                      self.searchResultsGeneration == generation,
                      self.searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) == query,
                      self.selectedScope == scope,
                      (self.searchScopeControl.selectedSegment == 1) == searchesAllNotes else {
                    return
                }
                self.activeSearchSession = searchSession
                self.applySearchResults(results, query: query, selecting: preferredURL)
            }
        }
        searchResultsTask = task
    }

    func applySearchResults(_ results: [NoteSearchResult], query: String, selecting preferredURL: URL?) {
        isSearchResultReloading = false
        notes = results.filter {
            !pendingDeletionPaths.contains($0.url.standardizedFileURL.path)
        }
        listRows = buildGroupedRows(for: notes, preservesInputOrder: true)
        updateNoteListHeader(query: query)

        suppressSelectionChanges = true
        reloadNoteBrowserData()
        updateNoteListEmptyState(query: query)

        if let preferredPath = preferredURL?.standardizedFileURL.path,
           let row = rowIndex(for: preferredPath) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
        suppressSelectionChanges = false
        synchronizeGallerySelectionFromTable()

        refreshSourceSelection()
        updateToolbarActionState()
        applyEditorSearchHighlightsForCurrentQuery()
    }

    enum NoteListResultDirection {
        case next
        case previous
    }

    func moveNoteListSelection(_ direction: NoteListResultDirection) -> Bool {
        let noteRows = listRows.indices.filter { listRows[$0].note != nil }
        guard !noteRows.isEmpty else { return false }

        let selectedRow = tableView.selectedRow
        let targetRow: Int
        if let currentIndex = noteRows.firstIndex(of: selectedRow) {
            switch direction {
            case .next:
                targetRow = noteRows[min(currentIndex + 1, noteRows.count - 1)]
            case .previous:
                targetRow = noteRows[max(currentIndex - 1, 0)]
            }
        } else if selectedRow >= 0 {
            switch direction {
            case .next:
                targetRow = noteRows.first(where: { $0 > selectedRow }) ?? noteRows[noteRows.count - 1]
            case .previous:
                targetRow = noteRows.last(where: { $0 < selectedRow }) ?? noteRows[0]
            }
        } else {
            targetRow = direction == .next ? noteRows[0] : noteRows[noteRows.count - 1]
        }

        do {
            try saveCurrentNoteIfNeeded(allowBackgroundHandoff: true)
            suppressSelectionChanges = true
            tableView.selectRowIndexes(IndexSet(integer: targetRow), byExtendingSelection: false)
            suppressSelectionChanges = false
            tableView.scrollRowToVisible(targetRow)
            loadSelectedRow()
            return true
        } catch {
            suppressSelectionChanges = false
            presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription)
            return true
        }
    }

    func loadFocusedNoteListResultFromSearch() -> Bool {
        guard selectNoteListRowIfNeeded() else { return false }
        loadSelectedRow()
        editorTextView.window?.makeFirstResponder(editorTextView)
        return true
    }

    func stepSearchResult(_ direction: NoteListResultDirection) -> Bool {
        let noteRows = listRows.indices.filter { listRows[$0].note != nil }
        guard !noteRows.isEmpty else { return false }

        let selectedRow = tableView.selectedRow
        let targetRow: Int
        if let currentIndex = noteRows.firstIndex(of: selectedRow) {
            switch direction {
            case .next:
                targetRow = noteRows[min(currentIndex + 1, noteRows.count - 1)]
            case .previous:
                targetRow = noteRows[max(currentIndex - 1, 0)]
            }
        } else {
            targetRow = direction == .next ? noteRows[0] : noteRows[noteRows.count - 1]
        }

        tableView.selectRowIndexes(IndexSet(integer: targetRow), byExtendingSelection: false)
        tableView.scrollRowToVisible(targetRow)
        return true
    }

    func selectNoteListRowIfNeeded() -> Bool {
        if tableView.selectedRow >= 0, note(at: tableView.selectedRow) != nil {
            return true
        }

        let row = listRows.firstIndex(where: { $0.note != nil })
        guard let row else {
            return false
        }

        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        return true
    }
}
