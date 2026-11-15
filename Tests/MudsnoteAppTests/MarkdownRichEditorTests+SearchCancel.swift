import AppKit
import Foundation
import Testing
@testable import Mudsnote
@testable import MudsnoteCore

extension MarkdownRichEditorTests {
    @Test func librarySearchShortcutRevealsInputFromEveryNavigationPage() throws {
        let suite = "mudsnote.library-search-entry.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let store = NoteStore(defaults: defaults, legacyDefaults: nil,
                              appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        _ = try store.saveNewNote(title: "Alpha", body: "Search fixture")
        let controller = LibraryWindowController(
            noteStore: store, onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {}
        )
        defer { controller.close() }
        controller.showWindowAndFocus()
        for presentation in [LibrarySidebarPresentation.list, .tree, .tags] {
            controller.showLibraryNavigationPage(presentation, scope: .all)
            _ = controller.setSourceListVisibleForLibrary(false)
            controller.focusSearchForLibrary()
            #expect(controller.isSourceListVisibleForLibrary)
            #expect(!controller.searchField.isHiddenOrHasHiddenAncestor)
            #expect(controller.searchField.currentEditor() === controller.window?.firstResponder)
            #expect(controller.sidebarPresentation == presentation)
            controller.searchForLibrary(query: "Alpha", allNotes: true)
            #expect(controller.sidebarSearchStatusView?.isHidden == false)
            #expect(controller.noteListCountLabel.stringValue == "1 条结果")
            #expect(controller.clearSearchFromKeyboard())
            #expect(controller.sidebarSearchStatusView?.isHidden == true)
            #expect(!controller.searchField.isHidden)
            #expect(controller.clearSearchFromKeyboard())
            #expect(controller.searchField.isHidden)
            #expect(!controller.sidebarLibraryTitle.isHidden)
        }
        controller.showOverview()
        controller.focusSearchForLibrary()
        #expect(!controller.isShowingOverview)
        #expect(!controller.searchField.isHiddenOrHasHiddenAncestor)
        #expect(controller.searchField.currentEditor() === controller.window?.firstResponder)
        #expect(controller.currentLibraryPage.scope == .all)
        controller.searchForLibrary(query: "Alpha", allNotes: true)
        controller.showLibraryNavigationPage(.list, scope: .recent)
        controller.searchForLibrary(query: "Alpha", allNotes: false)
        controller.navigateLibraryBack()
        #expect(controller.searchScopeControl.selectedSegment == 1)
        #expect(controller.searchField.stringValue == "Alpha")
        #expect(!controller.searchField.isHiddenOrHasHiddenAncestor)
    }

    @Test func searchRailFindsOutsideCurrentFolderAndHighlightsEveryTerm() async throws {
        let suite = "mudsnote.library-search-rail.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let store = NoteStore(defaults: defaults, legacyDefaults: nil,
                              appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        let folder = try store.createFolder(named: "Projects")
        _ = try store.saveNewNote(title: "Project", body: "Current folder", in: folder)
        let target = try store.saveNewNote(title: "Knock", body: "短密码的使用方式")
        let controller = LibraryWindowController(noteStore: store,
            onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close() }
        controller.showWindowAndFocus()
        controller.showLibraryNavigationPage(.tree, scope: .folder(folder))
        let button = try #require(controller.navigationRail?.buttons.first { $0.0 == "搜索" }?.1)
        button.performClick(nil)
        #expect(controller.searchScopeControl.selectedSegment == 1)
        #expect(controller.searchField.currentEditor() === controller.window?.firstResponder)
        #expect(controller.searchField.frame.width > 100)
        #expect(button.selected)
        controller.searchForLibrary(query: "knock短密码", allNotes: true)
        #expect(controller.noteListSearchResultsForLibrary().map(\.url) == [target])
        let text = "Knock 与短密码"
        let highlighted = controller.highlightedSearchString(text, font: .systemFont(ofSize: 14),
                                                             baseColor: .labelColor, query: "knock短密码")
        for term in ["Knock", "短密码"] {
            let range = (text as NSString).range(of: term)
            #expect(highlighted.attribute(.backgroundColor, at: range.location, effectiveRange: nil) != nil)
        }
        // Typing only schedules work; it must not rescan the document per keystroke.
        let scans = controller.editorSearchHighlightRemovalScanCount
        controller.searchField.stringValue = "knock"
        controller.scheduleSearchReloadFromTyping()
        #expect(controller.editorSearchHighlightRemovalScanCount == scans)
        controller.cancelPendingSearchReload()
    }

    @Test func nativeSearchCancelRestoresLibraryAndCancelsPendingQuery() async throws {
        let suite = "mudsnote.library-native-search-cancel.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let store = NoteStore(defaults: defaults, legacyDefaults: nil,
                              appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        _ = try store.saveNewNote(title: "Alpha", body: "First note")
        _ = try store.saveNewNote(title: "Beta", body: "Second note")
        let controller = LibraryWindowController(
            noteStore: store, onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {}
        )
        defer { controller.close() }
        controller.showWindowAndFocus()
        controller.searchForLibrary(query: "No matching note", allNotes: true)
        #expect(controller.noteListSearchResultsForLibrary().isEmpty)
        let selectionBeforeAction = controller.selectedMarkdownFileURLForLibrary()
        // A nonempty native action must not open a note or bypass typing debounce.
        controller.searchField.sendAction(controller.searchField.action, to: controller.searchField.target)
        #expect(controller.selectedMarkdownFileURLForLibrary() == selectionBeforeAction)
        #expect(controller.noteListSearchResultsForLibrary().isEmpty)

        let cell = try #require(controller.searchField.cell as? NSSearchFieldCell)
        let cancelButton = try #require(cell.cancelButtonCell)
        cancelButton.performClick(controller.searchField)

        #expect(controller.searchField.stringValue.isEmpty)
        #expect(controller.activeSearchSessionForLibrary() == nil)
        #expect(controller.searchScopeControl.isHidden)
        #expect(Set(controller.noteListSearchResultsForLibrary().map(\.title)) == ["Alpha", "Beta"])
        #expect(controller.noteListCountLabel.stringValue == "2 条笔记")
        #expect(!controller.sourceOutlineView.isHiddenOrHasHiddenAncestor)

        controller.searchField.stringValue = "Alpha"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification,
                                                     object: controller.searchField))
        cancelButton.performClick(controller.searchField)
        try await Task.sleep(for: .milliseconds(250))
        #expect(controller.searchField.stringValue.isEmpty)
        #expect(Set(controller.noteListSearchResultsForLibrary().map(\.title)) == ["Alpha", "Beta"])
        #expect(controller.searchScopeControl.isHidden)

        // Escape also repairs a cleared field if AppKit delivered no edit callback.
        controller.searchForLibrary(query: "No matching note", allNotes: true)
        controller.searchField.stringValue = ""
        #expect(controller.clearSearchFromKeyboard())
        #expect(Set(controller.noteListSearchResultsForLibrary().map(\.title)) == ["Alpha", "Beta"])
        #expect(controller.searchScopeControl.isHidden)
    }
}
