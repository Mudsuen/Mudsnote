import AppKit
import Foundation

extension EditorWindowController {

    // MARK: - Tag state

    func refreshTrackedTags() {
        activeTags = QuickCaptureDocumentState.extractedInlineTags(from: editorTextView.string)
    }

    func mergedDocumentTags(from markdown: String) -> [String] {
        QuickCaptureDocumentState.extractedInlineTags(from: markdown)
    }

    // MARK: - Inline suggestion visibility

    var isSuggestionVisible: Bool {
        !suggestionController.view.isHidden
    }

    func dismissInlineSuggestions() {
        inlineSuggestionContext = nil
        suggestionController.view.isHidden = true
    }

    // MARK: - Tag token matching

    func currentTagToken() -> (query: String, replacementRange: NSRange)? {
        let selection = editorTextView.selectedRange()
        guard selection.length == 0 else { return nil }

        let string = editorTextView.string as NSString
        let caret = min(selection.location, string.length)
        let paragraphRange = string.paragraphRange(for: NSRange(location: caret, length: 0))
        let linePrefix = string.substring(with: NSRange(location: paragraphRange.location, length: max(caret - paragraphRange.location, 0)))

        guard let match = linePrefix.range(of: #"(^|\s)#([^\s#]*)$"#, options: .regularExpression) else {
            return nil
        }

        let token = String(linePrefix[match])
        let query = String(token.trimmingCharacters(in: .whitespaces).dropFirst())
        let replacementRange = NSRange(
            location: paragraphRange.location + linePrefix.distance(from: linePrefix.startIndex, to: match.lowerBound) + (token.hasPrefix(" ") ? 1 : 0),
            length: token.trimmingCharacters(in: .whitespaces).utf16.count
        )
        return (query, replacementRange)
    }

    func rankedMatchingTags(for query: String) -> [String] {
        let known = noteStore.knownTags()
            .filter { candidate in
                !activeTags.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
            }

        guard !query.isEmpty else { return known }

        let loweredQuery = query.lowercased()
        return known
            .compactMap { tag -> (tag: String, score: Int)? in
                let loweredTag = tag.lowercased()
                if loweredTag == loweredQuery { return (tag, 1000) }
                if loweredTag.hasPrefix(loweredQuery) { return (tag, 850 - max(loweredTag.count - loweredQuery.count, 0)) }
                if let range = loweredTag.range(of: loweredQuery) {
                    let offset = loweredTag.distance(from: loweredTag.startIndex, to: range.lowerBound)
                    return (tag, 650 - offset)
                }
                if isSubsequence(loweredQuery, of: loweredTag) { return (tag, 420 - max(loweredTag.count - loweredQuery.count, 0)) }
                if let distance = levenshteinDistance(between: loweredQuery, and: loweredTag), distance <= 2 { return (tag, 240 - (distance * 40)) }
                return nil
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score { return lhs.tag.localizedCaseInsensitiveCompare(rhs.tag) == .orderedAscending }
                return lhs.score > rhs.score
            }
            .map(\.tag)
    }

    // MARK: - Inline suggestion lifecycle

    func updateInlineSuggestions() {
        guard editorTextView.window != nil else { return }
        guard let context = currentInlineSuggestionContext() else {
            dismissInlineSuggestions()
            return
        }

        inlineSuggestionContext = context
        let items: [SuggestionItem]
        switch context {
        case .tags(_, _, let tags):
            items = tags.map { SuggestionItem(title: "#\($0)", subtitle: nil, symbolName: nil) }
        case .slash(_, _, let commands):
            items = commands.map { SuggestionItem(title: $0.title, subtitle: nil, symbolName: nil) }
        }

        guard !items.isEmpty else {
            dismissInlineSuggestions()
            return
        }

        suggestionController.updateItems(items)
        positionSuggestionView(for: context)
    }

