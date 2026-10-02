import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

extension LibraryWindowController {
    func showWindowAndFocus() {
        hasRequestedWindowPresentation = true
        showWindow(nil)
        guard let window else { return }
        if !hasCenteredWindow {
            let preferredScreen = prefersExternalScreen ? Self.externalScreen() : nil
            let visibleFrame = (preferredScreen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1200, height: 820)
            if !usesCanonicalWindowSize, let storedFrame = noteStore.libraryWindowFrame {
                let restoredFrame = clampedPanelFrame(
                    NSRect(
                        x: storedFrame.x,
                        y: storedFrame.y,
                        width: storedFrame.width,
                        height: storedFrame.height
                    ),
                    fallbackSize: LibraryNotesLayout.presentedWindowSize,
                    visibleFrames: NSScreen.screens.map(\.visibleFrame),
                    minimumSize: LibraryNotesLayout.minimumWindowSize
                )
                window.setFrame(restoredFrame, display: true)
            } else {
                let targetSize = LibraryNotesLayout.presentedWindowSize(
                    in: visibleFrame,
                    usesCanonicalSize: usesCanonicalWindowSize
                )
                let targetOrigin = NSPoint(
                    x: visibleFrame.midX - targetSize.width / 2,
                    y: visibleFrame.midY - targetSize.height / 2
                )
                window.setFrame(NSRect(origin: targetOrigin, size: targetSize), display: true)
            }
            hasCenteredWindow = true
        }
        window.contentView?.layoutSubtreeIfNeeded()
        applyStoredLibrarySplitLayoutForLibrary()
        if noteListViewMode == .gallery {
            reloadGalleryData()
            synchronizeGallerySelectionFromTable()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        if noteListViewMode == .gallery {
            window.makeFirstResponder(galleryCollectionView)
        } else if selectedURL == nil {
            window.makeFirstResponder(tableView)
        } else {
            editorTextView.window?.makeFirstResponder(editorTextView)
        }
        hydrateInitialNoteListIfNeeded()
        releaseDeferredLaunchWorkIfReady()
        startLibraryFileSystemMonitorIfNeeded()
    }

    func releaseDeferredLaunchWorkIfReady() {
        guard hasRequestedWindowPresentation,
              !hasReleasedDeferredLaunchWork,
              !isLoadingInitialNote else { return }
        hasReleasedDeferredLaunchWork = true
        scheduleDeferredSourceFolderLoad()
        scheduleDeferredSourceTagLoad()
        scheduleFullLibrarySnapshotReload()
    }

    func hydrateInitialNoteListIfNeeded() {
        guard !hasHydratedInitialNoteList else { return }
        hasHydratedInitialNoteList = true
        if selectedURL == nil {
            let launchSnapshot = noteStore.cachedLibraryLaunchNote()
            let cachedPath = launchSnapshot?.url.standardizedFileURL.path
            let noteRow = cachedPath.flatMap(rowIndex(for:))
                ?? listRows.firstIndex(where: { $0.note != nil })
            guard let noteRow,
                  let noteToLoad = note(at: noteRow) else {
                scheduleFullLibrarySnapshotReload()
                return
            }
            suppressSelectionChanges = true
            tableView.selectRowIndexes(IndexSet(integer: noteRow), byExtendingSelection: false)
            suppressSelectionChanges = false
            if let launchSnapshot,
               launchSnapshot.url.standardizedFileURL.path
                    == noteToLoad.url.standardizedFileURL.path {
                showPersistedInitialNote(launchSnapshot, for: noteToLoad)
            } else {
                showInitialNoteLoadingShell(for: noteToLoad)
            }
            loadInitialNoteAfterLaunch(noteToLoad)
        }
    }

    func showPersistedInitialNote(
        _ snapshot: LibraryLaunchNoteSnapshot,
        for note: NoteSearchResult
    ) {
        isLoadingInitialNote = true
        isCreatingNewNote = false
        persistedLaunchFallbackURL = note.url.standardizedFileURL
        setSelectedURLForLibrary(note.url)
        selectedSourceContents = snapshot.document.sourceContents
        noteLinksView.update(.empty)
        setEditorEditable(false)
        applyDocument(
            title: snapshot.document.title,
            body: snapshot.document.body,
            tags: snapshot.document.tags
        )
        isDirty = false
        updateEditorCreatedDate(snapshot.createdAt)
        updateEditorStatus(editorEditedDateText(for: snapshot.modifiedAt))
        updateToolbarActionState()
    }

    func showInitialNoteLoadingShell(for note: NoteSearchResult) {
        isLoadingInitialNote = true
        isCreatingNewNote = false
        setSelectedURLForLibrary(note.url)
        selectedSourceContents = nil
        noteLinksView.update(.empty)
        setEditorEditable(false)
        applyDocument(title: note.title, body: "", tags: note.tags)
        isDirty = false
        updateEditorCreatedDate(note.createdAt)
        updateEditorStatus(editorEditedDateText(for: note.modifiedAt))
        updateToolbarActionState()
    }

    func loadInitialNoteAfterLaunch(_ note: NoteSearchResult) {
        let noteStore = noteStore
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result<LoadedLibraryNote, Error> {
                try noteStore.loadNoteDocument(at: note.url)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.applyInitialNoteLoadResult(result, for: note)
            }
        }
    }

