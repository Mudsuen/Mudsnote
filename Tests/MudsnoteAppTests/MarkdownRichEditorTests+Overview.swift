import AppKit
import Foundation
import Testing
@testable import Mudsnote
@testable import MudsnoteCore

extension MarkdownRichEditorTests {
    @Test func overviewPersistsConnectionsAndKeepsOriginalNotes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "mudsnote.overview." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: root)
        var model = NoteOverview()
        let first = model.add(root.appendingPathComponent("a.md"), areaID: model.areas[0].id)
        let second = model.add(root.appendingPathComponent("b.md"))
        #expect(model.add(root.appendingPathComponent("a.md")) == first)
        model.connect(first, second); model.connect(second, first); model.connect(first, first)
        #expect(model.connections.count == 1)
        try store.saveOverview(model)
        #expect(try store.loadOverview() == model)
        model.remap(root.appendingPathComponent("a.md"), to: root.appendingPathComponent("renamed.md"))
        #expect(model.cards.first?.id == first)
        model.removeCard(second)
        #expect(model.connections.isEmpty)
        // Malformed metadata is reported rather than silently replaced.
        try Data("broken".utf8).write(to: root.appendingPathComponent("Overview-v1.json"))
        #expect(throws: (any Error).self) { try store.loadOverview() }
        #expect(try String(contentsOf: root.appendingPathComponent("Overview-v1.json"), encoding: .utf8) == "broken")
    }

    @Test func overviewExpandsSharedEditorAndSavesBeforeCollapseOrSwitch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "mudsnote.overview-ui." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        let first = try store.saveNewNote(title: "First", body: "Original body")
        let second = try store.saveNewNote(title: "Second", body: "Second body")
        let controller = LibraryWindowController(noteStore: store, onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        controller.showWindowAndFocus()
        controller.showOverview()
        #expect(controller.isShowingOverview)
        let firstID = try #require(controller.overviewState?.cards.first { $0.url == first }?.id)
        controller.toggleOverviewCard(firstID)
        for _ in 0..<100 where controller.overviewView?.selectedID != firstID { try await Task.sleep(for: .milliseconds(10)) }
        #expect(controller.overviewView?.selectedID == firstID)
        #expect(controller.regularEditorView?.superview === controller.overviewView?.cards[firstID])
        controller.applyDocument(title: "First", body: "Edited in place 中文", tags: [])
        controller.markDirty()
        controller.toggleOverviewCard(firstID)
        #expect(controller.overviewView?.selectedID == nil)
        let savedURL = try #require(controller.selectedURL)
        #expect(try store.loadNote(at: savedURL).body == "Edited in place 中文")
        let secondID = try #require(controller.overviewState?.cards.first { $0.url == second }?.id)
        controller.toggleOverviewCard(secondID)
        for _ in 0..<100 where controller.overviewView?.selectedID != secondID { try await Task.sleep(for: .milliseconds(10)) }
        #expect(controller.selectedURL == second)
        #expect(controller.regularEditorView?.superview === controller.overviewView?.cards[secondID])
        #expect(controller.leaveOverview())
        #expect(controller.regularEditorView?.superview === controller.overviewHost)
        #expect(try store.loadOverview().cards.contains(where: { $0.id == firstID }))
    }
}
