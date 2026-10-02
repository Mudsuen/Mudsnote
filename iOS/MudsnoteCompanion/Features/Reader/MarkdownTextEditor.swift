import SwiftUI
import AVFoundation
import AVKit
import PencilKit
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

@MainActor
final class MarkdownRichTextView: UITextView {
    var checklistMarkers: [MarkdownEditorPresentation.ChecklistMarker] = [] {
        didSet { setNeedsDisplay() }
    }
    var bulletMarkers: [MarkdownEditorPresentation.BulletMarker] = [] {
        didSet { setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        for marker in checklistMarkers {
            let symbolRect = checklistSymbolRect(for: marker)
            let configuration = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
            let name = marker.checked ? "checkmark.square.fill" : "square"
            UIColor(MudsnoteColors.primary).set()
            UIImage(systemName: name, withConfiguration: configuration)?
                .withTintColor(UIColor(MudsnoteColors.primary), renderingMode: .alwaysOriginal)
                .draw(in: symbolRect)
        }
        UIColor(MudsnoteColors.text).setFill()
        for marker in bulletMarkers {
            let markerRect = renderedRect(for: marker.range)
            let diameter: CGFloat = 6
            let bulletRect = CGRect(
                x: markerRect.minX + 7,
                y: markerRect.midY - diameter / 2,
                width: diameter,
                height: diameter
            )
            UIBezierPath(ovalIn: bulletRect).fill()
        }
    }

    func checklistMarker(at point: CGPoint) -> MarkdownEditorPresentation.ChecklistMarker? {
        checklistMarkers.first { marker in
            checklistSymbolRect(for: marker).insetBy(dx: -8, dy: -8).contains(point)
        }
    }

    private func checklistSymbolRect(
        for marker: MarkdownEditorPresentation.ChecklistMarker
    ) -> CGRect {
        let markerRect = renderedRect(for: marker.range)
        let glyphIndex = layoutManager.glyphIndexForCharacter(
            at: min(marker.range.location, max(textStorage.length - 1, 0))
        )
        var lineRect = layoutManager.lineFragmentUsedRect(
            forGlyphAt: glyphIndex,
            effectiveRange: nil
        )
        lineRect.origin.x += textContainerInset.left
        lineRect.origin.y += textContainerInset.top
        let side: CGFloat = 20
        return CGRect(
            x: markerRect.minX,
            y: lineRect.midY - side / 2,
            width: side,
            height: side
        )
    }

    private func renderedRect(for range: NSRange) -> CGRect {
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: range,
            actualCharacterRange: nil
        )
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerInset.left
        rect.origin.y += textContainerInset.top
        return rect
    }
}

@MainActor
enum MarkdownEditorPresentation {
    struct ChecklistMarker: Equatable {
        var range: NSRange
        var checked: Bool
    }

    struct BulletMarker: Equatable {
        var range: NSRange
    }

    static func apply(to textView: UITextView, displaysSource: Bool) {
        // Rewriting text storage while an input method owns marked text cancels
        // the composition session (and can dismiss the software keyboard).
        // Wait for UIKit to commit the marked text before rendering Markdown.
        guard textView.markedTextRange == nil else { return }

        let storage = textView.textStorage
        let fullRange = NSRange(location: 0, length: storage.length)
        let selection = textView.selectedRange
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 3
        let bodyFont: UIFont = displaysSource
            ? .monospacedSystemFont(ofSize: 17, weight: .regular)
            : .preferredFont(forTextStyle: .body)
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: UIColor(MudsnoteColors.text),
            .paragraphStyle: paragraph,
        ]

        storage.beginEditing()
        if fullRange.length > 0 {
            storage.setAttributes(baseAttributes, range: fullRange)
        }
        guard !displaysSource, storage.length <= 512 * 1_024 else {
            (textView as? MarkdownRichTextView)?.checklistMarkers = []
            (textView as? MarkdownRichTextView)?.bulletMarkers = []
            storage.endEditing()
            textView.typingAttributes = baseAttributes
            textView.selectedRange = clamped(selection, length: storage.length)
            return
        }

