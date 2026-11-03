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
        try "# First\n\nUpdated outside the card\n".write(to: savedURL, atomically: true, encoding: .utf8)
        controller.sourceCountSnapshot = controller.sourceCountSnapshot.map { note in
            note.url == savedURL ? NoteSearchResult(url: savedURL, title: "First", snippet: "Updated outside", modifiedAt: Date().addingTimeInterval(2)) : note
        }
        for _ in 0..<100 where controller.overviewView?.cards[firstID]?.preview.stringValue.contains("Updated outside") != true { try await Task.sleep(for: .milliseconds(10)) }
        #expect(controller.overviewView?.cards[firstID]?.preview.stringValue.contains("Updated outside") == true)
        controller.activateDocumentTab(controller.activeDocumentTab.id)
        for _ in 0..<100 where controller.isShowingOverview { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!controller.isShowingOverview)
        #expect(controller.selectedURL == savedURL)
        controller.showOverview()
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

extension MarkdownRichEditorTests {
    @Test(arguments: ["rail", "toolbar", "command", "tab"])
    func ordinaryNewNoteLeavesOverviewWithoutAddingCard(entry: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "mudsnote.creation-routing." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        let original = try store.saveNewNote(title: "Original", body: "Before")
        let controller = LibraryWindowController(noteStore: store, onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        controller.showWindowAndFocus()
        controller.showOverview()
        let id = try #require(controller.overviewState?.cards.first(where: { $0.url == original })?.id)
        controller.toggleOverviewCard(id)
        for _ in 0..<100 where controller.overviewView?.selectedID != id { try await Task.sleep(for: .milliseconds(10)) }
        try #require(controller.overviewView?.selectedID == id)
        controller.applyDocument(title: "Original", body: "Pending 中文 edits", tags: [])
        controller.markDirty()
        let before = try store.loadOverview()
        switch entry {
        case "rail":
            let button = try #require(controller.window?.contentView?.allSubviews.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "OverviewRail-square.and.pencil" })
            button.performClick(nil)
        case "toolbar": controller.newNotePressed()
        case "tab": controller.newDocumentTabPressed()
        default: controller.createNewNoteForLibrary()
        }
        #expect(!controller.isShowingOverview)
        #expect(controller.overviewView?.selectedID == nil)
        #expect(controller.regularEditorView?.superview === controller.overviewHost)
        #expect(controller.regularEditorView?.isHidden == false)
        #expect(controller.editorTextView.string.isEmpty)
        #expect(try store.loadNote(at: original).body == "Pending 中文 edits")
        #expect(try store.loadOverview() == before)
        controller.applyDocument(title: "Ordinary", body: "Full editor body", tags: [])
        controller.markDirty()
        let saved = try #require(try controller.saveCurrentNoteForLibrary())
        #expect(saved != original)
        #expect(try store.loadNote(at: saved).body == "Full editor body")
        #expect(try store.loadOverview() == before)
    }

    @Test func overviewNewNoteButtonCreatesOnlyAnInlineCard() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "mudsnote.overview-new." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        _ = try store.saveNewNote(title: "Seed", body: "Unchanged")
        let controller = LibraryWindowController(noteStore: store, onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        controller.showWindowAndFocus()
        controller.showOverview()
        let before = try store.loadOverview().cards.count
        let button = try #require(controller.overviewView?.newNote)
        button.performClick(nil)
        for _ in 0..<100 where controller.overviewView?.selectedID == nil { try await Task.sleep(for: .milliseconds(10)) }
        let id = try #require(controller.overviewView?.selectedID)
        #expect(controller.isShowingOverview)
        #expect(controller.regularEditorView?.superview === controller.overviewView?.cards[id])
        #expect(try store.loadOverview().cards.count == before + 1)
        controller.applyDocument(title: "Inline", body: "Card body", tags: [])
        controller.markDirty()
        controller.toggleOverviewCard(id)
        let url = try #require(controller.overviewState?.cards.first(where: { $0.id == id })?.url)
        #expect(try store.loadNote(at: url).body == "Card body")
    }

    @Test(arguments: [false, true]) func overviewPointerFeedbackDrawsAndClearsInAWindow(bordered: Bool) throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 250), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let button = OverviewActionButton("", symbol: "house", action: {})
        button.isBordered = bordered
        button.frame = NSRect(x: 10, y: 10, width: 36, height: 36)
        let card = OverviewCardView(id: UUID(), open: {}, menu: {})
        card.frame = NSRect(x: 60, y: 10, width: 300, height: 180)
        window.contentView?.addSubview(button)
        window.contentView?.addSubview(card)
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        button.updateTrackingAreas(); card.updateTrackingAreas()
        let enter = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        let cardEnter = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: card.convert(NSPoint(x: card.bounds.midX, y: card.bounds.midY), to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 2, trackingNumber: 0, userData: nil))
        let exit = try #require(NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, trackingNumber: 0, userData: nil))
        func pixels() throws -> Data {
            window.displayIfNeeded()
            let bitmap = try #require(button.bitmapImageRepForCachingDisplay(in: button.bounds))
            button.cacheDisplay(in: button.bounds, to: bitmap)
            return try #require(bitmap.representation(using: .png, properties: [:]))
        }
        button.mouseExited(with: exit); card.mouseExited(with: exit)
        let normal = try pixels()
        card.updateLayer()
        let cardNormal = card.layer?.backgroundColor
        button.mouseEntered(with: enter); card.mouseEntered(with: cardEnter)
        #expect(button.isPointerHovered && card.isPointerHovered)
        #expect(try pixels() != normal)
        card.updateLayer()
        #expect(card.layer?.backgroundColor != cardNormal)
        button.mouseEntered(with: cardEnter)
        #expect(!button.isPointerHovered)
        #expect(try pixels() == normal)
        button.mouseExited(with: exit); card.mouseExited(with: exit)
        #expect(!button.isPointerHovered && !card.isPointerHovered)
        #expect(try pixels() == normal)
        card.updateLayer()
        #expect(card.layer?.backgroundColor == cardNormal)
    }
}


