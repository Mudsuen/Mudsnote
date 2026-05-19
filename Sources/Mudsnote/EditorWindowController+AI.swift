import AppKit
import Foundation
import MudsnoteCore

extension EditorWindowController {
    func configureAIContextMenu(_ menu: NSMenu) {
        menu.addItem(.separator())

        let aiMenu = NSMenu(title: "AI")
        for actionID in AIActionID.allCases {
            let item = NSMenuItem(title: actionID.displayName, action: #selector(aiContextMenuItemPressed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = actionID.rawValue
            item.isEnabled = aiMenuItemEnabled(for: actionID)
            aiMenu.addItem(item)
        }
        aiMenu.addItem(.separator())
        let settings = NSMenuItem(title: "配置 AI...", action: #selector(aiConfigurePressed(_:)), keyEquivalent: "")
        settings.target = self
        aiMenu.addItem(settings)

        let aiItem = NSMenuItem(title: "AI", action: nil, keyEquivalent: "")
        aiItem.submenu = aiMenu
        menu.addItem(aiItem)
    }

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
        guard let baseURL = URL(string: noteStore.aiOllamaBaseURLString),
              !noteStore.aiOllamaModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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
        let provider = OllamaAIProvider(baseURL: baseURL, model: noteStore.aiOllamaModel)
        let request = AIRequest(
            actionID: actionID,
            noteTitle: currentNoteTitleForAI(),
            inputMarkdown: context.markdown,
            scope: context.scope
        )

        Task {
            do {
                let output = try await provider.generate(request: request)
                await MainActor.run {
                    statusLabel.stringValue = previousStatus
                    presentAIResult(output, actionID: actionID, context: context)
                }
            } catch {
                await MainActor.run {
                    statusLabel.stringValue = previousStatus
                    presentAIError(error)
                }
            }
        }
    }

    private func currentNoteTitleForAI() -> String? {
        if let title = quickCaptureTitleTextView?.string.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        return fileURL?.deletingPathExtension().lastPathComponent
    }

    private func selectedMarkdownOrWholeNote(preferWholeNote: Bool) -> AIEditorContext? {
        let selection = editorTextView.selectedRange()
        if !preferWholeNote, selection.length > 0, let markdown = markdown(in: selection), !markdown.isBlank {
            return AIEditorContext(markdown: markdown, range: selection, scope: .selection)
        }
        let markdown = serializedBodyMarkdown()
        guard !markdown.isBlank else { return nil }
        return AIEditorContext(markdown: markdown, range: NSRange(location: editorTextView.string.utf16.count, length: 0), scope: .wholeNote)
    }

    private func selectedMarkdownOrCurrentParagraph() -> AIEditorContext? {
        let selection = editorTextView.selectedRange()
        if selection.length > 0, let markdown = markdown(in: selection), !markdown.isBlank {
            return AIEditorContext(markdown: markdown, range: selection, scope: .selection)
        }
        let lineRange = visibleLineRangeForSelection()
        guard let markdown = markdown(in: lineRange), !markdown.isBlank else { return nil }
        return AIEditorContext(markdown: markdown, range: lineRange, scope: .currentParagraph)
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
        let alert = NSAlert()
        alert.messageText = "AI 结果"
        alert.informativeText = "作用范围：\(context.scope.userVisibleName)。AI 输出仅在你应用后写入笔记。"
        alert.alertStyle = .informational

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 240))
        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.string = output
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        alert.accessoryView = scrollView

        switch actionID.defaultOutputMode {
        case .replaceInput:
            alert.addButton(withTitle: "替换")
            alert.addButton(withTitle: "插入下方")
        case .insertBelow, .copyOnly:
            alert.addButton(withTitle: "插入下方")
            alert.addButton(withTitle: "替换")
        }
        alert.addButton(withTitle: "复制")
        alert.addButton(withTitle: "取消")

        let result = alert.runModal()
        switch (actionID.defaultOutputMode, result) {
        case (.replaceInput, .alertFirstButtonReturn):
            applyAIReplacement(output, range: context.range)
        case (.replaceInput, .alertSecondButtonReturn):
            applyAIInsertion(output, after: context.range)
        case (.insertBelow, .alertFirstButtonReturn), (.copyOnly, .alertFirstButtonReturn):
            applyAIInsertion(output, after: context.range)
        case (.insertBelow, .alertSecondButtonReturn), (.copyOnly, .alertSecondButtonReturn):
            applyAIReplacement(output, range: context.range)
        case (_, .alertThirdButtonReturn):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(output, forType: .string)
        default:
            break
        }
        window?.makeFirstResponder(editorTextView)
    }

    private func applyAIReplacement(_ output: String, range: NSRange) {
        editorTextView.undoManager?.beginUndoGrouping()
        replaceText(in: range, with: output, attributes: theme.baseAttributes(for: .paragraph))
        editorTextView.undoManager?.endUndoGrouping()
        userDidEdit()
    }

    private func applyAIInsertion(_ output: String, after range: NSRange) {
        let insertionPoint = min(NSMaxRange(range), editorTextView.string.utf16.count)
        let separator: String
        if insertionPoint == 0 {
            separator = ""
        } else {
            separator = editorTextView.string.hasSuffix("\n") ? "\n" : "\n\n"
        }
        editorTextView.undoManager?.beginUndoGrouping()
        replaceText(
            in: NSRange(location: insertionPoint, length: 0),
            with: "\(separator)\(output)",
            attributes: theme.baseAttributes(for: .paragraph)
        )
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
