import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

extension LibraryWindowController {
    func deleteSelectedNoteForLibrary() throws {
        try deleteSelectedNotesForLibrary()
    }

    var canDeleteSelectedNotesFromMenuForLibrary: Bool {
        selectedScope != .trash && canUseSelectedNote
    }

    var canRestoreSelectedNotesFromMenuForLibrary: Bool {
        canRestoreSelectedNote
    }

    var canMoveSelectedNotesFromMenuForLibrary: Bool {
        canMoveSelectedNote
    }

    func makeMoveNoteMenuForLibrary() -> NSMenu {
        makeMoveNoteMenu()
    }

    func deleteSelectedNotesForLibrary() throws {
        let urls = selectedMarkdownFileURLsForLibrary()
        guard !urls.isEmpty else { return }
        if selectedScope == .trash {
            for url in urls {
                try noteStore.permanentlyDeleteTrashedNote(at: url)
            }
            removeNotesFromTrashSnapshot(at: urls)
        } else {
            try saveCurrentNoteIfNeeded()
            let selectedNotesByPath = Dictionary(uniqueKeysWithValues: urls.compactMap { url in
                let path = url.standardizedFileURL.path
                return sourceCountSnapshot.first { $0.url.standardizedFileURL.path == path }.map { (path, $0) }
            })
            for url in urls {
                let trashedURL = try noteStore.trashNote(at: url)
                if let note = selectedNotesByPath[url.standardizedFileURL.path] {
                    trashedNotesSnapshot.append(note.replacingURL(trashedURL, modifiedAt: Date()))
                }
            }
            sortAndTrimTrashSnapshot()
        }
        recordInternalFileSystemChanges(for: urls)
        if selectedScope != .trash {
            removeNotesFromSourceSnapshot(at: urls)
        }
        activeSearchSession = nil
        clearCurrentDocumentAfterRemoval()
        rebuildSourceRows(includeTags: sourceTagsLoaded)
        reloadNotes(loadFirstIfNeeded: true, mutationAnimation: .deletion)
    }

    func deleteSelectedNotesInBackgroundForLibrary() throws {
        let urls = selectedMarkdownFileURLsForLibrary().filter {
            !pendingDeletionPaths.contains($0.standardizedFileURL.path)
        }
        guard !urls.isEmpty else { return }

        // A dirty editor must be durably saved before its source can leave the
        // library. Clean-note deletion can publish its UI transition immediately.
        try saveCurrentNoteIfNeeded()

        let deletesFromTrash = selectedScope == .trash
        let snapshot = deletesFromTrash ? trashedNotesSnapshot : sourceCountSnapshot
        let notesByPath = Dictionary(uniqueKeysWithValues: urls.compactMap { url in
            let path = url.standardizedFileURL.path
            return snapshot.first {
                $0.url.standardizedFileURL.path == path
            }.map { (path, $0) }
        })
        let paths = Set(urls.map { $0.standardizedFileURL.path })
        pendingDeletionPaths.formUnion(paths)
        pendingDeletionBatchCount += 1

        if deletesFromTrash {
            removeNotesFromTrashSnapshot(at: urls)
        } else {
            removeNotesFromSourceSnapshot(at: urls)
        }
        clearCurrentDocumentAfterRemoval()
        reloadNotes(
            loadFirstIfNeeded: true,
            refreshCounts: false,
            mutationAnimation: .deletion
        )
        scheduleSourceCountRefresh(using: sourceCountSnapshot)

        let noteStore = noteStore
        let willPersist = backgroundDeletionWillPersist
        libraryMutationQueue.async { [weak self] in
            willPersist()
            var deletedNotes: [LibraryDeletedNote] = []
            var failures: [LibraryDeletionFailure] = []
            for sourceURL in urls {
                do {
                    if deletesFromTrash {
                        try noteStore.permanentlyDeleteTrashedNote(at: sourceURL)
                        deletedNotes.append(LibraryDeletedNote(
                            sourceURL: sourceURL,
                            trashedURL: nil
                        ))
                    } else {
                        let trashedURL = try noteStore.trashNote(at: sourceURL)
                        deletedNotes.append(LibraryDeletedNote(
                            sourceURL: sourceURL,
                            trashedURL: trashedURL
                        ))
                    }
                } catch {
                    failures.append(LibraryDeletionFailure(
                        sourceURL: sourceURL,
                        message: error.localizedDescription
                    ))
                }
            }
            let result = LibraryDeletionPersistenceResult(
                deletedNotes: deletedNotes,
                failures: failures
            )
            DispatchQueue.main.async {
                self?.finishBackgroundDeletion(
                    result,
                    notesByPath: notesByPath,
                    deletesFromTrash: deletesFromTrash
                )
            }
        }
    }