        let source = storage.string as NSString
        let checklistMarkers = checklists(in: source as String)
        for marker in checklistMarkers {
            storage.addAttributes([
                .foregroundColor: UIColor.clear,
                .font: UIFont.preferredFont(forTextStyle: .body),
            ], range: marker.range)
        }
        (textView as? MarkdownRichTextView)?.checklistMarkers = checklistMarkers
        let bulletMarkers = bullets(in: source as String)
        for marker in bulletMarkers {
            storage.addAttributes([
                .foregroundColor: UIColor.clear,
                .font: UIFont.preferredFont(forTextStyle: .body),
            ], range: marker.range)
        }
        (textView as? MarkdownRichTextView)?.bulletMarkers = bulletMarkers
        applyHeadings(in: source, storage: storage)
        applyDelimited(#"\*\*([^\n]+?)\*\*"#, markerLength: 2, trait: .traitBold, in: source, storage: storage)
        applyDelimited(#"<u>([^\n]+?)</u>"#, markerLength: 3, suffixMarkerLength: 4, trait: nil, in: source, storage: storage, extra: [.underlineStyle: NSUnderlineStyle.single.rawValue])
        applyDelimited(#"<mark>([^\n]+?)</mark>"#, markerLength: 6, suffixMarkerLength: 7, trait: nil, in: source, storage: storage, extra: [.backgroundColor: UIColor.systemYellow.withAlphaComponent(0.48)])
        applyDelimited(#"~~([^\n]+?)~~"#, markerLength: 2, trait: nil, in: source, storage: storage, extra: [.strikethroughStyle: NSUnderlineStyle.single.rawValue])
        applyDelimited(#"(?<!\*)\*([^*\n]+?)\*(?!\*)"#, markerLength: 1, trait: .traitItalic, in: source, storage: storage)
        applyDelimited(#"_([^_\n]+?)_"#, markerLength: 1, trait: .traitItalic, in: source, storage: storage)
        applyCode(in: source, storage: storage)
        applyLinks(in: source, storage: storage)
        storage.endEditing()
        textView.typingAttributes = baseAttributes
        textView.selectedRange = clamped(selection, length: storage.length)
    }

    private static func applyHeadings(in source: NSString, storage: NSTextStorage) {
        matches(#"(?m)^(#{1,6})[ \t]+([^\n]*)"#, in: source).forEach { match in
            let marker = match.range(at: 1)
            let level = marker.length
            let size: CGFloat = switch level {
            case 1: 28
            case 2: 24
            case 3: 21
            default: 18
            }
            storage.addAttribute(
                .font,
                value: UIFont.systemFont(ofSize: size, weight: .bold),
                range: match.range
            )
            conceal(NSRange(location: marker.location, length: marker.length + 1), in: storage)
        }
    }

    private static func applyDelimited(
        _ pattern: String,
        markerLength: Int,
        suffixMarkerLength: Int? = nil,
        trait: UIFontDescriptor.SymbolicTraits?,
        in source: NSString,
        storage: NSTextStorage,
        extra: [NSAttributedString.Key: Any] = [:]
    ) {
        matches(pattern, in: source).forEach { match in
            let content = match.range(at: 1)
            if let trait, content.length > 0 {
                let current = storage.attribute(.font, at: content.location, effectiveRange: nil) as? UIFont
                    ?? .preferredFont(forTextStyle: .body)
                if let descriptor = current.fontDescriptor.withSymbolicTraits(
                    current.fontDescriptor.symbolicTraits.union(trait)
                ) {
                    storage.addAttribute(.font, value: UIFont(descriptor: descriptor, size: current.pointSize), range: content)
                }
            }
            if !extra.isEmpty { storage.addAttributes(extra, range: content) }
            let trailingMarkerLength = suffixMarkerLength ?? markerLength
            conceal(NSRange(location: match.range.location, length: markerLength), in: storage)
            conceal(
                NSRange(
                    location: NSMaxRange(match.range) - trailingMarkerLength,
                    length: trailingMarkerLength
                ),
                in: storage
            )
        }
    }

    private static func applyCode(in source: NSString, storage: NSTextStorage) {
        matches(#"`([^`\n]+?)`"#, in: source).forEach { match in
            let content = match.range(at: 1)
            storage.addAttributes([
                .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular),
                .backgroundColor: UIColor.secondarySystemFill,
            ], range: content)
            conceal(NSRange(location: match.range.location, length: 1), in: storage)
            conceal(NSRange(location: NSMaxRange(match.range) - 1, length: 1), in: storage)
        }
    }

    private static func applyLinks(in source: NSString, storage: NSTextStorage) {
        matches(#"\[([^\]\n]+)\]\(([^)\n]+)\)"#, in: source).forEach { match in
            let label = match.range(at: 1)
            storage.addAttributes([
                .foregroundColor: UIColor(MudsnoteColors.primary),
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ], range: label)
            conceal(NSRange(location: match.range.location, length: 1), in: storage)
            conceal(NSRange(location: NSMaxRange(label), length: NSMaxRange(match.range) - NSMaxRange(label)), in: storage)
        }
    }

    private static func conceal(_ range: NSRange, in storage: NSTextStorage) {
        guard range.location >= 0, NSMaxRange(range) <= storage.length else { return }
        storage.addAttributes([
            .foregroundColor: UIColor.clear,
            .font: UIFont.systemFont(ofSize: 1),
        ], range: range)
    }

    private static func matches(_ pattern: String, in source: NSString) -> [NSTextCheckingResult] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return expression.matches(in: source as String, range: NSRange(location: 0, length: source.length))
    }

    private static func clamped(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        return NSRange(location: location, length: min(range.length, length - location))
    }

    static func checklists(in markdown: String) -> [ChecklistMarker] {
        let source = markdown as NSString
        return matches(#"(?m)^[ \t]*(- \[([ xX])\] )"#, in: source).map { match in
            let markerRange = match.range(at: 1)
            let stateRange = match.range(at: 2)
            let state = stateRange.location < source.length
                ? source.substring(with: stateRange).lowercased()
                : " "
            return ChecklistMarker(range: markerRange, checked: state == "x")
        }
    }

    static func bullets(in markdown: String) -> [BulletMarker] {
        let source = markdown as NSString
        return matches(#"(?m)^[ \t]*([-*+] )(?!\[[ xX]\] )"#, in: source).map { match in
            BulletMarker(range: match.range(at: 1))
        }
    }

    static func togglingChecklist(in markdown: String, marker: ChecklistMarker) -> String? {
        let source = NSMutableString(string: markdown)
        let stateLocation = marker.range.location + 3
        guard marker.range.length >= 5, stateLocation < source.length else { return nil }
        source.replaceCharacters(
            in: NSRange(location: stateLocation, length: 1),
            with: marker.checked ? " " : "x"
        )
        return source as String
    }
}

struct MarkdownTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var command: MarkdownEditingCommand?
    @Binding var linkDraft: MarkdownLinkDraft?
    @Binding var tagDraft: MarkdownInlineTagDraft?
    @Binding var noteMentionDraft: MarkdownNoteMentionDraft?
    var contentTopInset: CGFloat
    @Binding var scrollOffset: CGFloat
    var displaysSource: Bool
    var initialInsertionOffset: Int?
    var onCommitTag: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = MarkdownRichTextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textColor = UIColor(MudsnoteColors.text)
        view.tintColor = UIColor(MudsnoteColors.primary)
        view.font = .monospacedSystemFont(ofSize: 17, weight: .regular)
        view.textContainerInset = UIEdgeInsets(
            top: contentTopInset,
            left: 0,
            bottom: 0,
            right: 0
        )
        view.textContainer.lineFragmentPadding = 0
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive
        view.autocorrectionType = .yes
        view.smartDashesType = .no
        view.smartQuotesType = .no
        view.text = text
        view.selectedRange = NSRange(location: min(max(initialInsertionOffset ?? 0, 0), (text as NSString).length), length: 0)
        let checklistTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleChecklistTap(_:))
        )
        checklistTap.cancelsTouchesInView = false
        checklistTap.delegate = context.coordinator
        view.addGestureRecognizer(checklistTap)
        MarkdownEditorPresentation.apply(to: view, displaysSource: displaysSource)
        context.coordinator.lastPresentedText = text
        context.coordinator.lastDisplaysSource = displaysSource
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if abs(view.textContainerInset.top - contentTopInset) > 0.5 {
            view.textContainerInset.top = contentTopInset
        }
        let isComposingText = view.markedTextRange != nil
        if !isComposingText, view.text != text {
            let selection = view.selectedRange
            view.text = text
            view.selectedRange = NSRange(
                location: min(selection.location, (text as NSString).length),
                length: 0
            )
        }
        if !isComposingText,
           context.coordinator.lastPresentedText != text
            || context.coordinator.lastDisplaysSource != displaysSource {
            MarkdownEditorPresentation.apply(to: view, displaysSource: displaysSource)
            context.coordinator.lastPresentedText = text
            context.coordinator.lastDisplaysSource = displaysSource
        }
        if isFocused, !view.isFirstResponder {
            view.becomeFirstResponder()
            if initialInsertionOffset != nil {
                view.layoutIfNeeded()
                view.scrollRangeToVisible(view.selectedRange)
            }
        } else if !isFocused, view.isFirstResponder {
            view.resignFirstResponder()
        }
        if let command, context.coordinator.lastCommandID != command.id {
            context.coordinator.lastCommandID = command.id
            context.coordinator.apply(command.kind, to: view)
            DispatchQueue.main.async { self.command = nil }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: MarkdownTextEditor
        var lastCommandID: UUID?
        var lastPresentedText: String?
        var lastDisplaysSource: Bool?

        init(parent: MarkdownTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            // Marked text is provisional input owned by the active IME. Publishing
            // or restyling it makes SwiftUI update the representable mid-composition,
            // which interrupts Chinese/Japanese/Korean keyboards. UIKit calls this
            // delegate again after the composition is committed.
            guard textView.markedTextRange == nil else { return }
            parent.text = textView.text
            MarkdownEditorPresentation.apply(
                to: textView,
                displaysSource: parent.displaysSource
            )
            lastPresentedText = textView.text
            lastDisplaysSource = parent.displaysSource
            updateTagDraft(in: textView)
            updateNoteMentionDraft(in: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
            parent.tagDraft = nil
            parent.noteMentionDraft = nil
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            updateTagDraft(in: textView)
            updateNoteMentionDraft(in: textView)
        }

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard range.length > 0 else {
                return UIMenu(children: suggestedActions)
            }
            let bold = UIAction(
                title: String(localized: "Bold"),
                image: UIImage(systemName: "bold")
            ) { [weak self, weak textView] _ in
                guard let self, let textView else { return }
                self.apply(.bold, to: textView)
            }
            return UIMenu(
                children: suggestedActions + [
                    UIMenu(options: .displayInline, children: [bold])
                ]
            )
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            parent.scrollOffset = max(scrollView.contentOffset.y, 0)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let recognizer = gestureRecognizer as? UITapGestureRecognizer,
                  let view = recognizer.view as? MarkdownRichTextView else { return true }
            return view.checklistMarker(at: recognizer.location(in: view)) != nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            if !parent.displaysSource,
               (text == " " || text == "\n" || text == "\t"),
               let draft = MarkdownTagSyntax.inlineDraft(
                   in: textView.text,
                   selection: range
               ),
               let tag = MarkdownTagSyntax.normalizedTag(draft.query) {
                replace(
                    draft.replacementRange,
                    with: text == "\n" ? "\n" : "",
                    selecting: NSRange(
                        location: draft.replacementRange.location + (text == "\n" ? 1 : 0),
                        length: 0
                    ),
                    in: textView
                )
                parent.tagDraft = nil
                parent.onCommitTag(tag)
                return false
            }
            guard !parent.displaysSource else { return true }
            let edit: MarkdownListEdit?
            if text == "\n" {
                edit = MarkdownListEditing.returnEdit(in: textView.text, selection: range)
            } else if text.isEmpty {
                edit = MarkdownListEditing.backspaceEdit(in: textView.text, deletionRange: range)
            } else {
                edit = nil
            }
            guard let edit else { return true }
            replace(
                edit.range,
                with: edit.replacement,
                selecting: edit.selection,
                in: textView
            )
            return false
        }

        @objc func handleChecklistTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  !parent.displaysSource,
                  let view = recognizer.view as? MarkdownRichTextView,
                  let marker = view.checklistMarker(at: recognizer.location(in: view)),
                  let updated = MarkdownEditorPresentation.togglingChecklist(
                    in: view.text,
                    marker: marker
                  ) else { return }
            let selection = view.selectedRange
            view.text = updated
            view.selectedRange = selection
            parent.text = updated
            MarkdownEditorPresentation.apply(to: view, displaysSource: false)
            lastPresentedText = updated
            lastDisplaysSource = false
        }

