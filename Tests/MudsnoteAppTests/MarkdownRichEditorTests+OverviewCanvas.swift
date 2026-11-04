import AppKit
import Foundation
import Testing
@testable import Mudsnote
@testable import MudsnoteCore

extension MarkdownRichEditorTests {
    @Test func overviewCanvasPansFarInEveryDirectionWithoutGrowingBackingView() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "mudsnote.infinite-canvas." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        var state = NoteOverview(); state.seeded = true; try store.saveOverview(state)
        let controller = LibraryWindowController(noteStore: store, onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        controller.showWindowAndFocus(); controller.showOverview()
        let view = try #require(controller.overviewView)
        view.setPresentation(.mindMap); view.layoutSubtreeIfNeeded(); view.centerRoot()
        let initial = try #require(view.plan)
        let rootBefore = try #require(initial.frames[.root]).offsetBy(dx: -initial.worldOffset.x, dy: -initial.worldOffset.y)
        let visible = view.scroll.contentView.bounds.size
        let canvasSize = view.canvas.frame.size
        let worldBefore = CGPoint(x: view.scroll.contentView.bounds.minX - initial.worldOffset.x,
                                  y: view.scroll.contentView.bounds.minY - initial.worldOffset.y)
        for _ in 0..<80 {
            let clip = view.scroll.contentView.bounds
            view.panViewport(to: CGPoint(x: clip.minX - visible.width * 1.7, y: clip.minY + visible.height * 0.9))
        }
        let after = try #require(view.plan)
        let worldAfter = CGPoint(x: view.scroll.contentView.bounds.minX - after.worldOffset.x,
                                 y: view.scroll.contentView.bounds.minY - after.worldOffset.y)
        #expect(abs(worldAfter.x - worldBefore.x + visible.width * 136) < 0.1)
        #expect(abs(worldAfter.y - worldBefore.y - visible.height * 72) < 0.1)
        #expect(view.canvas.frame.size == canvasSize)
        #expect(try #require(after.frames[.root]).offsetBy(dx: -after.worldOffset.x, dy: -after.worldOffset.y) == rootBefore)
        view.centerRoot()
        let centered = try #require(view.plan?.frames[.root])
        #expect(abs(centered.midX - view.scroll.contentView.bounds.midX) < 1)
        #expect(abs(centered.midY - view.scroll.contentView.bounds.midY) < 1)
        #expect(try store.loadOverview() == state)
    }

    @Test func overviewFreeContentKeepsWorldPositionAndSurvivesOutlineConversion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "mudsnote.free-content." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        var state = NoteOverview(); state.seeded = true; try store.saveOverview(state)
        let controller = LibraryWindowController(noteStore: store, onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        controller.showWindowAndFocus(); controller.showOverview()
        let view = try #require(controller.overviewView)
        view.setPresentation(.mindMap); view.layoutSubtreeIfNeeded()
        view.centerWorldPoint(CGPoint(x: -100_000, y: 200_000))
        let clip = view.scroll.contentView.bounds
        let position = view.mapPosition(at: CGPoint(x: clip.midX, y: clip.midY))
        #expect(abs(position.x + 100_000) < 1 && abs(position.y - 200_000) < 1)
        view.createTopic(parent: .root, position: position)
        let topic = try #require(view.topicEdit?.node)
        view.topicEditor.string = "自由主题"
        #expect(view.commitTopicEditing())
        view.layoutSubtreeIfNeeded()
        let plan = try #require(view.plan)
        let frame = try #require(plan.frames[topic])
        #expect(abs(frame.minX - plan.worldOffset.x - position.x) < 1)
        #expect(abs(frame.minY - plan.worldOffset.y - position.y) < 1)
        let window = try #require(controller.window)
        #expect(window.makeFirstResponder(view))
        view.removeTopic(topic)
        #expect(window.windowController === controller)
        #expect(window.firstResponder === view)
        #expect(view.selectedID == nil && view.topicEdit == nil)
        #expect(view.structuralUndo.canUndo)
        let undo = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [.command], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, characters: "z", charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6))
        #expect(window.performKeyEquivalent(with: undo))
        #expect(view.state.areas.contains { OverviewNodeID.area($0.id) == topic })
        #expect(view.undoManager === view.structuralUndo)
        view.setPresentation(.outline)
        #expect(view.plan?.frames[topic] != nil)
        view.setPresentation(.mindMap)
        controller.createNoteInOverview(position: position)
        for _ in 0..<100 where view.selectedID == nil { try await Task.sleep(for: .milliseconds(10)) }
        let id = try #require(view.selectedID)
        let card = try #require(view.state.cards.first { $0.id == id })
        #expect(card.mapPosition == position)
        #expect(FileManager.default.fileExists(atPath: card.url.path))
        #expect(view.plan?.links.contains { $0.1 == .card(id) } == false)
        controller.toggleOverviewCard(id)
        view.setPresentation(.outline)
        #expect(view.plan?.frames[.card(id)] != nil)
        #expect(try store.loadOverview().cards.first { $0.id == id }?.mapPosition == position)
    }
}