    func finishBackgroundDeletion(
        _ result: LibraryDeletionPersistenceResult,
        notesByPath: [String: NoteSearchResult],
        deletesFromTrash: Bool
    ) {
        let completedPaths = Set(
            result.deletedNotes.map { $0.sourceURL.standardizedFileURL.path }
                + result.failures.map { $0.sourceURL.standardizedFileURL.path }
        )
        pendingDeletionPaths.subtract(completedPaths)

        var changedURLs: [URL] = []
        for deletedNote in result.deletedNotes {
            changedURLs.append(deletedNote.sourceURL)
            if let trashedURL = deletedNote.trashedURL {
                changedURLs.append(trashedURL)
                if let note = notesByPath[deletedNote.sourceURL.standardizedFileURL.path] {
                    trashedNotesSnapshot.append(
                        note.replacingURL(trashedURL, modifiedAt: Date())
                    )
                }
            }
        }
        if !changedURLs.isEmpty {
            recordInternalFileSystemChanges(for: changedURLs)
        }
        sortAndTrimTrashSnapshot()

        if !result.failures.isEmpty {
            for failure in result.failures {
                guard let note = notesByPath[failure.sourceURL.standardizedFileURL.path] else {
                    continue
                }
                if deletesFromTrash {
                    trashedNotesSnapshot.append(note)
                } else {
                    LibraryNoteListProjection.upsertByModifiedDate(
                        note,
                        into: &sourceCountSnapshot,
                        replacingPaths: Set([failure.sourceURL.standardizedFileURL.path]),
                        limit: Self.sourceCountSnapshotLimit
                    )
                }
            }
            if deletesFromTrash {
                sortAndTrimTrashSnapshot()
            }
            reloadNotes(
                loadFirstIfNeeded: selectedURL == nil,
                refreshCounts: false,
                mutationAnimation: .insertion
            )
            let details = result.failures.map(\.message).joined(separator: "\n")
            presentErrorAlert(
                message: deletesFromTrash ? "永久删除失败" : "删除失败，笔记已恢复",
                details: details
            )
        }

        activeSearchSession = nil
        scheduleSourceCountRefresh(using: sourceCountSnapshot)
        updateToolbarActionState()
        pendingDeletionBatchCount = max(0, pendingDeletionBatchCount - 1)
        if pendingDeletionBatchCount == 0 {
            let waiters = pendingDeletionWaiters
            pendingDeletionWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    func waitForBackgroundDeletionsForLibrary() async {
        guard pendingDeletionBatchCount > 0 else { return }
        await withCheckedContinuation { continuation in
            pendingDeletionWaiters.append(continuation)
        }
    }

    @discardableResult
    func restoreSelectedNoteForLibrary() throws -> URL? {
        let urls = selectedMarkdownFileURLsForLibrary()
        guard selectedScope == .trash, !urls.isEmpty else { return nil }
        let restoredURLs = try urls.map { try noteStore.restoreTrashedNote(at: $0) }
        let restoredURL = restoredURLs.first
        recordInternalFileSystemChanges(for: urls + restoredURLs)
        removeNotesFromTrashSnapshot(at: urls)
        for url in restoredURLs {
            let document = try noteStore.loadNote(at: url)
            let modifiedAt = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate])
                as? Date ?? Date()
            updateSourceCountSnapshotAfterSave(
                previousURL: nil,
                savedURL: url,
                title: document.title,
                tags: document.tags,
                modifiedAt: modifiedAt,
                snippet: libraryFirstMeaningfulLine(from: document.body) ?? "",
                hasAttachments: MarkdownEditorDocument.containsAttachmentReference(in: document.body),
                thumbnailURL: MarkdownEditorDocument.firstLocalImageURL(
                    in: document.body,
                    relativeTo: url
                )
            )
        }
        activeSearchSession = nil
        selectedScope = restoredURL.map { .folder($0.deletingLastPathComponent()) }
            ?? .folder(noteStore.notesDirectory)
        clearCurrentDocumentAfterRemoval()
        rebuildSourceRows(includeTags: sourceTagsLoaded)
        reloadNotes(selecting: restoredURL, loadFirstIfNeeded: true)
        return restoredURL
    }

