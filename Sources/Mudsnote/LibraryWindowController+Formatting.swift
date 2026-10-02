import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

extension LibraryWindowController {
    func libraryUserDidEdit() {
        guard !suppressEditorChanges else { return }
        if isEditorShowingMarkdownSource {
            editorSearchHighlightRefreshTask?.cancel()
            markDirty()
            return
        }
        let activeSearchQuery = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldRefreshSearchHighlights = !activeSearchQuery.isEmpty
        if !shouldRefreshSearchHighlights {
            removeEditorSearchHighlights()
        }
        if !normalizeCurrentLineAfterListPrefixEdit() {
            interpretTypedMarkdownIfNeeded()
        }
        updateTypingAttributesFromInsertionPoint()
        markDirty()
        if shouldRefreshSearchHighlights {
            scheduleEditorSearchHighlightRefresh(query: activeSearchQuery)
        }
    }

    func scheduleEditorSearchHighlightRefresh(query: String) {
        editorSearchHighlightRefreshTask?.cancel()
        editorSearchHighlightRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled, let self, !self.isEditorShowingMarkdownSource else { return }
            self.refreshEditorSearchHighlightsAtomically(query: query)
            self.editorSearchHighlightRefreshTask = nil
        }
    }

    func refreshEditorSearchHighlightsAtomically(query: String) {
        guard let storage = editorTextView.textStorage else { return }
        let wasSuppressingEditorChanges = suppressEditorChanges
        suppressEditorChanges = true
        storage.beginEditing()
        applyEditorSearchHighlights(query: query)
        storage.endEditing()
        suppressEditorChanges = wasSuppressingEditorChanges
    }

    func interpretTypedMarkdownIfNeeded() {
        guard let storage = editorTextView.textStorage else { return }

        let currentLineRange = visibleLineRangeForSelection()
        let currentText = (storage.string as NSString).substring(with: currentLineRange)
        guard MarkdownRichTextCodec.shouldInterpretMarkdown(in: currentText) else { return }

        let selection = editorTextView.selectedRange()
        let selectionStartOffset = max(selection.location - currentLineRange.location, 0)
        let selectionEndOffset = max(NSMaxRange(selection) - currentLineRange.location, 0)
        let rendered = MarkdownRichTextCodec.renderLine(currentText, theme: theme)
        let clampedStart = min(selectionStartOffset, rendered.length)
        let clampedEnd = min(selectionEndOffset, rendered.length)

        suppressEditorChanges = true
        storage.replaceCharacters(in: currentLineRange, with: rendered)
        suppressEditorChanges = false
        editorTextView.setSelectedRange(NSRange(
            location: currentLineRange.location + clampedStart,
            length: max(clampedEnd - clampedStart, 0)
        ))
    }

    func normalizeCurrentLineAfterListPrefixEdit() -> Bool {
        guard let storage = editorTextView.textStorage else { return false }

        let lineRange = visibleLineRangeForSelection()
        guard MarkdownRichTextCodec.needsParagraphResetAfterListPrefixEdit(range: lineRange, in: storage) else {
            return false
        }

        let storedKind = MarkdownRichTextCodec.storedParagraphKind(at: lineRange, in: storage) ?? .paragraph
        let contentRange = MarkdownRichTextCodec.paragraphContentRangeAfterListPrefixEdit(
            for: lineRange,
            in: storage,
            storedKind: storedKind
        )
        let inlineMarkdown = MarkdownRichTextCodec.serializeVisibleContent(
            range: contentRange,
            in: storage,
            paragraphKind: .paragraph,
            theme: theme
        )
        let replacement = MarkdownRichTextCodec.renderLine(
            MarkdownRichTextCodec.markdownLine(for: .paragraph, inlineContent: inlineMarkdown),
            theme: theme
        )

        let selection = editorTextView.selectedRange()
        let removedPrefixLength = max(contentRange.location - lineRange.location, 0)
        let selectionStartOffset = max(selection.location - lineRange.location - removedPrefixLength, 0)
        let selectionEndOffset = max(NSMaxRange(selection) - lineRange.location - removedPrefixLength, 0)
        let clampedStart = min(selectionStartOffset, replacement.length)
        let clampedEnd = min(selectionEndOffset, replacement.length)

        suppressEditorChanges = true
        storage.replaceCharacters(in: lineRange, with: replacement)
        suppressEditorChanges = false
        editorTextView.setSelectedRange(NSRange(
            location: lineRange.location + clampedStart,
            length: max(clampedEnd - clampedStart, 0)
        ))
        return true
    }

    func updateTypingAttributesFromInsertionPoint() {
        guard let storage = editorTextView.textStorage else { return }
        let selection = editorTextView.selectedRange()
        let location = max(min(selection.location, storage.length), 0)

        if storage.length == 0 {
            editorTextView.typingAttributes = theme.baseAttributes(for: .heading(level: 1))
            return
        }

        if location == 0 {
            if storage.length > 0,
               storage.attribute(.qmTableID, at: 0, effectiveRange: nil) != nil {
                var attributes = storage.attributes(at: 0, effectiveRange: nil)
                attributes.removeValue(forKey: .qmTablePlaceholder)
                editorTextView.typingAttributes = attributes
                return
            }
            editorTextView.typingAttributes = theme.baseAttributes(for: .heading(level: 1))
            return
        }

        let tableProbeLocation = min(location, storage.length - 1)
        if storage.attribute(.qmTableID, at: tableProbeLocation, effectiveRange: nil) != nil {
            var attributes = storage.attributes(at: tableProbeLocation, effectiveRange: nil)
            attributes.removeValue(forKey: .qmTablePlaceholder)
            editorTextView.typingAttributes = attributes
            return
        }

        let lineRange = visibleLineRangeForSelection()
        let paragraphKind = MarkdownRichTextCodec.paragraphKind(at: lineRange, in: storage)
        let contentRange = MarkdownRichTextCodec.visibleContentRange(for: lineRange, in: storage, kind: paragraphKind)

        if location <= contentRange.location {
            editorTextView.typingAttributes = theme.baseAttributes(for: paragraphKind)
            return
        }

        let probeLocation = max(min(location - 1, storage.length - 1), contentRange.location)
        editorTextView.typingAttributes = storage.attributes(at: probeLocation, effectiveRange: nil)
    }

    func visibleLineRangeForSelection() -> NSRange {
        let string = editorTextView.string as NSString
        let selection = editorTextView.selectedRange()
        let paragraphRange = string.paragraphRange(for: NSRange(location: min(selection.location, string.length), length: 0))
        let hasTrailingNewline = string.substring(with: paragraphRange).hasSuffix("\n")
        return NSRange(location: paragraphRange.location, length: max(paragraphRange.length - (hasTrailingNewline ? 1 : 0), 0))
    }

    func selectedLineRanges() -> [NSRange] {
        let string = editorTextView.string as NSString
        let selection = editorTextView.selectedRange()
        let fullRange = string.lineRange(for: selection)
        var ranges: [NSRange] = []
        var location = fullRange.location

        while location < NSMaxRange(fullRange) {
            let paragraphRange = string.paragraphRange(for: NSRange(location: location, length: 0))
            let hasTrailingNewline = string.substring(with: paragraphRange).hasSuffix("\n")
            ranges.append(NSRange(
                location: paragraphRange.location,
                length: max(paragraphRange.length - (hasTrailingNewline ? 1 : 0), 0)
            ))
            location = NSMaxRange(paragraphRange)
        }

        if ranges.isEmpty {
            ranges.append(NSRange(location: min(selection.location, string.length), length: 0))
        }
        return ranges
    }

    func handleStructuredNewline() -> Bool {
        guard let storage = editorTextView.textStorage else { return false }

        let lineRange = visibleLineRangeForSelection()
        let kind = MarkdownRichTextCodec.paragraphKind(at: lineRange, in: storage)
        let contentRange = MarkdownRichTextCodec.visibleContentRange(for: lineRange, in: storage, kind: kind)
        let content = (storage.string as NSString)
            .substring(with: contentRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch kind {
        case .paragraph:
            return false
        case .heading:
            insertStructuredLine(kind: .paragraph, inlineMarkdown: "")
            return true
        case .bullet, .ordered, .checklist:
            if content.isEmpty {
                convertCurrentLineToParagraph()
            } else {
                let nextKind: MarkdownParagraphKind
                switch kind {
                case .ordered(let index):
                    nextKind = .ordered(index: index + 1)
                case .checklist:
                    nextKind = .checklist(checked: false)
                default:
                    nextKind = kind
                }
                insertStructuredLine(kind: nextKind, inlineMarkdown: "")
            }
            return true
        }
    }

    func convertCurrentLineToParagraph() {
        guard let storage = editorTextView.textStorage else { return }
        let lineRange = visibleLineRangeForSelection()
        let replacement = MarkdownRichTextCodec.renderLine("", theme: theme)

        suppressEditorChanges = true
        storage.replaceCharacters(in: lineRange, with: replacement)
        suppressEditorChanges = false
        editorTextView.setSelectedRange(NSRange(location: lineRange.location, length: 0))
        updateTypingAttributesFromInsertionPoint()
        markDirty()
    }

    func insertStructuredLine(kind: MarkdownParagraphKind, inlineMarkdown: String) {
        guard let storage = editorTextView.textStorage else { return }
        let selection = editorTextView.selectedRange()
        let markdownLine = MarkdownRichTextCodec.markdownLine(for: kind, inlineContent: inlineMarkdown)
        let renderedLine = MarkdownRichTextCodec.renderLine(markdownLine, theme: theme)
        let replacement = NSMutableAttributedString(string: "\n", attributes: theme.baseAttributes(for: .paragraph))
        replacement.append(renderedLine)

        suppressEditorChanges = true
        storage.replaceCharacters(in: selection, with: replacement)
        suppressEditorChanges = false
        editorTextView.setSelectedRange(NSRange(location: selection.location + 1 + kind.prefixLength, length: 0))
        normalizeUnifiedTitleLineFormatting()
        updateTypingAttributesFromInsertionPoint()
        markDirty()
    }

    func toggleParagraphKind(_ target: MarkdownParagraphKind) {
        applyParagraphKind(target, togglesOffWhenMatching: true)
    }

    func setParagraphKind(_ target: MarkdownParagraphKind) {
        applyParagraphKind(target, togglesOffWhenMatching: false)
    }

    func applyParagraphKind(_ target: MarkdownParagraphKind, togglesOffWhenMatching: Bool) {
        guard selectedScope != .trash, let storage = editorTextView.textStorage else { return }
        let ranges = selectedLineRanges()
        let currentKinds = ranges.map { MarkdownRichTextCodec.paragraphKind(at: $0, in: storage) }
        let allMatchTarget = currentKinds.allSatisfy { sameParagraphCategory($0, target) }
        if allMatchTarget, !togglesOffWhenMatching {
            return
        }
        let shouldResetToParagraph = togglesOffWhenMatching && allMatchTarget
        var renderedLines: [NSAttributedString] = []

        for (index, lineRange) in ranges.enumerated() {
            let currentKind = currentKinds[index]
            let contentRange = MarkdownRichTextCodec.visibleContentRange(for: lineRange, in: storage, kind: currentKind)
            let inlineMarkdown = MarkdownRichTextCodec.serializeVisibleContent(
                range: contentRange,
                in: storage,
                paragraphKind: currentKind,
                theme: theme
            )
            let nextKind: MarkdownParagraphKind
            if shouldResetToParagraph {
                nextKind = .paragraph
            } else if case .ordered = target {
                nextKind = .ordered(index: index + 1)
            } else {
                nextKind = target
            }
            let lineMarkdown = MarkdownRichTextCodec.markdownLine(for: nextKind, inlineContent: inlineMarkdown)
            renderedLines.append(MarkdownRichTextCodec.renderLine(lineMarkdown, theme: theme))
        }

        let replacement = joinRenderedLines(renderedLines)
        let fullRange = combinedRange(of: ranges)
        suppressEditorChanges = true
        storage.replaceCharacters(in: fullRange, with: replacement)
        suppressEditorChanges = false
        editorTextView.setSelectedRange(NSRange(location: fullRange.location + replacement.length, length: 0))
        updateTypingAttributesFromInsertionPoint()
        markDirty()
    }

    func toggleChecklistIfNeeded(atCharacterIndex index: Int) -> Bool {
        guard let storage = editorTextView.textStorage, storage.length > 0 else { return false }

        let safeIndex = min(max(index, 0), max(storage.length - 1, 0))
        let string = storage.string as NSString
        let paragraphRange = string.paragraphRange(for: NSRange(location: safeIndex, length: 0))
        let visibleRange = NSRange(
            location: paragraphRange.location,
            length: max(paragraphRange.length - (string.substring(with: paragraphRange).hasSuffix("\n") ? 1 : 0), 0)
        )
        let kind = MarkdownRichTextCodec.paragraphKind(at: visibleRange, in: storage)

        guard case .checklist(let checked) = kind else { return false }
        let prefixRange = NSRange(location: visibleRange.location, length: min(kind.prefixLength, visibleRange.length))
        guard NSLocationInRange(safeIndex, prefixRange) else { return false }

        let contentRange = MarkdownRichTextCodec.visibleContentRange(for: visibleRange, in: storage, kind: kind)
        let inlineMarkdown = MarkdownRichTextCodec.serializeVisibleContent(
            range: contentRange,
            in: storage,
            paragraphKind: kind,
            theme: theme
        )
        let replacement = MarkdownRichTextCodec.renderLine(
            MarkdownRichTextCodec.markdownLine(for: .checklist(checked: !checked), inlineContent: inlineMarkdown),
            theme: theme
        )

        suppressEditorChanges = true
        storage.replaceCharacters(in: visibleRange, with: replacement)
        suppressEditorChanges = false
        editorTextView.setSelectedRange(NSRange(location: min(visibleRange.location + replacement.length, storage.length), length: 0))
        updateTypingAttributesFromInsertionPoint()
        markDirty()
        return true
    }

    func applyFormatCommand(_ command: LibraryFormatCommand) {
        guard !isEditorShowingMarkdownSource else { return }
        focusEditorForLibraryAction()
        let undoSnapshot = libraryFormattingUndoSnapshot()
        if let paragraphKind = command.paragraphKind {
            setParagraphKind(paragraphKind)
            registerLibraryFormattingUndoIfNeeded(before: undoSnapshot, actionName: command.undoActionName)
            return
        }
        switch command {
        case .bold:
            toggleInlineFontTrait(.boldFontMask)
        case .italic:
            toggleInlineFontTrait(.italicFontMask)
        case .underline:
            toggleIntAttribute(.underlineStyle, enabledValue: NSUnderlineStyle.single.rawValue, actionName: "下划线")
        case .strikethrough:
            toggleIntAttribute(.strikethroughStyle, enabledValue: NSUnderlineStyle.single.rawValue, actionName: "删除线")
        case .highlight:
            setHighlightForLibrary(enabled: true)
        case .removeHighlight:
            setHighlightForLibrary(enabled: false)
        case .heading1, .heading2, .heading3, .paragraph, .checklist, .bullet, .ordered:
            break
        }
        registerLibraryFormattingUndoIfNeeded(before: undoSnapshot, actionName: command.undoActionName)
    }

    func libraryFormattingUndoSnapshot() -> LibraryFormattingUndoSnapshot? {
        guard let storage = editorTextView.textStorage else { return nil }
        return LibraryFormattingUndoSnapshot(
            content: NSAttributedString(attributedString: storage),
            selection: editorTextView.selectedRange()
        )
    }

    func registerLibraryFormattingUndoIfNeeded(
        before: LibraryFormattingUndoSnapshot?,
        actionName: String
    ) {
        guard let before,
              let after = libraryFormattingUndoSnapshot(),
              !before.content.isEqual(to: after.content),
              let undoManager = editorTextView.undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.restoreLibraryFormattingSnapshot(before, inverse: after, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    func restoreLibraryFormattingSnapshot(
        _ snapshot: LibraryFormattingUndoSnapshot,
        inverse: LibraryFormattingUndoSnapshot,
        actionName: String
    ) {
        editorTextView.undoManager?.registerUndo(withTarget: self) { target in
            target.restoreLibraryFormattingSnapshot(inverse, inverse: snapshot, actionName: actionName)
        }
        editorTextView.undoManager?.setActionName(actionName)
        guard let storage = editorTextView.textStorage else { return }
        suppressEditorChanges = true
        storage.setAttributedString(snapshot.content)
        suppressEditorChanges = false
        let location = min(snapshot.selection.location, storage.length)
        let length = min(snapshot.selection.length, max(storage.length - location, 0))
        editorTextView.setSelectedRange(NSRange(location: location, length: length))
        updateTypingAttributesFromInsertionPoint()
        markDirty()
    }

    func setHighlightForLibrary(enabled: Bool) {
        guard selectedScope != .trash,
              let storage = editorTextView.textStorage,
              editorTextView.selectedRange().length > 0 else { return }
        let selection = editorTextView.selectedRange()
        suppressEditorChanges = true
        storage.beginEditing()
        if enabled {
            storage.addAttributes([
                .qmHighlight: true,
                .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.38)
            ], range: selection)
        } else {
            storage.removeAttribute(.qmHighlight, range: selection)
            var location = selection.location
            while location < NSMaxRange(selection) {
                var effectiveRange = NSRange(location: 0, length: 0)
                let isSearchHighlight = storage.attribute(
                    .qmSearchHighlight,
                    at: location,
                    effectiveRange: &effectiveRange
                ) != nil
                let clippedRange = NSIntersectionRange(selection, effectiveRange)
                if isSearchHighlight {
                    storage.addAttribute(
                        .backgroundColor,
                        value: NSColor.systemYellow.withAlphaComponent(0.30),
                        range: clippedRange
                    )
                } else {
                    storage.removeAttribute(.backgroundColor, range: clippedRange)
                }
                location = NSMaxRange(clippedRange)
            }
        }
        storage.endEditing()
        suppressEditorChanges = false
        editorTextView.setSelectedRange(selection)
        markDirty()
    }

    func toggleInlineFontTrait(_ trait: NSFontTraitMask) {
        guard selectedScope != .trash else { return }

        if trait.contains(.italicFontMask) {
            toggleItalicFormatting()
            return
        }

        let selection = editorTextView.selectedRange()
        if selection.length == 0 {
            var typing = editorTextView.typingAttributes
            let currentFont = (typing[.font] as? NSFont) ?? theme.bodyFont
            typing[.font] = toggledFont(from: currentFont, trait: trait)
            editorTextView.typingAttributes = typing
            return
        }

        guard let storage = editorTextView.textStorage else { return }
        let removesTrait = selectionEntirelyHasFontTrait(
            trait,
            selection: selection,
            storage: storage
        )
        suppressEditorChanges = true
        storage.beginEditing()
        var location = selection.location
        while location < NSMaxRange(selection) {
            var effectiveRange = NSRange(location: 0, length: 0)
            let font = (storage.attribute(.font, at: location, effectiveRange: &effectiveRange) as? NSFont) ?? theme.bodyFont
            let clippedRange = NSIntersectionRange(selection, effectiveRange)
            let updatedFont = removesTrait
                ? NSFontManager.shared.convert(font, toNotHaveTrait: trait)
                : NSFontManager.shared.convert(font, toHaveTrait: trait)
            storage.addAttribute(.font, value: updatedFont, range: clippedRange)
            location = NSMaxRange(clippedRange)
        }
        storage.endEditing()
        suppressEditorChanges = false
        editorTextView.setSelectedRange(selection)
        markDirty()
    }

    func toggleItalicFormatting() {
        let selection = editorTextView.selectedRange()
        if selection.length == 0 {
            var typing = editorTextView.typingAttributes
            let currentFont = (typing[.font] as? NSFont) ?? theme.bodyFont
            if isItalicActive(font: currentFont, obliqueness: typing[.obliqueness]) {
                typing[.font] = NSFontManager.shared.convert(currentFont, toNotHaveTrait: .italicFontMask)
                typing.removeValue(forKey: .obliqueness)
            } else {
                typing[.font] = NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask)
                typing[.obliqueness] = markdownItalicObliqueness
            }
            editorTextView.typingAttributes = typing
            return
        }

        guard let storage = editorTextView.textStorage else { return }
        let removesItalic = selectionEntirelyUsesItalic(
            selection: selection,
            storage: storage
        )
        suppressEditorChanges = true
        storage.beginEditing()
        var location = selection.location
        while location < NSMaxRange(selection) {
            var effectiveRange = NSRange(location: 0, length: 0)
            let attributes = storage.attributes(at: location, effectiveRange: &effectiveRange)
            let font = (attributes[.font] as? NSFont) ?? theme.bodyFont
            let clippedRange = NSIntersectionRange(selection, effectiveRange)
            if removesItalic {
                storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask), range: clippedRange)
                storage.removeAttribute(.obliqueness, range: clippedRange)
            } else {
                storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask), range: clippedRange)
                storage.addAttribute(.obliqueness, value: markdownItalicObliqueness, range: clippedRange)
            }
            location = NSMaxRange(clippedRange)
        }
        storage.endEditing()
        suppressEditorChanges = false
        editorTextView.setSelectedRange(selection)
        markDirty()
    }

    func selectionEntirelyHasFontTrait(
        _ trait: NSFontTraitMask,
        selection: NSRange,
        storage: NSTextStorage
    ) -> Bool {
        var allMatch = true
        storage.enumerateAttribute(.font, in: selection) { value, _, stop in
            let font = (value as? NSFont) ?? theme.bodyFont
            guard NSFontManager.shared.traits(of: font).contains(trait) else {
                allMatch = false
                stop.pointee = true
                return
            }
        }
        return allMatch
    }

    func selectionEntirelyUsesItalic(
        selection: NSRange,
        storage: NSTextStorage
    ) -> Bool {
        var allMatch = true
        storage.enumerateAttributes(in: selection) { attributes, _, stop in
            let font = (attributes[.font] as? NSFont) ?? theme.bodyFont
            guard isItalicActive(font: font, obliqueness: attributes[.obliqueness]) else {
                allMatch = false
                stop.pointee = true
                return
            }
        }
        return allMatch
    }

    func toggleIntAttribute(_ key: NSAttributedString.Key, enabledValue: Int, actionName: String) {
        guard selectedScope != .trash else { return }
        let selection = editorTextView.selectedRange()
        if selection.length == 0 {
            var typing = editorTextView.typingAttributes
            if (typing[key] as? Int) == enabledValue {
                typing.removeValue(forKey: key)
            } else {
                typing[key] = enabledValue
            }
            editorTextView.typingAttributes = typing
            return
        }

        guard let storage = editorTextView.textStorage else { return }
        var enabled = true
        var location = selection.location
        while location < NSMaxRange(selection) {
            var effectiveRange = NSRange(location: 0, length: 0)
            guard (storage.attribute(key, at: location, effectiveRange: &effectiveRange) as? Int) == enabledValue else {
                enabled = false
                break
            }
            location = max(location + 1, NSMaxRange(effectiveRange))
        }

        suppressEditorChanges = true
        storage.beginEditing()
        if enabled {
            storage.removeAttribute(key, range: selection)
            if key == .underlineStyle {
                storage.removeAttribute(.underlineColor, range: selection)
            } else if key == .strikethroughStyle {
                storage.removeAttribute(.strikethroughColor, range: selection)
            }
        } else {
            storage.addAttribute(key, value: enabledValue, range: selection)
        }
        storage.endEditing()
        suppressEditorChanges = false
        editorTextView.setSelectedRange(selection)
        updateTypingAttributesFromInsertionPoint()
        editorTextView.layoutManager?.invalidateDisplay(forCharacterRange: selection)
        _ = actionName
        markDirty()
    }

    func toggledFont(from font: NSFont, trait: NSFontTraitMask) -> NSFont {
        if NSFontManager.shared.traits(of: font).contains(trait) {
            return NSFontManager.shared.convert(font, toNotHaveTrait: trait)
        }
        return NSFontManager.shared.convert(font, toHaveTrait: trait)
    }

    func isItalicActive(font: NSFont, obliqueness: Any?) -> Bool {
        if NSFontManager.shared.traits(of: font).contains(.italicFontMask) {
            return true
        }
        if let number = obliqueness as? NSNumber {
            return abs(number.doubleValue) > 0.001
        }
        if let value = obliqueness as? CGFloat {
            return abs(value) > 0.001
        }
        if let value = obliqueness as? Double {
            return abs(value) > 0.001
        }
        return false
    }

    func sameParagraphCategory(_ lhs: MarkdownParagraphKind, _ rhs: MarkdownParagraphKind) -> Bool {
        switch (lhs, rhs) {
        case (.heading(let lhsLevel), .heading(let rhsLevel)):
            return lhsLevel == rhsLevel
        case (.bullet, .bullet), (.ordered, .ordered), (.checklist, .checklist), (.paragraph, .paragraph):
            return true
        default:
            return false
        }
    }

    func joinRenderedLines(_ lines: [NSAttributedString]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n", attributes: theme.baseAttributes(for: .paragraph)))
            }
            result.append(line)
        }
        return result
    }

    func combinedRange(of ranges: [NSRange]) -> NSRange {
        guard let first = ranges.first, let last = ranges.last else { return NSRange(location: 0, length: 0) }
        return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
    }
}
