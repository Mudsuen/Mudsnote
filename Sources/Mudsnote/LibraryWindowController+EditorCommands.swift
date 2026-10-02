import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

extension LibraryWindowController {
    func insertLinkForLibrary(label: String, url: String) {
        guard selectedScope != .trash else { return }
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }
        let linkLabel = trimmedLabel.isEmpty ? trimmedURL : trimmedLabel
        replaceSelectionWithRenderedMarkdown("[\(escapedMarkdownLabel(linkLabel))](\(escapedMarkdownURL(trimmedURL)))")
    }

    @discardableResult
    func insertAttachmentReferenceForLibrary(from fileURL: URL) throws -> URL {
        guard selectedScope != .trash else { return fileURL }
        let noteDirectory = targetDirectoryForAttachment()
        let copiedURL = try MarkdownAttachmentStorage.storeFile(fileURL, in: noteDirectory)
        insertStoredAttachmentForLibrary(copiedURL, relativeTo: noteDirectory)
        return copiedURL
    }

    func markdownTextView(_ textView: MarkdownTextView, pasteAttachmentsFrom pasteboard: NSPasteboard) -> Bool {
        guard textView === editorTextView,
              canEditCurrentDocument,
              let payload = MarkdownAttachmentStorage.pastePayload(from: pasteboard) else {
            return false
        }

        let noteDirectory = targetDirectoryForAttachment()
        do {
            switch payload {
            case .files(let fileURLs):
                for fileURL in fileURLs {
                    let storedURL = try MarkdownAttachmentStorage.storeFile(fileURL, in: noteDirectory)
                    insertStoredAttachmentForLibrary(storedURL, relativeTo: noteDirectory)
                }
            case .imagePNG(let data):
                let storedURL = try MarkdownAttachmentStorage.storePastedPNG(data, in: noteDirectory)
                insertStoredAttachmentForLibrary(storedURL, relativeTo: noteDirectory)
            }
        } catch {
            presentErrorAlert(message: "粘贴附件失败", details: error.localizedDescription)
        }
        return true
    }

    func insertStoredAttachmentForLibrary(_ fileURL: URL, relativeTo noteDirectory: URL) {
        let markdown = MarkdownAttachmentStorage.markdownReference(for: fileURL, relativeTo: noteDirectory)
        let renderingBaseURL = selectedURL
            ?? noteDirectory.appendingPathComponent(".mudsnote-unsaved.md")
        insertMarkdownBlockForLibrary(markdown, renderingBaseURL: renderingBaseURL)
    }

    func selectedTextForLinkDefault() -> String {
        let selection = editorTextView.selectedRange()
        guard selection.length > 0, NSMaxRange(selection) <= (editorTextView.string as NSString).length else {
            return ""
        }
        return (editorTextView.string as NSString).substring(with: selection)
    }

    func insertMarkdownBlockForLibrary(_ markdown: String, renderingBaseURL: URL? = nil) {
        guard selectedScope != .trash else { return }
        focusEditorForLibraryAction()
        let selection = editorTextView.selectedRange()
        let nsString = editorTextView.string as NSString
        var block = markdown

        if selection.location > 0,
           nsString.substring(with: NSRange(location: selection.location - 1, length: 1)) != "\n" {
            block = "\n" + block
        }
        if NSMaxRange(selection) < nsString.length,
           !block.hasSuffix("\n") {
            block += "\n"
        }

        replaceSelectionWithRenderedMarkdown(block, renderingBaseURL: renderingBaseURL)
    }

    func replaceSelectionWithRenderedMarkdown(_ markdown: String, renderingBaseURL: URL? = nil) {
        guard selectedScope != .trash, let storage = editorTextView.textStorage else { return }
        focusEditorForLibraryAction()
        let selection = editorTextView.selectedRange()
        let rendered = MarkdownRichTextCodec.render(
            markdown: markdown,
            theme: theme,
            baseURL: renderingBaseURL ?? selectedURL,
            imageDisplayWidthProvider: noteStore.libraryImageDisplayWidth(for:)
        )

        suppressEditorChanges = true
        storage.replaceCharacters(in: selection, with: rendered)
        suppressEditorChanges = false
        editorTextView.setSelectedRange(NSRange(location: selection.location + rendered.length, length: 0))
        updateTypingAttributesFromInsertionPoint()
        editorTextView.scrollRangeToVisible(editorTextView.selectedRange())
        markDirty()
    }

    func targetDirectoryForAttachment() -> URL {
        if let selectedURL {
            return selectedURL.deletingLastPathComponent()
        }
        return targetDirectoryForNewNote()
    }

    func escapedMarkdownLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    func escapedMarkdownURL(_ url: String) -> String {
        url
            .replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: ")", with: "%29")
    }

    func markdownTextViewInsertNewline(_ textView: MarkdownTextView) {
        if commitSelectedMetadataTagIfNeeded(insertingTrailingText: "\n") { return }
        guard handleStructuredNewline() else {
            textView.insertNewlineIgnoringFieldEditor(self)
            updateTypingAttributesFromInsertionPoint()
            return
        }
    }

    func markdownTextView(_ textView: MarkdownTextView, shouldInterceptInsertedText text: String) -> Bool {
        guard text == " " || text == "\t" else { return false }
        return commitSelectedMetadataTagIfNeeded(insertingTrailingText: text)
    }

    func commitSelectedMetadataTagIfNeeded(
        insertingTrailingText trailingText: String
    ) -> Bool {
        let selection = editorTextView.selectedRange()
        guard selection.length == 0 else { return false }
        let source = editorTextView.string as NSString
        let caret = min(selection.location, source.length)
        let paragraph = source.paragraphRange(
            for: NSRange(location: caret, length: 0)
        )
        let prefix = source.substring(with: NSRange(
            location: paragraph.location,
            length: max(0, caret - paragraph.location)
        ))
        guard let match = prefix.range(
            of: #"(^|\s)#([^\s#]+)$"#,
            options: .regularExpression
        ) else { return false }
        let token = String(prefix[match]).trimmingCharacters(in: .whitespaces)
        let tag = String(token.dropFirst())
        guard !tag.isEmpty else { return false }
        guard let hash = prefix[match].firstIndex(of: "#") else { return false }
        let tokenRange = NSRange(hash..<match.upperBound, in: prefix)
        let range = NSRange(location: paragraph.location + tokenRange.location, length: tokenRange.length)
        editorTextView.textStorage?.replaceCharacters(in: range, with: trailingText)
        editorTextView.setSelectedRange(NSRange(
            location: range.location + trailingText.utf16.count,
            length: 0
        ))
        dismissEditorSlashSuggestions()
        selectedTags = MarkdownEditorDocument.normalizedTags(selectedTags + [tag])
        editorTextView.setMetadataTags(selectedTags) { [weak self] removed in
            self?.removeSelectedMetadataTag(removed)
        }
        markDirty()
        return true
    }

    @objc func addSelectedNoteTagPressed() {
        guard canEditCurrentDocument else { return }
        editorTextView.beginAddingMetadataTag(suggestions: sourceTagNames) { [weak self] input in
            self?.addSelectedMetadataTag(input)
        }
    }

    func addSelectedMetadataTag(_ input: String) {
        guard canEditCurrentDocument,
              let tag = MarkdownEditorDocument.normalizedTags([input]).first,
              !tag.isEmpty else { return }
        selectedTags = MarkdownEditorDocument.normalizedTags(selectedTags + [tag])
        editorTextView.setMetadataTags(selectedTags) { [weak self] in self?.removeSelectedMetadataTag($0) }
        sourceTagNames = MarkdownEditorDocument.normalizedTags(sourceTagNames + [tag])
        markDirty()
        rebuildSourceRows(includeTags: true)
    }

    @objc func addLibraryTagToNote(_ sender: NSMenuItem) {
        guard let tag = sender.representedObject as? String else { return }
        addSelectedMetadataTag(tag)
    }

    @objc func removeLibraryTagFromNote(_ sender: NSMenuItem) {
        guard canEditCurrentDocument, let tag = sender.representedObject as? String else { return }
        removeSelectedMetadataTag(tag)
    }

    @objc func renameLibraryTagPressed(_ sender: NSMenuItem) {
        guard !tagMutationInProgress else { return }
        guard let tag = sender.representedObject as? String else { return }
        let alert = NSAlert()
        alert.messageText = "重命名标签"
        alert.informativeText = "更新所有使用此标签的笔记；同名标签会合并。"
        let input = NSTextField(string: tag)
        input.frame = NSRect(x: 0, y: 0, width: 280, height: 26)
        input.setAccessibilityLabel("新标签名称")
        alert.accessoryView = input
        alert.addButton(withTitle: "重命名")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn,
              let name = MarkdownEditorDocument.normalizedTags([input.stringValue]).first,
              !name.isEmpty, name != tag else { return }
        do { drainBackgroundAutosaves(); try saveCurrentNoteIfNeeded() }
        catch { presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription); return }
        let store = noteStore
        let roots = store.preferredDirectories
        let extraURLs = externallyOpenedDocumentsByPath.keys.map { URL(fileURLWithPath: $0) }
        tagMutationInProgress = true
        updateEditorStatus("正在重命名标签…")
        Task { [weak self] in
            defer { self?.tagMutationInProgress = false; self?.updateEditorStatus("") }
            do {
                _ = try await Task.detached(priority: .userInitiated) { try store.renameTag(tag, to: name, roots: roots, additionalNoteURLs: extraURLs) }.value
                guard let self else { return }
                selectedTags = MarkdownEditorDocument.normalizedTags(selectedTags.map {
                    $0.localizedCaseInsensitiveCompare(tag) == .orderedSame ? name : $0
                })
                editorTextView.setMetadataTags(selectedTags) { [weak self] in self?.removeSelectedMetadataTag($0) }
                if case .tag(let selected) = selectedScope, selected.localizedCaseInsensitiveCompare(tag) == .orderedSame {
                    selectedScope = .tag(name)
                }
                invalidateSourceTagsForLibrary()
                forceFullLibrarySnapshotReload()
                scheduleDeferredSourceTagLoad()
            } catch { self?.presentErrorAlert(message: "无法重命名标签", details: error.localizedDescription) }
        }
    }

    func removeSelectedMetadataTag(_ tag: String) {
        guard selectedTags.contains(where: { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }) else { return }
        selectedTags.removeAll {
            $0.localizedCaseInsensitiveCompare(tag) == .orderedSame
        }
        editorTextView.setMetadataTags(selectedTags) { [weak self] removed in
            self?.removeSelectedMetadataTag(removed)
        }
        markDirty()
    }

    func markdownTextView(_ textView: MarkdownTextView, handleKeyDown event: NSEvent) -> Bool {
        guard textView === editorTextView else { return false }
        if !editorSuggestionController.view.isHidden {
            switch event.keyCode {
            case UInt16(kVK_DownArrow):
                editorSuggestionController.moveSelection(delta: 1)
                return true
            case UInt16(kVK_UpArrow):
                editorSuggestionController.moveSelection(delta: -1)
                return true
            case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
                if editorTagSuggestion != nil {
                    if editorSuggestionController.acceptSelection() {
                        textView.insertNewlineIgnoringFieldEditor(self)
                        return true
                    }
                    if commitSelectedMetadataTagIfNeeded(insertingTrailingText: "\n") { return true }
                    dismissEditorSlashSuggestions()
                    return false
                }
                editorSuggestionController.acceptSelection()
                return true
            case UInt16(kVK_Escape):
                dismissEditorSlashSuggestions()
                return true
            default:
                break
            }
        }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == UInt16(kVK_Space),
           modifiers.isEmpty,
           let attachment = textView.fileAttachmentReferenceNearSelection() {
            return previewAttachmentForLibrary(atPath: attachment.path)
        }

        guard event.keyCode == UInt16(kVK_Delete),
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command] else {
            return false
        }
        return deleteCurrentMarkdownTableRowForLibrary()
    }

    func updateEditorSlashSuggestions() {
        if editorTextView.hasMarkedText() {
            return
        }
        guard !isEditorShowingMarkdownSource,
              selectedScope != .trash,
              editorTextView.selectedRange().length == 0,
              let host = window?.contentView else {
            editorSlashSuggestionLastInput = nil
            dismissEditorSlashSuggestions()
            return
        }
        guard let string = editorTextView.textStorage?.mutableString else {
            dismissEditorSlashSuggestions()
            return
        }
        let caret = min(editorTextView.selectedRange().location, string.length)
        let maximumLookback = 128
        let lowerBound = max(caret - maximumLookback, 0)
        let newlineRange = string.rangeOfCharacter(
            from: .newlines,
            options: .backwards,
            range: NSRange(location: lowerBound, length: caret - lowerBound)
        )
        let prefixStart = newlineRange.location == NSNotFound
            ? lowerBound
            : NSMaxRange(newlineRange)
        let startsAtParagraphBoundary = prefixStart == 0 || newlineRange.location != NSNotFound
        let prefixRange = NSRange(location: prefixStart, length: caret - prefixStart)
        let prefix = string.substring(with: prefixRange)
        editorSlashSuggestionInspectionLengthForLibrary = prefixRange.length

        let tagPattern = startsAtParagraphBoundary ? #"(^|\s)#([^\s#]*)$"# : #"\s#([^\s#]*)$"#
        if let match = prefix.range(of: tagPattern, options: .regularExpression),
           let hash = prefix[match].firstIndex(of: "#") {
            scheduleDeferredSourceTagLoad(forEditor: true)
            let token = String(prefix[hash..<match.upperBound])
            let query = String(token.dropFirst())
            let range = NSRange(hash..<match.upperBound, in: prefix)
            let replacementRange = NSRange(location: prefixStart + range.location, length: range.length)
            var tags = sourceTagNames.filter { tag in
                !selectedTags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
                    && (query.isEmpty || tag.localizedCaseInsensitiveContains(query))
            }.sorted {
                let lhsPrefix = $0.lowercased().hasPrefix(query.lowercased())
                let rhsPrefix = $1.lowercased().hasPrefix(query.lowercased())
                return lhsPrefix != rhsPrefix ? lhsPrefix : $0.localizedStandardCompare($1) == .orderedAscending
            }
            if !query.isEmpty,
               !tags.contains(where: { $0.localizedCaseInsensitiveCompare(query) == .orderedSame }),
               !selectedTags.contains(where: { $0.localizedCaseInsensitiveCompare(query) == .orderedSame }) {
                tags.insert(query, at: 0)
            }
            tags = Array(tags.prefix(8))
            editorTagSuggestion = (replacementRange, tags)
            editorSlashSuggestion = nil
            editorNoteSuggestion = nil
            hostEditorSuggestionView(in: host)
            editorSuggestionController.updateItems(tags.isEmpty
                ? [SuggestionItem(title: "输入标签名称", subtitle: nil, symbolName: "number", isSelectable: false)]
                : tags.map { tag in
                    SuggestionItem(title: "#\(tag)", subtitle: sourceTagNames.contains(tag) ? "标签" : "新建标签", symbolName: "number")
                })
            let size = editorSuggestionController.preferredContentSize
            let anchor = editorTextView.convert(caretRectInWindow(for: editorTextView, at: replacementRange.location), to: host)
            let origin = NSPoint(
                x: min(max(anchor.minX, 4), max(host.bounds.width - size.width - 4, 4)),
                y: min(max(anchor.minY - size.height - 6, 4), max(host.bounds.height - size.height - 4, 4))
            )
            editorSuggestionController.view.frame = NSRect(origin: origin, size: size)
            editorSuggestionController.view.isHidden = false
            slashCommandInputSourceSession.end()
            return
        }
        editorTagSuggestion = nil

        let mentionPattern = startsAtParagraphBoundary
            ? #"(^|\s)@([^@\n]*)$"#
            : #"\s@([^@\n]*)$"#
        if let match = prefix.range(of: mentionPattern, options: .regularExpression) {
            let matchedText = String(prefix[match])
            if let atIndex = matchedText.firstIndex(of: "@") {
                let token = String(matchedText[atIndex...])
                let query = String(token.dropFirst())
                let matchRange = NSRange(match, in: prefix)
                let tokenOffset = matchedText[..<atIndex].utf16.count
                let replacementRange = NSRange(
                    location: prefixStart + matchRange.location + tokenOffset,
                    length: token.utf16.count
                )
                if editorNoteSuggestionQuery != query {
                    scheduleEditorNoteSuggestions(query: query)
                    dismissEditorSlashSuggestions()
                    return
                }
                guard !editorNoteSuggestions.isEmpty else {
                    dismissEditorSlashSuggestions()
                    return
                }
                editorSlashSuggestion = nil
                editorNoteSuggestion = (
                    replacementRange,
                    editorNoteSuggestions
                )
                hostEditorSuggestionView(in: host)
                editorSuggestionController.updateItems(editorNoteSuggestions.map {
                    SuggestionItem(
                        title: $0.title,
                        subtitle: $0.url.deletingLastPathComponent().lastPathComponent,
                        symbolName: "note.text"
                    )
                })
                let size = editorSuggestionController.preferredContentSize
                let tokenRect = editorTextView.convert(
                    caretRectInWindow(for: editorTextView, at: replacementRange.location),
                    to: host
                )
                var origin = NSPoint(x: tokenRect.minX, y: tokenRect.minY - size.height - 6)
                origin.x = min(max(origin.x, 4), max(host.bounds.width - size.width - 4, 4))
                origin.y = min(max(origin.y, 4), max(host.bounds.height - size.height - 4, 4))
                editorSuggestionController.view.frame = NSRect(origin: origin, size: size)
                editorSuggestionController.view.isHidden = false
                slashCommandInputSourceSession.end()
                return
            }
        }

        if let previousInput = editorSlashSuggestionLastInput,
           previousInput.caret == caret,
           previousInput.prefixStart == prefixStart,
           previousInput.prefix == prefix {
            return
        }
        editorSlashSuggestionLastInput = (caret, prefixStart, prefix)

        let pattern = startsAtParagraphBoundary
            ? #"(^|\s)/([^\s/]*)$"#
            : #"\s/([^\s/]*)$"#
        guard let match = prefix.range(of: pattern, options: .regularExpression) else {
            dismissEditorSlashSuggestions()
            return
        }
        let matchedText = String(prefix[match])
        guard let slashIndex = matchedText.firstIndex(of: "/") else {
            dismissEditorSlashSuggestions()
            return
        }
        let token = String(matchedText[slashIndex...])
        let query = String(token.dropFirst()).lowercased()
        let commands = SlashCommand.matching(query, includesAI: false)
        hostEditorSuggestionView(in: host)
        let matchRange = NSRange(match, in: prefix)
        let tokenOffset = matchedText[..<slashIndex].utf16.count
        let replacementRange = NSRange(
            location: prefixStart + matchRange.location + tokenOffset,
            length: token.utf16.count
        )
        editorSlashSuggestion = (replacementRange, commands)
        editorNoteSuggestion = nil
        let items = commands.isEmpty
            ? [SuggestionItem(title: "无匹配命令", subtitle: nil, symbolName: nil)]
            : commands.map { SuggestionItem(title: $0.title, subtitle: nil, symbolName: nil) }
        editorSuggestionController.updateItems(items)
        let size = editorSuggestionController.preferredContentSize
        let tokenRect = editorTextView.convert(
            caretRectInWindow(for: editorTextView, at: replacementRange.location),
            to: host
        )
        var origin = NSPoint(x: tokenRect.minX, y: tokenRect.minY - size.height - 6)
        origin.x = min(max(origin.x, 4), max(host.bounds.width - size.width - 4, 4))
        origin.y = min(max(origin.y, 4), max(host.bounds.height - size.height - 4, 4))
        editorSuggestionController.view.frame = NSRect(origin: origin, size: size)
        editorSuggestionController.view.isHidden = false
        scheduleEditorSlashInputSourceSwitch()
    }

    func scheduleEditorSlashInputSourceSwitch() {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  !editorSuggestionController.view.isHidden,
                  editorSlashSuggestion != nil else { return }
            slashCommandInputSourceSession.beginIfAllowed(
                hasMarkedText: editorTextView.hasMarkedText(),
                editorIsFirstResponder: window?.firstResponder === editorTextView
            )
        }
    }

    func dismissEditorSlashSuggestions() {
        editorTagSuggestion = nil
        editorSlashSuggestion = nil
        editorNoteSuggestion = nil
        editorSuggestionController.view.isHidden = true
        slashCommandInputSourceSession.end()
    }

    func acceptEditorSlashSuggestion(at index: Int) {
        if let suggestion = editorTagSuggestion, suggestion.items.indices.contains(index) {
            let tag = suggestion.items[index]
            editorTextView.textStorage?.replaceCharacters(in: suggestion.replacementRange, with: "")
            editorTextView.setSelectedRange(NSRange(location: suggestion.replacementRange.location, length: 0))
            dismissEditorSlashSuggestions()
            addSelectedMetadataTag(tag)
            return
        }
        if let suggestion = editorNoteSuggestion,
           suggestion.items.indices.contains(index) {
            let item = suggestion.items[index]
            let sourceURL = selectedURL
                ?? targetDirectoryForNewNote().appendingPathComponent("Untitled.md")
            let markdown = noteStore.markdownKnowledgeLink(
                from: sourceURL,
                to: item.url,
                title: item.title
            )
            editorTextView.setSelectedRange(suggestion.replacementRange)
            dismissEditorSlashSuggestions()
            replaceSelectionWithRenderedMarkdown(markdown, renderingBaseURL: sourceURL)
            return
        }
        guard let suggestion = editorSlashSuggestion,
              suggestion.commands.indices.contains(index),
              let storage = editorTextView.textStorage else { return }
        let command = suggestion.commands[index]
        suppressEditorChanges = true
        storage.replaceCharacters(in: suggestion.replacementRange, with: "")
        suppressEditorChanges = false
        editorTextView.setSelectedRange(NSRange(location: suggestion.replacementRange.location, length: 0))
        dismissEditorSlashSuggestions()
        switch command {
        case .heading1: applyFormatCommand(.heading1)
        case .heading2: applyFormatCommand(.heading2)
        case .heading3: applyFormatCommand(.heading3)
        case .checklist: applyFormatCommand(.checklist)
        case .bulletList: applyFormatCommand(.bullet)
        case .orderedList: applyFormatCommand(.ordered)
        case .divider:
            editorTextView.insertText("---", replacementRange: editorTextView.selectedRange())
            libraryUserDidEdit()
        case .aiSummarize, .aiFix, .aiTodos:
            break
        }
    }

    func scheduleEditorNoteSuggestions(query: String) {
        editorNoteSuggestionTask?.cancel()
        editorNoteSuggestionQuery = query
        editorNoteSuggestions = []
        let noteStore = self.noteStore
        let sourceURL = selectedURL
            ?? targetDirectoryForNewNote().appendingPathComponent("Untitled.md")
        let currentBody = normalizedEditorMarkdownBody()
        editorNoteSuggestionTask = Task { [weak self] in
            let suggestions = await Task.detached(priority: .userInitiated) {
                noteStore.noteMentionSuggestions(
                    query: query,
                    sourceURL: sourceURL,
                    currentBody: currentBody
                )
            }.value
            guard !Task.isCancelled,
                  let self,
                  editorNoteSuggestionQuery == query else { return }
            editorNoteSuggestions = suggestions
            editorNoteSuggestionTask = nil
            editorSlashSuggestionLastInput = nil
            updateEditorSlashSuggestions()
        }
    }

    func markdownTextViewToggleBold(_ textView: MarkdownTextView) { applyFormatCommand(.bold) }

    func markdownTextViewToggleItalic(_ textView: MarkdownTextView) { applyFormatCommand(.italic) }

    func markdownTextViewToggleUnderline(_ textView: MarkdownTextView) { applyFormatCommand(.underline) }

    func markdownTextViewToggleStrikethrough(_ textView: MarkdownTextView) { applyFormatCommand(.strikethrough) }

    func markdownTextViewToggleHeading(_ textView: MarkdownTextView) { applyFormatCommand(.heading1) }

    func markdownTextViewToggleBulletList(_ textView: MarkdownTextView) { applyFormatCommand(.bullet) }

    func markdownTextViewToggleOrderedList(_ textView: MarkdownTextView) { applyFormatCommand(.ordered) }

    func markdownTextViewToggleChecklist(_ textView: MarkdownTextView) { applyFormatCommand(.checklist) }

    func markdownTextView(_ textView: MarkdownTextView, didClickCharacterAt index: Int) -> Bool {
        toggleChecklistIfNeeded(atCharacterIndex: index)
    }

    func markdownTextView(_ textView: MarkdownTextView, didDoubleClickAttachmentAt index: Int) -> Bool {
        guard
            let storage = textView.textStorage,
            index >= 0,
            index < storage.length,
            let path = storage.attribute(.qmAttachmentFilePath, at: index, effectiveRange: nil) as? String
        else { return false }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
        return true
    }

    func markdownTextView(_ textView: MarkdownTextView, didCommandClickLinkAt index: Int) -> Bool {
        guard let link = textView.linkReference(atCharacterIndex: index) else { return false }
        return openMarkdownLinkForLibrary(link)
    }

    @discardableResult
    func configureAttachmentContextMenu(_ menu: NSMenu, forAttachment attachment: MarkdownAttachmentReference) -> Bool {
        configureAttachmentContextMenu(menu, forAttachmentPath: attachment.path, markdown: attachment.markdown)
    }

    @discardableResult
    func configureAttachmentContextMenu(_ menu: NSMenu, forAttachmentPath path: String, markdown: String? = nil) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }

        let previewItem = NSMenuItem(title: "快速查看", action: #selector(previewAttachmentMenuItemPressed(_:)), keyEquivalent: " ")
        previewItem.keyEquivalentModifierMask = []
        previewItem.target = self
        previewItem.representedObject = path

        let openItem = NSMenuItem(title: "打开附件", action: #selector(openAttachmentMenuItemPressed(_:)), keyEquivalent: "")
        openItem.target = self
        openItem.representedObject = path

        let revealItem = NSMenuItem(title: "在 Finder 中显示", action: #selector(revealAttachmentMenuItemPressed(_:)), keyEquivalent: "")
        revealItem.target = self
        revealItem.representedObject = path

        let copyPathItem = NSMenuItem(title: "复制附件路径", action: #selector(copyAttachmentPathMenuItemPressed(_:)), keyEquivalent: "")
        copyPathItem.target = self
        copyPathItem.representedObject = path

        let copyMarkdownItem = NSMenuItem(title: "复制 Markdown 链接", action: #selector(copyAttachmentMarkdownMenuItemPressed(_:)), keyEquivalent: "")
        copyMarkdownItem.target = self
        copyMarkdownItem.representedObject = markdown
        copyMarkdownItem.isEnabled = !(markdown?.isEmpty ?? true)

        if !menu.items.isEmpty {
            menu.insertItem(.separator(), at: 0)
        }
        for item in [copyPathItem, copyMarkdownItem, revealItem, openItem, previewItem] {
            menu.insertItem(item, at: 0)
        }
        return true
    }

    @objc
    func previewAttachmentMenuItemPressed(_ sender: NSMenuItem) {
        guard let url = attachmentURL(from: sender) else { return }
        attachmentQuickLookController.preview(url)
    }

    @discardableResult
    func previewAttachmentForLibrary(atPath path: String) -> Bool {
        attachmentQuickLookController.preview(URL(fileURLWithPath: path))
    }

    @objc
    func openAttachmentMenuItemPressed(_ sender: NSMenuItem) {
        guard let url = attachmentURL(from: sender) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc
    func revealAttachmentMenuItemPressed(_ sender: NSMenuItem) {
        guard let url = attachmentURL(from: sender) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc
    func copyAttachmentPathMenuItemPressed(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    @objc
    func copyAttachmentMarkdownMenuItemPressed(_ sender: NSMenuItem) {
        guard let markdown = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    func attachmentURL(from sender: NSMenuItem) -> URL? {
        guard let path = sender.representedObject as? String else { return nil }
        return URL(fileURLWithPath: path)
    }
}