    func removeNotesFromTrashSnapshot(at urls: [URL]) {
        let removedPaths = Set(urls.map { $0.standardizedFileURL.path })
        trashedNotesSnapshot.removeAll { removedPaths.contains($0.url.standardizedFileURL.path) }
    }

    func sortAndTrimTrashSnapshot() {
        trashedNotesSnapshot.sort { $0.modifiedAt > $1.modifiedAt }
        if trashedNotesSnapshot.count > Self.sourceCountSnapshotLimit {
            trashedNotesSnapshot.removeLast(trashedNotesSnapshot.count - Self.sourceCountSnapshotLimit)
        }
    }

    func selectedMarkdownFileURLForLibrary() -> URL? {
        selectedMarkdownFileURLsForLibrary().first
    }

    var currentNoteHasUnsavedChangesForLibrary: Bool {
        isDirty
    }

    func openMarkdownDocumentForLibrary(at url: URL) throws {
        try saveCurrentNoteIfNeeded(allowBackgroundHandoff: true)
        cancelActiveNoteLoad()
        isLoadingInitialNote = false
        isCreatingNewNote = false
        let standardizedURL = url.standardizedFileURL
        let loaded = try noteLoader(standardizedURL)
        let modifiedAt = fileModificationDateLoader(standardizedURL) ?? Date()
        let note = NoteSearchResult(
            url: standardizedURL,
            title: loaded.title,
            snippet: libraryFirstMeaningfulLine(from: loaded.body) ?? "",
            modifiedAt: modifiedAt,
            tags: loaded.tags,
            hasAttachments: MarkdownEditorDocument.containsAttachmentReference(in: loaded.body),
            thumbnailURL: MarkdownEditorDocument.firstLocalImageURL(in: loaded.body, relativeTo: standardizedURL)
        )

        externallyOpenedDocumentsByPath[standardizedURL.path] = note
        sourceCountSnapshot = includingExternallyOpenedDocuments(in: sourceCountSnapshot)
        selectedScope = .folder(standardizedURL.deletingLastPathComponent())
        searchField.stringValue = ""
        activeSearchSession = nil
        let cached = cacheLoadedNote(loaded, for: note, fileModifiedAt: modifiedAt)
        rebuildSourceRows(includeTags: sourceTagsLoaded)
        reloadNotes(
            selecting: standardizedURL,
            loadFirstIfNeeded: false,
            allNotesSnapshot: sourceCountSnapshot
        )
        applyLoadedNote(cached, for: note)
        releaseDeferredLaunchWorkIfReady()
        if let row = rowIndex(for: standardizedURL.path) {
            tableView.scrollRowToVisible(row)
        }
        window?.makeFirstResponder(editorTextView)
    }

    func showAttachmentManagerForLibrary() {
        let controller: LibraryAttachmentManagerWindowController
        if let existing = attachmentManagerWindowController {
            controller = existing
        } else {
            controller = LibraryAttachmentManagerWindowController(
                rootsProvider: { [weak self] in
                    self?.noteStore.preferredDirectories ?? []
                },
                onOpenNote: { [weak self] url in
                    do {
                        try self?.openMarkdownDocumentForLibrary(at: url)
                    } catch {
                        self?.presentErrorAlert(
                            message: "无法打开引用笔记",
                            details: error.localizedDescription
                        )
                    }
                }
            )
            attachmentManagerWindowController = controller
        }
        controller.showAndRefresh()
    }

    @objc
    func manageAttachmentsPressed() {
        showAttachmentManagerForLibrary()
    }

    func selectNoteForVisualQA(at url: URL) {
        let standardizedURL = url.standardizedFileURL
        visualQASelectedURL = standardizedURL
        reloadNotes(
            selecting: standardizedURL,
            loadFirstIfNeeded: true,
            refreshCounts: false
        )
        window?.makeFirstResponder(tableView)
    }

