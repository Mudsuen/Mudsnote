import AppKit
import Testing
@testable import QuickMarkdown

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

        #expect(!visible.contains("# "))
        #expect(!visible.contains("- [ ]"))
        #expect(visible.contains("Heading"))
        #expect(visible.contains("\u{2610} "))
    }

    @Test
    func richCodecTreatsBracketShortcutsAsChecklist() {
        let squareRendered = MarkdownRichTextCodec.renderLine("[] ", theme: theme)
        let fullWidthRendered = MarkdownRichTextCodec.renderLine("【】 task", theme: theme)

        #expect(squareRendered.string == "\u{2610} ")
        #expect(fullWidthRendered.string.hasPrefix("\u{2610} "))
        #expect(MarkdownRichTextCodec.serialize(squareRendered, theme: theme) == "- [ ] ")
        #expect(MarkdownRichTextCodec.serialize(fullWidthRendered, theme: theme) == "- [ ] task")
    }

    @Test
    func richCodecShowsEmptyListPrefixesImmediately() {
        let bulletRendered = MarkdownRichTextCodec.renderLine("- ", theme: theme)
        let orderedRendered = MarkdownRichTextCodec.renderLine("1. ", theme: theme)

        #expect(bulletRendered.string == "\u{2022} ")
        #expect(orderedRendered.string == "1. ")
        #expect(MarkdownRichTextCodec.serialize(bulletRendered, theme: theme) == "- ")
        #expect(MarkdownRichTextCodec.serialize(orderedRendered, theme: theme) == "1. ")
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
}
