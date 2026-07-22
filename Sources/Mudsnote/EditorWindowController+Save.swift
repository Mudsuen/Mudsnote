import AppKit
import Foundation
import MudsnoteCore

extension EditorWindowController {

    @objc func savePressed() {
        let document = currentDocument()

        if document.title.isEmpty && document.body.isEmpty {
            noteStore.deleteDraft(id: currentDraftID)
            window?.close()
            return
        }

        do {
            let previousDraftID = currentDraftID
            let savedURL: URL

            if let existingURL = activeFloatingNoteURL ?? fileURL {
                savedURL = try noteStore.updateNote(
                    at: existingURL,
                    title: document.title,
                    body: document.body,
                    tags: document.tags,
                    in: selectedDirectoryURL
                )
            } else {
                savedURL = try noteStore.saveNewNote(
                    title: document.title,
                    body: document.body,
                    tags: document.tags,
                    in: selectedDirectoryURL
                )
            }

            fileURL = savedURL
            if isFloatingNoteMode {
                activeFloatingNoteURL = savedURL
                fileURL = nil
            }
            selectedDirectoryURL = savedURL.deletingLastPathComponent()
            noteStore.deleteDraft(id: previousDraftID)
            noteStore.deleteDraft(id: currentDraftID)
            isDirty = false
            onSave(savedURL)
            window?.close()
        } catch {
            presentErrorAlert(message: "无法保存笔记", details: error.localizedDescription)
        }
    }

    @objc func cancelPressed() {
        window?.close()
    }

    @objc func searchPressed() {
        if isFloatingNoteMode {
            showFloatingNoteBrowser(relativeTo: floatingNoteBrowseButton)
            return
        }
        onRequestSearch()
    }

    func loadFloatingNote(at url: URL) {
        guard isFloatingNoteMode else { return }
        persistDraft(force: true)
        suppressAutosave = true
        defer { suppressAutosave = false }

        do {
            let note = try noteStore.loadNote(at: url)
            activeFloatingNoteURL = url
            selectedDirectoryURL = url.deletingLastPathComponent()
            applyInitialContent(title: note.title, body: note.body)

            if let draft = noteStore.loadDraft(id: currentDraftID), draft.sourcePath == url.path {
                applyBodyMarkdown(MarkdownEditorDocument(title: draft.title, body: draft.body).editorText)
                selectedDirectoryURL = URL(fileURLWithPath: draft.selectedDirectoryPath, isDirectory: true)
                isDirty = true
                statusLabel.stringValue = "已恢复"
            } else {
                isDirty = false
                statusLabel.stringValue = "编辑中"
            }

            suppressAutosave = false
            refreshChrome()
            overlayScrollIndicator?.updateIndicator()
            updateTypingAttributesFromInsertionPoint()
            updateToolbarSelectionState()
            updateInlineSuggestions()
            window?.makeFirstResponder(editorTextView)
            editorTextView.setSelectedRange(NSRange(location: editorTextView.string.utf16.count, length: 0))
        } catch {
            presentErrorAlert(message: "无法加载笔记", details: error.localizedDescription)
        }
    }

    func showFloatingNoteBrowser(relativeTo anchorView: NSView?) {
        guard isFloatingNoteMode else { return }

        if floatingNoteBrowserController?.window?.isVisible == true {
            floatingNoteBrowserController?.window?.close()
            return
        }

        let controller: FloatingNoteBrowserController
        if let existing = floatingNoteBrowserController {
            controller = existing
        } else {
            controller = FloatingNoteBrowserController(
                noteStore: noteStore,
                selectedWindowID: floatingWindowID,
                openWindows: floatingNoteWindows,
                onOpen: onRequestOpenFloatingNote,
                onActivate: onRequestActivateFloatingNote,
                onClose: onRequestCloseFloatingNote,
                onCreate: onRequestCreateFloatingNote
            )
            floatingNoteBrowserController = controller
        }

        controller.selectedWindowID = floatingWindowID
        controller.show(relativeTo: anchorView, parentWindow: window)
    }

    func refreshFloatingNoteBrowser() {
        floatingNoteBrowserController?.refresh()
    }

    @objc func quickCaptureDirectoryPressed() {
        guard let directory = chooseDirectory(startingAt: selectedDirectoryURL)?.standardizedFileURL else { return }
        selectedDirectoryURL = directory
        isDirty = true
        refreshChrome()
        persistDraft(force: true)
    }

    func presentErrorAlert(message: String, details: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = details
        alert.runModal()
    }
}
