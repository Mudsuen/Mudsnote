import AppKit
import Carbon.HIToolbox
import CoreServices
import ImageIO
@_spi(Testing) import MudsnoteCore
import Testing
@testable import Mudsnote

extension MarkdownRichEditorTests {
    @MainActor
    @Test
    func floatingEditorExposesSelectionFormattingToolbar() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "Selected text",
            theme: controller.theme
        ))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 8))

        let menu = try #require(controller.editorTextView.selectionMenuProvider?())
        #expect(menu.items.map(\.title) == ["转换为", "加粗", "斜体", "高亮", "添加链接"])
        #expect(menu.items.first { $0.title == "下划线" } == nil)
        #expect(menu.items.first { $0.title == "删除线" } == nil)
        #expect(menu.items.first?.submenu?.items.map(\.title) == [
            "正文", "标题", "副标题", "小标题", "项目符号列表", "编号列表", "待办列表"
        ])

        let linkItem = try #require(menu.items.first { $0.title == "添加链接" })
        #expect(NSApp.sendAction(try #require(linkItem.action), to: linkItem.target, from: linkItem))
        let linkEditor = try #require(controller.linkEditorSheetController)
        linkEditor.destinationField.stringValue = "https://muds.top"
        linkEditor.submitForTesting()
        #expect(MarkdownRichTextCodec.serialize(
            controller.editorTextView.attributedString(),
            theme: controller.theme
        ) == "[Selected](https://muds.top) text")
    }

    @Test
    func quickCaptureDocumentStateDerivesTitleWithoutRemovingBody() {
        let state = QuickCaptureDocumentState(
            title: "",
            bodyMarkdown: "\n\n  这是第一句。第二句仍在正文\n- [ ] Finish report\n#ops\n"
        )

        #expect(state.normalizedTitle == "这是第一句。")
        #expect(state.normalizedBody == "这是第一句。第二句仍在正文\n- [ ] Finish report\n#ops")
        #expect(state.document.title == "这是第一句。")
        #expect(state.document.body == "这是第一句。第二句仍在正文\n- [ ] Finish report\n#ops")
        #expect(state.document.tags.isEmpty)
        #expect(state.hasMeaningfulContent == true)
    }

    @Test
    func quickCaptureDoesNotTreatBodyHashtagsAsMetadataTags() {
        #expect(
            QuickCaptureDocumentState.extractedInlineTags(
                from: "Body #area/topic #中文/层级 #trailing/"
            ).isEmpty
        )

        let rendered = MarkdownRichTextCodec.renderLine("Body #area/topic", theme: theme)
        #expect(MarkdownRichTextCodec.serialize(rendered, theme: theme) == "Body #area/topic")
    }

    @Test
    func quickCaptureTitleDerivationHandlesMarkdownPunctuationAndLength() {
        #expect(QuickCaptureDocumentState.derivedTitle(from: "  \n# Plan v2? Keep this") == "Plan v2?")
        #expect(QuickCaptureDocumentState.derivedTitle(from: "\n「中文标题！」后续") == "「中文标题！」")
        #expect(QuickCaptureDocumentState.derivedTitle(from: "\n\n") == "")

        let longSentence = String(repeating: "长", count: 200)
        #expect(QuickCaptureDocumentState.derivedTitle(from: longSentence).count == 80)
    }

    @Test
    func quickCaptureLegacyTitleAndBodyMergeWithoutLossOrDuplication() {
        #expect(
            QuickCaptureDocumentState.unifiedMarkdown(
                legacyTitle: "Legacy title",
                bodyMarkdown: "Body line\nSecond line"
            ) == "Legacy title\n\nBody line\nSecond line"
        )
        #expect(
            QuickCaptureDocumentState.unifiedMarkdown(
                legacyTitle: "Already present.",
                bodyMarkdown: "Already present. More text\nSecond line"
            ) == "Already present. More text\nSecond line"
        )
        #expect(
            QuickCaptureDocumentState.unifiedMarkdown(
                legacyTitle: "",
                bodyMarkdown: "Body only"
            ) == "Body only"
        )
    }

    @MainActor
    @Test
    func quickCaptureTagSuggestionsLoadWithoutBlockingEditorInput() async throws {
        let harness = try makeEditorControllerHarness(
            draftID: "quick-capture",
            showsSaveButton: true,
            configureStore: { store in
                store.configurePreferredDirectories([store.notesDirectory], defaultDirectory: store.notesDirectory)
            }
        )
        defer { harness.tearDown() }
        _ = try harness.store.saveNewNote(title: "Tagged", body: "Saved note", tags: ["alpha"])

        let controller = harness.controller
        controller.editorTextView.string = "#al"
        controller.editorTextView.setSelectedRange(NSRange(location: 3, length: 0))
        controller.updateInlineSuggestions()

        #expect(controller.knownTagsForSuggestions == nil || controller.knownTagsForSuggestions?.contains("alpha") == true)
        try await Task.sleep(for: .milliseconds(100))

        #expect(controller.knownTagsForSuggestions?.contains("alpha") == true)
        guard case .tags(let query, _, let items) = controller.inlineSuggestionContext else {
            Issue.record("Expected tag suggestions after the background tag index load")
            return
        }
        #expect(query == "al")
        #expect(items == ["al", "alpha"])
    }

    @MainActor
    @Test
    func quickCaptureAtMentionRanksNotesAndInsertsRelativeMarkdownLink() async throws {
        let harness = try makeEditorControllerHarness(
            draftID: "quick-capture",
            showsSaveButton: true
        )
        defer { harness.tearDown() }
        let target = try harness.store.saveNewNote(
            title: "Project Atlas",
            body: "Target"
        )
        _ = try harness.store.saveNewNote(
            title: "Weekly Notes",
            body: "Project Atlas is mentioned in the body"
        )

        let controller = harness.controller
        controller.editorTextView.string = "@Project Atlas"
        controller.editorTextView.setSelectedRange(NSRange(location: 14, length: 0))
        controller.updateInlineSuggestions()
        try await Task.sleep(for: .milliseconds(100))

        guard case .notes(let query, _, let items) = controller.inlineSuggestionContext else {
            Issue.record("Expected note suggestions after typing @")
            return
        }
        #expect(query == "Project Atlas")
        #expect(items.first?.url == target)
        controller.acceptInlineSuggestion(at: 0)
        let markdown = MarkdownRichTextCodec.serialize(
            controller.editorTextView.attributedString(),
            theme: controller.theme
        )
        #expect(markdown.hasPrefix("[Project Atlas]("))
        #expect(!markdown.contains("@Project Atlas"))
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
    func floatingToolbarButtonAppliesInlineTypingFormat() throws {
        let harness = try makeEditorControllerHarness(draftID: "standard-editor", showsSaveButton: false)
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
        let harness = try makeEditorControllerHarness(draftID: "standard-editor", showsSaveButton: false)
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
    func floatingDraftAutosaveDoesNotReplaceStatusText() throws {
        let harness = try makeEditorControllerHarness(draftID: "quiet-autosave-status", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let statusBeforeEdit = controller.statusLabel.stringValue

        controller.editorTextView.string = "Quiet draft"
        controller.markDocumentDirty()
        #expect(controller.statusLabel.stringValue == statusBeforeEdit)

        try controller.persistDraft(force: true)
        #expect(controller.statusLabel.stringValue == statusBeforeEdit)
        #expect(harness.store.loadDraft(id: "quiet-autosave-status")?.title == "Quiet draft")
    }

    @MainActor
    @Test
    func floatingDraftAutosaveWritesOffMainAndClearsMatchingRevision() async throws {
        let recorder = DraftPersistenceRecorder()
        let harness = try makeEditorControllerHarness(
            draftID: "background-draft-autosave",
            showsSaveButton: false,
            saveDraftSnapshot: recorder.record
        )
        defer { harness.tearDown() }
        let controller = harness.controller

        controller.editorTextView.string = "Background draft"
        controller.markDocumentDirty()
        await controller.flushPendingDraftAutosaveForTesting()

        let recorded = recorder.snapshot()
        #expect(recorded.savedTitles == ["Background draft"])
        #expect(!recorded.observedMainThread)
        #expect(!controller.isDirty)
    }

    @MainActor
    @Test
    func floatingReturnInsertsNewlineAndAutosavesWithoutCrashing() async throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        controller.editorTextView.string = "Before"
        controller.editorTextView.setSelectedRange(NSRange(location: 6, length: 0))

        controller.editorTextView.keyDown(with: try keyEvent(
            keyCode: UInt16(kVK_Return),
            modifiers: [],
            characters: "\r",
            windowNumber: controller.window?.windowNumber ?? 0
        ))
        await Task.yield()
        await controller.flushPendingDraftAutosaveForTesting()

        #expect(controller.editorTextView.string == "Before\n")
        #expect(harness.store.loadDraft(id: controller.currentDraftID)?.title == "Before")
    }

    @MainActor
    @Test
    func floatingSlashSuggestionsStayTextOnlyAndKeepAnEmptyStateVisible() async throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let recorder = SlashCommandInputSourceSessionRecorder()
        controller.slashCommandInputSourceSession = recorder
        controller.window?.makeFirstResponder(controller.editorTextView)

        controller.editorTextView.string = "/"
        controller.editorTextView.setSelectedRange(NSRange(location: 1, length: 0))
        controller.updateInlineSuggestions()
        try await Task.sleep(for: .milliseconds(10))

        let scrollView = try #require(
            controller.suggestionController.view.subviews.compactMap { $0 as? NSScrollView }.first
        )
        let listView = try #require(scrollView.documentView as? SuggestionListView)
        #expect(listView.items.map(\.title) == SlashCommand.allCases.map(\.title))
        #expect(listView.items.allSatisfy { $0.symbolName == nil })
        #expect(recorder.beginCalls.last?.hasMarkedText == false)
        #expect(recorder.beginCalls.last?.editorIsFirstResponder == true)

        controller.editorTextView.string = "/does-not-exist"
        controller.editorTextView.setSelectedRange(NSRange(location: 15, length: 0))
        controller.updateInlineSuggestions()
        try await Task.sleep(for: .milliseconds(10))

        guard case .slash(_, _, let commands) = controller.inlineSuggestionContext else {
            Issue.record("Expected a slash context with no command matches")
            return
        }
        #expect(commands.isEmpty)
        #expect(!controller.suggestionController.view.isHidden)
        #expect(listView.items == [
            SuggestionItem(
                title: "无匹配命令",
                subtitle: nil,
                symbolName: nil,
                isSelectable: false
            )
        ])
    }

    @MainActor
    @Test
    func quickCaptureFooterRemovesTagActionAndAlignsRemainingControls() throws {
        let harness = try makeEditorControllerHarness(
            draftID: "quick-capture",
            showsSaveButton: true,
            configureStore: { store in
                let inbox = store.notesDirectory.appendingPathComponent("000-Inbox", isDirectory: true)
                let projects = store.notesDirectory.appendingPathComponent("100_Projects", isDirectory: true)
                let areas = store.notesDirectory.appendingPathComponent("200_Areas", isDirectory: true)
                try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
                try? FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
                try? FileManager.default.createDirectory(at: areas, withIntermediateDirectories: true)
                store.configurePreferredDirectories([store.notesDirectory], defaultDirectory: store.notesDirectory)
            }
        )
        defer { harness.tearDown() }

        let directoryButton = try #require(harness.controller.quickCaptureDirectoryButton)
        let saveButton = try #require(harness.controller.saveButton as? HoverToolbarButton)
        let cancelButton = try #require(harness.controller.cancelButton as? HoverToolbarButton)

        #expect(harness.controller.selectedDirectoryURL == harness.store.notesDirectory)
        #expect(harness.controller.quickCaptureDestinationTitle() == "Notes")
        let directoryMenu = harness.controller.makeQuickCaptureDirectoryMenu()
        #expect(directoryMenu.items.compactMap { ($0.representedObject as? URL)?.lastPathComponent } == [
            "000-Inbox",
            "200_Areas",
            "100_Projects"
        ])
        #expect(directoryMenu.items.map(\.title) == ["Inbox", "Areas", "Projects"])
        #expect(saveButton.title.isEmpty)
        #expect(saveButton.toolTip == "保存")
        #expect(saveButton.preferredSize == NSSize(width: 28, height: 28))
        #expect(cancelButton.title.isEmpty)
        #expect(cancelButton.toolTip == "取消")
        #expect(cancelButton.preferredSize == NSSize(width: 28, height: 28))
        let tagButtons = harness.controller.window?.contentView?.allSubviews
            .compactMap { $0 as? NSButton }
            .filter { $0.accessibilityIdentifier() == "QuickCapture标签Button" } ?? []
        #expect(tagButtons.isEmpty)
        #expect(directoryButton.frame.midY == cancelButton.frame.midY)
        #expect(cancelButton.frame.midY == saveButton.frame.midY)
        #expect(saveButton.layer?.backgroundColor == NSColor.clear.cgColor)
        #expect(cancelButton.layer?.backgroundColor == NSColor.clear.cgColor)

        let saveRestingBackground = saveButton.layer?.backgroundColor
        saveButton.highlight(true)
        #expect(saveButton.layer?.backgroundColor == saveRestingBackground)
        #expect(saveButton.alphaValue < 1)
        saveButton.highlight(false)
        #expect(saveButton.alphaValue == 1)
    }

    @MainActor
    @Test
    func quickCaptureUsesOneEditorAndRestoresLegacyDraftWithoutDuplication() throws {
        let harness = try makeEditorControllerHarness(
            draftID: "quick-capture",
            showsSaveButton: true,
            configureStore: { store in
                store.configurePreferredDirectories([store.notesDirectory], defaultDirectory: store.notesDirectory)
                try? store.saveDraft(DraftSnapshot(
                    id: "quick-capture",
                    sourcePath: nil,
                    selectedDirectoryPath: store.notesDirectory.path,
                    title: "Recovered title.",
                    body: "Recovered title. Body remains\nSecond line",
                    updatedAt: Date()
                ))
            }
        )
        defer { harness.tearDown() }
        let controller = harness.controller

        let separateTitleEditors = controller.window?.contentView?.allSubviews
            .compactMap { $0 as? FocusableTitleTextView } ?? []
        #expect(separateTitleEditors.isEmpty)
        #expect(controller.editorTextView.string == "Recovered title. Body remains\nSecond line")
        #expect(controller.currentDocument().title == "Recovered title.")
        #expect(controller.currentDocument().body == "Recovered title. Body remains\nSecond line")

        controller.showWindowAndFocus()
        #expect(controller.window?.firstResponder === controller.editorTextView)
    }

    @MainActor
    @Test
    func quickCaptureSaveUsesFirstSentenceAsTitleAndPreservesFullBody() throws {
        var savedURL: URL?
        let harness = try makeEditorControllerHarness(
            draftID: "quick-capture",
            showsSaveButton: true,
            configureStore: { store in
                store.configurePreferredDirectories([store.notesDirectory], defaultDirectory: store.notesDirectory)
            },
            onSave: { savedURL = $0 }
        )
        defer { harness.tearDown() }
        let controller = harness.controller
        controller.editorTextView.string = "\nProject / Alpha? Keep this sentence.\nSecond line"

        controller.savePressed()

        let url = try #require(savedURL)
        let saved = try harness.store.loadNote(at: url)
        #expect(saved.title == "Project / Alpha?")
        #expect(saved.body == "Project / Alpha? Keep this sentence.\nSecond line")
        #expect(!url.lastPathComponent.contains("/"))
        #expect(url.deletingLastPathComponent() == harness.store.notesDirectory)
    }

    @MainActor
    @Test
    func floatingNoteUsesHeaderChromeAndEmptyBodyPlaceholder() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller

        #expect(controller.floatingNotePlaceholderLabel?.isHidden == false)
        #expect(controller.toolbarButtonsByAction.isEmpty)
        #expect(controller.toolbarButtons.isEmpty)
        #expect(controller.toolbarButtonVisualHeight < controller.toolbarButtonHeight)
        #expect(controller.window?.contentView?.allSubviews.contains { $0 is DragHandleView } == false)
        #expect(controller.floatingNoteTitlebarChromeViews.count == 1)
        #expect(controller.floatingNoteTitlebarChromeViews.allSatisfy { $0.alphaValue == 1 })
        #expect(controller.floatingNoteBrowseButton?.toolTip == "管理悬浮笔记")
        #expect(controller.shellContentView?.subviews.contains { $0 is NSBox } == false)
        let managerButton = try #require(controller.floatingNoteBrowseButton as? HoverToolbarButton)
        #expect(managerButton.target === controller)
        #expect(managerButton.action == #selector(EditorWindowController.floatingBrowseNotesPressed(_:)))
        #expect(managerButton.superview === controller.window?.contentView)
        #expect(managerButton.accessibilityIdentifier() == "FloatingNoteManagerButton")
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let managerCenter = managerButton.convert(
            NSPoint(x: managerButton.bounds.midX, y: managerButton.bounds.midY),
            to: controller.window?.contentView
        )
        #expect(controller.window?.contentView?.hitTest(managerCenter) === managerButton)

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
    func floatingBrowseButtonDispatchesCompleteClicksToBrowserPanel() async throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller

        controller.showWindowAndFocus()
        controller.window?.setContentSize(NSSize(width: 300, height: 314))
        let managerButton = try #require(controller.floatingNoteBrowseButton)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        func dispatchClick(expectedPresentationCount: Int) async throws {
            let location = managerButton.convert(
                NSPoint(x: managerButton.bounds.midX, y: managerButton.bounds.midY),
                to: nil
            )
            let windowNumber = controller.window?.windowNumber ?? 0
            let mouseDown = try #require(NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: location,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            ))
            let mouseUp = try #require(NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: location,
                modifierFlags: [],
                timestamp: 0.01,
                windowNumber: windowNumber,
                context: nil,
                eventNumber: 2,
                clickCount: 1,
                pressure: 0
            ))
            NSApp.postEvent(mouseUp, atStart: true)
            controller.window?.sendEvent(mouseDown)

            let deadline = Date().addingTimeInterval(1)
            while ((controller.floatingNoteBrowserController?.presentationCount ?? 0) < expectedPresentationCount
                   || controller.floatingNoteBrowserController?.window?.isKeyWindow != true),
                  Date() < deadline {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }

        try await dispatchClick(expectedPresentationCount: 1)

        let browser = try #require(controller.floatingNoteBrowserController)
        #expect(browser.presentationCount == 1)
        #expect(browser.window?.isVisible == true)
        #expect(browser.window?.isKeyWindow == true)
        #expect(browser.window?.parent === controller.window)
        if let browserFrame = browser.window?.frame,
           let parentFrame = controller.window?.frame,
           let visibleFrame = controller.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            #expect(browserFrame.intersects(visibleFrame))
            #expect(browserFrame.minX >= parentFrame.minX)
            #expect(browserFrame.maxX <= parentFrame.maxX)
            #expect(browserFrame.minY >= parentFrame.minY)
            #expect(browserFrame.maxY <= parentFrame.maxY)
        }

        browser.window?.close()
        controller.window?.resignKey()
        #expect(controller.window?.isKeyWindow == false)
        try await dispatchClick(expectedPresentationCount: 2)
        #expect(browser.presentationCount == 2)
        #expect(browser.window?.isVisible == true)
        #expect(browser.window?.parent === controller.window)
        #expect(browser.window?.frame.width == FloatingNoteBrowserController.compactPanelWidth)
        #expect(browser.window?.frame.height == 116)
        #expect(browser.window?.contentView?.allSubviews.contains {
            ($0 as? NSButton)?.title == "关闭窗口"
        } == false)
        browser.window?.close()
    }

    @MainActor
    @Test
    func floatingWindowManagerShowsAllOpenWindowsWithIndividualCloseActions() throws {
        var openWindows: [FloatingNoteWindowDescriptor] = []
        var closedWindowID: UUID?
        var addedURL: URL?
        var createCount = 0
        let harness = try makeEditorControllerHarness(
            draftID: "floating-note",
            showsSaveButton: false,
            floatingNoteWindows: { openWindows },
            onRequestOpenFloatingNote: { addedURL = $0 },
            onRequestCloseFloatingNote: { closedWindowID = $0 },
            onRequestCreateFloatingNote: { createCount += 1 }
        )
        defer { harness.tearDown() }

        try harness.store.ensureNotesDirectory()
        let firstURL = try harness.store.saveNewNote(title: "First", body: "One", in: harness.store.notesDirectory)
        let secondURL = try harness.store.saveNewNote(title: "Second", body: "Two", in: harness.store.notesDirectory)
        let firstID = UUID()
        openWindows = [
            FloatingNoteWindowDescriptor(id: firstID, url: firstURL, title: "First", subtitle: "One"),
            FloatingNoteWindowDescriptor(id: UUID(), url: secondURL, title: "Second", subtitle: "Two")
        ]

        harness.controller.showWindowAndFocus()
        harness.controller.showFloatingNoteBrowser(relativeTo: harness.controller.floatingNoteBrowseButton)
        let browser = try #require(harness.controller.floatingNoteBrowserController)

        #expect(browser.displayedURLs.map(\.standardizedFileURL) == [firstURL, secondURL].map(\.standardizedFileURL))
        #expect(browser.displayedOpenStates == [true, true])
        #expect(browser.window?.frame.width == 300)
        #expect(browser.window?.frame.height == 156)
        #expect(browser.resultRowHeight == 36)
        #expect(browser.usesVerticalScroller == false)
        #expect(browser.verticalScrollElasticity == .none)
        browser.window?.contentView?.layoutSubtreeIfNeeded()
        let firstCell = try #require(browser.resultCell(at: 0))
        firstCell.layoutSubtreeIfNeeded()
        #expect(firstCell.frame.width > 270)
        let titleFrame = firstCell.convert(firstCell.titleLabel.frame, from: firstCell.titleLabel.superview)
        #expect(titleFrame.minX >= 10)
        #expect(abs(firstCell.titleLabel.frame.midY - firstCell.snippetLabel.frame.midY) < 1)
        #expect(firstCell.actionButton.frame.width == 24)
        #expect(firstCell.layer?.cornerRadius == 9)
        let firstCloseButton = try #require(browser.rowActionButton(at: 0))
        #expect(firstCloseButton.toolTip?.hasPrefix("关闭") == true)

        openWindows += (0..<4).map {
            FloatingNoteWindowDescriptor(id: UUID(), url: nil, title: "Window \($0)", subtitle: "Unsaved")
        }
        browser.refresh()
        #expect(browser.usesVerticalScroller == true)
        #expect(browser.verticalScrollElasticity == .automatic)

        openWindows.removeLast(4)
        browser.refresh()
        #expect(browser.usesVerticalScroller == false)
        #expect(browser.verticalScrollElasticity == .none)
        #expect(browser.verticalScrollOffset == 0)

        let action = try #require(firstCloseButton.action)
        _ = NSApp.sendAction(action, to: firstCloseButton.target, from: firstCloseButton)
        #expect(closedWindowID == firstID)
        #expect(addedURL == nil)
        #expect(browser.newWindowButton.toolTip == "新建悬浮窗口")
        browser.newWindowButton.performClick(nil)
        #expect(createCount == 1)
        #expect(browser.window?.isVisible == false)
        browser.window?.close()
    }

    @MainActor
    @Test
    func floatingWindowManagerSupportsKeyboardNavigationAndPreservesSelection() throws {
        var openWindows: [FloatingNoteWindowDescriptor] = []
        var activatedWindowID: UUID?
        let harness = try makeEditorControllerHarness(
            draftID: "floating-note",
            showsSaveButton: false,
            floatingNoteWindows: { openWindows },
            onRequestActivateFloatingNote: { activatedWindowID = $0 }
        )
        defer { harness.tearDown() }

        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        openWindows = [
            FloatingNoteWindowDescriptor(id: firstID, url: nil, title: "First", subtitle: "One"),
            FloatingNoteWindowDescriptor(id: secondID, url: nil, title: "Second", subtitle: "Two"),
            FloatingNoteWindowDescriptor(id: thirdID, url: nil, title: "Third", subtitle: "Three")
        ]

        harness.controller.showWindowAndFocus()
        harness.controller.showFloatingNoteBrowser(relativeTo: harness.controller.floatingNoteBrowseButton)
        let browser = try #require(harness.controller.floatingNoteBrowserController)
        let fieldEditor = NSTextView()

        #expect(browser.selectedResultRow == 0)
        browser.window?.contentView?.layoutSubtreeIfNeeded()
        #expect(browser.resultCell(at: 0)?.isSelectedForPresentation == true)
        #expect(browser.control(
            browser.searchField,
            textView: fieldEditor,
            doCommandBy: #selector(NSResponder.moveDown(_:))
        ))
        #expect(browser.selectedResultRow == 1)
        #expect(browser.resultCell(at: 1)?.isSelectedForPresentation == true)

        #expect(browser.control(
            browser.searchField,
            textView: fieldEditor,
            doCommandBy: #selector(NSResponder.moveDown(_:))
        ))
        #expect(browser.control(
            browser.searchField,
            textView: fieldEditor,
            doCommandBy: #selector(NSResponder.moveDown(_:))
        ))
        #expect(browser.selectedResultRow == 2)
        #expect(browser.control(
            browser.searchField,
            textView: fieldEditor,
            doCommandBy: #selector(NSResponder.moveUp(_:))
        ))
        #expect(browser.selectedResultRow == 1)

        openWindows = [
            FloatingNoteWindowDescriptor(id: thirdID, url: nil, title: "Third", subtitle: "Three"),
            FloatingNoteWindowDescriptor(id: firstID, url: nil, title: "First", subtitle: "One"),
            FloatingNoteWindowDescriptor(id: secondID, url: nil, title: "Second", subtitle: "Two")
        ]
        browser.refresh()
        #expect(browser.selectedResultRow == 2)

        #expect(browser.control(
            browser.searchField,
            textView: fieldEditor,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))
        #expect(activatedWindowID == secondID)
        #expect(browser.window?.isVisible == false)

        harness.controller.showFloatingNoteBrowser(relativeTo: harness.controller.floatingNoteBrowseButton)
        #expect(browser.window?.isVisible == true)
        #expect(browser.control(
            browser.searchField,
            textView: fieldEditor,
            doCommandBy: #selector(NSResponder.cancelOperation(_:))
        ))
        #expect(browser.window?.isVisible == false)
    }

    @MainActor
    @Test
    func floatingWindowManagerBoundsSearchCandidates() async throws {
        let harness = try makeEditorControllerHarness(
            draftID: "floating-note",
            showsSaveButton: false
        )
        defer { harness.tearDown() }

        try harness.store.ensureNotesDirectory()
        for index in 0..<(FloatingNoteBrowserController.maximumSearchResults + 5) {
            _ = try harness.store.saveNewNote(
                title: "Needle \(index)",
                body: "Bounded floating search result",
                in: harness.store.notesDirectory
            )
        }

        harness.controller.showWindowAndFocus()
        harness.controller.showFloatingNoteBrowser(relativeTo: harness.controller.floatingNoteBrowseButton)
        let browser = try #require(harness.controller.floatingNoteBrowserController)
        browser.searchField.stringValue = "Needle"
        browser.controlTextDidChange(Notification(
            name: NSControl.textDidChangeNotification,
            object: browser.searchField
        ))
        await browser.waitForSearchForTesting()

        #expect(browser.displayedURLs.count == FloatingNoteBrowserController.maximumSearchResults)
        #expect(browser.selectedResultRow == 0)
        browser.window?.close()
    }

    @MainActor
    @Test
    func floatingNotesDefaultToConfiguredFolderAndHighlightDirectly() throws {
        let harness = try makeEditorControllerHarness(
            draftID: "floating-note",
            showsSaveButton: false,
            configureStore: { store in
                let inbox = store.notesDirectory.appendingPathComponent("000-Inbox", isDirectory: true)
                try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            }
        )
        defer { harness.tearDown() }

        let expectedInbox = harness.store.notesDirectory.appendingPathComponent("000-Inbox", isDirectory: true)
        #expect(harness.store.preferredInboxDirectory == expectedInbox.standardizedFileURL)
        // A new floating note defaults to the configured default folder, not
        // the auto-detected inbox.
        #expect(harness.controller.selectedDirectoryURL == harness.store.notesDirectory)

        let controller = harness.controller
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(
            string: "highlight me",
            attributes: controller.theme.baseAttributes(for: .paragraph)
        ))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 9))
        let menu = try #require(controller.makeSelectionFormattingMenu())
        let highlight = try #require(menu.items.first { $0.title == "高亮" })
        #expect(NSApp.sendAction(try #require(highlight.action), to: highlight.target, from: highlight))
        #expect(MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme) == "<mark>highlight</mark> me")
    }

    @Test
    func floatingSelectionPanelCentersHorizontallyOnPointerAndPreservesSelectionY() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let panelSize = NSSize(width: 240, height: 40)

        #expect(MarkdownTextView.selectionFormattingPanelOrigin(
            centeredAtPointerX: 400,
            verticalOrigin: 182,
            panelSize: panelSize,
            visibleFrame: visibleFrame
        ) == NSPoint(x: 280, y: 182))
        #expect(MarkdownTextView.selectionFormattingPanelOrigin(
            centeredAtPointerX: 10,
            verticalOrigin: -24,
            panelSize: panelSize,
            visibleFrame: visibleFrame
        ) == NSPoint(x: 0, y: -24))
    }

    @Test
    func floatingWindowsPreferASeparateOnScreenFrame() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let first = NSRect(x: 514, y: 514, width: 412, height: 314)
        let second = nonOverlappingPanelFrame(first, occupiedFrames: [first], visibleFrames: [screen])

        #expect(screen.contains(second))
        #expect(!first.intersects(second))
    }

    @MainActor
    @Test
    func floatingEditorQuickLooksSelectedFileAttachment() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let notesDirectory = harness.store.notesDirectory
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        let noteURL = notesDirectory.appendingPathComponent("Attachment Note.md")
        let attachmentURL = notesDirectory.appendingPathComponent("preview.pdf")
        try Data("PDF preview".utf8).write(to: attachmentURL)

        let attributed = MarkdownRichTextCodec.render(
            markdown: "[Preview](preview.pdf)",
            theme: controller.theme,
            baseURL: noteURL
        )
        controller.editorTextView.textStorage?.setAttributedString(attributed)
        var attachmentRange: NSRange?
        attributed.enumerateAttribute(
            .qmAttachmentFilePath,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, range, _ in
            if value as? String == attachmentURL.path {
                attachmentRange = range
            }
        }

        controller.editorTextView.setSelectedRange(try #require(attachmentRange))
        let spaceEvent = try keyEvent(keyCode: UInt16(kVK_Space), modifiers: [], characters: " ")
        #expect(controller.markdownTextView(controller.editorTextView, handleKeyDown: spaceEvent))
        #expect(controller.attachmentQuickLookController.previewedURL == attachmentURL.standardizedFileURL)

        let menu = NSMenu()
        #expect(controller.configureAttachmentContextMenu(
            menu,
            forAttachmentPath: attachmentURL.path,
            markdown: "[Preview](preview.pdf)"
        ))
        #expect(menu.items.first?.title == "快速查看")
        #expect(menu.items.first?.keyEquivalent == " ")
        controller.attachmentQuickLookController.dismiss()
    }
}
