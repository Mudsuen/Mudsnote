import AppKit
import Carbon.HIToolbox
import MudsnoteCore
import Testing
@testable import Mudsnote

private extension NSView {
    var allSubviews: [NSView] {
        subviews + subviews.flatMap(\.allSubviews)
    }
}

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
    func richCodecRoundTripsHeadingLevelsAndChineseItalic() {
        let markdown = """
        # Heading 1
        ## Heading 2
        ### Heading 3
        *中文斜体*
        """

        let attributed = MarkdownRichTextCodec.render(markdown: markdown, theme: theme)
        let chineseRange = (attributed.string as NSString).range(of: "中文斜体")
        let obliqueness = attributed.attribute(.obliqueness, at: chineseRange.location, effectiveRange: nil) as? NSNumber
        let serialized = MarkdownRichTextCodec.serialize(attributed, theme: theme)

        #expect(chineseRange.location != NSNotFound)
        #expect((obliqueness?.doubleValue ?? 0) > 0)
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
    func richCodecRendersLocalMarkdownImagesAndSerializesPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-rich-image-tests-\(UUID().uuidString)", isDirectory: true)
        let noteURL = root.appendingPathComponent("Note.md")
        let imageURL = root
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent("preview.png")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pngData = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="))
        try pngData.write(to: imageURL)

        let markdown = "Before\n![Preview](Attachments/preview.png)\nAfter"
        let rendered = MarkdownRichTextCodec.render(markdown: markdown, theme: theme, baseURL: noteURL)
        var imageMarkdown: String?
        rendered.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rendered.length)) { value, range, stop in
            guard value as? NSTextAttachment != nil else { return }
            imageMarkdown = rendered.attribute(.qmImageMarkdown, at: range.location, effectiveRange: nil) as? String
            stop.pointee = true
        }

        #expect(imageMarkdown == "![Preview](Attachments/preview.png)")
        #expect(MarkdownRichTextCodec.serialize(rendered, theme: theme) == markdown)
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

    @MainActor
    @Test
    func deletingChecklistPrefixResetsLineToParagraph() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let rendered = MarkdownRichTextCodec.renderLine("- [ ] task", theme: controller.theme)
        controller.editorTextView.textStorage?.setAttributedString(rendered)
        controller.editorTextView.textStorage?.deleteCharacters(in: NSRange(location: 0, length: 1))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 0))

        controller.userDidEdit()

        let storage = try #require(controller.editorTextView.textStorage)
        let lineRange = NSRange(location: 0, length: storage.length)
        #expect(storage.string == "task")
        #expect(storage.attribute(.attachment, at: 0, effectiveRange: nil) == nil)
        #expect(MarkdownRichTextCodec.paragraphKind(at: lineRange, in: storage) == .paragraph)
        #expect(MarkdownRichTextCodec.serialize(storage, theme: controller.theme) == "task")
        #expect(controller.toolbarButtonsByAction[.checklist]?.isActive == false)
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
    func richCodecKeepsEmptyBacktickPairVisibleWhileTyping() {
        let rendered = MarkdownRichTextCodec.renderLine("``", theme: theme)

        #expect(rendered.string == "``")
        #expect(rendered.attribute(.qmCode, at: 0, effectiveRange: nil) == nil)
        #expect(MarkdownRichTextCodec.serialize(rendered, theme: theme) == "``")
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
    func quickEntryPanelRoutesCommandCommaToPreferences() throws {
        let panel = QuickEntryPanel(size: NSSize(width: 320, height: 260))
        var didRequestPreferences = false
        panel.onCommandComma = {
            didRequestPreferences = true
        }
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: ",",
            charactersIgnoringModifiers: ",",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_Comma)
        ))

        panel.sendEvent(event)

        #expect(didRequestPreferences)
    }

    @Test
    func optionRFloatingHotKeyParses() throws {
        let spec = try #require(HotKeySpec.parse("option+r"))

        #expect(spec.keyCode == UInt32(kVK_ANSI_R))
        #expect(spec.modifiers == UInt32(optionKey))
        #expect(spec.displayString == "option+r")
        #expect(spec.userVisibleString == "⌥R")
    }

    @Test
    func hotKeySpecRecognizesRecordedEvents() throws {
        let floatingEvent = try keyEvent(keyCode: UInt16(kVK_ANSI_R), modifiers: [.option], characters: "r")
        let floatingSpec = try #require(HotKeySpec.from(event: floatingEvent))
        #expect(floatingSpec.displayString == "option+r")
        #expect(floatingSpec.userVisibleString == "⌥R")

        let saveEvent = try keyEvent(keyCode: UInt16(kVK_Return), modifiers: [.command], characters: "\r")
        let saveSpec = try #require(HotKeySpec.from(event: saveEvent))
        #expect(saveSpec.displayString == "command+return")
        #expect(saveSpec.userVisibleString == "⌘↩")
    }

    @MainActor
    @Test
    func shortcutRecorderCapturesKeyEquivalentStyleShortcut() throws {
        let recorder = ShortcutRecorderButton(shortcutString: "option+r")
        let mouseEvent = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        recorder.mouseDown(with: mouseEvent)

        #expect(recorder.isRecording)

        let event = try keyEvent(keyCode: UInt16(kVK_Return), modifiers: [.command], characters: "\r")
        recorder.recordShortcutEvent(event)

        #expect(!recorder.isRecording)
        #expect(recorder.shortcutString == "command+return")
        #expect(recorder.title == "⌘↩")
    }

    @MainActor
    @Test
    func floatingNoteDoesNotSaveOnCommandSAndUsesConfiguredSaveShortcut() throws {
        var savedURLs: [URL] = []
        let harness = try makeEditorControllerHarness(
            draftID: "floating-note",
            showsSaveButton: false,
            saveShortcut: HotKeySpec.parse("command+return"),
            onSave: { savedURLs.append($0) }
        )
        defer { harness.tearDown() }
        let controller = harness.controller
        let panel = try #require(controller.window as? QuickEntryPanel)
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(
            string: "Floating title\nbody",
            attributes: controller.theme.baseAttributes(for: .paragraph)
        ))

        panel.sendEvent(try keyEvent(keyCode: UInt16(kVK_ANSI_S), modifiers: [.command], characters: "s", windowNumber: panel.windowNumber))
        #expect(savedURLs.isEmpty)

        panel.sendEvent(try keyEvent(keyCode: UInt16(kVK_Return), modifiers: [.command], characters: "\r", windowNumber: panel.windowNumber))
        #expect(savedURLs.count == 1)
    }

    @MainActor
    @Test
    func formattingKeyboardShortcutsApplyExpectedStylesAndParagraphKinds() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(
            string: "selected text",
            attributes: controller.theme.baseAttributes(for: .paragraph)
        ))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 8))

        #expect(controller.handleShortcutEvent(try keyEvent(keyCode: UInt16(kVK_ANSI_B), modifiers: [.command], characters: "b")))
        #expect(controller.handleShortcutEvent(try keyEvent(keyCode: UInt16(kVK_ANSI_I), modifiers: [.command], characters: "i")))
        #expect(controller.handleShortcutEvent(try keyEvent(keyCode: UInt16(kVK_ANSI_U), modifiers: [.command], characters: "u")))
        #expect(controller.handleShortcutEvent(try keyEvent(keyCode: UInt16(kVK_ANSI_X), modifiers: [.command, .shift], characters: "X")))

        let storage = try #require(controller.editorTextView.textStorage)
        let font = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let traits = NSFontManager.shared.traits(of: font)
        #expect(traits.contains(.boldFontMask))
        #expect(traits.contains(.italicFontMask))
        #expect((storage.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int) == NSUnderlineStyle.single.rawValue)
        #expect((storage.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int) == NSUnderlineStyle.single.rawValue)

        let heading1Kind = try paragraphKind(after: keyEvent(keyCode: UInt16(kVK_ANSI_1), modifiers: [.command, .option], characters: "1"), controller: controller)
        let heading2Kind = try paragraphKind(after: keyEvent(keyCode: UInt16(kVK_ANSI_2), modifiers: [.command, .option], characters: "2"), controller: controller)
        let heading3Kind = try paragraphKind(after: keyEvent(keyCode: UInt16(kVK_ANSI_3), modifiers: [.command, .option], characters: "3"), controller: controller)
        let orderedKind = try paragraphKind(after: keyEvent(keyCode: UInt16(kVK_ANSI_7), modifiers: [.command, .shift], characters: "&"), controller: controller)
        let bulletKind = try paragraphKind(after: keyEvent(keyCode: UInt16(kVK_ANSI_8), modifiers: [.command, .shift], characters: "*"), controller: controller)
        let checklistKind = try paragraphKind(after: keyEvent(keyCode: UInt16(kVK_ANSI_9), modifiers: [.command, .shift], characters: "("), controller: controller)

        #expect(heading1Kind.headingLevel == 1)
        #expect(heading2Kind.headingLevel == 2)
        #expect(heading3Kind.headingLevel == 3)
        #expect(orderedKind.isOrderedList)
        #expect(bulletKind.isBulletList)
        #expect(checklistKind.isChecklist)
    }

    @MainActor
    @Test
    func italicShortcutAppliesObliquenessForChineseText() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(
            string: "中文斜体",
            attributes: controller.theme.baseAttributes(for: .paragraph)
        ))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 4))

        #expect(controller.handleShortcutEvent(try keyEvent(keyCode: UInt16(kVK_ANSI_I), modifiers: [.command], characters: "i")))

        let storage = try #require(controller.editorTextView.textStorage)
        let obliqueness = storage.attribute(.obliqueness, at: 0, effectiveRange: nil) as? NSNumber
        #expect((obliqueness?.doubleValue ?? 0) > 0)
        #expect(MarkdownRichTextCodec.serialize(storage, theme: controller.theme) == "*中文斜体*")
    }

    @Test
    func clampedPanelFrameMovesOffscreenFrameIntoVisibleArea() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let offscreen = NSRect(x: 35, y: -288, width: 322, height: 416)

        let clamped = clampedPanelFrame(
            offscreen,
            fallbackSize: NSSize(width: 412, height: 314),
            visibleFrames: [visible]
        )

        #expect(clamped.origin.y >= visible.minY)
        #expect(visible.contains(NSPoint(x: clamped.midX, y: clamped.midY)))
        #expect(clamped.size == offscreen.size)
    }

    @MainActor
    @Test
    func floatingToolbarButtonAppliesInlineTypingFormat() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 0))
        let boldButton = try #require(controller.toolbarButtonsByAction[.bold])

        controller.toolbarButtonPressed(boldButton)

        let font = try #require(controller.editorTextView.typingAttributes[.font] as? NSFont)
        #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        #expect(controller.toolbarButtonsByAction[.bold]?.isActive == true)
    }

    @MainActor
    @Test
    func floatingToolbarMouseDownImmediatelyAppliesFormatting() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let boldButton = try #require(controller.toolbarButtonsByAction[.bold])
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))

        boldButton.mouseDown(with: event)

        let font = try #require(controller.editorTextView.typingAttributes[.font] as? NSFont)
        #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }

    @MainActor
    @Test
    func toolbarMouseDownFormatsPreviouslySelectedTextAfterSelectionCollapse() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let boldButton = try #require(controller.toolbarButtonsByAction[.bold])
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(string: "selected text", attributes: controller.theme.baseAttributes(for: .paragraph)))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 8))
        controller.rememberEditorSelectionForToolbarActions()
        controller.editorTextView.setSelectedRange(NSRange(location: 13, length: 0))

        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        boldButton.mouseDown(with: event)

        let storage = try #require(controller.editorTextView.textStorage)
        let formattedFont = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let untouchedFont = try #require(storage.attribute(.font, at: 9, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: formattedFont).contains(.boldFontMask))
        #expect(!NSFontManager.shared.traits(of: untouchedFont).contains(.boldFontMask))
    }

    @MainActor
    @Test
    func panelPreflightPreservesSelectionBeforeToolbarClickCollapsesIt() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let panel = try #require(controller.window as? QuickEntryPanel)
        let boldButton = try #require(controller.toolbarButtonsByAction[.bold])
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(string: "selected text", attributes: controller.theme.baseAttributes(for: .paragraph)))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 8))

        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        panel.onLeftMouseDownPreflight?(event)
        controller.editorTextView.setSelectedRange(NSRange(location: 13, length: 0))
        boldButton.mouseDown(with: event)

        let storage = try #require(controller.editorTextView.textStorage)
        let formattedFont = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: formattedFont).contains(.boldFontMask))
    }

    @MainActor
    @Test
    func toolbarMouseDownTogglesSelectedTextAcrossRepeatedClicks() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let boldButton = try #require(controller.toolbarButtonsByAction[.bold])
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(string: "selected text", attributes: controller.theme.baseAttributes(for: .paragraph)))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 8))
        controller.rememberEditorSelectionForToolbarActions()
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))

        boldButton.mouseDown(with: event)
        boldButton.mouseDown(with: event)

        let storage = try #require(controller.editorTextView.textStorage)
        let font = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(!NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        #expect(controller.editorTextView.selectedRange() == NSRange(location: 0, length: 8))
    }

    @MainActor
    @Test
    func toolbarMouseDownAppliesDifferentFormatsToCachedSelection() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let boldButton = try #require(controller.toolbarButtonsByAction[.bold])
        let italicButton = try #require(controller.toolbarButtonsByAction[.italic])
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(string: "selected text", attributes: controller.theme.baseAttributes(for: .paragraph)))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 8))
        controller.rememberEditorSelectionForToolbarActions()
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))

        boldButton.mouseDown(with: event)
        controller.editorTextView.setSelectedRange(NSRange(location: 13, length: 0))
        italicButton.mouseDown(with: event)

        let storage = try #require(controller.editorTextView.textStorage)
        let font = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let traits = NSFontManager.shared.traits(of: font)
        #expect(traits.contains(.boldFontMask))
        #expect(traits.contains(.italicFontMask))
    }

    @MainActor
    @Test
    func toolbarKeepsSingleHeadingButtonForHeadingOne() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let headingButton = try #require(controller.toolbarButtonsByAction[.heading])
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(string: "selected text", attributes: controller.theme.baseAttributes(for: .paragraph)))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 8))
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))

        headingButton.mouseDown(with: event)

        let storage = try #require(controller.editorTextView.textStorage)
        let kind = MarkdownRichTextCodec.paragraphKind(at: NSRange(location: 0, length: storage.length), in: storage)
        #expect(kind.headingLevel == 1)
        #expect(controller.toolbarButtonsByAction.count == 8)
        #expect(MarkdownRichTextCodec.serialize(storage, theme: controller.theme) == "# selected text")
    }

    @MainActor
    @Test
    func toolbarInlineFormattingCanBeUndone() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let boldButton = try #require(controller.toolbarButtonsByAction[.bold])
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(string: "selected text", attributes: controller.theme.baseAttributes(for: .paragraph)))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 8))
        controller.editorTextView.undoManager?.removeAllActions()
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))

        boldButton.mouseDown(with: event)
        controller.editorTextView.undoManager?.undo()

        let storage = try #require(controller.editorTextView.textStorage)
        let font = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(!NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        #expect(controller.editorTextView.selectedRange() == NSRange(location: 0, length: 8))
    }

    @MainActor
    @Test
    func libraryWindowUsesNotesLikeSplitAndLoadsFirstNote() throws {
        let suiteName = "mudsnote.library-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let noteURL = try store.saveNewNote(title: "Library Seed", body: "Body line", tags: ["library"])
        let noteModifiedAt = try #require((try? FileManager.default.attributesOfItem(atPath: noteURL.path)[.modificationDate]) as? Date)
        let noteDateFormatter = DateFormatter()
        noteDateFormatter.dateStyle = .medium
        noteDateFormatter.timeStyle = .short

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let window = try #require(controller.window)
        #expect(window.title == "Mudsnote 笔记")
        #expect(window.titleVisibility == .hidden)
        #expect(window.titlebarAppearsTransparent)
        #expect(window.styleMask.contains(.resizable))
        #expect(window.toolbar?.displayMode == .iconOnly)
        let toolbarItemIDs = Set((window.toolbar?.items ?? []).map(\.itemIdentifier.rawValue))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.add-folder"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.toggle-sidebar"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.new-note"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.format"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.checklist"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.table"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.link"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.attachment"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.export"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.more"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.search"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.save"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.move"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.delete"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.restore"))
        let toolbarSearchFields = (window.toolbar?.items ?? []).flatMap { item in
            item.view?.allSubviews.compactMap { $0 as? NSSearchField } ?? []
        }
        let toolbarSearchField = try #require(toolbarSearchFields.first)
        #expect(toolbarSearchField.identifier?.rawValue == "LibraryToolbarSearchField")
        #expect(toolbarSearchField === controller.searchField)
        let formatItem = try #require((window.toolbar?.items ?? []).first {
            $0.itemIdentifier.rawValue == "mudsnote.library.toolbar.format"
        })
        #expect(formatItem.image?.accessibilityDescription == "格式")
        let splitView = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSSplitView }.first)
        #expect(splitView.arrangedSubviews.count == 3)
        let libraryGroup = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.first {
            $0.identifier?.rawValue == "LibrarySourceGroup-Mudsnote"
        })
        #expect(libraryGroup.stringValue == "Mudsnote")
        let noteListTitle = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.first {
            $0.identifier?.rawValue == "LibraryNoteListTitle"
        })
        let noteListCount = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.first {
            $0.identifier?.rawValue == "LibraryNoteListCount"
        })
        let noteListEmpty = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.first {
            $0.identifier?.rawValue == "LibraryNoteListEmptyLabel"
        })
        #expect(noteListTitle.stringValue == "所有笔记")
        #expect(noteListCount.stringValue == "1 条笔记")
        #expect(noteListEmpty.isHidden)
        #expect(controller.tableView.numberOfRows == 2)
        #expect(controller.tableView(controller.tableView, isGroupRow: 0))
        #expect(!controller.tableView(controller.tableView, shouldSelectRow: 0))
        #expect(controller.tableView(controller.tableView, heightOfRow: 1) == 68)
        let firstNoteCell = try #require(controller.tableView(controller.tableView, viewFor: nil, row: 1) as? LibraryNoteCellView)
        #expect(firstNoteCell.snippetLabel.attributedStringValue.string == "Body line")
        #expect(firstNoteCell.titleLabel.font?.pointSize == 13.5)
        #expect(firstNoteCell.titleLabel.maximumNumberOfLines == 1)
        #expect(firstNoteCell.snippetLabel.maximumNumberOfLines == 1)
        #expect(firstNoteCell.metaLabel.maximumNumberOfLines == 1)
        #expect(firstNoteCell.attachmentImageView.identifier?.rawValue == "LibraryNoteAttachmentIndicator")
        #expect(firstNoteCell.attachmentImageView.isHidden)
        #expect(controller.titleField.stringValue == "Library Seed")
        #expect(controller.statusLabel.identifier?.rawValue == "LibraryEditorStatusLabel")
        #expect(controller.statusLabel.alignment == .center)
        #expect(controller.statusLabel.stringValue == noteDateFormatter.string(from: noteModifiedAt))
        #expect(!controller.statusLabel.stringValue.contains("·"))
        #expect(MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme) == "Body line")
        let allCount = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.first {
            $0.identifier?.rawValue == "LibrarySourceCount-0"
        })
        #expect(allCount.stringValue == "1")
        let folderCount = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.first {
            $0.identifier?.rawValue == "LibrarySourceCount-10"
        })
        #expect(folderCount.stringValue == "1")
        let tagButton = window.contentView?.allSubviews.compactMap { $0 as? NSButton }.first { $0.title == "#library" }
        #expect(tagButton == nil)

        controller.updatePanelOpacity(NoteStore.minimumPanelOpacity)
        #expect(window.alphaValue == 1)
    }

    @MainActor
    @Test
    func libraryNoteScrollViewFitsSingleColumnToVisibleWidth() {
        let tableView = LibraryNoteTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("library-note"))
        column.width = 248
        column.minWidth = 220
        column.resizingMask = .userResizingMask
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        let scrollView = LibraryNoteScrollView(frame: NSRect(x: 0, y: 0, width: 340, height: 300))
        scrollView.documentView = tableView
        scrollView.contentView.bounds = NSRect(x: 0, y: 0, width: 340, height: 300)
        tableView.frame = NSRect(x: 92, y: 0, width: 248, height: 300)

        scrollView.layout()

        let visibleWidth = scrollView.frame.width
        #expect(tableView.frame.origin.x == 0)
        #expect(tableView.frame.width >= visibleWidth)
        #expect(column.width == visibleWidth)
    }

    @MainActor
    @Test
    func libraryToolbarUsesNotesLikeDisabledStates() throws {
        let suiteName = "mudsnote.library-toolbar-state-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-toolbar-state-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)

        let emptyController = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { emptyController.close() }

        func toolbarItem(_ rawValue: String) -> NSToolbarItem {
            NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier(rawValue))
        }

        let formatItem = toolbarItem("mudsnote.library.toolbar.format")
        let checklistItem = toolbarItem("mudsnote.library.toolbar.checklist")
        let saveItem = toolbarItem("mudsnote.library.toolbar.save")
        let moreItem = toolbarItem("mudsnote.library.toolbar.more")
        let openItem = toolbarItem("mudsnote.library.toolbar.open-separate")
        let deleteItem = toolbarItem("mudsnote.library.toolbar.delete")
        let restoreItem = toolbarItem("mudsnote.library.toolbar.restore")
        let exportItem = toolbarItem("mudsnote.library.toolbar.export")
        let newItem = toolbarItem("mudsnote.library.toolbar.new-note")

        #expect(!emptyController.validateToolbarItem(formatItem))
        #expect(!emptyController.validateToolbarItem(checklistItem))
        #expect(!emptyController.validateToolbarItem(saveItem))
        #expect(!emptyController.validateToolbarItem(moreItem))
        #expect(!emptyController.validateToolbarItem(openItem))
        #expect(!emptyController.validateToolbarItem(deleteItem))
        #expect(!emptyController.validateToolbarItem(restoreItem))
        #expect(!emptyController.validateToolbarItem(exportItem))
        #expect(emptyController.validateToolbarItem(newItem))

        let visibleNewItem = try #require((emptyController.window?.toolbar?.items ?? []).first {
            $0.itemIdentifier.rawValue == "mudsnote.library.toolbar.new-note"
        })
        #expect(NSApp.sendAction(try #require(visibleNewItem.action), to: visibleNewItem.target, from: visibleNewItem))
        #expect(emptyController.validateToolbarItem(formatItem))
        #expect(emptyController.validateToolbarItem(checklistItem))
        #expect(emptyController.validateToolbarItem(saveItem))
        #expect(emptyController.validateToolbarItem(moreItem))

        let noteURL = try store.saveNewNote(title: "Toolbar State", body: "Body line")
        let selectedController = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { selectedController.close() }

        #expect(selectedController.selectedMarkdownFileURLForLibrary()?.path == noteURL.standardizedFileURL.path)
        #expect(selectedController.validateToolbarItem(formatItem))
        #expect(selectedController.validateToolbarItem(saveItem))
        #expect(selectedController.validateToolbarItem(moreItem))
        #expect(selectedController.validateToolbarItem(openItem))
        #expect(selectedController.validateToolbarItem(deleteItem))
        #expect(selectedController.validateToolbarItem(exportItem))
        #expect(!selectedController.validateToolbarItem(restoreItem))

        let normalMoreMenu = selectedController.makeMoreActionsMenuForLibrary()
        #expect(normalMoreMenu.items.first { $0.title == "保存" }?.isEnabled == true)
        #expect(normalMoreMenu.items.first { $0.title == "导出 Markdown..." }?.isEnabled == true)
        #expect(normalMoreMenu.items.first { $0.title == "删除" }?.isEnabled == true)

        try selectedController.deleteSelectedNoteForLibrary()
        let trashButton = try #require(selectedController.window?.contentView?.allSubviews.compactMap { $0 as? NSButton }.first {
            $0.title == "最近删除"
        })
        trashButton.performClick(nil)

        #expect(!selectedController.validateToolbarItem(formatItem))
        #expect(!selectedController.validateToolbarItem(checklistItem))
        #expect(!selectedController.validateToolbarItem(saveItem))
        #expect(!selectedController.validateToolbarItem(exportItem))
        #expect(selectedController.validateToolbarItem(moreItem))
        #expect(selectedController.validateToolbarItem(deleteItem))
        #expect(selectedController.validateToolbarItem(restoreItem))

        let trashMoreMenu = selectedController.makeMoreActionsMenuForLibrary()
        #expect(trashMoreMenu.items.first { $0.title == "保存" }?.isEnabled == false)
        #expect(trashMoreMenu.items.first { $0.title == "导出 Markdown..." }?.isEnabled == false)
        #expect(trashMoreMenu.items.first { $0.title == "恢复" }?.isEnabled == true)
        #expect(trashMoreMenu.items.first { $0.title == "永久删除" }?.isEnabled == true)
    }

    @MainActor
    @Test
    func libraryWindowEditorToolbarInsertsRichMarkdownTools() throws {
        let suiteName = "mudsnote.library-editor-tools-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-editor-tools-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let noteURL = try store.saveNewNote(title: "Editor Tools", body: "plain")
        let sourceAttachment = root.appendingPathComponent("source file.pdf")
        try "attachment".write(to: sourceAttachment, atomically: true, encoding: .utf8)

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let window = try #require(controller.window)
        let toolbarItemIDs = Set((window.toolbar?.items ?? []).map(\.itemIdentifier.rawValue))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.format"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.checklist"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.table"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.link"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.attachment"))

        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 5))
        controller.markdownTextViewToggleBold(controller.editorTextView)
        #expect(MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme) == "**plain**")

        let checklistItem = try #require((window.toolbar?.items ?? []).first {
            $0.itemIdentifier.rawValue == "mudsnote.library.toolbar.checklist"
        })
        controller.editorTextView.setSelectedRange(NSRange(location: controller.editorTextView.attributedString().length, length: 0))
        #expect(NSApp.sendAction(try #require(checklistItem.action), to: checklistItem.target, from: checklistItem))

        controller.insertTableForLibrary()
        controller.insertLinkForLibrary(label: "Muds", url: "https://muds.top")
        let copiedAttachment = try controller.insertAttachmentReferenceForLibrary(from: sourceAttachment)

        #expect(FileManager.default.fileExists(atPath: copiedAttachment.path))
        #expect(copiedAttachment.path.contains("/Attachments/"))

        _ = try controller.saveCurrentNoteForLibrary()

        let saved = try store.loadNote(at: noteURL)
        #expect(saved.body.contains("**plain**"))
        #expect(saved.body.contains("- [ ]"))
        #expect(saved.body.contains("| Column 1 | Column 2 |"))
        #expect(saved.body.contains("[Muds](https://muds.top)"))
        #expect(saved.body.contains("[source file](Attachments/"))
        #expect(saved.body.contains("source%20file.pdf"))
        let attachmentCell = try #require(controller.tableView(controller.tableView, viewFor: nil, row: 1) as? LibraryNoteCellView)
        #expect(!attachmentCell.attachmentImageView.isHidden)
        #expect(controller.noteListSearchResultsForLibrary().first?.hasAttachments == true)
    }

    @MainActor
    @Test
    func libraryWindowAutosavesEditedExistingNote() async throws {
        let suiteName = "mudsnote.library-autosave-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-autosave-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let noteURL = try store.saveNewNote(title: "Autosave Seed", body: "Original body")

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "Autosaved body",
            theme: controller.theme,
            baseURL: noteURL
        ))
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.editorTextView))

        try await Task.sleep(nanoseconds: 1_100_000_000)

        let loaded = try store.loadNote(at: noteURL)
        #expect(loaded.body == "Autosaved body")
        #expect(controller.statusLabel.stringValue != "已修改")
    }

    @MainActor
    @Test
    func libraryNoteListShowsImageAttachmentThumbnail() throws {
        let suiteName = "mudsnote.library-thumbnail-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-thumbnail-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let noteURL = try store.saveNewNote(
            title: "Image Attachment",
            body: "![Preview](Attachments/thumb.png)"
        )
        let imageURL = noteURL.deletingLastPathComponent()
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent("thumb.png")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let pngData = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="))
        try pngData.write(to: imageURL)

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let cell = try #require(controller.tableView(controller.tableView, viewFor: nil, row: 1) as? LibraryNoteCellView)

        #expect(controller.noteListSearchResultsForLibrary().first?.thumbnailURL?.path == imageURL.standardizedFileURL.path)
        #expect(!cell.thumbnailImageView.isHidden)
        #expect(cell.thumbnailImageView.image != nil)
        #expect(cell.thumbnailImageView.constraints.contains {
            $0.firstAttribute == .width && $0.constant == 44
        })
        #expect(cell.thumbnailImageView.constraints.contains {
            $0.firstAttribute == .height && $0.constant == 44
        })
        #expect(cell.attachmentImageView.isHidden)

        var editorHasImagePreview = false
        let editorContent = controller.editorTextView.attributedString()
        editorContent.enumerateAttribute(.attachment, in: NSRange(location: 0, length: editorContent.length)) { value, _, stop in
            guard value as? NSTextAttachment != nil else { return }
            editorHasImagePreview = true
            stop.pointee = true
        }
        #expect(editorHasImagePreview)
        #expect(MarkdownRichTextCodec.serialize(editorContent, theme: controller.theme) == "![Preview](Attachments/thumb.png)")
    }

    @MainActor
    @Test
    func libraryWindowSearchScopesAndHighlightsMatches() throws {
        let suiteName = "mudsnote.library-search-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-search-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let projectsFolder = try store.createFolder(named: "Projects")
        let archiveFolder = try store.createFolder(named: "Archive")
        _ = try store.saveNewNote(title: "Alpha Project", body: "current folder alpha body", in: projectsFolder)
        _ = try store.saveNewNote(title: "Archive Note", body: "global alpha body", in: archiveFolder)

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let window = try #require(controller.window)
        controller.loadSourceFoldersForLibrary()
        let scopeControl = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSSegmentedControl }.first {
            $0.identifier?.rawValue == "LibrarySearchScopeControl"
        })
        #expect(scopeControl.selectedSegment == 0)
        #expect(scopeControl.isHidden)

        let projectsButton = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSButton }.first {
            $0.title == "Projects"
        })
        projectsButton.performClick(nil)

        controller.searchForLibrary(query: "alpha", allNotes: false)
        #expect(!scopeControl.isHidden)
        #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["Alpha Project"])
        #expect(controller.noteListSearchResultsForLibrary().first?.snippet == "current folder alpha body")
        #expect(controller.noteListTitleLabel.stringValue == "Projects")
        #expect(controller.noteListCountLabel.stringValue == "1 个结果")

        let cell = try #require(controller.tableView(controller.tableView, viewFor: nil, row: 1) as? LibraryNoteCellView)
        let titleHighlight = cell.titleLabel.attributedStringValue.attribute(
            .backgroundColor,
            at: 0,
            effectiveRange: nil
        )
        let snippetRange = (cell.snippetLabel.attributedStringValue.string as NSString).range(of: "alpha")
        let snippetHighlight = cell.snippetLabel.attributedStringValue.attribute(
            .backgroundColor,
            at: snippetRange.location,
            effectiveRange: nil
        )
        #expect(titleHighlight != nil)
        #expect(snippetRange.location != NSNotFound)
        #expect(snippetHighlight != nil)

        controller.searchForLibrary(query: "alpha", allNotes: true)
        let allTitles = Set(controller.noteListSearchResultsForLibrary().map(\.title))
        #expect(allTitles == Set(["Alpha Project", "Archive Note"]))
        #expect(scopeControl.selectedSegment == 1)
        #expect(controller.noteListTitleLabel.stringValue == "所有笔记")
        #expect(controller.noteListCountLabel.stringValue == "2 个结果")

        controller.searchForLibrary(query: "not-present-anywhere", allNotes: true)
        let emptyLabel = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.first {
            $0.identifier?.rawValue == "LibraryNoteListEmptyLabel"
        })
        #expect(controller.noteListSearchResultsForLibrary().isEmpty)
        #expect(controller.tableView.numberOfRows == 0)
        #expect(!emptyLabel.isHidden)
        #expect(emptyLabel.stringValue == "未找到结果")
    }

    @MainActor
    @Test
    func librarySearchFieldKeyboardNavigatesResultsAndClearsQuery() throws {
        let suiteName = "mudsnote.library-search-keyboard-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-search-keyboard-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        _ = try store.saveNewNote(title: "Alpha First", body: "first keyboard body")
        _ = try store.saveNewNote(title: "Alpha Last", body: "last keyboard body")
        _ = try store.saveNewNote(title: "Beta Note", body: "other body")

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        controller.searchForLibrary(query: "alpha", allNotes: true)
        controller.tableView.deselectAll(nil)
        let fieldEditor = NSTextView()
        let lastResultTitle = try #require(controller.noteListSearchResultsForLibrary().last?.title)

        #expect(controller.control(controller.searchField, textView: fieldEditor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        #expect(controller.tableView.selectedRow == 1)
        controller.tableView.deselectAll(nil)

        #expect(controller.control(controller.searchField, textView: fieldEditor, doCommandBy: #selector(NSResponder.moveUp(_:))))
        #expect(controller.tableView.selectedRow == 2)

        #expect(controller.control(controller.searchField, textView: fieldEditor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(controller.titleField.stringValue == lastResultTitle)
        #expect(MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme).contains("keyboard body"))

        #expect(controller.control(controller.searchField, textView: fieldEditor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(controller.searchField.stringValue.isEmpty)
        #expect(controller.searchScopeControl.isHidden)
        #expect(controller.noteListTitleLabel.stringValue == "所有笔记")
    }

    @MainActor
    @Test
    func libraryWindowLoadsTagRowsAfterShellIsVisible() throws {
        let suiteName = "mudsnote.library-tag-source-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-tag-source-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        _ = try store.saveNewNote(title: "Tagged Seed", body: "tag body", tags: ["library"])
        _ = try store.saveNewNote(title: "Plain Seed", body: "plain body")

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let window = try #require(controller.window)
        #expect(window.contentView?.allSubviews.compactMap { $0 as? NSButton }.contains {
            $0.title == "library"
        } == false)

        controller.loadSourceTagsForLibrary()

        let tagButton = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSButton }.first {
            $0.title == "library"
        })
        let tagCount = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.first {
            $0.identifier?.rawValue == "LibrarySourceCount-100"
        })
        #expect(tagCount.stringValue == "1")

        tagButton.performClick(nil)
        #expect(controller.noteListTitleLabel.stringValue == "#library")
        #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["Tagged Seed"])
    }

    @MainActor
    @Test
    func libraryWindowShowsNestedFoldersInSourceList() throws {
        let suiteName = "mudsnote.library-nested-folder-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-nested-folder-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let projectsFolder = try store.createFolder(named: "Projects")
        let clientFolder = projectsFolder.appendingPathComponent("Client", isDirectory: true)
        try FileManager.default.createDirectory(at: clientFolder, withIntermediateDirectories: true)
        _ = try store.saveNewNote(title: "Client Seed", body: "Nested body", in: clientFolder)

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let window = try #require(controller.window)
        controller.loadSourceFoldersForLibrary()
        #expect(window.contentView?.allSubviews.compactMap { $0 as? NSButton }.contains {
            $0.title == "Projects"
        } == true)
        #expect(window.contentView?.allSubviews.compactMap { $0 as? NSButton }.contains {
            $0.title == "Client"
        } == false)

        let initialProjectsDisclosure = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSButton }.first {
            $0.identifier?.rawValue == "LibraryFolderDisclosure-11"
        })
        initialProjectsDisclosure.performClick(nil)

        let clientButton = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSButton }.first {
            $0.title == "Client"
        })
        clientButton.performClick(nil)

        #expect(controller.noteListTitleLabel.stringValue == "Client")
        #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["Client Seed"])

        let moveMenu = try #require(controller.makeMoreActionsMenuForLibrary().items.first {
            $0.title == "移到文件夹"
        }?.submenu)
        let clientMoveItem = try #require(moveMenu.items.first {
            $0.representedObject as? URL == clientFolder.standardizedFileURL
        })
        #expect(clientMoveItem.title.hasPrefix("    "))
        #expect(clientMoveItem.title.trimmingCharacters(in: .whitespaces) == "Client")

        let projectsDisclosure = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSButton }.first {
            $0.identifier?.rawValue == "LibraryFolderDisclosure-11"
        })
        projectsDisclosure.performClick(nil)
        #expect(controller.noteListTitleLabel.stringValue == "Projects")
        #expect(window.contentView?.allSubviews.compactMap { $0 as? NSButton }.contains {
            $0.title == "Client"
        } == false)

        let collapsedProjectsDisclosure = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSButton }.first {
            $0.identifier?.rawValue == "LibraryFolderDisclosure-11"
        })
        collapsedProjectsDisclosure.performClick(nil)
        #expect(window.contentView?.allSubviews.compactMap { $0 as? NSButton }.contains {
            $0.title == "Client"
        } == true)
    }

    @MainActor
    @Test
    func libraryWindowCreatesMovesRenamesAndDeletesFolders() throws {
        let suiteName = "mudsnote.library-folder-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-folder-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let projectsFolder = try store.createFolder(named: "Projects")
        let archiveFolder = try store.createFolder(named: "Archive")

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let window = try #require(controller.window)
        controller.loadSourceFoldersForLibrary()
        let projectsButton = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSButton }.first {
            $0.title == "Projects"
        })
        projectsButton.performClick(nil)

        let newItem = try #require((window.toolbar?.items ?? []).first {
            $0.itemIdentifier.rawValue == "mudsnote.library.toolbar.new-note"
        })
        #expect(NSApp.sendAction(try #require(newItem.action), to: newItem.target, from: newItem))
        controller.titleField.stringValue = "Folder Seed"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.titleField))
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(
            string: "Folder body",
            attributes: controller.theme.baseAttributes(for: .paragraph)
        ))
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.editorTextView))
        _ = try controller.saveCurrentNoteForLibrary()

        let savedInProjects = try #require(store.listNotes(limit: 10, roots: [projectsFolder]).first)
        #expect(savedInProjects.title == "Folder Seed")

        let movedURL = try controller.moveSelectedNoteForLibrary(to: archiveFolder)
        #expect(movedURL.deletingLastPathComponent().standardizedFileURL.path == archiveFolder.standardizedFileURL.path)
        #expect(store.listNotes(limit: 10, roots: [projectsFolder]).isEmpty)
        #expect(store.listNotes(limit: 10, roots: [archiveFolder]).first?.title == "Folder Seed")

        let renamedArchive = try controller.renameSelectedFolderForLibrary(to: "Renamed Archive")
        #expect(FileManager.default.fileExists(atPath: renamedArchive.path))
        #expect(!FileManager.default.fileExists(atPath: archiveFolder.path))
        #expect(window.contentView?.allSubviews.compactMap { $0 as? NSButton }.contains {
            $0.title == "Renamed Archive"
        } == true)

        try controller.deleteSelectedFolderForLibrary()
        #expect(!FileManager.default.fileExists(atPath: renamedArchive.path))
        #expect(store.listTrashedNotes(limit: 10).first?.title == "Folder Seed")
        let trashCount = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.first {
            $0.identifier?.rawValue == "LibrarySourceCount-3"
        })
        #expect(trashCount.stringValue == "1")
    }

    @MainActor
    @Test
    func libraryWindowDeletesRestoresAndPermanentlyDeletesNotes() throws {
        let suiteName = "mudsnote.library-trash-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-trash-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let noteURL = try store.saveNewNote(title: "Trash Seed", body: "Body line")

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let window = try #require(controller.window)
        let moreMenu = controller.makeMoreActionsMenuForLibrary()
        let moreMenuTitles = moreMenu.items.map(\.title)
        #expect(moreMenuTitles.contains("独立窗口打开"))
        #expect(moreMenuTitles.contains("移到文件夹"))
        #expect(moreMenuTitles.contains("保存"))
        #expect(moreMenuTitles.contains("在 Finder 中显示"))
        #expect(moreMenuTitles.contains("复制 Markdown 路径"))
        #expect(moreMenuTitles.contains("导出 Markdown..."))
        #expect(moreMenuTitles.contains("删除"))
        #expect(controller.selectedMarkdownFileURLForLibrary()?.path == noteURL.standardizedFileURL.path)
        #expect(controller.revealSelectedNoteInFinderForLibrary()?.path == noteURL.standardizedFileURL.path)
        #expect(controller.copySelectedMarkdownPathForLibrary() == noteURL.standardizedFileURL.path)
        #expect(NSPasteboard.general.string(forType: .string) == noteURL.standardizedFileURL.path)
        let exportURL = root.appendingPathComponent("Exported Toolbar Seed.md")
        #expect(try controller.exportSelectedMarkdownForLibrary(to: exportURL)?.path == exportURL.standardizedFileURL.path)
        let exportedMarkdown = try String(contentsOf: exportURL, encoding: .utf8)
        #expect(exportedMarkdown.contains("Trash Seed"))
        #expect(exportedMarkdown.contains("Body line"))

        try controller.deleteSelectedNoteForLibrary()
        #expect(!FileManager.default.fileExists(atPath: noteURL.path))
        let trashedURL = try #require(store.listTrashedNotes(limit: 10).first?.url)
        #expect(FileManager.default.fileExists(atPath: trashedURL.path))

        let trashButton = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSButton }.first {
            $0.title == "最近删除"
        })
        trashButton.performClick(nil)
        #expect(controller.titleField.stringValue == "Trash Seed")
        #expect(!controller.titleField.isEditable)
        #expect(!controller.editorTextView.isEditable)
        let trashCount = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.first {
            $0.identifier?.rawValue == "LibrarySourceCount-3"
        })
        #expect(trashCount.stringValue == "1")

        let trashMoreMenu = controller.makeMoreActionsMenuForLibrary()
        let trashMenuTitles = trashMoreMenu.items.map(\.title)
        #expect(trashMenuTitles.contains("恢复"))
        #expect(trashMenuTitles.contains("永久删除"))

        _ = try controller.restoreSelectedNoteForLibrary()
        #expect(FileManager.default.fileExists(atPath: noteURL.path))
        #expect(store.listTrashedNotes(limit: 10).isEmpty)
        #expect(controller.titleField.stringValue == "Trash Seed")
        #expect(controller.titleField.isEditable)
        #expect(controller.editorTextView.isEditable)

        try controller.deleteSelectedNoteForLibrary()
        let restoredTrashButton = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSButton }.first {
            $0.title == "最近删除"
        })
        restoredTrashButton.performClick(nil)
        #expect(controller.titleField.stringValue == "Trash Seed")
        try controller.deleteSelectedNoteForLibrary()
        #expect(store.listTrashedNotes(limit: 10).isEmpty)
        #expect(controller.tableView.numberOfRows == 0)
        #expect(controller.noteListEmptyLabel.stringValue == "最近删除为空")
        #expect(!controller.noteListEmptyLabel.isHidden)
    }

    @MainActor
    @Test
    func libraryWindowNoteListKeyboardOpensAndDeletesNotes() throws {
        let suiteName = "mudsnote.library-keyboard-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-keyboard-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let noteURL = try store.saveNewNote(title: "Keyboard Seed", body: "Keyboard body")
        var openedURL: URL?

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { openedURL = $0 },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        _ = try #require(controller.window)
        controller.tableView.keyDown(with: try keyEvent(keyCode: 36, modifiers: [], characters: "\r"))
        #expect(openedURL?.standardizedFileURL.path == noteURL.standardizedFileURL.path)

        controller.tableView.keyDown(with: try keyEvent(keyCode: 51, modifiers: [], characters: "\u{7F}"))
        #expect(!FileManager.default.fileExists(atPath: noteURL.path))
        #expect(store.listTrashedNotes(limit: 10).first?.title == "Keyboard Seed")

        let trashButton = try #require(controller.window?.contentView?.allSubviews.compactMap { $0 as? NSButton }.first {
            $0.title == "最近删除"
        })
        trashButton.performClick(nil)
        #expect(controller.titleField.stringValue == "Keyboard Seed")

        controller.tableView.keyDown(with: try keyEvent(keyCode: 117, modifiers: [], characters: "\u{F728}"))
        #expect(store.listTrashedNotes(limit: 10).isEmpty)
        #expect(controller.tableView.numberOfRows == 0)
    }

    @MainActor
    @Test
    func defaultLaunchOpensLibraryUnlessAnotherSurfaceIsRequested() {
        #expect(AppController.shouldOpenLibraryOnLaunch(arguments: []))
        #expect(AppController.shouldOpenLibraryOnLaunch(arguments: ["--library"]))
        #expect(AppController.shouldOpenLibraryOnLaunch(arguments: ["-psn_0_12345"]))
        #expect(!AppController.shouldOpenLibraryOnLaunch(arguments: ["--quick-capture"]))
        #expect(!AppController.shouldOpenLibraryOnLaunch(arguments: ["--floating-note"]))
        #expect(!AppController.shouldOpenLibraryOnLaunch(arguments: ["--search"]))
        #expect(!AppController.shouldOpenLibraryOnLaunch(arguments: ["--preferences"]))
    }

    @MainActor
    @Test
    func preferencesWindowUsesStandardMacSettingsChrome() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-preferences-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let controller = PreferencesWindowController(
            currentDirectory: root,
            availableDirectories: [root],
            currentOpacity: NoteStore.defaultPanelOpacity,
            currentQuickCaptureHotKey: "option+shift+n",
            currentFloatingHotKey: "option+r",
            currentSaveShortcut: "command+return",
            revealSavedNoteInFinder: true,
            floatingNoteStaysOnTop: true,
            spellCheckingEnabled: true,
            aiEnabled: false,
            aiOllamaBaseURL: "http://localhost:11434",
            aiOllamaModel: "llama3.2",
            onPreviewOpacity: { _ in },
            onResetWindowFrames: {},
            onSave: { _ in }
        )
        defer { controller.close() }

        let window = try #require(controller.window)
        #expect(window.title == "Mudsnote 设置")
        #expect(window.styleMask.contains(NSWindow.StyleMask.titled))
        #expect(!window.styleMask.contains(NSWindow.StyleMask.fullSizeContentView))
        #expect(window.isOpaque)
        #expect(window.backgroundColor == NSColor.windowBackgroundColor)
        #expect(window.alphaValue == 1)
        #expect(window.toolbarStyle == NSWindow.ToolbarStyle.preference)
        #expect(window.toolbar?.selectedItemIdentifier?.rawValue == "mudsnote.settings.general")

        controller.updatePanelOpacity(NoteStore.minimumPanelOpacity)
        #expect(window.alphaValue == 1)
    }

    @MainActor
    @Test
    func editorDisablesSpellCheckingFromPreference() throws {
        let harness = try makeEditorControllerHarness(
            draftID: "quick-capture",
            showsSaveButton: true,
            configureStore: { store in
                store.spellCheckingEnabled = false
            }
        )
        defer { harness.tearDown() }

        #expect(!harness.controller.editorTextView.isContinuousSpellCheckingEnabled)
    }

    @MainActor
    @Test
    func slashSuggestionPopoverUsesCompactMenuSizing() throws {
        let controller = SuggestionPopoverController()
        controller.loadViewIfNeeded()

        controller.updateItems([
            SuggestionItem(title: "Heading 1", subtitle: nil, symbolName: nil),
            SuggestionItem(title: "Heading 2", subtitle: nil, symbolName: nil),
            SuggestionItem(title: "Heading 3", subtitle: nil, symbolName: nil),
            SuggestionItem(title: "To-do List", subtitle: nil, symbolName: nil),
            SuggestionItem(title: "Bulleted List", subtitle: nil, symbolName: nil),
            SuggestionItem(title: "Numbered List", subtitle: nil, symbolName: nil),
            SuggestionItem(title: "Divider", subtitle: nil, symbolName: nil)
        ])

        #expect(controller.preferredContentSize.width < 102)
        #expect(controller.preferredContentSize.width >= 96)
        #expect(controller.preferredContentSize.height == 120)
        #expect(controller.view.layer?.borderWidth == 0)
        #expect(controller.view.layer?.backgroundColor != NSColor.clear.cgColor)

        let scrollView = try #require(controller.view.subviews.compactMap { $0 as? NSScrollView }.first)
        let listView = try #require(scrollView.documentView as? SuggestionListView)
        #expect(listView.frame.width == controller.contentWidth)
        #expect(controller.preferredContentSize.width == controller.contentWidth)
        #expect(!scrollView.hasVerticalScroller)
    }

    @MainActor
    @Test
    func inlineSuggestionPopoverIsHostedAtWindowContentLevel() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let contentView = try #require(controller.window?.contentView)

        #expect(controller.suggestionController.view.superview === contentView)

        controller.editorTextView.string = "/heading"
        controller.editorTextView.setSelectedRange(NSRange(location: 8, length: 0))
        controller.updateInlineSuggestions()

        #expect(controller.suggestionController.view.superview === contentView)
        #expect(!controller.suggestionController.view.isHidden)
        #expect(controller.suggestionController.view.frame.minX >= 4)
        #expect(controller.suggestionController.view.frame.maxX <= contentView.bounds.maxX - 4)

        let tokenStartRect = controller.editorTextView.convert(
            caretRectInWindow(for: controller.editorTextView, at: 0),
            to: contentView
        )
        let caretRect = controller.editorTextView.convert(
            caretRectInWindow(for: controller.editorTextView),
            to: contentView
        )
        let expectedX = min(
            max(tokenStartRect.minX, 4),
            max(contentView.bounds.width - controller.suggestionController.view.frame.width - 4, 4)
        )
        #expect(abs(controller.suggestionController.view.frame.minX - expectedX) < 1)
        #expect(controller.suggestionController.view.frame.minX < caretRect.minX)
    }

    @MainActor
    @Test
    func activeToolbarButtonUsesWhiteFillHighlight() {
        let button = HoverToolbarButton(frame: NSRect(x: 0, y: 0, width: 30, height: 26))
        button.isActive = true

        #expect(button.layer?.borderWidth == 0)
        #expect(button.layer?.backgroundColor != NSColor.clear.cgColor)
        #expect(button.contentTintColor == panelPrimaryTextColor())
    }

    @MainActor
    @Test
    func floatingNoteUsesHeaderChromeAndEmptyBodyPlaceholder() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller

        #expect(controller.floatingNotePlaceholderLabel?.isHidden == false)
        #expect(controller.window?.contentView?.allSubviews.contains { $0 is DragHandleView } == false)
        #expect(controller.floatingNoteTitlebarChromeViews.allSatisfy { !($0 is NSButton) })
        #expect(controller.floatingNoteTitlebarChromeViews.count == 1)
        #expect(controller.floatingNoteTitlebarChromeViews.allSatisfy { $0.alphaValue == 1 })
        let headerStack = try #require(controller.floatingNoteTitlebarChromeViews.first as? NSStackView)
        #expect(headerStack.arrangedSubviews.count == 1)
        #expect(controller.floatingNoteBrowseButton?.toolTip == "浏览笔记")
        #expect(controller.floatingNoteBrowseButton?.performsActionOnMouseDown == true)

        controller.setFloatingNoteTitlebarChromeVisible(true)

        #expect(controller.floatingNoteTitlebarChromeViews.allSatisfy { $0.alphaValue == 1 })

        controller.editorTextView.string = "qqq\nbody"
        controller.userDidEdit()

        #expect(controller.floatingNotePlaceholderLabel?.isHidden == true)
    }

    @MainActor
    @Test
    func floatingNoteCanSwitchToExistingNoteAndSaveBackToIt() throws {
        var savedURL: URL?
        let harness = try makeEditorControllerHarness(
            draftID: "floating-note",
            showsSaveButton: false,
            onSave: { savedURL = $0 }
        )
        defer { harness.tearDown() }

        try harness.store.ensureNotesDirectory()
        let noteURL = try harness.store.saveNewNote(title: "Existing", body: "Original body", in: harness.store.notesDirectory)

        harness.controller.loadFloatingNote(at: noteURL)

        #expect(harness.controller.activeFloatingNoteURL == noteURL)
        #expect(harness.controller.currentDocument().title == "Existing")
        #expect(harness.controller.currentDocument().body == "Original body")

        let updated = MarkdownRichTextCodec.render(markdown: "# Existing\n\nUpdated body", theme: harness.controller.theme)
        harness.controller.editorTextView.textStorage?.setAttributedString(updated)
        harness.controller.savePressed()

        let loaded = try harness.store.loadNote(at: noteURL)
        #expect(loaded.title == "Existing")
        #expect(loaded.body == "Updated body")
        #expect(savedURL == noteURL)
    }

    @MainActor
    @Test
    func floatingBrowseButtonOpensBrowserPanel() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller

        controller.showWindowAndFocus()
        controller.floatingBrowseNotesPressed(controller.floatingNoteBrowseButton)

        let browser = try #require(controller.floatingNoteBrowserController)
        #expect(browser.window?.isVisible == true)
        #expect(browser.window?.canBecomeKey == true)
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

    private struct EditorControllerHarness {
        let root: URL
        let suiteName: String
        let defaults: UserDefaults
        let store: NoteStore
        let controller: EditorWindowController

        @MainActor
        func tearDown() {
            controller.close()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func makeEditorControllerHarness(
        draftID: String,
        showsSaveButton: Bool,
        saveShortcut: HotKeySpec? = nil,
        configureStore: (NoteStore) -> Void = { _ in },
        onSave: @escaping (URL) -> Void = { _ in }
    ) throws -> EditorControllerHarness {
        let suiteName = "mudsnote.app-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-app-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        configureStore(store)

        let controller = EditorWindowController(
            noteStore: store,
            panelOpacity: NoteStore.defaultPanelOpacity,
            fileURL: nil,
            draftIDOverride: draftID,
            saveShortcut: saveShortcut,
            showsSaveButton: showsSaveButton,
            onSave: onSave,
            onClose: {},
            onRequestSearch: {},
            onRequestPreferences: {}
        )

        return EditorControllerHarness(root: root, suiteName: suiteName, defaults: defaults, store: store, controller: controller)
    }

    private func keyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        characters: String,
        windowNumber: Int = 0
    ) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters.lowercased(),
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    private func paragraphKind(after event: NSEvent, controller: EditorWindowController) throws -> MarkdownParagraphKind {
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(
            string: "item",
            attributes: controller.theme.baseAttributes(for: .paragraph)
        ))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 4))
        #expect(controller.handleShortcutEvent(event))

        let storage = try #require(controller.editorTextView.textStorage)
        return MarkdownRichTextCodec.paragraphKind(at: NSRange(location: 0, length: storage.length), in: storage)
    }
}

private extension MarkdownParagraphKind {
    var headingLevel: Int? {
        if case .heading(let level) = self { return level }
        return nil
    }

    var isOrderedList: Bool {
        if case .ordered = self { return true }
        return false
    }

    var isBulletList: Bool {
        if case .bullet = self { return true }
        return false
    }

    var isChecklist: Bool {
        if case .checklist = self { return true }
        return false
    }
}
