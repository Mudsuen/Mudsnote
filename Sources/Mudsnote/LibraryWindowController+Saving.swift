import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

extension LibraryWindowController {
    func markDirty() {
        guard !suppressEditorChanges, selectedScope != .trash else { return }
        editorContentRevision &+= 1
        let becameDirty = !isDirty
        isDirty = true
        activeDocumentTab.isDirty = true
        if becameDirty {
            updateToolbarActionState()
        }
        scheduleAutosave()
    }

    func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.autosaveCurrentNote()
            }
        }
    }

    func autosaveCurrentNote() {
        autosaveTask?.cancel()
        autosaveTask = nil
        guard isDirty, selectedScope != .trash else { return }

        enqueueBackgroundAutosave()
    }

    func enqueueBackgroundAutosave() {
        if backgroundAutosaveIsActive {
            backgroundAutosaveNeedsLatest = true
            return
        }
        let editorSnapshot: LibraryBackgroundEditorSnapshot
        if isEditorShowingMarkdownSource {
            editorSnapshot = LibraryBackgroundEditorSnapshot(
                sourceMarkdown: editorTextView.string,
                theme: theme
            )
        } else {
            editorSnapshot = LibraryBackgroundEditorSnapshot(
                attributedMarkdown: editorTextView.attributedString(),
                theme: theme
            )
        }

        backgroundAutosaveGeneration &+= 1
        backgroundAutosaveIsActive = true
        let generation = backgroundAutosaveGeneration
        let editorRevision = editorContentRevision
        let previousURL = selectedURL
        let tags = selectedTags
        let targetDirectory = previousURL?.deletingLastPathComponent() ?? targetDirectoryForNewNote()
        let updatesInPlace = previousURL.map {
            externallyOpenedDocumentsByPath[$0.path] != nil
        } ?? false
        let expectedContents = selectedSourceContents
        backgroundAutosaveActiveEditorRevision = editorRevision
        backgroundAutosaveActivePreviousURL = previousURL
        cancelSourceSnapshotValidation()
        let noteStore = noteStore
        let resultStore = backgroundAutosaveResultStore
        let willPersist = backgroundAutosaveWillPersist
        autosavePersistenceQueue.async { [weak self] in
            willPersist()
            let result = Result {
                let document = MarkdownEditorDocument.parse(
                    editorText: editorSnapshot.markdown(),
                    tags: tags
                )
                let title = document.title
                let snapshot = LibraryBackgroundSaveSnapshot(
                    generation: generation,
                    editorRevision: editorRevision,
                    previousURL: previousURL,
                    title: title,
                    body: document.body,
                    tags: tags,
                    targetDirectory: targetDirectory,
                    updatesInPlace: updatesInPlace,
                    expectedContents: expectedContents
                )
                return try Self.performBackgroundSave(snapshot, noteStore: noteStore)
            }
            resultStore.insert(LibraryBackgroundSaveResultBox(result), for: generation)
            DispatchQueue.main.async { [weak self] in
                self?.finishBackgroundAutosave(generation: generation)
            }
        }
    }

    nonisolated static func performBackgroundSave(
        _ snapshot: LibraryBackgroundSaveSnapshot,
        noteStore: NoteStore
    ) throws -> LibraryBackgroundSaveSuccess {
        let savedURL: URL
        let sourceContents: String
        let conflictedOriginalURL: URL?
        if let previousURL = snapshot.previousURL {
            guard let expectedContents = snapshot.expectedContents else {
                throw CocoaError(.fileReadUnknown)
            }
            let result = try noteStore.updateNote(
                at: previousURL.standardizedFileURL,
                title: snapshot.title,
                body: snapshot.body,
                tags: snapshot.tags,
                expectedContents: expectedContents,
                updatesInPlace: snapshot.updatesInPlace
            )
            savedURL = result.url
            sourceContents = result.sourceContents
            conflictedOriginalURL = result.conflictedOriginalURL
        } else {
            savedURL = try noteStore.saveNewNote(
                title: snapshot.title,
                body: snapshot.body,
                tags: snapshot.tags,
                in: snapshot.targetDirectory
            )
            sourceContents = try String(contentsOf: savedURL, encoding: .utf8)
            conflictedOriginalURL = nil
        }

        let savedResourceValues = try? savedURL.resourceValues(forKeys: [.contentModificationDateKey])
        let savedAt = savedResourceValues?.contentModificationDate ?? Date()
        return LibraryBackgroundSaveSuccess(
            snapshot: snapshot,
            savedURL: savedURL,
            savedAt: savedAt,
            snippet: libraryFirstMeaningfulLine(from: snapshot.body) ?? "",
            hasAttachments: MarkdownEditorDocument.containsAttachmentReference(in: snapshot.body),
            thumbnailURL: MarkdownEditorDocument.firstLocalImageURL(
                in: snapshot.body,
                relativeTo: savedURL
            ),
            sourceContents: sourceContents,
            conflictedOriginalURL: conflictedOriginalURL
        )
    }

    func finishBackgroundAutosave(generation: Int) {
        let boxedResult = backgroundAutosaveResultStore.remove(generation: generation)
        guard let boxedResult else { return }
        backgroundAutosaveIsActive = false
        backgroundAutosaveActiveEditorRevision = nil
        backgroundAutosaveActivePreviousURL = nil

        switch boxedResult.result {
        case .success(let success):
            applyBackgroundSaveSuccess(success)
            if backgroundAutosaveNeedsLatest, isDirty {
                backgroundAutosaveNeedsLatest = false
                enqueueBackgroundAutosave()
            } else {
                backgroundAutosaveNeedsLatest = false
            }
        case .failure:
            backgroundAutosaveNeedsLatest = false
            updateEditorStatus(
                "自动保存失败，编辑仍保留",
                kind: .failure,
                toolTip: "按 Command-S 重试保存",
                announcesChange: true
            )
            NSSound.beep()
        }
        flushDeferredFileSystemChangesAfterAutosave()
    }

    func applyBackgroundSaveSuccess(_ success: LibraryBackgroundSaveSuccess) {
        let snapshot = success.snapshot
        let changedURLs = [snapshot.previousURL, success.savedURL].compactMap { $0 }
        recordInternalFileSystemChanges(for: changedURLs)
        if let previousURL = snapshot.previousURL {
            loadedNoteCache.removeEntry(forKey: loadedNoteCacheKey(for: previousURL))
        }
        loadedNoteCache.removeEntry(forKey: loadedNoteCacheKey(for: success.savedURL))
        let sourceCountsChanged = updateSourceCountSnapshotAfterSave(
            previousURL: success.conflictedOriginalURL == nil ? snapshot.previousURL : nil,
            savedURL: success.savedURL,
            title: snapshot.title,
            tags: snapshot.tags,
            modifiedAt: success.savedAt,
            snippet: success.snippet,
            hasAttachments: success.hasAttachments,
            thumbnailURL: success.thumbnailURL
        )
        if let conflictedOriginalURL = success.conflictedOriginalURL,
           externallyOpenedDocumentsByPath[conflictedOriginalURL.standardizedFileURL.path] != nil,
           let recoveryNote = sourceCountSnapshot.first(where: {
               $0.url.standardizedFileURL == success.savedURL.standardizedFileURL
           }) {
            externallyOpenedDocumentsByPath[success.savedURL.standardizedFileURL.path] = recoveryNote
        }
        let isCurrentDocument = selectedScope != .trash
            && selectedURL?.path == snapshot.previousURL?.path
        guard isCurrentDocument else {
            onSave(success.savedURL)
            return
        }

        setSelectedURLForLibrary(success.savedURL)
        activeDocumentTab.url = success.savedURL
        activeDocumentTab.title = snapshot.title.isEmpty
            ? success.savedURL.deletingPathExtension().lastPathComponent
            : snapshot.title
        selectedSourceContents = success.sourceContents
        activeSearchSession = nil
        isCreatingNewNote = false
        isDirty = editorContentRevision != snapshot.editorRevision
        activeDocumentTab.isDirty = isDirty
        updateDocumentTabBar()
        refreshVisibleNoteListAfterSave(
            selecting: success.savedURL,
            replacing: snapshot.previousURL,
            isNewNote: snapshot.previousURL == nil,
            refreshesSourceCounts: sourceCountsChanged
        )
        if success.conflictedOriginalURL != nil {
            updateEditorStatus(
                "检测到外部修改，本地编辑已保存为冲突副本",
                kind: .failure,
                toolTip: "原文件保持不变；当前编辑已切换到冲突副本",
                announcesChange: true
            )
        } else if !isDirty {
            updateEditorStatus(editorEditedDateText(for: success.savedAt))
        }
        refreshNoteLinksAfterSave(
            for: success.savedURL,
            replacing: success.conflictedOriginalURL == nil ? snapshot.previousURL : nil,
            body: snapshot.body
        )
        onSave(success.savedURL)
        updateToolbarActionState()
    }

    func drainBackgroundAutosaves() {
        while backgroundAutosaveIsActive {
            autosavePersistenceQueue.sync {}
            for generation in backgroundAutosaveResultStore.pendingGenerations() {
                finishBackgroundAutosave(generation: generation)
            }
        }
    }

    func saveCurrentNoteIfNeeded(allowBackgroundHandoff: Bool = false) throws {
        guard isDirty else { return }
        if allowBackgroundHandoff, handOffCurrentEditorToBackgroundAutosave() {
            return
        }
        _ = try saveCurrentNote(force: false)
    }

    func handOffCurrentEditorToBackgroundAutosave() -> Bool {
        if !backgroundAutosaveIsActive {
            autosaveCurrentNote()
        }
        return backgroundAutosaveIsActive
            && backgroundAutosaveActiveEditorRevision == editorContentRevision
            && backgroundAutosaveActivePreviousURL?.path == selectedURL?.path
    }

    func serializedEditorMarkdown() -> String {
        if isEditorShowingMarkdownSource {
            return editorTextView.string
        }
        return MarkdownRichTextCodec.serialize(editorTextView.attributedString(), theme: theme)
    }

    func currentEditorDocument() -> MarkdownEditorDocument {
        MarkdownEditorDocument.parse(
            editorText: serializedEditorMarkdown(),
            tags: selectedTags
        )
    }

    func currentEditorMarkdownBody() -> String {
        currentEditorDocument().body
    }

    func updateEditorStatus(
        _ text: String,
        kind: EditorStatusKind = .normal,
        toolTip: String? = nil,
        announcesChange: Bool = false
    ) {
        statusLabel.stringValue = text
        statusLabel.toolTip = toolTip
        statusLabel.setAccessibilityValue(text)
        switch kind {
        case .normal:
            statusLabel.textColor = panelTertiaryTextColor()
        case .failure:
            statusLabel.textColor = .systemRed
        }
        if announcesChange {
            NSAccessibility.post(element: statusLabel, notification: .valueChanged)
        }
        layoutEditorStatusLabel()
    }

    func layoutEditorStatusLabel() {
        guard let layoutManager = editorTextView.layoutManager,
              let textContainer = editorTextView.textContainer else { return }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let contentBottom = editorTextView.textContainerInset.height + usedRect.maxY
        let viewportHeight = editorTextView.enclosingScrollView?.contentView.bounds.height ?? 0
        let relationsTop = contentBottom + LibraryNotesLayout.editorBottomInset
        var documentHeight = max(viewportHeight, relationsTop)
        if !noteLinksView.isPinned, noteLinksView.superview === editorTextView {
            noteLinksView.setFrameSize(NSSize(width: max(0, editorTextView.bounds.width - 20), height: noteLinksView.frame.height))
            noteLinksView.layoutSubtreeIfNeeded()
            let linksHeight = noteLinksView.fittingSize.height
            noteLinksView.frame = NSRect(x: 0, y: relationsTop,
                width: max(0, editorTextView.bounds.width - 20), height: linksHeight)
            documentHeight = max(viewportHeight, noteLinksView.frame.maxY + 16)
        }
        editorTextView.minimumScrollableContentHeight = documentHeight
        editorTextView.minSize = NSSize(width: 0, height: documentHeight)
        if abs(editorTextView.frame.height - documentHeight) > 0.5 {
            var frame = editorTextView.frame
            frame.size.height = documentHeight
            editorTextView.frame = frame
        }

    }

    @discardableResult
    func saveCurrentNote(force: Bool) throws -> URL? {
        drainBackgroundAutosaves()
        guard force || isDirty else { return selectedURL }
        guard selectedScope != .trash else { return selectedURL }
        autosaveTask?.cancel()
        autosaveTask = nil
        cancelSourceSnapshotValidation()

        let document = currentEditorDocument()
        let body = document.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = document.title
        guard selectedURL != nil || isCreatingNewNote || !title.isEmpty || !body.isEmpty else { return nil }

        let previousURL = selectedURL
        let savedURL: URL
        let sourceContents: String
        let conflictedOriginalURL: URL?
        if let previousURL {
            loadedNoteCache.removeEntry(forKey: loadedNoteCacheKey(for: previousURL))
            guard let expectedContents = selectedSourceContents else {
                throw CocoaError(.fileReadUnknown)
            }
            let result = try noteStore.updateNote(
                at: previousURL,
                title: title,
                body: body,
                tags: selectedTags,
                expectedContents: expectedContents,
                updatesInPlace: externallyOpenedDocumentsByPath[
                    previousURL.standardizedFileURL.path
                ] != nil
            )
            savedURL = result.url
            sourceContents = result.sourceContents
            conflictedOriginalURL = result.conflictedOriginalURL
        } else {
            savedURL = try noteStore.saveNewNote(
                title: title,
                body: body,
                tags: selectedTags,
                in: targetDirectoryForNewNote()
            )
            sourceContents = try String(contentsOf: savedURL, encoding: .utf8)
            conflictedOriginalURL = nil
        }

        let changedURLs = [previousURL, savedURL].compactMap { $0 }
        recordInternalFileSystemChanges(for: changedURLs)
        setSelectedURLForLibrary(savedURL)
        activeDocumentTab.url = savedURL
        activeDocumentTab.title = title.isEmpty
            ? savedURL.deletingPathExtension().lastPathComponent
            : title
        activeDocumentTab.isDirty = false
        updateDocumentTabBar()
        selectedSourceContents = sourceContents
        activeSearchSession = nil
        isCreatingNewNote = false
        isDirty = false
        let savedAt = (try? FileManager.default.attributesOfItem(atPath: savedURL.path)[.modificationDate])
            as? Date ?? Date()
        let sourceCountsChanged = updateSourceCountSnapshotAfterSave(
            previousURL: conflictedOriginalURL == nil ? previousURL : nil,
            savedURL: savedURL,
            title: title,
            tags: selectedTags,
            modifiedAt: savedAt,
            snippet: libraryFirstMeaningfulLine(from: body) ?? "",
            hasAttachments: MarkdownEditorDocument.containsAttachmentReference(in: body),
            thumbnailURL: MarkdownEditorDocument.firstLocalImageURL(in: body, relativeTo: savedURL)
        )
        if let conflictedOriginalURL,
           externallyOpenedDocumentsByPath[conflictedOriginalURL.standardizedFileURL.path] != nil,
           let recoveryNote = sourceCountSnapshot.first(where: {
               $0.url.standardizedFileURL == savedURL.standardizedFileURL
           }) {
            externallyOpenedDocumentsByPath[savedURL.standardizedFileURL.path] = recoveryNote
        }
        refreshVisibleNoteListAfterSave(
            selecting: savedURL,
            replacing: conflictedOriginalURL == nil ? previousURL : nil,
            isNewNote: previousURL == nil,
            refreshesSourceCounts: sourceCountsChanged
        )
        if conflictedOriginalURL != nil {
            updateEditorStatus(
                "检测到外部修改，本地编辑已保存为冲突副本",
                kind: .failure,
                toolTip: "原文件保持不变；当前编辑已切换到冲突副本",
                announcesChange: true
            )
        } else {
            updateEditorStatus(editorEditedDateText(for: savedAt))
        }
        refreshNoteLinksAfterSave(
            for: savedURL,
            replacing: conflictedOriginalURL == nil ? previousURL : nil,
            body: body
        )
        onSave(savedURL)
        updateToolbarActionState()
        return savedURL
    }

    @discardableResult
    func updateSourceCountSnapshotAfterSave(
        previousURL: URL?,
        savedURL: URL,
        title: String,
        tags: [String],
        modifiedAt: Date,
        snippet: String,
        hasAttachments: Bool,
        thumbnailURL: URL?
    ) -> Bool {
        let previousPath = previousURL?.path
        let savedPath = savedURL.path
        let previousNote = sourceCountSnapshot.first {
            $0.url.path == previousPath || $0.url.path == savedPath
        }
        let previousTagKeys = Set(previousNote?.tags.map {
            $0.folding(options: [.caseInsensitive], locale: .current)
        } ?? [])
        let savedTagKeys = Set(tags.map {
            $0.folding(options: [.caseInsensitive], locale: .current)
        })
        let sourceCountsChanged = previousNote == nil
            || previousPath != savedPath
            || previousTagKeys != savedTagKeys
        let updatedNote = NoteSearchResult(
            url: savedURL,
            title: title,
            snippet: snippet,
            modifiedAt: modifiedAt,
            createdAt: previousNote?.createdAt ?? modifiedAt,
            tags: tags,
            hasAttachments: hasAttachments,
            thumbnailURL: thumbnailURL
        )
        if let previousPath,
           externallyOpenedDocumentsByPath.removeValue(forKey: previousPath) != nil {
            externallyOpenedDocumentsByPath[savedPath] = updatedNote
        }
        LibraryNoteListProjection.upsertByModifiedDate(
            updatedNote,
            into: &sourceCountSnapshot,
            replacingPaths: Set([
                previousURL?.path,
                previousPath,
                savedURL.path,
                savedPath
            ].compactMap { $0 }),
            limit: Self.sourceCountSnapshotLimit
        )
        persistCurrentLibraryPresentationCache()
        return sourceCountsChanged
    }

    func refreshVisibleNoteListAfterSave(
        selecting savedURL: URL,
        replacing previousURL: URL?,
        isNewNote: Bool,
        refreshesSourceCounts: Bool
    ) {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            scheduleSearchResultReload(query: query, selecting: savedURL)
            return
        }

        notes = notesForSelectedScope(
            limit: Self.noteListResultLimit,
            allNotes: sourceCountSnapshot
        )
        let refreshedPaths = isNewNote
            ? Set<String>()
            : Set([previousURL, savedURL].compactMap { $0?.path })
        rebuildNoteListRowsForDisplayOptions(
            mutationAnimation: isNewNote ? .insertion : nil,
            refreshedNotePaths: refreshedPaths
        )
        if isNewNote,
           let row = rowIndex(for: savedURL.path) {
            suppressSelectionChanges = true
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            suppressSelectionChanges = false
            synchronizeGallerySelectionFromTable()
        }
        updateNoteListHeader(query: "")
        if refreshesSourceCounts {
            scheduleSourceCountRefresh(using: sourceCountSnapshot)
        }
    }

    func waitForSourceCountRefreshForLibrary() async {
        await sourceCountRefreshTask?.value
    }

    func removeNotesFromSourceSnapshot(at urls: [URL]) {
        let removedPaths = Set(urls.map { $0.standardizedFileURL.path })
        sourceCountSnapshot.removeAll { removedPaths.contains($0.url.standardizedFileURL.path) }
        persistCurrentLibraryPresentationCache()
    }

    func remapSourceSnapshotNotes(from sourceURLs: [URL], to destinationURLs: [URL]) {
        let destinationBySourcePath = Dictionary(uniqueKeysWithValues: zip(sourceURLs, destinationURLs).map {
            ($0.standardizedFileURL.path, $1.standardizedFileURL)
        })
        for (sourcePath, destinationURL) in destinationBySourcePath {
            guard let externalNote = externallyOpenedDocumentsByPath.removeValue(forKey: sourcePath),
                  !isInsideConfiguredLibraryRoot(destinationURL) else { continue }
            externallyOpenedDocumentsByPath[destinationURL.path] = externalNote.replacingURL(destinationURL)
        }
        sourceCountSnapshot = sourceCountSnapshot.map { note in
            guard let destinationURL = destinationBySourcePath[note.url.standardizedFileURL.path] else { return note }
            return note.replacingURL(destinationURL)
        }
        persistCurrentLibraryPresentationCache()
    }

    func remapSourceSnapshotFolder(from sourceURL: URL, to destinationURL: URL) {
        let sourcePath = sourceURL.standardizedFileURL.path
        let destination = destinationURL.standardizedFileURL
        for tab in documentTabs {
            guard let path = tab.url?.standardizedFileURL.path,
                  path.hasPrefix(sourcePath + "/") else { continue }
            tab.url = destination.appendingPathComponent(String(path.dropFirst(sourcePath.count + 1)))
        }
        updateDocumentTabBar()
        sourceCountSnapshot = sourceCountSnapshot.map { note in
            let notePath = note.url.standardizedFileURL.path
            guard notePath.hasPrefix(sourcePath + "/") else { return note }
            let relativePath = String(notePath.dropFirst(sourcePath.count + 1))
            return note.replacingURL(destination.appendingPathComponent(relativePath))
        }
        persistCurrentLibraryPresentationCache()
    }

    func removeSourceSnapshotNotes(in folderURL: URL) {
        let folderPath = folderURL.standardizedFileURL.path
        sourceCountSnapshot.removeAll {
            $0.url.standardizedFileURL.path.hasPrefix(folderPath + "/")
        }
        persistCurrentLibraryPresentationCache()
    }

    func persistCurrentLibraryPresentationCache() {
        let snapshot = sourceCountSnapshot
        let noteStore = noteStore
        launchNoteCacheQueue.async {
            noteStore.cacheLibraryPresentationSnapshot(snapshot)
        }
    }

    @discardableResult
    func saveCurrentNoteForLibrary() throws -> URL? {
        let savedURL = try saveCurrentNote(force: true)
        if let savedURL {
            reloadNotes(selecting: savedURL, loadFirstIfNeeded: false)
        }
        return savedURL
    }

    @discardableResult
    func flushPendingAutosaveForTesting() throws -> URL? {
        try saveCurrentNote(force: false)
    }

    func flushBackgroundAutosaveForTesting() {
        autosaveTask?.cancel()
        autosaveTask = nil
        autosaveCurrentNote()
        drainBackgroundAutosaves()
    }

    func triggerBackgroundAutosaveForTesting() {
        autosaveTask?.cancel()
        autosaveTask = nil
        autosaveCurrentNote()
    }

    func waitForBackgroundAutosaveForTesting() async {
        while backgroundAutosaveIsActive {
            await withCheckedContinuation { continuation in
                autosavePersistenceQueue.async {
                    continuation.resume()
                }
            }
            drainBackgroundAutosaves()
        }
    }
}
