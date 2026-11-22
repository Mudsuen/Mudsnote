import AppKit
import Foundation
import MudsnoteCore

extension EditorWindowController {

    private func aiMenuItemEnabled(for actionID: AIActionID) -> Bool {
        guard noteStore.aiEnabled else { return false }
        switch actionID {
        case .summarize:
            return selectedMarkdownOrWholeNote(preferWholeNote: false) != nil
        case .fix:
            return selectedMarkdownOrCurrentParagraph() != nil
        case .todos:
            return selectedMarkdownOrWholeNote(preferWholeNote: false) != nil
        }
    }

    @objc
    private func aiContextMenuItemPressed(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let actionID = AIActionID(rawValue: rawValue)
        else { return }
        runAIAction(actionID)
    }

    @objc
    private func aiConfigurePressed(_ sender: NSMenuItem) {
        onRequestPreferences()
    }

    func runAIAction(_ actionID: AIActionID) {
        guard noteStore.aiEnabled else {
            presentAIError(AIError.disabled)
            return
        }
        guard let executableURL = CodexRuntimeLocator.resolve(configuredPath: noteStore.aiCodexExecutablePath) else {
            presentAIError(AIError.providerNotConfigured)
            return
        }

        let context: AIEditorContext?
        switch actionID {
        case .summarize, .todos:
            context = selectedMarkdownOrWholeNote(preferWholeNote: false)
        case .fix:
            context = selectedMarkdownOrCurrentParagraph()
        }

        guard let context else {
            presentAIError(AIError.emptyInput)
            return
        }

        let previousStatus = statusLabel.stringValue
        statusLabel.stringValue = "AI 正在生成..."
        let provider = CodexAIProvider(executableURL: executableURL)
        let request = AIRequest(
            actionID: actionID,
            noteTitle: currentNoteTitleForAI(),
            inputMarkdown: context.markdown,
            scope: context.scope
        )

        aiTask?.cancel()
        let requestID = UUID()
        aiRequestID = requestID
        aiTask = Task { @MainActor [weak self] in
            do {
                let output = try await provider.generate(request: request)
                guard let self, !Task.isCancelled, self.aiRequestID == requestID, !self.didCloseWindow else { return }
                self.aiTask = nil
                self.statusLabel.stringValue = previousStatus
                self.presentAIResult(output, actionID: actionID, context: context)
            } catch {
                guard let self, !Task.isCancelled, self.aiRequestID == requestID, !self.didCloseWindow else { return }
                self.aiTask = nil
                self.statusLabel.stringValue = previousStatus
                self.presentAIError(error)
            }
        }
    }

    private func currentNoteTitleForAI() -> String? {
        if isQuickCaptureMode {
            let title = currentQuickCaptureTitleValue()
            return title.isEmpty ? nil : title
        }
        return (activeFloatingNoteURL ?? fileURL)?.deletingPathExtension().lastPathComponent
    }

    private func selectedMarkdownOrWholeNote(preferWholeNote: Bool) -> AIEditorContext? {
        let selection = editorTextView.selectedRange()
        if !preferWholeNote, selection.length > 0, let markdown = markdown(in: selection), !markdown.isBlank {
            return AIEditorContext(documentIdentity: documentIdentity, revision: draftContentRevision, markdown: markdown, range: selection, scope: .selection)
        }
        let markdown = serializedBodyMarkdown()
        guard !markdown.isBlank else { return nil }
        return AIEditorContext(documentIdentity: documentIdentity, revision: draftContentRevision, markdown: markdown, range: NSRange(location: 0, length: editorTextView.string.utf16.count), scope: .wholeNote)
    }

    private func selectedMarkdownOrCurrentParagraph() -> AIEditorContext? {
        let selection = editorTextView.selectedRange()
        if selection.length > 0, let markdown = markdown(in: selection), !markdown.isBlank {
            return AIEditorContext(documentIdentity: documentIdentity, revision: draftContentRevision, markdown: markdown, range: selection, scope: .selection)
        }
        let lineRange = visibleLineRangeForSelection()
        guard let markdown = markdown(in: lineRange), !markdown.isBlank else { return nil }
        return AIEditorContext(documentIdentity: documentIdentity, revision: draftContentRevision, markdown: markdown, range: lineRange, scope: .currentParagraph)
    }

    private func markdown(in range: NSRange) -> String? {
        guard let storage = editorTextView.textStorage else { return nil }
        let clamped = NSRange(
            location: min(max(range.location, 0), storage.length),
            length: min(max(range.length, 0), max(storage.length - min(max(range.location, 0), storage.length), 0))
        )
        guard clamped.length > 0 else { return nil }
        return MarkdownRichTextCodec.serialize(storage.attributedSubstring(from: clamped), theme: theme)
    }

