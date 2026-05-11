import AppKit
import Carbon.HIToolbox
import MudsnoteCore
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
            onPreviewOpacity: { _ in },
            onResetWindowFrames: {},
            onSave: { _, _, _, _, _, _ in }
        )
        defer { controller.close() }

        let window = try #require(controller.window)
        #expect(window.title == "Mudsnote Settings")
        #expect(window.styleMask.contains(.titled))
        #expect(!window.styleMask.contains(.fullSizeContentView))
        #expect(window.isOpaque)
        #expect(window.backgroundColor == .windowBackgroundColor)
        #expect(window.alphaValue == 1)
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

        return EditorControllerHarness(root: root, suiteName: suiteName, defaults: defaults, controller: controller)
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