    func currentInlineSuggestionContext() -> InlineSuggestionContext? {
        let selection = editorTextView.selectedRange()
        guard selection.length == 0 else { return nil }

        if let tagToken = currentTagToken() {
            let items = rankedMatchingTags(for: tagToken.query)
            if !items.isEmpty {
                return .tags(query: tagToken.query, replacementRange: tagToken.replacementRange, items: items)
            }
        }

        let string = editorTextView.string as NSString
        let caret = min(selection.location, string.length)
        let paragraphRange = string.paragraphRange(for: NSRange(location: caret, length: 0))
        let linePrefix = string.substring(with: NSRange(location: paragraphRange.location, length: max(caret - paragraphRange.location, 0)))

        if let match = linePrefix.range(of: #"(^|\s)/([^\s/]*)$"#, options: .regularExpression) {
            let token = String(linePrefix[match])
            let query = token.trimmingCharacters(in: .whitespaces).dropFirst().lowercased()
            let replacementRange = NSRange(
                location: paragraphRange.location + linePrefix.distance(from: linePrefix.startIndex, to: match.lowerBound) + (token.hasPrefix(" ") ? 1 : 0),
                length: token.trimmingCharacters(in: .whitespaces).utf16.count
            )
            let commands = SlashCommand.allCases.filter {
                query.isEmpty || $0.title.lowercased().contains(query) || $0.subtitle.lowercased().contains(query)
            }
            return commands.isEmpty ? nil : .slash(query: String(query), replacementRange: replacementRange, items: commands)
        }

        return nil
    }

    func acceptInlineSuggestion(at index: Int) {
        guard let context = inlineSuggestionContext else { return }

        switch context {
        case .tags(_, let replacementRange, let items):
            guard items.indices.contains(index) else { return }
            applyTag(items[index], replacementRange: replacementRange)
        case .slash(_, let replacementRange, let items):
            guard items.indices.contains(index) else { return }
            applySlashCommand(items[index], replacementRange: replacementRange)
        }
        dismissInlineSuggestions()
    }

    func positionSuggestionView(for context: InlineSuggestionContext) {
        guard let host = shellContentView else { return }

        let anchorRect = editorTextView.convert(caretRectInWindow(for: editorTextView), to: host)
        let size = suggestionController.preferredContentSize
        var origin = NSPoint(x: anchorRect.maxX + 4, y: anchorRect.maxY - size.height + 14)

        switch context {
        case .tags:
            origin.x = anchorRect.maxX + 4
            origin.y = anchorRect.maxY - size.height + 12
        case .slash:
            origin.x = anchorRect.minX
            origin.y = anchorRect.minY - size.height - 6
        }

        origin.x = min(max(origin.x, 4), max(host.bounds.width - size.width - 4, 4))
        origin.y = min(max(origin.y, 4), max(host.bounds.height - size.height - 4, 4))

        suggestionController.view.frame = NSRect(origin: origin, size: size)
        suggestionController.view.isHidden = false
    }

    // MARK: - Tag / slash application

    func applyTag(_ tag: String, replacementRange: NSRange) {
        replaceText(in: replacementRange, with: "#\(tag)")
        refreshChrome()
        userDidEdit()
    }

    func applySlashCommand(_ command: SlashCommand, replacementRange: NSRange) {
        replaceText(in: replacementRange, with: "")
        switch command {
        case .heading: toggleParagraphKind(.heading(level: 1))
        case .checklist: toggleParagraphKind(.checklist(checked: false))
        case .bulletList: toggleParagraphKind(.bullet)
        case .orderedList: toggleParagraphKind(.ordered(index: 1))
        case .divider:
            insertTextAtSelection("---")
            userDidEdit()
        }
    }

    func commitPendingTagIfNeeded(insertingTrailingText trailingText: String? = nil) -> Bool {
        guard let token = currentTagToken() else { return false }
        let normalized = token.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        applyTag(normalized, replacementRange: token.replacementRange)
        if let trailingText {
            let neutralAttributes = neutralTypingAttributesForCurrentLine()
            insertTextAtSelection(trailingText, attributes: neutralAttributes)
            editorTextView.typingAttributes = neutralAttributes
        }
        return true
    }