    func selectedNoteStillMatchesInitialLoad(_ note: NoteSearchResult) -> Bool {
        // The editor URL is shared by tree, list, tabs, and external-file navigation.
        // A hidden list can still select the previous note after a tree click.
        if let selectedURL {
            return selectedURL.standardizedFileURL == note.url.standardizedFileURL
        }
        if let selectedNote = self.note(at: tableView.selectedRow) {
            return selectedNote.url.standardizedFileURL == note.url.standardizedFileURL
        }

        return true
    }

    func applyInitialNoteLoadResult(_ result: Result<LoadedLibraryNote, Error>, for note: NoteSearchResult) {
        guard window?.isVisible == true else {
            isLoadingInitialNote = false
            hasHydratedInitialNoteList = false
            return
        }
        if case .failure(let error) = result,
           isMissingInitialNoteError(error) {
            persistedLaunchFallbackURL = nil
            noteStore.removeRecentFileReference(at: note.url)
            guard selectedNoteStillMatchesInitialLoad(note) else {
                releaseDeferredLaunchWorkIfReady()
                return
            }
            recoverFromMissingInitialNote(note)
            releaseDeferredLaunchWorkIfReady()
            return
        }
        guard selectedNoteStillMatchesInitialLoad(note) else {
            releaseDeferredLaunchWorkIfReady()
            return
        }
        if case .failure(let error) = result,
           persistedLaunchFallbackURL?.standardizedFileURL.path
                == note.url.standardizedFileURL.path {
            isLoadingInitialNote = false
            updateEditorStatus(
                "暂时无法刷新",
                kind: .failure,
                toolTip: error.localizedDescription
            )
            updateToolbarActionState()
            releaseDeferredLaunchWorkIfReady()
            return
        }
        persistedLaunchFallbackURL = nil
        applyLoadedNoteResult(result, for: note)
    }