        func apply(_ kind: MarkdownEditingCommand.Kind, to textView: UITextView) {
            switch kind {
            case .title:
                applyParagraphStyle(.title, in: textView)
            case .heading:
                applyParagraphStyle(.heading, in: textView)
            case .subheading:
                applyParagraphStyle(.subheading, in: textView)
            case .body:
                applyParagraphStyle(.body, in: textView)
            case .bold:
                toggleInlineStyle(prefix: "**", suffix: "**", placeholder: "bold", in: textView)
            case .italic:
                toggleInlineStyle(prefix: "_", suffix: "_", placeholder: "italic", in: textView)
            case .underline:
                toggleInlineStyle(prefix: "<u>", suffix: "</u>", placeholder: "underline", in: textView)
            case .highlight:
                toggleInlineStyle(prefix: "<mark>", suffix: "</mark>", placeholder: "highlight", in: textView)
            case .strikethrough:
                toggleInlineStyle(prefix: "~~", suffix: "~~", placeholder: "strikethrough", in: textView)
            case .bullet:
                toggleLinePrefix("- ", in: textView)
            case .ordered:
                toggleOrderedList(in: textView)
            case .checklist:
                toggleLinePrefix("- [ ] ", in: textView)
            case .outdent:
                changeListIndentation(.decrease, in: textView)
            case .indent:
                changeListIndentation(.increase, in: textView)
            case .quote:
                toggleLinePrefix("> ", in: textView)
            case .code:
                toggleInlineStyle(prefix: "`", suffix: "`", placeholder: "code", in: textView)
            case .link:
                let draft = MarkdownLinkEditing.draft(
                    in: textView.text,
                    selection: textView.selectedRange
                )
                DispatchQueue.main.async { self.parent.linkDraft = draft }
            case .applyLink(let draft, let label, let destination):
                if let edit = MarkdownLinkEditing.insertionEdit(
                    for: draft,
                    label: label,
                    destination: destination
                ) {
                    replace(edit.range, with: edit.replacement, selecting: edit.selection, in: textView)
                }
            case .removeLink(let draft):
                if let edit = MarkdownLinkEditing.removalEdit(for: draft) {
                    replace(edit.range, with: edit.replacement, selecting: edit.selection, in: textView)
                }
            case .applyNoteMention(let range, let label, let destination):
                let draft = MarkdownLinkDraft(
                    range: range,
                    label: "",
                    destination: "",
                    isExisting: false
                )
                if let edit = MarkdownLinkEditing.insertionEdit(
                    for: draft,
                    label: label,
                    destination: destination
                ) {
                    replace(edit.range, with: edit.replacement, selecting: edit.selection, in: textView)
                }
            case .table:
                if let edit = MarkdownTableEditing.insertionEdit(
                    in: textView.text,
                    selection: textView.selectedRange
                ) {
                    replace(edit.range, with: edit.replacement, selecting: edit.selection, in: textView)
                }
            case .undo:
                textView.undoManager?.undo()
            case .redo:
                textView.undoManager?.redo()
            case .insertText(let text):
                let insertion = triggerAwareInsertion(
                    text,
                    in: textView
                )
                replace(
                    textView.selectedRange,
                    with: insertion,
                    selecting: NSRange(
                        location: textView.selectedRange.location + insertion.utf16.count,
                        length: 0
                    ),
                    in: textView
                )
            case .applyTag(let range, let tag):
                replace(
                    range,
                    with: "",
                    selecting: NSRange(location: range.location, length: 0),
                    in: textView
                )
                parent.tagDraft = nil
                parent.onCommitTag(tag)
            }
            parent.text = textView.text
            MarkdownEditorPresentation.apply(
                to: textView,
                displaysSource: parent.displaysSource
            )
            lastPresentedText = textView.text
            lastDisplaysSource = parent.displaysSource
        }

