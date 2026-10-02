import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

extension LibraryWindowController {
    func toggleSourceSection(_ section: LibrarySourceSection) {
        let shouldExpand = isSourceSectionCollapsed(section)
        setSourceSection(section, collapsed: !shouldExpand)
        guard let item = sourceOutlineItemsByIdentifier[
            section == .folders ? "group:files" : "group:tags"
        ] else { return }
        if shouldExpand {
            sourceOutlineView.expandItem(item, expandChildren: false)
            refreshSourceSelection()
        } else {
            sourceOutlineView.collapseItem(item, collapseChildren: false)
        }
    }

    func setSourceSection(_ section: LibrarySourceSection, collapsed: Bool) {
        switch section {
        case .folders:
            sourceFoldersSectionCollapsed = collapsed
            noteStore.libraryFoldersSectionCollapsed = collapsed
            if !collapsed {
                scheduleDeferredSourceFolderLoad()
            }
        case .tags:
            sourceTagsSectionCollapsed = collapsed
            noteStore.libraryTagsSectionCollapsed = collapsed
            if !collapsed {
                scheduleDeferredSourceTagLoad()
            }
        }
    }

    func persistSourceDisclosureState() {
        noteStore.libraryCollapsedFolderPaths = collapsedFolderPaths
        noteStore.libraryExpandedFolderPaths = expandedFolderPaths
    }

    func reloadPersistedSourceDisclosureState() {
        collapsedFolderPaths = noteStore.libraryCollapsedFolderPaths
        expandedFolderPaths = noteStore.libraryExpandedFolderPaths
        sourceFoldersSectionCollapsed = noteStore.libraryFoldersSectionCollapsed
        sourceTagsSectionCollapsed = noteStore.libraryTagsSectionCollapsed
    }

    @objc
    func addFolderPressed() {
        beginInlineFolderCreationForLibrary()
    }

    @objc
    func addExistingLibraryFolderMenuItemPressed() {
        presentAddExistingLibraryFolderPanelForLibrary()
    }

    @objc
    func removeLibraryFolderMenuItemPressed(_ sender: NSMenuItem) {
        guard let directory = sender.representedObject as? URL,
              confirmDestructiveAction(
                title: "从资料库移除？",
                message: "只会从列表移除该文件夹，不会删除其中的文件。"
              ) else { return }

        do {
            try removeRegisteredLibraryFolderForLibrary(at: directory)
        } catch {
            presentErrorAlert(message: "无法移除文件夹", details: error.localizedDescription)
        }
    }

    @objc
    func revealLibraryFolderMenuItemPressed(_ sender: NSMenuItem) {
        guard let directory = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([directory.standardizedFileURL])
    }