extension MarkdownRichEditorTests {
    @Test func codexShellNavigationKeepsOrdinaryPagesAndRestoresOverview() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "mudsnote.codex-shell." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        let first = try store.saveNewNote(title: "Plan", body: "Original")
        let second = try store.saveNewNote(title: "Second", body: "Read me")
        let controller = LibraryWindowController(noteStore: store, onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        controller.showWindowAndFocus(); controller.showOverview()
        let id = try #require(controller.overviewState?.cards.first(where: { $0.url == first })?.id)
        controller.toggleOverviewCard(id)
        for _ in 0..<100 where controller.overviewView?.selectedID != id { try await Task.sleep(for: .milliseconds(10)) }
        controller.pageBackStack.removeAll(); controller.pageForwardStack.removeAll()
        let before = try store.loadOverview()
        controller.applyDocument(title: "Plan", body: "Pending 中文", tags: []); controller.markDirty()
        let note = try #require(controller.sourceCountSnapshot.first(where: { $0.url == second }))
        controller.load(note: note)
        for _ in 0..<100 where controller.isLoadingInitialNote || controller.selectedURL != second { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!controller.isShowingOverview)
        #expect(try store.loadNote(at: first).body == "Pending 中文")
        #expect(try store.loadOverview() == before)
        controller.navigateLibraryBack()
        #expect(controller.isShowingOverview)
        #expect(controller.overviewView?.selectedID == id)
        controller.navigateLibraryForward()
        #expect(!controller.isShowingOverview)
        #expect(controller.selectedURL == second)
        #expect(controller.pageForwardStack.isEmpty)
        controller.showOverview()
        for size in [NSSize(width: 896, height: 580), NSSize(width: 979, height: 728), NSSize(width: 1200, height: 800)] {
            controller.window?.setFrame(NSRect(origin: .zero, size: size), display: true)
            controller.window?.contentView?.layoutSubtreeIfNeeded()
            controller.overviewView?.layoutSubtreeIfNeeded()
            let overview = try #require(controller.overviewView)
            #expect(overview.canvas.bounds.width <= overview.bounds.width + 1)
            #expect(overview.cards.values.allSatisfy { $0.frame.maxX <= overview.canvas.bounds.width + 1 })
        }
        _ = controller.setSourceListVisibleForLibrary(false)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        #expect(controller.navigationRail?.isHiddenOrHasHiddenAncestor == false)
        #expect(controller.sourceListView?.isHiddenOrHasHiddenAncestor == true)
        _ = controller.setSourceListVisibleForLibrary(true)
        let cell = try #require(controller.noteCell(for: note, tableView: controller.tableView) as? LibraryNoteCellView)
        #expect(cell.toolTip?.contains("Read me") == true)
        #expect(!cell.titleLabel.isHidden && !cell.snippetLabel.isHidden && !cell.metaLabel.isHidden)
    }
}

