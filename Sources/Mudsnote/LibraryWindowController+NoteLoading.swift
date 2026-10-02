import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

extension LibraryWindowController {
    func loadSelectedRow() {
        let row = tableView.selectedRow
        guard let note = note(at: row) else {
            return
        }
        load(note: note)
    }

    func load(note: NoteSearchResult) {
        if selectedScope == .trash, !isTrashURL(note.url) {
            selectedScope = .folder(note.url.deletingLastPathComponent())
            lastTreeScope = selectedScope
            lastListScope = selectedScope
        }
        if prepareDocumentTab(for: note) { return }
        recordNoteNavigation(to: note.url)
        isLoadingInitialNote = false
        persistedLaunchFallbackURL = nil
        isCreatingNewNote = false
        cancelActiveNoteLoad(preservingFallback: true)
        notePrefetchTask?.cancel()
        notePrefetchTask = nil
        if let cached = cachedLoadedNote(for: note) {
            noteLoadFallbackURL = nil
            applyLoadedNote(cached, for: note)
            scheduleCachedNoteValidation(cached, for: note)
            releaseDeferredLaunchWorkIfReady()
            return
        }

        guard window?.isVisible == true,
              visualQASelectedURL == nil else {
            loadNoteSynchronously(note)
            return
        }

        beginNoteSwitchLoading(note)
        let generation = noteLoadGeneration
        let editorRevision = editorContentRevision
        let noteLoader = noteLoader
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            let result = Result<LoadedLibraryNote, Error> {
                try noteLoader(note.url)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      !Task.isCancelled,
                      generation == self.noteLoadGeneration,
                      editorRevision == self.editorContentRevision,
                      self.selectedNoteStillMatchesInitialLoad(note) else {
                    return
                }
                self.noteLoadTask = nil
                self.applyLoadedNoteResult(result, for: note)
            }
        }
        noteLoadTask = task
    }

    func reloadSelectedNoteAfterExternalChange(_ note: NoteSearchResult) {
        cancelActiveNoteLoad()
        let generation = noteLoadGeneration
        let editorRevision = editorContentRevision
        let noteLoader = noteLoader
        let fileModificationDateLoader = fileModificationDateLoader
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            let result = Result<LoadedLibraryNote, Error> {
                try noteLoader(note.url)
            }
            let fileModifiedAt = fileModificationDateLoader(note.url)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      !Task.isCancelled,
                      generation == self.noteLoadGeneration,
                      editorRevision == self.editorContentRevision,
                      !self.isDirty,
                      self.selectedNoteStillMatchesInitialLoad(note) else { return }
                self.noteLoadTask = nil
                switch result {
                case .success(let loaded):
                    let cached = self.cacheLoadedNote(
                        loaded,
                        for: note,
                        fileModifiedAt: fileModifiedAt
                    )
                    self.applyLoadedNote(cached, for: note, preservingEditorSelection: true)
                case .failure(let error):
                    self.presentErrorAlert(message: "无法刷新笔记", details: error.localizedDescription)
                }
            }
        }
        noteLoadTask = task
    }

    func loadNoteSynchronously(_ note: NoteSearchResult) {
        do {
            let loaded = try noteLoader(note.url)
            applyLoadedNoteResult(.success(loaded), for: note)
        } catch {
            presentErrorAlert(message: "无法打开笔记", details: error.localizedDescription)
        }
    }

    func cancelActiveNoteLoad(preservingFallback: Bool = false) {
        noteLoadTask?.cancel()
        noteLoadTask = nil
        noteLoadGeneration += 1
        if !preservingFallback {
            noteLoadFallbackURL = nil
        }
    }

    func beginNoteSwitchLoading(_ note: NoteSearchResult) {
        if noteLoadFallbackURL == nil {
            noteLoadFallbackURL = selectedURL
        }
        isLoadingInitialNote = true
        setSelectedURLForLibrary(note.url)
        setEditorEditable(false)
        updateEditorStatus("正在载入…")
        updateToolbarActionState()
    }

    func applyLoadedNoteResult(
        _ result: Result<LoadedLibraryNote, Error>,
        for note: NoteSearchResult,
        fileModifiedAt: Date? = nil
    ) {
        isLoadingInitialNote = false
        defer { releaseDeferredLaunchWorkIfReady() }
        switch result {
        case .success(let loaded):
            noteLoadFallbackURL = nil
            let cached = cacheLoadedNote(loaded, for: note, fileModifiedAt: fileModifiedAt)
            applyLoadedNote(cached, for: note)
        case .failure(let error):
            let fallbackURL = noteLoadFallbackURL
            noteLoadFallbackURL = nil
            setSelectedURLForLibrary(fallbackURL)
            setEditorEditable(selectedScope != .trash)
            restoreNoteBrowserSelection(to: fallbackURL)
            updateToolbarActionState()
            presentErrorAlert(message: "无法打开笔记", details: error.localizedDescription)
        }
    }

    func applyLoadedNote(_ cached: LoadedLibraryNoteCacheEntry, for note: NoteSearchResult) {
        applyLoadedNote(cached, for: note, preservingEditorSelection: false)
    }

    func applyLoadedNote(
        _ cached: LoadedLibraryNoteCacheEntry,
        for note: NoteSearchResult,
        preservingEditorSelection: Bool
    ) {
        setSelectedURLForLibrary(note.url)
        activeDocumentTab.url = note.url
        activeDocumentTab.title = note.title.isEmpty
            ? note.url.deletingPathExtension().lastPathComponent
            : note.title
        activeDocumentTab.isDirty = false
        updateDocumentTabBar()
        selectedSourceContents = cached.loaded.sourceContents
        setEditorEditable(selectedScope != .trash)

        let preservedSelection = preservingEditorSelection ? editorTextView.selectedRange() : nil
        if preservingEditorSelection,
           titleField.stringValue == cached.loaded.title,
           selectedTags == cached.loaded.tags,
           normalizedEditorMarkdownBody() == normalizedMarkdownBody(cached.loaded.body) {
            isDirty = false
            updateEditorCreatedDate(note.createdAt)
            updateEditorStatus(editorEditedDateText(for: note.modifiedAt))
            updateToolbarActionState()
            refreshNoteLinks(for: note.url, body: cached.loaded.body)
            return
        }

        let renderedBody: NSAttributedString
        if let rendered = cached.renderedBody {
            renderedBody = rendered
        } else {
            let rendered = MarkdownRichTextCodec.render(
                markdown: MarkdownEditorDocument.composeEditorText(
                    title: cached.loaded.title,
                    body: cached.loaded.body,
                    hasMetadataTags: !cached.loaded.tags.isEmpty
                ),
                theme: theme,
                baseURL: note.url,
                imageDisplayWidthProvider: noteStore.libraryImageDisplayWidth(for:)
            )
            renderedBody = rendered
            if !MarkdownEditorDocument.containsAttachmentReference(in: cached.loaded.body) {
                cached.renderedBody = rendered.copy() as? NSAttributedString
            }
        }

        applyDocument(
            title: cached.loaded.title,
            body: cached.loaded.body,
            tags: cached.loaded.tags,
            renderedBody: renderedBody,
            preservedSelection: preservedSelection
        )
        isDirty = false
        updateEditorCreatedDate(note.createdAt)
        updateEditorStatus(editorEditedDateText(for: note.modifiedAt))
        applyEditorSearchHighlightsForCurrentQuery()
        updateToolbarActionState()
        refreshNoteLinks(for: note.url, body: cached.loaded.body)
        prefetchAdjacentNotes(around: note)
    }
}