    @objc
    func toggleSourceListPressed() {
        setSourceListVisibleForLibrary(
            !isSourceListVisibleForLibrary,
            animated: window?.isVisible == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }

    @objc
    func toggleSidebarPresentationPressed() {
        if !searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = clearSearchFromKeyboard()
            setSidebarPresentation(.tree, animated: false)
            return
        }
        setSidebarPresentation(
            sidebarPresentation == .tree ? .list : .tree,
            animated: window?.isVisible == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }

    @objc
    func newNotePressed() {
        do {
            try saveCurrentNoteIfNeeded(allowBackgroundHandoff: true)
            if noteListViewMode == .gallery {
                noteListViewMode = .list
                noteStore.libraryNoteViewModeRawValue = LibraryNoteViewMode.list.rawValue
                applyNoteListViewModeChrome(animated: window?.isVisible == true)
            }
            if selectedScope == .trash {
                selectedScope = .folder(noteStore.notesDirectory)
            }
            cancelActiveNoteLoad()
            isLoadingInitialNote = false
            isCreatingNewNote = true
            setSelectedURLForLibrary(nil)
            selectedSourceContents = nil
            noteLinksView.update(.empty)
            selectedTags = []
            suppressSelectionChanges = true
            tableView.deselectAll(nil)
            suppressSelectionChanges = false
            setEditorEditable(true)
            applyDocument(title: "", body: "", tags: [])
            isDirty = true
            updateEditorCreatedDate(Date())
            if backgroundAutosaveIsActive {
                autosaveCurrentNote()
            } else {
                _ = try saveCurrentNote(force: true)
            }
            updateEditorStatus(editorEditedDateText(for: Date()))
            refreshSourceSelection()
            updateToolbarActionState()
            window?.makeFirstResponder(editorTextView)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCreatingNewNote else { return }
                self.window?.makeFirstResponder(self.editorTextView)
            }
        } catch {
            presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription)
        }
    }

    func createNewNoteForLibrary() {
        newNotePressed()
    }

    func createNewFolderForLibrary() {
        addFolderPressed()
    }

    func presentAddExistingLibraryFolderPanelForLibrary() {
        let panel = NSOpenPanel()
        panel.title = "将文件夹添加到资料库"
        panel.prompt = "添加"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = noteStore.notesDirectory.deletingLastPathComponent()

        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do {
            try addExistingLibraryFolderForLibrary(at: directory)
        } catch {
            presentErrorAlert(message: "无法添加文件夹", details: error.localizedDescription)
        }
    }

    func focusSearchForLibrary() {
        window?.makeFirstResponder(searchField)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.searchField)
        }
    }

    @objc
    func savePressed() {
        do {
            _ = try saveCurrentNoteForLibrary()
        } catch {
            presentErrorAlert(message: "保存失败", details: error.localizedDescription)
        }
    }

    @objc
    func openSelectedInSeparateWindow() {
        guard canUseSingleSelectedNote, let selectedURL else { return }
        onOpenInSeparateWindow(selectedURL)
    }

    func handleNoteListKeyCommand(_ command: LibraryNoteKeyCommand) -> Bool {
        switch command {
        case .open:
            guard selectedURL != nil else { return false }
            openSelectedInSeparateWindow()
            return true
        case .delete:
            guard selectedURL != nil else { return false }
            do {
                try deleteSelectedNotesInBackgroundForLibrary()
                return true
            } catch {
                presentErrorAlert(message: selectedScope == .trash ? "永久删除失败" : "删除失败", details: error.localizedDescription)
                return true
            }
        case .moveDown:
            return moveNoteListSelection(.next)
        case .moveUp:
            return moveNoteListSelection(.previous)
        }
    }

    @objc
    func formatPressed(_ sender: Any?) {
        guard canEditCurrentDocument, !isEditorShowingMarkdownSource else { return }
        let menu = makeFormatMenuForLibrary()
        guard !menu.items.isEmpty else { return }
        popToolbarMenu(menu, from: sender)
    }

    @objc
    func formatMenuItemPressed(_ sender: NSMenuItem) {
        guard let command = LibraryFormatCommand(rawValue: sender.tag) else { return }
        applyFormatCommand(command)
    }

    @objc
    func checklistPressed() {
        guard canEditCurrentDocument, !isEditorShowingMarkdownSource else { return }
        focusEditorForLibraryAction()
        let undoSnapshot = libraryFormattingUndoSnapshot()
        toggleParagraphKind(.checklist(checked: false))
        registerLibraryFormattingUndoIfNeeded(before: undoSnapshot, actionName: "待办列表")
    }

    @objc
    func tablePressed() {
        guard canEditCurrentDocument, !isEditorShowingMarkdownSource else { return }
        insertTableForLibrary()
    }

    @objc
    func linkPressed() {
        guard canEditCurrentDocument, !isEditorShowingMarkdownSource else { return }
        if let link = editorTextView.linkReference(for: editorTextView.selectedRange()) {
            presentLinkEditorForLibrary(
                title: "编辑链接",
                destination: link.url,
                name: link.label
            ) { [weak self] destination, name in
                self?.updateLinkForLibrary(
                    link,
                    label: name.isEmpty ? destination : name,
                    url: destination
                )
            }
            return
        }

        let defaultLabel = selectedTextForLinkDefault()
        presentLinkEditorForLibrary(
            title: "添加链接",
            destination: "",
            name: defaultLabel
        ) { [weak self] destination, name in
            self?.insertLinkForLibrary(
                label: name.isEmpty ? destination : name,
                url: destination
            )
        }
    }

    @objc
    func attachmentPressed() {
        guard canEditCurrentDocument, !isEditorShowingMarkdownSource else { return }
        let panel = NSOpenPanel()
        panel.title = "添加附件"
        panel.prompt = "添加"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true

        guard panel.runModal() == .OK else { return }

        do {
            for url in panel.urls {
                _ = try insertAttachmentReferenceForLibrary(from: url)
            }
        } catch {
            presentErrorAlert(message: "添加附件失败", details: error.localizedDescription)
        }
    }

    @objc
    func toggleEditorSourceModePressed() {
        guard canEditCurrentDocument, let storage = editorTextView.textStorage else { return }
        let selection = editorTextView.selectedRange()
        suppressEditorChanges = true
        if isEditorShowingMarkdownSource {
            let markdown = storage.string
            editorTextView.isRichText = true
            editorTextView.markdownPasteTheme = theme
            storage.setAttributedString(
                MarkdownRichTextCodec.render(
                    markdown: markdown,
                    theme: theme,
                    baseURL: selectedURL,
                    imageDisplayWidthProvider: noteStore.libraryImageDisplayWidth(for:)
                )
            )
            markLoadedUnifiedTitleFormatting()
            editorTextView.typingAttributes = theme.baseAttributes(for: .paragraph)
            isEditorShowingMarkdownSource = false
        } else {
            let markdown = MarkdownRichTextCodec.serialize(editorTextView.attributedString(), theme: theme)
            removeEditorSearchHighlights()
            editorTextView.isRichText = false
            editorTextView.markdownPasteTheme = nil
            let sourceAttributes: [NSAttributedString.Key: Any] = [
                .font: theme.codeFont,
                .foregroundColor: theme.textColor,
                .paragraphStyle: theme.paragraphStyle(for: .paragraph)
            ]
            storage.setAttributedString(NSAttributedString(string: markdown, attributes: sourceAttributes))
            editorTextView.typingAttributes = sourceAttributes
            isEditorShowingMarkdownSource = true
        }
        suppressEditorChanges = false
        editorTextView.setSelectedRange(NSRange(location: min(selection.location, storage.length), length: 0))
        editorTextView.window?.makeFirstResponder(editorTextView)
        updateToolbarActionState()
    }

    @objc
    func moveSelectedNotePressed(_ sender: Any?) {
        guard canMoveSelectedNote else { return }
        let menu = makeMoveNoteMenu()
        guard !menu.items.isEmpty else { return }
        popToolbarMenu(menu, from: sender)
    }

    @objc
    func moveNoteMenuItemPressed(_ sender: NSMenuItem) {
        guard let directory = sender.representedObject as? URL else { return }
        do {
            _ = try moveSelectedNotesForLibrary(to: directory)
        } catch {
            presentErrorAlert(message: "移动失败", details: error.localizedDescription)
        }
    }

    @objc
    func deleteSelectedNotePressed() {
        do {
            try deleteSelectedNotesInBackgroundForLibrary()
        } catch {
            presentErrorAlert(message: "删除失败", details: error.localizedDescription)
        }
    }

    @objc
    func togglePinnedNotesPressed() {
        _ = togglePinnedStateForSelectedNotesForLibrary()
    }

    @objc
    func renameFolderMenuItemPressed(_ sender: NSMenuItem) {
        guard let directory = sender.representedObject as? URL else { return }
        beginInlineFolderRenameForLibrary(at: directory)
    }

    @objc
    func deleteFolderMenuItemPressed(_ sender: NSMenuItem) {
        guard let directory = sender.representedObject as? URL else { return }

        do {
            selectedScope = .folder(directory)
            try deleteSelectedFolderForLibrary()
        } catch {
            presentErrorAlert(message: "无法删除文件夹", details: error.localizedDescription)
        }
    }

    @objc
    func moveFolderMenuItemPressed(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? LibraryFolderMoveRequest else { return }
        do {
            _ = try moveFolderForLibrary(at: request.source, to: request.destinationParent)
        } catch {
            presentErrorAlert(message: "无法移动文件夹", details: error.localizedDescription)
        }
    }

    @objc
    func changeFolderIconMenuItemPressed(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? LibraryFolderIconRequest else { return }
        noteStore.setLibraryFolderIconName(request.symbolName, for: request.folderURL)
        refreshVisibleSourceOutlinePresentation()
        sourceOutlineView.window?.displayIfNeeded()
    }

    @objc
    func restoreSelectedNotePressed() {
        do {
            _ = try restoreSelectedNoteForLibrary()
        } catch {
            presentErrorAlert(message: "恢复失败", details: error.localizedDescription)
        }
    }

    @objc
    func revealSelectedNoteInFinderPressed() {
        let urls = revealSelectedNotesInFinderForLibrary()
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    @objc
    func copySelectedMarkdownPathPressed() {
        _ = copySelectedMarkdownPathForLibrary()
    }

    @objc
    func copySelectedMarkdownContentPressed() {
        do {
            _ = try copySelectedMarkdownContentForLibrary()
        } catch {
            presentErrorAlert(message: "复制失败", details: error.localizedDescription)
        }
    }

    @objc
    func exportSelectedMarkdownPressed() {
        guard canExportSelectedNote else { return }

        let sourceURLs = selectedMarkdownFileURLsForLibrary()
        if sourceURLs.count > 1 {
            let panel = NSOpenPanel()
            panel.title = "导出 Markdown 笔记"
            panel.prompt = "导出"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false

            guard panel.runModal() == .OK,
                  let destinationDirectory = panel.url else { return }

            do {
                _ = try exportSelectedMarkdownFilesForLibrary(to: destinationDirectory)
            } catch {
                presentErrorAlert(message: "导出失败", details: error.localizedDescription)
            }
            return
        }

        guard let sourceURL = sourceURLs.first else { return }

        let panel = NSSavePanel()
        panel.title = "导出 Markdown"
        panel.prompt = "导出"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "markdown"),
            .plainText
        ].compactMap { $0 }
        panel.nameFieldStringValue = sourceURL.lastPathComponent

        guard panel.runModal() == .OK,
              let destinationURL = panel.url else { return }

        do {
            _ = try exportSelectedMarkdownForLibrary(to: destinationURL)
        } catch {
            presentErrorAlert(message: "导出失败", details: error.localizedDescription)
        }
    }
}
