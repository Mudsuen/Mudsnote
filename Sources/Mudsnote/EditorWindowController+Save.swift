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
                let expectedContents: String
                if let sourceContentsAtLoad {
                    expectedContents = sourceContentsAtLoad
                } else {
                    expectedContents = try String(contentsOf: existingURL, encoding: .utf8)
                }
                let result = try noteStore.updateNote(
                    at: existingURL,
                    title: document.title,
                    body: document.body,
                    tags: document.tags,
                    expectedContents: expectedContents,
                    updatesInPlace: false,
                    in: selectedDirectoryURL
                )
                savedURL = result.url
                sourceContentsAtLoad = result.sourceContents
                if let originalURL = result.conflictedOriginalURL {
                    presentErrorAlert(
                        message: "检测到外部修改",
                        details: "外部版本保留在：\n\(originalURL.path)\n\n当前编辑另存为：\n\(savedURL.path)"
                    )
                }
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
        do {
            try persistDraft(force: true)
        } catch {
            handleDraftPersistenceFailureForTransition(error)
            return
        }
        suppressAutosave = true
        defer { suppressAutosave = false }

        do {
            let note = try noteStore.loadNoteDocument(at: url)
            activeFloatingNoteURL = url
            selectedDirectoryURL = url.deletingLastPathComponent()
            sourceContentsAtLoad = note.sourceContents
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
                openWindows: floatingNoteWindows,
                onOpen: onRequestOpenFloatingNote,
                onActivate: onRequestActivateFloatingNote,
                onClose: onRequestCloseFloatingNote,
                onCreate: onRequestCreateFloatingNote
            )
            floatingNoteBrowserController = controller
        }

        controller.show(relativeTo: anchorView, parentWindow: window)
    }

    func refreshFloatingNoteBrowser() {
        floatingNoteBrowserController?.refresh()
    }

    @objc func quickCaptureDirectoryPressed() {
        guard let directoryButton = quickCaptureDirectoryButton as? FocusAwareGhostButton else { return }
        let menu = makeQuickCaptureDirectoryMenu()
        defer {
            directoryButton.highlight(false)
            directoryButton.updateAppearance()
        }
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: directoryButton.bounds.height + 6),
            in: directoryButton
        )
    }

    func makeQuickCaptureDirectoryMenu() -> NSMenu {
        let menu = NSMenu(title: "笔记文件夹")
        menu.autoenablesItems = false

        for directory in quickCaptureMainDirectories() {
            let normalizedDirectory = directory.standardizedFileURL
            let item = NSMenuItem(
                title: quickCaptureFolderDisplayName(for: normalizedDirectory),
                action: #selector(quickCaptureDirectoryMenuItemPressed(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = normalizedDirectory
            item.toolTip = displayPath(normalizedDirectory)
            item.state = normalizedDirectory.path == selectedDirectoryURL.standardizedFileURL.path ? .on : .off
            menu.addItem(item)
        }

        if menu.items.isEmpty {
            let item = NSMenuItem(title: displayPath(noteStore.notesDirectory), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        return menu
    }

    func quickCaptureMainDirectories() -> [URL] {
        let fileManager = FileManager.default
        let childDirectories = noteStore.preferredDirectories.flatMap { root in
            ((try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []).filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
        }

        let candidates = childDirectories.isEmpty ? noteStore.preferredDirectories : childDirectories
        var seenPaths = Set<String>()
        let inboxPath = noteStore.preferredInboxDirectory.standardizedFileURL.path
        return candidates
            .map(\.standardizedFileURL)
            .filter { seenPaths.insert($0.path).inserted }
            .sorted { lhs, rhs in
                let lhsIsInbox = lhs.path == inboxPath
                let rhsIsInbox = rhs.path == inboxPath
                if lhsIsInbox != rhsIsInbox { return lhsIsInbox }
                return quickCaptureFolderDisplayName(for: lhs)
                    .localizedCaseInsensitiveCompare(quickCaptureFolderDisplayName(for: rhs)) == .orderedAscending
            }
    }

    @objc private func quickCaptureDirectoryMenuItemPressed(_ sender: NSMenuItem) {
        guard let directory = (sender.representedObject as? URL)?.standardizedFileURL else { return }
        selectedDirectoryURL = directory
        isDirty = true
        refreshChrome()
        do {
            try persistDraft(force: true)
        } catch {
            handleDraftPersistenceFailureForTransition(error)
        }
    }

    private func handleDraftPersistenceFailureForTransition(_ error: Error) {
        statusLabel.stringValue = "草稿保存失败，当前编辑仍保留"
        NSSound.beep()
        if let draftPersistenceErrorHandler {
            draftPersistenceErrorHandler(error)
        } else {
            presentErrorAlert(
                message: "无法保存草稿",
                details: "当前编辑和窗口状态已保留。\n\n\(error.localizedDescription)"
            )
        }
    }

    func presentErrorAlert(message: String, details: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = details
        alert.runModal()
    }
}