        private func triggerAwareInsertion(
            _ text: String,
            in textView: UITextView
        ) -> String {
            guard text == "#" || text == "@",
                  textView.selectedRange.length == 0,
                  textView.selectedRange.location > 0
            else { return text }
            let source = textView.text as NSString
            let previous = source.substring(
                with: NSRange(location: textView.selectedRange.location - 1, length: 1)
            )
            return previous.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
                ? " \(text)"
                : text
        }

        private func updateTagDraft(in textView: UITextView) {
            parent.tagDraft = MarkdownTagSyntax.inlineDraft(
                in: textView.text,
                selection: textView.selectedRange
            )
        }

        private func updateNoteMentionDraft(in textView: UITextView) {
            let selection = textView.selectedRange
            guard selection.length == 0 else {
                parent.noteMentionDraft = nil
                return
            }
            let source = textView.text as NSString
            let caret = min(selection.location, source.length)
            let paragraphRange = source.paragraphRange(
                for: NSRange(location: caret, length: 0)
            )
            let prefixRange = NSRange(
                location: paragraphRange.location,
                length: max(caret - paragraphRange.location, 0)
            )
            let prefix = source.substring(with: prefixRange)
            guard let match = prefix.range(
                of: #"(^|\s)@([^@\n]*)$"#,
                options: .regularExpression
            ) else {
                parent.noteMentionDraft = nil
                return
            }
            let matched = String(prefix[match])
            guard let atIndex = matched.firstIndex(of: "@") else {
                parent.noteMentionDraft = nil
                return
            }
            let token = String(matched[atIndex...])
            let matchRange = NSRange(match, in: prefix)
            parent.noteMentionDraft = MarkdownNoteMentionDraft(
                query: String(token.dropFirst()),
                replacementRange: NSRange(
                    location: prefixRange.location
                        + matchRange.location
                        + matched[..<atIndex].utf16.count,
                    length: token.utf16.count
                )
            )
        }

