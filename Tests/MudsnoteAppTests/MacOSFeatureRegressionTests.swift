import AppKit
import Foundation
import Testing
@testable import Mudsnote
@testable import MudsnoteCore

@MainActor
struct MacOSAppFeatureRegressionTests {
    private func makeController() throws -> (EditorWindowController, URL, UserDefaults) {
        let suiteName = "mudsnote.macos-app-feature-regressions.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-macos-app-feature-regressions-\(UUID().uuidString)", isDirectory: true)
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
            draftIDOverride: "feature-regression",
            showsSaveButton: false,
            onSave: { _ in },
            onClose: {},
            onRequestSearch: {},
            onRequestPreferences: {}
        )
        return (controller, root, defaults)
    }

    @Test
    func mixedBoldSelectionBecomesEntirelyBoldOnFirstCommand() throws {
        let (controller, root, defaults) = try makeController()
        defer {
            controller.close()
            try? FileManager.default.removeItem(at: root)
            _ = defaults
        }
        let regular = controller.theme.baseAttributes(for: .paragraph)
        var bold = regular
        bold[.font] = controller.theme.boldFont
        let content = NSMutableAttributedString(string: "A", attributes: bold)
        content.append(NSAttributedString(string: "B", attributes: regular))
        controller.editorTextView.textStorage?.setAttributedString(content)
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 2))

        controller.toggleInlineFontTrait(.boldFontMask)

        let storage = try #require(controller.editorTextView.textStorage)
        for location in 0..<2 {
            let font = try #require(storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont)
            #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        }
    }

    @Test
    func mixedSpecialFormatSelectionsBecomeUniformlyFormattedOnFirstCommand() throws {
        let (controller, root, defaults) = try makeController()
        defer {
            controller.close()
            try? FileManager.default.removeItem(at: root)
            _ = defaults
        }
        let regular = controller.theme.baseAttributes(for: .paragraph)
        let storage = try #require(controller.editorTextView.textStorage)

        var italic = regular
        italic[.font] = NSFontManager.shared.convert(
            controller.theme.bodyFont,
            toHaveTrait: .italicFontMask
        )
        storage.setAttributedString(NSAttributedString(string: "AB", attributes: regular))
        storage.addAttributes(italic, range: NSRange(location: 0, length: 1))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 2))
        controller.toggleInlineFontTrait(.italicFontMask)
        for location in 0..<2 {
            let attributes = storage.attributes(at: location, effectiveRange: nil)
            let font = try #require(attributes[.font] as? NSFont)
            #expect(
                NSFontManager.shared.traits(of: font).contains(.italicFontMask)
                    || (attributes[.obliqueness] as? Double ?? 0) != 0
            )
        }

        storage.setAttributedString(NSAttributedString(string: "AB", attributes: regular))
        storage.addAttribute(
            .underlineStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 0, length: 1)
        )
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 2))
        controller.applyUnderline()
        for location in 0..<2 {
            #expect((storage.attribute(.underlineStyle, at: location, effectiveRange: nil) as? Int) == NSUnderlineStyle.single.rawValue)
        }

        storage.setAttributedString(NSAttributedString(string: "AB", attributes: regular))
        storage.addAttribute(
            .qmHighlight,
            value: true,
            range: NSRange(location: 0, length: 1)
        )
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 2))
        controller.toggleHighlightFormatting()
        for location in 0..<2 {
            #expect((storage.attribute(.qmHighlight, at: location, effectiveRange: nil) as? Bool) == true)
        }
    }

    @Test
    func deletingFormattedSelectionClearsInlineTypingFormats() throws {
        let editor = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let theme = MarkdownEditorTheme(
            textColor: .textColor,
            mutedTextColor: .secondaryLabelColor,
            accentColor: .controlAccentColor,
            bodyFont: .systemFont(ofSize: 14),
            boldFont: .boldSystemFont(ofSize: 14),
            italicFont: NSFontManager.shared.convert(.systemFont(ofSize: 14), toHaveTrait: .italicFontMask),
            codeFont: .monospacedSystemFont(ofSize: 13, weight: .regular)
        )
        editor.markdownPasteTheme = theme
        editor.textStorage?.setAttributedString(NSAttributedString(
            string: "formatted",
            attributes: [
                .font: theme.boldFont,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .qmHighlight: true,
                .backgroundColor: NSColor.systemYellow
            ]
        ))
        editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))

        editor.deleteBackward(nil)

        let font = try #require(editor.typingAttributes[.font] as? NSFont)
        #expect(!NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        #expect(editor.typingAttributes[.underlineStyle] == nil)
        #expect(editor.typingAttributes[.qmHighlight] == nil)
        #expect(editor.typingAttributes[.backgroundColor] == nil)
    }

    @Test
    func richPasteInsideParagraphDoesNotCreateThreeLines() throws {
        let editor = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let theme = MarkdownEditorTheme(
            textColor: .textColor,
            mutedTextColor: .secondaryLabelColor,
            accentColor: .controlAccentColor,
            bodyFont: .systemFont(ofSize: 14),
            boldFont: .boldSystemFont(ofSize: 14),
            italicFont: NSFontManager.shared.convert(.systemFont(ofSize: 14), toHaveTrait: .italicFontMask),
            codeFont: .monospacedSystemFont(ofSize: 13, weight: .regular)
        )
        editor.markdownPasteTheme = theme
        editor.string = "beforeafter"
        editor.setSelectedRange(NSRange(location: 6, length: 0))
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        let rtf = try NSAttributedString(
            string: "middle",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 14)]
        ).data(
            from: NSRange(location: 0, length: 6),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        pasteboard.setData(rtf, forType: .rtf)

        #expect(editor.pasteContents(from: pasteboard))
        #expect(editor.string == "beforemiddleafter")
    }

    @Test
    func grayAndBlackThemesProvideDistinctSelectionTints() {
        #expect(MudsnoteThemeColor.allCases.contains(.gray))
        #expect(MudsnoteThemeColor.allCases.contains(.black))
        #expect(MudsnoteThemeColor.gray.noteSelectionColor != MudsnoteThemeColor.black.noteSelectionColor)
    }
}
