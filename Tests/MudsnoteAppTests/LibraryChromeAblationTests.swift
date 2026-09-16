import AppKit
import Foundation
import MudsnoteCore
import Testing
@testable import Mudsnote

// Opt-in measurement experiment, using synthetic notes and real AppKit layout.
// MUDSNOTE_CHROME_ABLATION_OUTPUT=/tmp/chrome.json ./scripts/verify macos pr
@Suite(.serialized)
struct LibraryChromeAblationTests {
    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MUDSNOTE_CHROME_ABLATION_OUTPUT"] != nil))
    func chromeFactorAblation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "mudsnote.chrome-ablation." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let store = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        let noteURL = try store.saveNewNote(title: "布局对照", body: "Synthetic body for layout and focus verification.")
        var results = [[String: Any]]()
        func descendants(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(descendants) }
        for width in [896.0, 1100.0] {
            for mask in 0..<8 {
                let controller = LibraryWindowController(noteStore: store, onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
                let window = try #require(controller.window)
                defer { controller.close() }
                let toolbar = NSToolbar(identifier: "ablation-" + UUID().uuidString)
                toolbar.delegate = controller
                toolbar.displayMode = .iconOnly
                window.toolbar = toolbar
                window.toolbarStyle = mask & 1 == 0 ? .unified : .unifiedCompact
                let search = try #require(toolbar.items.first { $0.itemIdentifier.rawValue == "mudsnote.library.toolbar.search" }?.view)
                controller.searchField.constraints.first { $0.firstAttribute == .height }?.constant = mask & 2 == 0 ? 32 : 24
                search.constraints.first { $0.firstAttribute == .height }?.constant = mask & 2 == 0 ? 36 : 28
                search.setFrameSize(NSSize(width: search.frame.width, height: mask & 2 == 0 ? 36 : 28))
                controller.editorTextView.textContainerInset.height = mask & 4 == 0 ? 34.75 : 24
                controller.showWindowAndFocus()
                window.setContentSize(NSSize(width: width, height: 600))
                try await Task.sleep(for: .milliseconds(80))
                window.contentView?.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                let views = descendants(try #require(window.contentView?.superview))
                let tab = try #require(views.first { $0.identifier?.rawValue == "LibraryDocumentTabHeader" })
                let editor = try #require(views.first { $0.identifier?.rawValue == "LibraryEditorStack" })
                let tabFrame = tab.convert(tab.bounds, to: nil)
                let editorFrame = editor.convert(editor.bounds, to: nil)
                let contentBefore = controller.editorTextView.string
                let selectedBefore = controller.selectedMarkdownFileURLForLibrary()
                controller.editorTextView.window?.makeFirstResponder(controller.editorTextView)
                let responderBefore = window.firstResponder
                let toggle = try #require(views.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "LibrarySidebarPresentationButton" })
                toggle.performClick(nil)
                toggle.performClick(nil)
                #expect(controller.editorTextView.string == contentBefore)
                #expect(controller.selectedMarkdownFileURLForLibrary() == selectedBefore)
                #expect(window.firstResponder === responderBefore)
                #expect(selectedBefore?.standardizedFileURL == noteURL.standardizedFileURL)
                results.append([
                    "width": width, "mask": mask,
                    "compactToolbar": mask & 1 != 0, "compactSearch": mask & 2 != 0, "compactMetadata": mask & 4 != 0,
                    "chromeHeight": window.frame.height - editorFrame.maxY,
                    "tabHeight": tabFrame.height,
                    "tabToEditorGap": tabFrame.minY - editorFrame.maxY,
                    "titleStartFromWindowTop": window.frame.height - editorFrame.maxY + controller.editorTextView.textContainerInset.height,
                    "searchFitsWrapper": search.bounds.contains(controller.searchField.frame),
                    "contentAndFocusPreserved": true
                ])
            }
        }
        let output = try #require(ProcessInfo.processInfo.environment["MUDSNOTE_CHROME_ABLATION_OUTPUT"])
        try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: output))
    }
}