    func stabilizeVisualQASelectionIfNeeded() {
        guard let visualQASelectedURL,
              let row = rowIndex(for: visualQASelectedURL.path) else {
            return
        }
        suppressSelectionChanges = true
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        suppressSelectionChanges = false
        tableView.scrollRowToVisible(row)
        if row <= 1, let scrollView = tableView.enclosingScrollView {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    func selectedMarkdownFileURLsForLibrary() -> [URL] {
        if isShowingSidebarTree,
           let item = sourceOutlineView.item(atRow: sourceOutlineView.selectedRow) as? LibrarySourceOutlineItem,
           let note = item.note,
           note.url.standardizedFileURL == selectedURL?.standardizedFileURL {
            return [note.url.standardizedFileURL]
        }
        var urls: [URL] = []
        var seenPaths = Set<String>()

        for row in tableView.selectedRowIndexes.sorted() {
            guard let url = note(at: row)?.url.standardizedFileURL else { continue }
            if seenPaths.insert(url.path).inserted {
                urls.append(url)
            }
        }

        if urls.isEmpty,
           let selectedURL = selectedURL?.standardizedFileURL,
           seenPaths.insert(selectedURL.path).inserted {
            urls.append(selectedURL)
        }

        return urls
    }

    func noteDragPreviewCountForLibrary(rowIndexes: IndexSet) -> Int {
        var seenPaths = Set<String>()
        var count = 0
        for row in rowIndexes.sorted() {
            guard let path = note(at: row)?.url.standardizedFileURL.path,
                  seenPaths.insert(path).inserted else {
                continue
            }
            count += 1
        }
        return count
    }

    func noteDragPreviewBadgeTitleForLibrary(rowIndexes: IndexSet) -> String? {
        let count = noteDragPreviewCountForLibrary(rowIndexes: rowIndexes)
        return count > 1 ? String(count) : nil
    }

    func noteDragPreviewImageForLibrary(rowIndexes: IndexSet) -> NSImage? {
        let draggedNotes = rowIndexes.sorted().compactMap { note(at: $0) }
        guard let firstNote = draggedNotes.first else { return nil }

        let count = noteDragPreviewCountForLibrary(rowIndexes: rowIndexes)
        let imageSize = NSSize(width: 248, height: 64)
        let image = NSImage(size: imageSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        if count > 1 {
            let shadowRect = NSRect(x: 8, y: 2, width: 232, height: 52)
            let shadowPath = NSBezierPath(roundedRect: shadowRect, xRadius: 8, yRadius: 8)
            NSColor(calibratedWhite: 0.08, alpha: 0.78).setFill()
            shadowPath.fill()
        }

        let cardRect = NSRect(x: 0, y: 8, width: 232, height: 52)
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 8, yRadius: 8)
        NSColor(calibratedRed: 0.55, green: 0.43, blue: 0.08, alpha: 0.96).setFill()
        cardPath.fill()

        let title = firstNote.title.isEmpty ? "无标题" : firstNote.title
        let snippet = noteListSnippetText(for: firstNote)
        (title as NSString).draw(
            in: NSRect(x: 16, y: 31, width: 176, height: 18),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
        )
        (snippet as NSString).draw(
            in: NSRect(x: 16, y: 15, width: 176, height: 14),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.72)
            ]
        )

        if let badgeTitle = noteDragPreviewBadgeTitleForLibrary(rowIndexes: rowIndexes) {
            let badgeRect = NSRect(x: 206, y: 38, width: 28, height: 22)
            let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 11, yRadius: 11)
            NSColor.white.withAlphaComponent(0.96).setFill()
            badgePath.fill()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            (badgeTitle as NSString).draw(
                in: NSRect(x: badgeRect.minX, y: badgeRect.minY + 3, width: badgeRect.width, height: 16),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .bold),
                    .foregroundColor: NSColor(calibratedRed: 0.38, green: 0.28, blue: 0.04, alpha: 1),
                    .paragraphStyle: paragraph
                ]
            )
        }

        return image
    }

    @discardableResult
    func copySelectedMarkdownPathForLibrary() -> String? {
        let paths = selectedMarkdownFileURLsForLibrary().map(\.path)
        guard !paths.isEmpty else { return nil }
        let path = paths.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        return path
    }

    func revealSelectedNoteInFinderForLibrary() -> URL? {
        revealSelectedNotesInFinderForLibrary().first
    }

    func revealSelectedNotesInFinderForLibrary() -> [URL] {
        selectedMarkdownFileURLsForLibrary()
    }

    @discardableResult
    func copySelectedMarkdownContentForLibrary() throws -> String? {
        guard canExportSelectedNote else { return nil }

        try saveCurrentNoteIfNeeded()
        let markdown = try selectedMarkdownFileURLsForLibrary()
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n\n---\n\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        return markdown
    }

    @discardableResult
    func exportSelectedMarkdownForLibrary(to destinationURL: URL) throws -> URL? {
        guard canExportSelectedNote else { return nil }

        try saveCurrentNoteIfNeeded()
        // Saving a changed title may rename the document. Resolve its path afterward.
        guard let sourceURL = selectedMarkdownFileURLForLibrary() else { return nil }
        let destination = destinationURL.standardizedFileURL
        guard destination != sourceURL.standardizedFileURL else { return destination }
        // Read first, then replace atomically: failed exports must preserve both files.
        let contents = try Data(contentsOf: sourceURL)
        try contents.write(to: destination, options: .atomic)
        return destination
    }

    @discardableResult
    func exportSelectedMarkdownFilesForLibrary(to destinationDirectoryURL: URL) throws -> [URL] {
        guard canExportSelectedNote else { return [] }

        try saveCurrentNoteIfNeeded()
        let destinationDirectory = destinationDirectoryURL.standardizedFileURL
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        var reservedNames = Set<String>()
        return try selectedMarkdownFileURLsForLibrary().map { sourceURL in
            let destination = uniqueExportDestination(
                for: sourceURL,
                in: destinationDirectory,
                reservedNames: &reservedNames
            )
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return destination
        }
    }

    func preservesCurrentLoadedNoteForMultiSelection() -> Bool {
        guard tableView.selectedRowIndexes.count > 1,
              let selectedPath = selectedURL?.standardizedFileURL.path else {
            return false
        }
        return selectedMarkdownFileURLsForLibrary().contains {
            $0.standardizedFileURL.path == selectedPath
        }
    }

    func uniqueExportDestination(
        for sourceURL: URL,
        in destinationDirectory: URL,
        reservedNames: inout Set<String>
    ) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let pathExtension = sourceURL.pathExtension
        var candidateName = sourceURL.lastPathComponent
        var suffix = 2

        while reservedNames.contains(candidateName)
            || FileManager.default.fileExists(atPath: destinationDirectory.appendingPathComponent(candidateName).path) {
            candidateName = pathExtension.isEmpty
                ? "\(baseName) \(suffix)"
                : "\(baseName) \(suffix).\(pathExtension)"
            suffix += 1
        }

        reservedNames.insert(candidateName)
        return destinationDirectory.appendingPathComponent(candidateName)
    }

    func searchForLibrary(query: String, allNotes: Bool) {
        cancelPendingSearchReload()
        cancelActiveSearchResultReload()
        searchField.stringValue = query
        searchScopeControl.selectedSegment = allNotes ? 1 : 0
        reloadNotes(
            loadFirstIfNeeded: false,
            refreshCounts: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        applyEditorSearchHighlightsForCurrentQuery()
    }

    func selectRecentScopeForLibrary() {
        selectedScope = .recent
        reloadNotesForNavigation(loadFirstIfNeeded: true)
    }

    func refreshSelectedScopeFromCachedSnapshotForLibrary() {
        reloadNotesForNavigation(selecting: selectedURL, loadFirstIfNeeded: false)
        scheduleSourceSnapshotValidation(loadFirstIfNeeded: false)
    }

    func waitForSourceSnapshotValidationForLibrary() async {
        let task = sourceSnapshotValidationTask
        await task?.value
    }

    func refreshFolderNoteVisibilityForLibrary() {
        activeSearchSession = nil
        let previousURL = selectedURL
        reloadNotesForNavigation(selecting: previousURL, loadFirstIfNeeded: true)
        if notes.isEmpty {
            clearCurrentDocumentAfterRemoval()
        }
    }

    func refreshThemeColorForLibrary() {
        LibraryNoteRowView.selectionFillColor = selectedThemeColor.noteSelectionColor
        refreshVisibleSourceOutlinePresentation()
        tableView.reloadData()
        window?.displayIfNeeded()
    }

    func noteListSearchResultsForLibrary() -> [NoteSearchResult] {
        notes
    }

    func activeSearchSessionForLibrary() -> NoteSearchSession? {
        activeSearchSession
    }
}