        private func toggleInlineStyle(
            prefix: String,
            suffix: String,
            placeholder: String,
            in textView: UITextView
        ) {
            guard let edit = MarkdownInlineEditing.toggleEdit(
                in: textView.text,
                selection: textView.selectedRange,
                prefix: prefix,
                suffix: suffix,
                placeholder: placeholder
            ) else { return }
            replace(
                edit.range,
                with: edit.replacement,
                selecting: edit.selection,
                in: textView
            )
        }

        private func applyParagraphStyle(
            _ style: MarkdownParagraphEditing.Style,
            in textView: UITextView
        ) {
            guard let edit = MarkdownParagraphEditing.styleEdit(
                in: textView.text,
                selection: textView.selectedRange,
                style: style
            ) else { return }
            replace(
                edit.range,
                with: edit.replacement,
                selecting: edit.selection,
                in: textView
            )
        }

        private func toggleLinePrefix(_ prefix: String, in textView: UITextView) {
            guard let edit = MarkdownListEditing.prefixEdit(
                in: textView.text,
                selection: textView.selectedRange,
                prefix: prefix
            ) else { return }
            replace(
                edit.range,
                with: edit.replacement,
                selecting: edit.selection,
                in: textView
            )
        }

        private func toggleOrderedList(in textView: UITextView) {
            guard let edit = MarkdownListEditing.orderedEdit(
                in: textView.text,
                selection: textView.selectedRange
            ) else { return }
            replace(
                edit.range,
                with: edit.replacement,
                selecting: edit.selection,
                in: textView
            )
        }

        private func changeListIndentation(
            _ direction: MarkdownListEditing.IndentationDirection,
            in textView: UITextView
        ) {
            guard let edit = MarkdownListEditing.indentationEdit(
                in: textView.text,
                selection: textView.selectedRange,
                direction: direction
            ) else { return }
            replace(
                edit.range,
                with: edit.replacement,
                selecting: edit.selection,
                in: textView
            )
        }

        private func replace(
            _ range: NSRange,
            with replacement: String,
            selecting selection: NSRange,
            in textView: UITextView
        ) {
            guard let textRange = textView.textRange(from: range) else { return }
            textView.replace(textRange, withText: replacement)
            textView.selectedRange = selection
            textViewDidChange(textView)
        }
    }
}

extension UITextView {
    func textRange(from range: NSRange) -> UITextRange? {
        guard let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length) else { return nil }
        return textRange(from: start, to: end)
    }
}