extension MarkdownRichEditorTests {
    @Test func codexShellCriticalControlsStaySingleLineAndUnbordered() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "mudsnote.shell-controls." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        _ = try store.saveNewNote(title: "Fixture", body: "Synthetic only")
        let controller = LibraryWindowController(noteStore: store, onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        controller.showWindowAndFocus(); controller.showOverview()
        let window = try #require(controller.window)
        let button = try #require(window.contentView?.allSubviews.compactMap { $0 as? SidebarNewNoteButton }.first)
        for size in [NSSize(width: 896, height: 580), NSSize(width: 979, height: 728)] {
            window.setFrame(NSRect(origin: .zero, size: size), display: true)
            window.contentView?.layoutSubtreeIfNeeded()
            button.layoutSubtreeIfNeeded()
            #expect(button.bounds.width >= 180)
            #expect(button.label.frame.width >= button.label.intrinsicContentSize.width)
            #expect(button.label.maximumNumberOfLines == 1)
            #expect(button.label.cell?.wraps == false)
            #expect(button.glyph.frame.maxX < button.label.frame.minX)
            let point = button.convert(NSPoint(x: button.label.frame.midX, y: button.label.frame.midY), to: button.superview)
            #expect(button.hitTest(point) === button)
        }
        #expect(button.accessibilityLabel() == "新建笔记")
        let titleItem = try #require(window.toolbar?.items.first { $0.itemIdentifier == LibraryWindowController.pageTitleToolbarItemIdentifier })
        #expect(!titleItem.isBordered && titleItem.isEnabled && !titleItem.autovalidates)
        #expect(titleItem.view === controller.toolbarPageTitle)
        #expect(controller.toolbarPageTitle.bounds.width <= 160)
        #expect(controller.toolbarPageTitle.accessibilityRole() == .staticText)
        #expect(controller.toolbarPageTitle.accessibilityLabel() == "总览")
    }

    @Test func codexShellSidebarActionKeepsHoverAndActivation() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 238, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var count = 0
        let button = SidebarNewNoteButton { count += 1 }
        button.frame = NSRect(x: 12, y: 30, width: 214, height: 32)
        window.contentView?.addSubview(button)
        window.makeKeyAndOrderFront(nil); window.contentView?.layoutSubtreeIfNeeded()
        button.performClick(nil)
        #expect(count == 1)
        let enter = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
        let exit = try #require(NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, trackingNumber: 0, userData: nil))
        func pixels() throws -> Data {
            window.displayIfNeeded()
            let bitmap = try #require(button.bitmapImageRepForCachingDisplay(in: button.bounds))
            button.cacheDisplay(in: button.bounds, to: bitmap)
            return try #require(bitmap.representation(using: .png, properties: [:]))
        }
        button.mouseExited(with: exit)
        let normal = try pixels()
        button.mouseEntered(with: enter)
        #expect(button.isPointerHovered)
        #expect(try pixels() != normal)
        button.mouseExited(with: exit)
        #expect(!button.isPointerHovered)
        #expect(try pixels() == normal)
    }
}
