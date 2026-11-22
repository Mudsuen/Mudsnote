import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import Mudsnote
@testable import MudsnoteCore

@MainActor
@Suite(.serialized)
struct AuditOptimizationTests {
    private func makeStore() throws -> (NoteStore, URL, String, UserDefaults) {
        let suiteName = "mudsnote.audit-optimization.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-audit-opt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        try store.ensureNotesDirectory()
        return (store, root, suiteName, defaults)
    }

    private func cleanup(root: URL, suiteName: String, defaults: UserDefaults) {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    private func makeTheme() -> MarkdownEditorTheme {
        MarkdownEditorTheme(
            textColor: .labelColor,
            mutedTextColor: .secondaryLabelColor,
            accentColor: .controlAccentColor,
            bodyFont: .systemFont(ofSize: 14, weight: .regular),
            boldFont: .systemFont(ofSize: 14, weight: .bold),
            italicFont: NSFontManager.shared.convert(.systemFont(ofSize: 14, weight: .regular), toHaveTrait: .italicFontMask),
            codeFont: .monospacedSystemFont(ofSize: 13, weight: .medium)
        )
    }

    @Test
    func sanitizedTypingAttributesStripsStickyLinkCodeAndAttachmentMetadata() {
        let theme = makeTheme()
        let attachment = NSTextAttachment()
        var sticky = theme.baseAttributes(for: .paragraph)
        sticky[.attachment] = attachment
        sticky[.qmAttachmentFilePath] = "/tmp/image.png"
        sticky[.qmAttachmentMarkdown] = "![img](image.png)"
        sticky[.qmLinkURL] = "https://example.com"
        sticky[.qmAutomaticLink] = true
        sticky[.qmCode] = true
        sticky[.qmTag] = "#work"
        sticky[.qmSearchHighlight] = true
        sticky[MarkdownRichTextCodec.literalMarkdownKey] = true
        sticky[NSAttributedString.Key("MudsnoteOriginalMarkdown")] = "raw"
        sticky[.qmTablePlaceholder] = true
        sticky[.underlineStyle] = NSUnderlineStyle.single.rawValue
        sticky[.foregroundColor] = theme.accentColor
        sticky[.backgroundColor] = NSColor.systemYellow.withAlphaComponent(0.30)

        let clean = MarkdownRichTextCodec.sanitizedTypingAttributes(
            from: sticky,
            paragraphKind: .paragraph,
            theme: theme
        )
        #expect(clean[.attachment] == nil)
        #expect(clean[.qmAttachmentFilePath] == nil)
        #expect(clean[.qmAttachmentMarkdown] == nil)
        #expect(clean[.qmLinkURL] == nil)
        #expect(clean[.qmAutomaticLink] == nil)
        #expect(clean[.qmCode] == nil)
        #expect(clean[.qmTag] == nil)
        #expect(clean[.qmSearchHighlight] == nil)
        #expect(clean[MarkdownRichTextCodec.literalMarkdownKey] == nil)
        #expect(clean[NSAttributedString.Key("MudsnoteOriginalMarkdown")] == nil)
        #expect(clean[.qmTablePlaceholder] == nil)
        #expect(clean[.underlineStyle] == nil)
        #expect(clean[.backgroundColor] == nil)
    }

    @Test
    func markdownCodecPreservesDecimalsDatesBoldItalicAndEscapedTableBackslash() {
        let theme = makeTheme()

        let decimalLine = MarkdownRichTextCodec.renderLine("3.14 is pi", theme: theme)
        #expect(MarkdownRichTextCodec.serialize(decimalLine, theme: theme) == "3.14 is pi")
        #expect(MarkdownRichTextCodec.paragraphKind(at: NSRange(location: 0, length: decimalLine.length), in: decimalLine) == .paragraph)

        let dateLine = MarkdownRichTextCodec.renderLine("2026.11.22 release notes", theme: theme)
        #expect(MarkdownRichTextCodec.serialize(dateLine, theme: theme) == "2026.11.22 release notes")
        #expect(MarkdownRichTextCodec.paragraphKind(at: NSRange(location: 0, length: dateLine.length), in: dateLine) == .paragraph)

        let boldItalic = MarkdownRichTextCodec.renderLine("***Important*** text", theme: theme)
        #expect(boldItalic.string == "Important text")
        let serializedBoldItalic = MarkdownRichTextCodec.serialize(boldItalic, theme: theme)
        #expect(serializedBoldItalic.contains("Important"))
        #expect(serializedBoldItalic.contains("**") && serializedBoldItalic.contains("*"))

        let tableMarkdown = "| A | B |\n| --- | --- |\n| path\\\\ | line 1<br>line 2 |"
        let renderedTable = MarkdownRichTextCodec.render(markdown: tableMarkdown, theme: theme)
        let serializedTable = MarkdownRichTextCodec.serialize(renderedTable, theme: theme)
        #expect(serializedTable.contains("| path\\\\ | line 1<br>line 2 |"))
    }

    @Test
    func hotKeyParseEnforcesRequiredModifier() {
        #expect(HotKeySpec.parse("a") == nil)
        #expect(HotKeySpec.parse("shift+a") == nil)
        #expect(HotKeySpec.parse("option+shift+n") != nil)
        #expect(HotKeySpec.parse("command+return") != nil)
    }

    @Test
    func floatingNoteSwitchPreservesTargetTagsAndSavesOnce() throws {
        let (store, root, suiteName, defaults) = try makeStore()
        defer { cleanup(root: root, suiteName: suiteName, defaults: defaults) }

        let firstURL = try store.saveNewNote(title: "First", body: "First body", tags: ["alpha"])
        let secondURL = try store.saveNewNote(title: "Second", body: "Second body", tags: ["beta", "gamma"])

        var saveCallbackCount = 0
        let controller = EditorWindowController(
            noteStore: store,
            panelOpacity: NoteStore.defaultPanelOpacity,
            fileURL: firstURL,
            draftIDOverride: "floating-note",
            showsSaveButton: false,
            onSave: { _ in saveCallbackCount += 1 },
            onClose: {},
            onRequestSearch: {},
            onRequestPreferences: {}
        )
        defer { controller.close() }

        #expect(controller.activeTags == ["alpha"])
        controller.loadFloatingNote(at: secondURL)
        #expect(controller.activeTags == ["beta", "gamma"])

        saveCallbackCount = 0
        controller.savePressed()
        #expect(saveCallbackCount == 1)
        let savedSecond = try store.loadNoteDocument(at: secondURL)
        #expect(savedSecond.tags == ["beta", "gamma"])
    }

    @Test
    func libraryDateScopeOverviewPersistenceAndWindowClosedStateWorkReliably() throws {
        let (store, root, suiteName, defaults) = try makeStore()
        defer { cleanup(root: root, suiteName: suiteName, defaults: defaults) }

        let subFolder = store.notesDirectory.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: subFolder, withIntermediateDirectories: true)
        _ = try store.saveNewNote(title: "Spec", body: "Body", in: subFolder)

        store.librarySidebarPresentationRawValue = LibrarySidebarPresentation.tree.rawValue
        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        // 1. showOverview should not overwrite persisted sidebar presentation preference.
        controller.showOverview()
        #expect(store.librarySidebarPresentationRawValue == LibrarySidebarPresentation.tree.rawValue)

        // 2. showFolderInListMenuItemPressed updates selectedScope to the chosen folder.
        let item = NSMenuItem(title: "以列表显示", action: nil, keyEquivalent: "")
        item.representedObject = subFolder
        controller.showFolderInListMenuItemPressed(item)
        #expect(controller.selectedScope == .folder(subFolder.standardizedFileURL))

        // 3. noteListDateText respects the injected `now` parameter.
        var components = DateComponents()
        components.year = 2024
        components.month = 6
        components.day = 15
        components.hour = 14
        components.minute = 30
        let fixedNow = try #require(Calendar.current.date(from: components))
        let fixedYesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: fixedNow))
        #expect(controller.noteListDateText(for: fixedYesterday, now: fixedNow) == LibraryCopy.yesterday)

        // 4. Window close state distinguishes hidden/minimized from genuinely closed.
        #expect(controller.isWindowClosed == false)
        controller.window?.orderOut(nil)
        #expect(controller.isWindowClosed == false)
        controller.close()
        #expect(controller.isWindowClosed == true)
    }

    @Test
    func overviewIgnoresFunctionKeysInsteadOfOverwritingTopicTitle() throws {
        let (store, root, suiteName, defaults) = try makeStore()
        defer { cleanup(root: root, suiteName: suiteName, defaults: defaults) }

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }
        controller.showOverview()
        let overview = try #require(controller.overviewView)
        var areaID: UUID?
        _ = controller.changeOverview { state in
            let area = NoteOverview.Area(title: "Architecture", parentID: nil)
            areaID = area.id
            state.areas.append(area)
        }
        let targetID = try #require(areaID)
        _ = overview.select(.area(targetID))

        let f1String = String(UnicodeScalar(NSF1FunctionKey)!)
        let f1Event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            characters: f1String,
            charactersIgnoringModifiers: f1String,
            isARepeat: false,
            keyCode: 122
        ))
        #expect(overview.handleKey(f1Event) == false)
        #expect(overview.topicEdit == nil)
        #expect(overview.topicEditor.isHidden == true)
        #expect(controller.overviewState?.areas.first(where: { $0.id == targetID })?.title == "Architecture")
    }
}
