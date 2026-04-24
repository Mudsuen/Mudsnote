import AppKit
import Testing
@testable import Mudsnote

@MainActor
struct MarkdownRichEditorTests {
    private let theme = MarkdownEditorTheme(
        textColor: NSColor.white,
        mutedTextColor: NSColor.white.withAlphaComponent(0.7),
        accentColor: NSColor.white,
        bodyFont: NSFont.systemFont(ofSize: 14, weight: .regular),
        boldFont: NSFont.systemFont(ofSize: 14, weight: .bold),
        italicFont: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 14, weight: .regular), toHaveTrait: .italicFontMask),
        codeFont: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
    )

    @Test
    func richCodecRoundTripsHeadingAndLists() {
        let markdown = """
        # Smoke Title

        - [ ] alpha
        1. first
        2. next
        """

        let attributed = MarkdownRichTextCodec.render(markdown: markdown, theme: theme)
        let serialized = MarkdownRichTextCodec.serialize(attributed, theme: theme)

        #expect(serialized == markdown)
    }

    @Test
    func richCodecRemovesMarkdownMarkersFromVisibleText() {
        let markdown = """
        # Heading
        - [ ] task
        """

        let attributed = MarkdownRichTextCodec.render(markdown: markdown, theme: theme)
        let visible = attributed.string
        let checklistAttachment = attributed.attribute(.attachment, at: 8, effectiveRange: nil) as? NSTextAttachment

        #expect(!visible.contains("# "))
        #expect(!visible.contains("- [ ]"))
        #expect(visible.contains("Heading"))
        #expect(checklistAttachment != nil)
    }

    @Test
    func richCodecTreatsBracketShortcutsAsChecklist() {
        let squareRendered = MarkdownRichTextCodec.renderLine("[] ", theme: theme)
        let fullWidthRendered = MarkdownRichTextCodec.renderLine("【】 task", theme: theme)

        #expect(squareRendered.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment != nil)
        #expect(fullWidthRendered.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment != nil)
        #expect(MarkdownRichTextCodec.serialize(squareRendered, theme: theme) == "- [ ] ")
        #expect(MarkdownRichTextCodec.serialize(fullWidthRendered, theme: theme) == "- [ ] task")
    }

    @Test
    func richCodecShowsEmptyListPrefixesImmediately() {
        let bulletRendered = MarkdownRichTextCodec.renderLine("- ", theme: theme)
        let orderedRendered = MarkdownRichTextCodec.renderLine("1. ", theme: theme)

        #expect(bulletRendered.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment != nil)
        #expect(orderedRendered.string == "1. ")
        #expect(MarkdownRichTextCodec.serialize(bulletRendered, theme: theme) == "- ")
        #expect(MarkdownRichTextCodec.serialize(orderedRendered, theme: theme) == "1. ")
    }

    @Test
    func richCodecInterpretsBareBulletPrefixAsSoonAsSpaceIsTyped() {
        #expect(MarkdownRichTextCodec.shouldInterpretMarkdown(in: "- "))
        #expect(MarkdownRichTextCodec.shouldInterpretMarkdown(in: "* "))
        #expect(MarkdownRichTextCodec.shouldInterpretMarkdown(in: "+ "))
    }

    @Test
    func richCodecRendersInlineTagsInBlueWithoutChangingMarkdown() {
        let rendered = MarkdownRichTextCodec.renderLine("hello #alpha world", theme: theme)
        let visible = rendered.string as NSString
        let tagRange = visible.range(of: "#alpha")
        let color = rendered.attribute(.foregroundColor, at: tagRange.location, effectiveRange: nil) as? NSColor
        let isTag = rendered.attribute(.qmTag, at: tagRange.location, effectiveRange: nil) as? Bool

        #expect(tagRange.location != NSNotFound)
        #expect(isTag == true)
        #expect(color == NSColor.systemBlue.withAlphaComponent(0.96))
        #expect(MarkdownRichTextCodec.serialize(rendered, theme: theme) == "hello #alpha world")
    }

    @Test
    func quickCaptureDocumentStateSeparatesTitleAndBody() {
        let state = QuickCaptureDocumentState(
            title: "  Weekly Review  ",
            bodyMarkdown: "\n- [ ] Finish report\n#ops\n"
        )

        #expect(state.normalizedTitle == "Weekly Review")
        #expect(state.normalizedBody == "- [ ] Finish report\n#ops")
        #expect(state.document.title == "Weekly Review")
        #expect(state.document.body == "- [ ] Finish report\n#ops")
        #expect(state.document.tags == ["ops"])
        #expect(state.hasMeaningfulContent == true)
    }

    @Test
    func quickCaptureTagToggleAddsAndRemovesStandaloneTags() {
        let original = "Draft body\n#alpha\nkeep #beta"
        let removed = QuickCaptureDocumentState.toggledTag("alpha", in: original)
        let added = QuickCaptureDocumentState.toggledTag("gamma", in: removed)

        #expect(!QuickCaptureDocumentState.containsTag("alpha", in: removed))
        #expect(QuickCaptureDocumentState.containsTag("beta", in: removed))
        #expect(QuickCaptureDocumentState.containsTag("gamma", in: added))
        #expect(added.contains("#gamma"))
    }

    @MainActor
    @Test
    func movableBackgroundViewReturnsSelfForEmptyHitAreas() {
        let view = WindowMoveBackgroundView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        let point = NSPoint(x: 24, y: 20)

        #expect(view.hitTest(point) === view)
        #expect(view.mouseDownCanMoveWindow == false)
    }

    @MainActor
    @Test
    func subviewPassthroughViewDoesNotSwallowBlankClicks() {
        let view = SubviewPassthroughView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        let point = NSPoint(x: 24, y: 20)

        #expect(view.hitTest(point) == nil)
    }

    @MainActor
    @Test
    func focusProxyContainerLetsTextFieldKeepDirectHits() {
        let proxy = FocusProxyContainerView(frame: NSRect(x: 0, y: 0, width: 220, height: 40))
        let field = FocusableTextField(string: "")
        field.frame = NSRect(x: 12, y: 6, width: 160, height: 28)
        proxy.addSubview(field)

        #expect(proxy.hitTest(NSPoint(x: 24, y: 20)) === field)
        #expect(proxy.hitTest(NSPoint(x: 208, y: 20)) === proxy)
    }

    @MainActor
    @Test
    func titleEditorProxyLetsTitleViewReceiveDirectHits() {
        let proxy = TitleEditorProxyView(frame: NSRect(x: 0, y: 0, width: 220, height: 34))
        let textView = FocusableTitleTextView(frame: proxy.bounds)
        proxy.addSubview(textView)

        #expect(proxy.hitTest(NSPoint(x: 24, y: 16)) === textView)
        #expect(proxy.hitTest(NSPoint(x: 200, y: 16)) === textView)
    }

    @MainActor
    @Test
    func titleTextViewReportsMarkedTextStateChanges() {
        let textView = FocusableTitleTextView(frame: NSRect(x: 0, y: 0, width: 220, height: 34))
        var callbackCount = 0
        textView.onTextInputStateChanged = { callbackCount += 1 }

        textView.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        textView.unmarkText()

        #expect(callbackCount >= 2)
    }
}