    func isMissingInitialNoteError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           (nsError.code == CocoaError.Code.fileNoSuchFile.rawValue
            || nsError.code == CocoaError.Code.fileReadNoSuchFile.rawValue) {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain,
           nsError.code == Int(POSIXErrorCode.ENOENT.rawValue) {
            return true
        }
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isMissingInitialNoteError(underlyingError)
        }
        return false
    }

    func recoverFromMissingInitialNote(_ missingNote: NoteSearchResult) {
        let missingPath = missingNote.url.standardizedFileURL.path
        notes.removeAll { $0.url.standardizedFileURL.path == missingPath }
        listRows = buildGroupedRows(for: notes)

        suppressSelectionChanges = true
        reloadNoteBrowserData()
        tableView.deselectAll(nil)
        suppressSelectionChanges = false
        synchronizeGallerySelectionFromTable()
        clearCurrentDocumentAfterRemoval()
        updateEditorStatus("")
        updateNoteListHeader(query: "")
        updateNoteListEmptyState(query: "")

        guard let nextNoteRow = listRows.firstIndex(where: { $0.note != nil }),
              let nextNote = note(at: nextNoteRow) else {
            updateToolbarActionState()
            return
        }

        suppressSelectionChanges = true
        tableView.selectRowIndexes(IndexSet(integer: nextNoteRow), byExtendingSelection: false)
        suppressSelectionChanges = false
        synchronizeGallerySelectionFromTable()
        showInitialNoteLoadingShell(for: nextNote)
        loadInitialNoteAfterLaunch(nextNote)
    }

    func scheduleFullLibrarySnapshotReload() {
        guard !fullLibrarySnapshotReloadScheduled else { return }
        fullLibrarySnapshotReloadScheduled = true
        fullLibrarySnapshotReloadGeneration += 1
        let generation = fullLibrarySnapshotReloadGeneration
        isFullLibrarySnapshotLoading = true
        updateNoteListHeader(query: searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        let noteStore = noteStore
        let snapshotLimit = Self.sourceCountSnapshotLimit
        let preferredDirectories = noteStore.preferredDirectories
        let sourceFolderPaths = currentSourceFolderPaths()
        let externalDocumentPaths = Set(externallyOpenedDocumentsByPath.keys)
        Task.detached(priority: .utility) { [weak self] in
            let inboxDirectory = noteStore.preferredInboxDirectory
            let recentCount = Self.recentFilesVisibleInLibrary(
                noteStore: noteStore,
                preferredDirectories: preferredDirectories,
                externalDocumentPaths: externalDocumentPaths,
                limit: 80
            ).count
            if let cachedNotes = noteStore.cachedNotes(
                limit: snapshotLimit,
                roots: preferredDirectories
            ) {
                let cachedCountIndex = LibrarySourceCountIndex(
                    notes: cachedNotes,
                    folderPaths: sourceFolderPaths,
                    inboxDirectory: inboxDirectory
                )
                await MainActor.run {
                    guard let self,
                          generation == self.fullLibrarySnapshotReloadGeneration,
                          self.isFullLibrarySnapshotLoading else { return }
                    let mergedCachedNotes = self.includingExternallyOpenedDocuments(in: cachedNotes)
                    self.sourceInboxDirectory = inboxDirectory
                    self.sourceCountSnapshot = mergedCachedNotes
                    self.refreshSourceCounts(
                        using: mergedCachedNotes,
                        countIndex: self.currentSourceFolderPaths() == sourceFolderPaths
                            ? cachedCountIndex
                            : nil,
                        recentCount: recentCount
                    )
                }
            }
            let allNotes = noteStore.listNotesRefreshingIndex(
                limit: snapshotLimit,
                roots: preferredDirectories
            )
            noteStore.cacheLibraryPresentationSnapshot(allNotes)
            let trashedNotes = noteStore.listTrashedNotes(limit: snapshotLimit)
            let countIndex = LibrarySourceCountIndex(
                notes: allNotes,
                folderPaths: sourceFolderPaths,
                inboxDirectory: inboxDirectory
            )
            await MainActor.run {
                guard let self,
                      generation == self.fullLibrarySnapshotReloadGeneration else { return }
                self.fullLibrarySnapshotReloadScheduled = false
                self.isFullLibrarySnapshotLoading = false
                guard self.window?.isVisible == true else { return }
                self.sourceInboxDirectory = inboxDirectory
                self.trashedNotesSnapshot = trashedNotes
                let mergedAllNotes = self.includingExternallyOpenedDocuments(in: allNotes)
                self.applySourceTagsFromValidatedSnapshot(mergedAllNotes)
                let reusableCountIndex = self.currentSourceFolderPaths() == sourceFolderPaths
                    ? countIndex
                    : nil
                let currentQuery = self.searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !currentQuery.isEmpty {
                    self.sourceCountSnapshot = mergedAllNotes
                    self.refreshSourceCounts(
                        using: mergedAllNotes,
                        countIndex: reusableCountIndex,
                        recentCount: recentCount
                    )
                    self.updateNoteListHeader(query: currentQuery)
                    return
                }
                let shouldLoadFirstAfterSnapshot = self.selectedURL == nil && self.tableView.selectedRow < 0
                self.reloadNotes(
                    selecting: self.selectedURL,
                    loadFirstIfNeeded: shouldLoadFirstAfterSnapshot,
                    allNotesSnapshot: mergedAllNotes,
                    sourceCountIndex: reusableCountIndex,
                    sourceRecentCount: recentCount
                )
            }
        }
    }

    func forceFullLibrarySnapshotReload() {
        fullLibrarySnapshotReloadGeneration += 1
        fullLibrarySnapshotReloadScheduled = false
        scheduleFullLibrarySnapshotReload()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        do {
            try saveCurrentNoteIfNeeded(allowBackgroundHandoff: true)
            return true
        } catch {
            presentErrorAlert(message: "无法关闭资料库", details: error.localizedDescription)
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let librarySplitView {
            NotificationCenter.default.removeObserver(
                self,
                name: NSSplitView.didResizeSubviewsNotification,
                object: librarySplitView
            )
        }
        autosaveTask?.cancel()
        autosaveTask = nil
        editorNoteSuggestionTask?.cancel()
        editorNoteSuggestionTask = nil
        cancelActiveNoteLoad()
        notePrefetchTask?.cancel()
        notePrefetchTask = nil
        cancelNoteLinksRefresh()
        thumbnailImageLoadTasks.values.forEach { $0.cancel() }
        thumbnailImageLoadTasks.removeAll()
        pendingThumbnailReloadPaths.removeAll()
        thumbnailReloadScheduled = false
        fileSystemMonitor?.stop()
        fileSystemMonitor = nil
        internallyMutatedPaths.removeAll()
        attachmentQuickLookController.dismiss()
        attachmentManagerWindowController?.close()
        attachmentManagerWindowController = nil
        knowledgeGraphWindowController?.close()
        knowledgeGraphWindowController = nil
        cancelSourceSnapshotValidation()
        sourceCountRefreshTask?.cancel()
        sourceCountRefreshTask = nil
        sourceCountRefreshGeneration += 1
        searchReloadWorkItem?.cancel()
        searchReloadWorkItem = nil
        editorMetricsRefreshTask?.cancel()
        editorMetricsRefreshTask = nil
        editorSearchHighlightRefreshTask?.cancel()
        editorSearchHighlightRefreshTask = nil
        knowledgeSynthesisTask?.cancel()
        knowledgeSynthesisTask = nil
        knowledgeSynthesisGeneration += 1
        cancelActiveSearchResultReload()
        hasPendingSearchReload = false
        splitLayoutPersistenceWorkItem?.cancel()
        splitLayoutPersistenceWorkItem = nil
        windowFramePersistenceWorkItem?.cancel()
        windowFramePersistenceWorkItem = nil
        persistLibraryWindowFrameForLibrary()
        persistLibrarySplitLayoutForLibrary()
        onClose()
    }

    func windowDidMove(_ notification: Notification) {
        scheduleLibraryWindowFramePersistence()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshToolbarEditorTextButtonFocus(isWindowFocused: true)
    }

    func windowDidResignKey(_ notification: Notification) {
        refreshToolbarEditorTextButtonFocus(isWindowFocused: false)
    }

    func windowDidResize(_ notification: Notification) {
        scheduleLibraryWindowFramePersistence()
        layoutEditorStatusLabel()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        windowFramePersistenceWorkItem?.cancel()
        windowFramePersistenceWorkItem = nil
        persistLibraryWindowFrameForLibrary()
    }

    func scheduleLibraryWindowFramePersistence() {
        guard !usesCanonicalWindowSize,
              hasRequestedWindowPresentation,
              hasCenteredWindow else {
            return
        }
        windowFramePersistenceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.windowFramePersistenceWorkItem = nil
            self?.persistLibraryWindowFrameForLibrary()
        }
        windowFramePersistenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(180), execute: workItem)
    }

    func persistLibraryWindowFrameForLibrary() {
        guard !usesCanonicalWindowSize,
              hasCenteredWindow,
              let frame = window?.frame else {
            return
        }
        noteStore.libraryWindowFrame = StoredWindowFrame(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.width,
            height: frame.height
        )
    }
}