    private func presentAIResult(_ output: String, actionID: AIActionID, context: AIEditorContext) {
        let contextIsCurrent = aiContextIsCurrent(context)
        let primaryIsReplace = actionID.defaultOutputMode == .replaceInput

        let handleChoice: (NSApplication.ModalResponse) -> Void = { [weak self] result in
            guard let self else { return }
            guard result == .alertThirdButtonReturn || self.aiContextIsCurrent(context) else { return }
            switch (actionID.defaultOutputMode, result) {
            case (.replaceInput, .alertFirstButtonReturn):
                self.applyAIReplacement(output, range: context.range)
            case (.replaceInput, .alertSecondButtonReturn):
                self.applyAIInsertion(output, after: context.range)
            case (.insertBelow, .alertFirstButtonReturn), (.copyOnly, .alertFirstButtonReturn):
                self.applyAIInsertion(output, after: context.range)
            case (.insertBelow, .alertSecondButtonReturn), (.copyOnly, .alertSecondButtonReturn):
                self.applyAIReplacement(output, range: context.range)
            case (_, .alertThirdButtonReturn):
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(output, forType: .string)
            default:
                break
            }
            self.window?.makeFirstResponder(self.editorTextView)
        }

        let alert = NSAlert()
        alert.messageText = "AI 结果预览"
        alert.informativeText = contextIsCurrent
            ? "作用范围：\(context.scope.userVisibleName)。上方为原文，下方为 AI 生成内容，确认后才写入笔记。"
            : "原文已变化，结果仅供复制。请重新发起请求后再替换。"
        alert.alertStyle = .informational

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 300))

        let diffScroll = NSScrollView(frame: container.bounds)
        diffScroll.autoresizingMask = [.width, .height]
        diffScroll.hasVerticalScroller = true
        diffScroll.borderType = .bezelBorder

        let diffTextView = NSTextView(frame: diffScroll.bounds)
        diffTextView.isEditable = false
        diffTextView.isSelectable = true
        diffTextView.textContainerInset = NSSize(width: 8, height: 8)
        diffTextView.textStorage?.setAttributedString(Self.makeAIDiffPreview(original: context.markdown, proposed: output))
        diffScroll.documentView = diffTextView
        container.addSubview(diffScroll)
        alert.accessoryView = container

        if primaryIsReplace {
            alert.addButton(withTitle: "替换")
            alert.addButton(withTitle: "插入下方")
        } else {
            alert.addButton(withTitle: "插入下方")
            alert.addButton(withTitle: "替换")
        }
        alert.addButton(withTitle: "复制")
        alert.addButton(withTitle: "取消")

        if !contextIsCurrent {
            alert.buttons.prefix(2).forEach { $0.isEnabled = false }
        }

        if let hostWindow = window, hostWindow.isVisible {
            alert.beginSheetModal(for: hostWindow) { response in
                handleChoice(response)
            }
        } else {
            handleChoice(alert.runModal())
        }
    }

    private static func makeAIDiffPreview(original: String, proposed: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let headerFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let bodyFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        result.append(NSAttributedString(
            string: "原文\n",
            attributes: [.font: headerFont, .foregroundColor: NSColor.secondaryLabelColor]
        ))
        let originalExcerpt = original.count > 1200 ? String(original.prefix(1200)) + "…" : original
        result.append(NSAttributedString(
            string: originalExcerpt + "\n\n",
            attributes: [
                .font: bodyFont,
                .foregroundColor: NSColor.secondaryLabelColor,
                .backgroundColor: NSColor.systemRed.withAlphaComponent(0.08)
            ]
        ))
        result.append(NSAttributedString(
            string: "AI 建议\n",
            attributes: [.font: headerFont, .foregroundColor: NSColor.controlAccentColor]
        ))
        result.append(NSAttributedString(
            string: proposed,
            attributes: [
                .font: bodyFont,
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: NSColor.systemGreen.withAlphaComponent(0.10)
            ]
        ))
        return result
    }

    private func aiContextIsCurrent(_ context: AIEditorContext) -> Bool {
        context.documentIdentity == documentIdentity && context.revision == draftContentRevision
            && context.range.location >= 0 && context.range.length >= 0
            && context.range.location <= editorTextView.string.utf16.count
            && context.range.length <= editorTextView.string.utf16.count - context.range.location
    }

    private func applyAIReplacement(_ output: String, range: NSRange) {
        let rendered = MarkdownRichTextCodec.render(
            markdown: output,
            theme: theme,
            baseURL: fileURLForRendering
        )
        editorTextView.undoManager?.beginUndoGrouping()
        replaceText(in: range, withAttributed: rendered)
        editorTextView.undoManager?.endUndoGrouping()
        userDidEdit()
    }

    private func applyAIInsertion(_ output: String, after range: NSRange) {
        let text = editorTextView.string as NSString
        let insertionPoint = min(NSMaxRange(range), text.length)
        let separator: String
        if insertionPoint == 0 {
            separator = ""
        } else {
            let previousUnit = text.character(at: insertionPoint - 1)
            separator = (previousUnit == 0x000A || previousUnit == 0x000D) ? "\n" : "\n\n"
        }
        let combined = NSMutableAttributedString()
        if !separator.isEmpty {
            combined.append(NSAttributedString(string: separator, attributes: theme.baseAttributes(for: .paragraph)))
        }
        combined.append(MarkdownRichTextCodec.render(
            markdown: output,
            theme: theme,
            baseURL: fileURLForRendering
        ))
        editorTextView.undoManager?.beginUndoGrouping()
        replaceText(in: NSRange(location: insertionPoint, length: 0), withAttributed: combined)
        editorTextView.undoManager?.endUndoGrouping()
        userDidEdit()
    }

    private func presentAIError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "AI 命令不可用"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "打开设置")
        if alert.runModal() == .alertSecondButtonReturn {
            onRequestPreferences()
        }
    }
}

private struct AIEditorContext {
    let documentIdentity: UUID
    let revision: Int
    let markdown: String
    let range: NSRange
    let scope: AIInputScope
}

private extension AIInputScope {
    var userVisibleName: String {
        switch self {
        case .selection: return "选中文本"
        case .currentParagraph: return "当前段落"
        case .wholeNote: return "当前笔记"
        }
    }
}

private extension String {
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
