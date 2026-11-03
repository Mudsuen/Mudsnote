import AppKit
import Foundation
import Testing
@testable import Mudsnote
@testable import MudsnoteCore

extension MarkdownRichEditorTests {
    @Test func overviewRecoveryRetainsNewMetadataWithoutReplacingLegacyOrMalformedState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "mudsnote.overview-recovery." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let store = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: root)
        var model = NoteOverview(); model.title = "新标题"; model.areas[0].details = "新增描述"
        try store.saveOverview(model)
        var legacy = model; legacy.title = nil; legacy.areas[0].details = nil
        let canonical = root.appendingPathComponent("Overview-v1.json")
        try JSONEncoder().encode(legacy).write(to: canonical, options: .atomic)
        #expect(try store.loadOverview() == legacy)
        let recovery = root.appendingPathComponent("Overview-recovery.json")
        #expect(try JSONDecoder().decode(NoteOverview.self, from: Data(contentsOf: recovery)) == model)
        try Data("malformed".utf8).write(to: canonical)
        #expect(throws: (any Error).self) { try store.loadOverview() }
        #expect(try String(contentsOf: canonical, encoding: .utf8) == "malformed")
        #expect(try JSONDecoder().decode(NoteOverview.self, from: Data(contentsOf: recovery)) == model)
    }

    @Test func overviewFiveLevelMovesFocusAndUndoPreserveLinkedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "mudsnote.overview-five-levels." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        let first = try store.saveNewNote(title: "Linked", body: "Canonical 中文")
        let second = try store.saveNewNote(title: "Other", body: "Other body")
        var model = NoteOverview(); model.areas = []; model.seeded = true; model.title = "层级验证"
        var ids: [UUID] = []
        for name in ["工作", "项目", "阶段", "任务", "执行"] {
            let area = NoteOverview.Area(title: name, parentID: ids.last)
            model.areas.append(area); ids.append(area.id)
        }
        model.areas[2].details = "分阶段验证，多层描述。"
        let other = NoteOverview.Area(title: "生活")
        model.areas.append(other)
        let card = model.add(first, areaID: ids[4]), otherCard = model.add(second, areaID: other.id)
        model.connect(card, otherCard)
        try store.saveOverview(model)
        let controller = LibraryWindowController(noteStore: store, onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        controller.showWindowAndFocus(); controller.showOverview()
        let overview = try #require(controller.overviewView)
        overview.setPresentation(.outline)
        #expect(overview.plan?.depths[.area(ids[4])] == 5)
        let frames = ids.compactMap { overview.plan?.frames[.area($0)] }
        #expect(frames.count == 5)
        for i in 1..<frames.count { #expect(abs(frames[i].minX - frames[i - 1].minX - 28) < 0.1) }
        #expect(!overview.canMove(.area(ids[0]), to: .area(ids[4])))
        #expect(try store.loadOverview() == model)
        #expect(overview.move(.area(ids[4]), to: .root))
        #expect(try store.loadOverview().areas.first { $0.id == ids[4] }?.parentID == nil)
        #expect(OverviewTree(overview.state).parents[.card(card)] == .area(ids[4]))
        overview.structuralUndo.undo()
        #expect(try store.loadOverview() == model)
        overview.structuralUndo.redo()
        #expect(overview.state.areas.first { $0.id == ids[4] }?.parentID == nil)
        overview.structuralUndo.undo()
        overview.focus(.area(ids[2]))
        #expect(overview.plan?.root == .area(ids[2]))
        #expect(overview.hosts[.area(ids[0])]?.isHidden == true)
        #expect(overview.hosts[.area(ids[3])]?.isHidden == false)
        overview.focus(.root)
        overview.toggleBranch(.area(ids[1]))
        #expect(overview.cards[card]?.isHiddenOrHasHiddenAncestor == true)
        #expect(store.libraryOverviewCollapsedNodes.contains(OverviewNodeID.area(ids[1]).dragString))
        overview.toggleBranch(.area(ids[1]))
        #expect(overview.cards[card]?.isHiddenOrHasHiddenAncestor == false)
        overview.structuralUndo.removeAllActions()
        overview.removeTopic(.area(ids[0]))
        #expect(overview.state.areas.count == 1 && overview.state.cards.count == 1)
        #expect(overview.state.connections.isEmpty)
        #expect(try store.loadNote(at: first).body == "Canonical 中文")
        #expect(try store.loadNote(at: second).body == "Other body")
        overview.structuralUndo.undo()
        #expect(try store.loadOverview() == model)
        overview.setPresentation(.mindMap); overview.setStructure(.balanced)
        #expect(overview.plan?.sides[.area(ids[0])] == 1)
        #expect(overview.plan?.sides[.area(other.id)] == -1)
        let longText = String(repeating: "多层主题长标题", count: 12)
        _ = controller.changeOverview { state in state.areas[4].title = longText }
        overview.layoutSubtreeIfNeeded()
        let longNode = try #require(overview.plan?.frames[.area(ids[4])])
        #expect(longNode.height > 44)
        let all = Array(try #require(overview.plan).frames.values)
        for i in all.indices { for j in all.indices where j > i { #expect(!all[i].intersects(all[j])) } }
    }

    @Test func overviewInlineCommandsAndDayNightPreferencesStayIndependent() throws {
        #expect(OverviewTypography.font(16).fontName == "SourceSansPro-Regular")
        #expect(OverviewTypography.font(34, weight: .semibold).fontName == "SourceSansPro-Semibold")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "mudsnote.overview-inline-modes." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        var model = NoteOverview(); model.areas = []; model.seeded = true
        try store.saveOverview(model)
        let controller = LibraryWindowController(noteStore: store, onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        controller.showWindowAndFocus(); controller.showOverview()
        let overview = try #require(controller.overviewView)
        let descriptionPoint = overview.rootHost.convert(NSPoint(x: overview.principles.frame.midX, y: overview.principles.frame.midY), to: overview.canvas)
        #expect(overview.rootHost.hitTest(descriptionPoint) === overview.principles)
        overview.createTopic(parent: .root)
        let first = try #require(overview.topicEdit?.node)
        overview.topicEditor.string = "一级"
        #expect(overview.commitTopicEditing())
        overview.beginTopicEdit(first)
        overview.topicEditor.setMarkedText("输入", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(overview.topicEditor.hasMarkedText())
        let markedRange = overview.topicEditor.markedRange()
        overview.needsLayout = true; overview.layoutSubtreeIfNeeded()
        #expect(overview.topicEditor.hasMarkedText() && overview.topicEditor.markedRange() == markedRange)
        #expect(overview.commitTopicEditing())
        #expect(overview.nodeTitle(first).contains("输入"))
        overview.setPresentation(.outline)
        overview.activeNode = first
        let tab = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0, context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48))
        #expect(overview.handleKey(tab))
        #expect(overview.state.areas.count == 1)
        overview.setPresentation(.mindMap)
        #expect(overview.handleKey(tab))
        #expect(overview.state.areas.count == 2)
        let child = try #require(overview.topicEdit?.node)
        #expect(OverviewTree(overview.state).parents[child] == first)
        overview.topicEditor.string = "二级"
        #expect(overview.commitTopicEditing())
        overview.beginTopicEdit(child, details: true)
        overview.topicEditor.string = "多行描述\n第二行"
        #expect(overview.commitTopicEditing())
        overview.setOverviewAppearance(.light)
        overview.setMapStyle(.focus)
        #expect(!overview.colors.dark && overview.colors.mapBackground == OverviewColors.rgb(23, 23, 23))
        overview.setPresentation(.outline)
        #expect(overview.colors.outlineBackground == .white)
        overview.setOverviewAppearance(.dark)
        overview.setMapStyle(.ink)
        #expect(overview.colors.dark && overview.colors.mapBackground == .white)
        #expect(store.libraryOverviewAppearanceRawValue == OverviewAppearance.dark.rawValue)
        #expect(store.libraryOverviewMapStyleRawValue == OverviewMapStyle.ink.rawValue)
        #expect(try store.loadOverview() == overview.state)
        #expect(overview.changeIndent(child, outward: true))
        #expect(OverviewTree(overview.state).parents[child] == .root)
        #expect(overview.nodeDetails(child) == "多行描述\n第二行")
        overview.beginTopicEdit(.root, details: true)
        overview.topicEditor.string = "宗旨第一行\n宗旨第二行"
        #expect(overview.commitTopicEditing())
        overview.layoutSubtreeIfNeeded()
        #expect(overview.principles.frame.height >= 48)
    }

    @Test func overviewAppearanceRestoresSharedEditorAfterSaving() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "mudsnote.overview-editor-appearance." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        let url = try store.saveNewNote(title: "Note", body: "Before")
        let controller = LibraryWindowController(noteStore: store, onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        controller.showWindowAndFocus(); controller.showOverview()
        let overview = try #require(controller.overviewView)
        let editor = try #require(controller.regularEditorView)
        let appearance = editor.appearance?.name
        let id = try #require(overview.state.cards.first { $0.url == url }?.id)
        overview.layoutSubtreeIfNeeded()
        let card = try #require(overview.cards[id])
        let point = card.convert(NSPoint(x: card.heading.frame.midX, y: card.heading.frame.midY), to: card.superview)
        #expect(card.hitTest(point) === card)
        controller.toggleOverviewCard(id)
        for _ in 0..<100 where overview.selectedID != id { try await Task.sleep(for: .milliseconds(10)) }
        #expect(overview.selectedID == id)
        overview.setMapStyle(.ink)
        #expect(editor.appearance?.name == .aqua)
        overview.setMapStyle(.focus)
        #expect(editor.appearance?.name == .darkAqua)
        overview.setPresentation(.outline); overview.setOverviewAppearance(.light)
        #expect(editor.appearance?.name == .aqua)
        controller.applyDocument(title: "Note", body: "After 中文", tags: []); controller.markDirty()
        #expect(controller.leaveOverview())
        #expect(editor.appearance?.name == appearance)
        #expect(try store.loadNote(at: url).body == "After 中文")
    }
}