    func neutralTypingAttributesForCurrentLine() -> [NSAttributedString.Key: Any] {
        guard let storage = editorTextView.textStorage, storage.length > 0 else {
            return theme.baseAttributes(for: .paragraph)
        }
        let lineRange = visibleLineRangeForSelection()
        let kind = MarkdownRichTextCodec.paragraphKind(at: lineRange, in: storage)
        var attributes = theme.baseAttributes(for: kind)
        attributes.removeValue(forKey: .qmTag)
        return attributes
    }

    // MARK: - Tag menu (quick capture)

    func showQuickCaptureTagMenu(from sender: NSButton) {
        let menu = NSMenu()

        let insertHashItem = NSMenuItem(title: "Insert # in Notes", action: #selector(insertInlineHashMarkerFromMenu(_:)), keyEquivalent: "")
        insertHashItem.target = self
        menu.addItem(insertHashItem)

        let knownTags = noteStore.knownTags(limit: 12)
        if knownTags.isEmpty {
            menu.addItem(.separator())
            let emptyItem = NSMenuItem(title: "No saved tags yet", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            menu.addItem(.separator())
            for tag in knownTags {
                let item = NSMenuItem(title: "#\(tag)", action: #selector(toggleQuickCaptureTagFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = tag
                item.state = QuickCaptureDocumentState.containsTag(tag, in: serializedBodyMarkdown()) ? .on : .off
                menu.addItem(item)
            }
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 6), in: sender)
    }

    @objc private func insertInlineHashMarkerFromMenu(_ sender: NSMenuItem) {
        window?.makeFirstResponder(editorTextView)
        editorTextView.setSelectedRange(NSRange(location: editorTextView.string.utf16.count, length: 0))
        insertTextAtSelection("#")
        userDidEdit()
    }

    @objc private func toggleQuickCaptureTagFromMenu(_ sender: NSMenuItem) {
        guard let tag = sender.representedObject as? String else { return }
        let updatedBody = QuickCaptureDocumentState.toggledTag(tag, in: serializedBodyMarkdown())
        replaceBodyMarkdownFromQuickCaptureMenu(updatedBody)
    }

    private func replaceBodyMarkdownFromQuickCaptureMenu(_ markdown: String) {
        suppressAutosave = true
        applyBodyMarkdown(markdown)
        suppressAutosave = false
        window?.makeFirstResponder(editorTextView)
        editorTextView.setSelectedRange(NSRange(location: editorTextView.string.utf16.count, length: 0))
        updateTypingAttributesFromInsertionPoint()
        updateToolbarSelectionState()
        updateInlineSuggestions()
        refreshChrome()
        markDocumentDirty()
    }

    // MARK: - String algorithms

    private func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        guard !needle.isEmpty else { return true }
        var needleIndex = needle.startIndex
        for character in haystack where needleIndex < needle.endIndex {
            if character == needle[needleIndex] { needle.formIndex(after: &needleIndex) }
        }
        return needleIndex == needle.endIndex
    }

    private func levenshteinDistance(between lhs: String, and rhs: String) -> Int? {
        guard !lhs.isEmpty, !rhs.isEmpty else { return nil }
        let left = Array(lhs)
        let right = Array(rhs)
        var previous = Array(0...right.count)

        for (leftIndex, leftChar) in left.enumerated() {
            var current = [leftIndex + 1]
            current.reserveCapacity(right.count + 1)
            for (rightIndex, rightChar) in right.enumerated() {
                current.append(min(current[rightIndex] + 1, previous[rightIndex + 1] + 1, previous[rightIndex] + (leftChar == rightChar ? 0 : 1)))
            }
            previous = current
        }

        return previous.last
    }
}
