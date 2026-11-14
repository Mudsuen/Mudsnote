import AppKit
import MudsnoteCore

@MainActor final class LibraryWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let owner = windowController as? LibraryWindowController,
           owner.isShowingOverview,
           owner.overviewView?.performKeyEquivalent(with: event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor final class OverviewRailView: NSView { override var isFlipped: Bool { true } }

@MainActor final class OverviewContentHost: NSView {
    override var isFlipped: Bool { true }
    weak var owner: LibraryWindowController?
    override func layout() {
        super.layout()
        guard let owner else { return }
        if owner.isShowingOverview {
            let inset = safeAreaInsets.top
            owner.overviewView?.frame = NSRect(x: 0, y: inset, width: bounds.width, height: max(0, bounds.height - inset))
        }
        else { owner.regularEditorView?.frame = bounds }
    }
}

@MainActor final class OverviewMenuItem: NSMenuItem {
    var invoke: () -> Void
    init(_ title: String, invoke: @escaping () -> Void) {
        self.invoke = invoke
        super.init(title: title, action: #selector(pressed), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc func pressed() {
        // Let AppKit finish restoring menu focus before opening an inline editor.
        let action = invoke
        DispatchQueue.main.async { action() }
    }
}

extension LibraryWindowController {
    func buildOverviewHost(editor: NSView) -> NSView {
        regularEditorView = editor
        let host = OverviewContentHost()
        host.owner = self
        host.wantsLayer = true
        host.layer?.backgroundColor = LibraryNotesPalette.windowBackground.cgColor
        overviewHost = host
        editor.translatesAutoresizingMaskIntoConstraints = true
        host.addSubview(editor)
        return host
    }

    func buildOverviewRail() -> NSView {
        let rail = LibraryNavigationRail()
        rail.identifier = NSUserInterfaceItemIdentifier("LibraryNavigationRail")
        navigationRail = rail
        let actions: [(String, String, () -> Void)] = [
            ("总览", "house", { [weak self] in self?.showOverview() }),
            ("最近笔记", "clock", { [weak self] in
                self?.showLibraryNavigationPage(.list, scope: .recent)
            }),
            ("目录", "folder", { [weak self] in
                self?.showLibraryNavigationPage(.tree, scope: .all)
            }),
            ("标签", "number", { [weak self] in
                self?.showLibraryNavigationPage(.tags, scope: .all)
            })
        ]
        for item in actions {
            let button = LibraryRailButton(title: item.0, symbol: item.1, action: item.2)
            button.identifier = NSUserInterfaceItemIdentifier("OverviewRail-" + item.1)
            rail.buttons.append((item.0, button)); rail.addSubview(button)
        }
        let settings = LibraryRailButton(title: "设置", symbol: "ellipsis") {
            if let item = NSApp.mainMenu?.items.first?.submenu?.items.first(where: { $0.title.hasPrefix("设置") }), let selector = item.action {
                NSApp.sendAction(selector, to: item.target, from: item)
            }
        }
        rail.settings = settings; rail.addSubview(settings)
        return rail
    }

    func showLibraryNavigationPage(_ presentation: LibrarySidebarPresentation, scope: LibraryScope) {
        if !isShowingOverview, sidebarPresentation == presentation, selectedScope == scope,
           isSourceListVisibleForLibrary, searchField.stringValue.isEmpty,
           !(presentation == .tags && sourceTagsSectionCollapsed) {
            resumeSelectedNoteLoadIfNeeded()
            return
        }
        guard beginLibraryPageNavigation(), leaveOverview() else { return }
        let wasRestoring = isRestoringLibraryPage
        isRestoringLibraryPage = true
        defer { isRestoringLibraryPage = wasRestoring }
        _ = clearSearchFromKeyboard(reload: false)
        setSidebarSearchPresented(false)
        if presentation == .tags {
            sourceTagsSectionCollapsed = false
            noteStore.libraryTagsSectionCollapsed = false
        }
        guard activateSourceScope(scope, presentation: presentation) else { return }
        _ = setSourceListVisibleForLibrary(true)
        if presentation == .tags {
            if let tags = sourceOutlineItemsByIdentifier["group:tags"] {
                sourceOutlineView.expandItem(tags)
            }
            scheduleDeferredSourceTagLoad()
        }
        updateSidebarScopeButton()
        revealSelectedNoteInBrowser()
    }

    @objc func showOverview() {
        if !isShowingOverview, !beginLibraryPageNavigation() { return }
        guard commitOverviewEditor() else { return }
        if overviewState == nil {
            do { overviewState = try noteStore.loadOverview() }
            catch { presentErrorAlert(message: "无法读取总览", details: error.localizedDescription); return }
        }
        if overviewView == nil, let host = overviewHost {
            let overview = LibraryOverviewView(owner: self)
            overviewView = overview
            host.addSubview(overview)
        }
        cancelActiveNoteLoad()
        if let id = overviewView?.selectedID { overviewView?.cards[id]?.embed(nil) }
        overviewView?.selectedID = nil
        overviewView?.activeNode = nil
        if let editor = regularEditorView { overviewHost?.addSubview(editor) }
        isShowingOverview = true
        updateDocumentTabBar()
        _ = clearSearchFromKeyboard(reload: false)
        setSidebarSearchPresented(false)
        _ = setSourceListVisibleForLibrary(false)
        overviewView?.isHidden = false
        if overviewView?.selectedID == nil { regularEditorView?.isHidden = true }
        setSidebarPresentation(.list, animated: false)
        selectedScope = .all
        lastListScope = .all
        reloadNotes(loadFirstIfNeeded: false, refreshCounts: false)
        if overviewState?.seeded != true, !sourceCountSnapshot.isEmpty {
            _ = changeOverview { state in
                if state.cards.isEmpty {
                    for note in sourceCountSnapshot.sorted(by: { $0.modifiedAt > $1.modifiedAt }).prefix(4) {
                        _ = state.add(note.url, areaID: state.areas.first(where: { note.tags.contains($0.title) || note.url.deletingLastPathComponent().lastPathComponent == $0.title })?.id)
                    }
                }
                state.seeded = true
            }
        }
        refreshOverview()
        overviewHost?.needsLayout = true
        window?.contentView?.layoutSubtreeIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isShowingOverview, let overview = self.overviewView,
                  overview.activeNode == nil else { return }
            self.overviewHost?.layoutSubtreeIfNeeded()
            overview.resetViewport()
        }
    }

    @discardableResult func commitOverviewEditor() -> Bool {
        guard overviewView?.commitTopicEditing() != false else { return false }
        // A read-only overview has no embedded editor to serialize or drain.
        guard !isShowingOverview || overviewView?.selectedID != nil else { return true }
        // End input-method composition before serializing the shared editor.
        if let responder = window?.firstResponder as? NSView,
           let editor = regularEditorView,
           responder === editor || responder.isDescendant(of: editor) {
            window?.makeFirstResponder(nil)
        }
        do { drainBackgroundAutosaves(); try saveCurrentNoteIfNeeded(); return true }
        catch { presentErrorAlert(message: "无法保存笔记", details: error.localizedDescription); return false }
    }

    @discardableResult func leaveOverview() -> Bool {
        guard isShowingOverview else { return true }
        guard commitOverviewEditor() else { return false }
        overviewView?.restoreEditorAppearance()
        overviewView?.finishCardTransition()
        cancelActiveNoteLoad()
        if let id = overviewView?.selectedID { overviewView?.cards[id]?.embed(nil) }
        overviewView?.selectedID = nil
        isShowingOverview = false
        updateSidebarScopeButton()
        updateDocumentTabBar()
        overviewView?.isHidden = true
        if let editor = regularEditorView, let host = overviewHost {
            editor.removeFromSuperview(); host.addSubview(editor); editor.isHidden = false
        }
        overviewHost?.needsLayout = true
        return true
    }

    func refreshOverview() {
        guard let state = overviewState else { return }
        overviewView?.update(state, notes: sourceCountSnapshot)
    }

    @discardableResult func changeOverview(_ change: (inout NoteOverview) -> Void) -> Bool {
        guard var next = overviewState else { return false }
        let previous = next
        change(&next)
        do { try noteStore.saveOverview(next) }
        catch { presentErrorAlert(message: "无法保存总览", details: error.localizedDescription); return false }
        overviewState = next
        if next != previous { overviewView?.recordChange(from: previous) }
        refreshOverview()
        return true
    }

    func toggleOverviewCard(_ id: UUID) {
        guard let card = overviewState?.cards.first(where: { $0.id == id }) else { return }
        if overviewView?.selectedID == id {
            guard commitOverviewEditor() else { return }
            overviewView?.restoreEditorAppearance()
            overviewView?.cards[id]?.embed(nil)
            overviewView?.selectedID = nil
            updateDocumentTabBar()
            regularEditorView?.isHidden = true
            if let editor = regularEditorView { overviewHost?.addSubview(editor) }
            overviewView?.invalidatePreview(id)
            refreshOverview()
            return
        }
        let note = sourceCountSnapshot.first { $0.url.standardizedFileURL == card.url.standardizedFileURL }
            ?? NoteSearchResult(url: card.url, title: card.url.deletingPathExtension().lastPathComponent, snippet: "", modifiedAt: Date())
        openOverviewNote(note)
    }

    func openOverviewNote(_ note: NoteSearchResult) {
        guard commitOverviewEditor(), regularEditorView != nil else { return }
        overviewView?.finishCardTransition()
        cancelActiveNoteLoad()
        let generation = noteLoadGeneration
        let revision = editorContentRevision
        let loader = noteLoader
        noteLoadTask = Task { [weak self] in
            let result = await Task.detached { Result { try loader(note.url) } }.value
            guard !Task.isCancelled, let self, self.isShowingOverview, generation == self.noteLoadGeneration, revision == self.editorContentRevision else { return }
            self.noteLoadTask = nil
            switch result {
            case .failure(let error): self.presentErrorAlert(message: "无法打开笔记", details: error.localizedDescription)
            case .success(let loaded): _ = self.finishOpeningOverviewNote(note, loaded: loaded)
            }
        }
    }

    @discardableResult func finishOpeningOverviewNote(_ note: NoteSearchResult, loaded: LoadedLibraryNote) -> Bool {
        guard let editor = regularEditorView,
              changeOverview({ _ = $0.add(note.url) }),
              let id = overviewState?.cards.first(where: { $0.url.standardizedFileURL == note.url.standardizedFileURL })?.id else { return false }
        if let old = overviewView?.selectedID { overviewView?.cards[old]?.embed(nil) }
        isLoadingInitialNote = false; isCreatingNewNote = false
        applyLoadedNoteResult(.success(loaded), for: note)
        overviewView?.selectedID = id
        updateDocumentTabBar()
        editor.isHidden = false
        overviewView?.cards[id]?.embed(editor)
        overviewView?.revealCard(id)
        // The shared editor was measured in the previous pane. Finish its new
        // card layout before revealing the caret or accepting text input.
        editor.layoutSubtreeIfNeeded()
        layoutEditorStatusLabel()
        editorTextView.scrollRangeToVisible(editorTextView.selectedRange())
        window?.makeFirstResponder(editorTextView)
        return true
    }

    func createNoteInOverview(area: UUID? = nil, position: NoteOverview.MapPosition? = nil) {
        guard isShowingOverview else { return }
        guard commitOverviewEditor() else { return }
        do {
            let url = try noteStore.saveNewNote(title: "", body: "", in: noteStore.notesDirectory)
            if area != nil || position != nil {
                guard changeOverview({ state in
                    let id = state.add(url, areaID: area)
                    if let index = state.cards.firstIndex(where: { $0.id == id }) { state.cards[index].mapPosition = position }
                }) else { return }
            }
            let note = NoteSearchResult(url: url, title: "未命名笔记", snippet: "", modifiedAt: Date())
            openOverviewNote(note)
        } catch { presentErrorAlert(message: "无法新建笔记", details: error.localizedDescription) }
    }

    func editOverviewPrinciples() {
        guard let state = overviewState else { return }
        if let value = overviewTextPrompt(title: "宗旨", value: state.principles) { _ = changeOverview { $0.principles = value } }
    }

    func editOverviewArea(_ parent: UUID?) {
        if let value = overviewTextPrompt(title: parent == nil ? "添加领域" : "添加子领域", value: ""), !value.isEmpty {
            _ = changeOverview { $0.areas.append(.init(title: value, parentID: parent)) }
        }
    }

    func overviewTextPrompt(title: String, value: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(string: value)
        field.frame = NSRect(x: 0, y: 0, width: 360, height: 28)
        alert.accessoryView = field
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func pickOverviewNote(area: UUID?, connecting: UUID?, position: NoteOverview.MapPosition? = nil) {
        let candidates = sourceCountSnapshot.sorted { $0.modifiedAt > $1.modifiedAt }
        let alert = NSAlert()
        alert.messageText = connecting == nil ? "添加笔记到总览" : "关联笔记"
        let picker = NSComboBox(frame: NSRect(x: 0, y: 0, width: 440, height: 28))
        let labels = candidates.map { $0.title + " — " + $0.url.lastPathComponent }
        picker.addItems(withObjectValues: labels)
        picker.completes = true
        picker.numberOfVisibleItems = 14
        alert.accessoryView = picker
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = picker
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let exactLabels = labels.indices.filter { labels[$0] == picker.stringValue }
        let exactLabel = exactLabels.count == 1 ? exactLabels[0] : nil
        let matchingTitles = candidates.indices.filter { candidates[$0].title == picker.stringValue }
        let index = picker.indexOfSelectedItem >= 0 ? picker.indexOfSelectedItem
            : exactLabel ?? (matchingTitles.count == 1 ? matchingTitles[0] : -1)
        guard candidates.indices.contains(index) else { presentErrorAlert(message: "请选择一篇笔记", details: "从列表中选择要关联的笔记。"); return }
        _ = changeOverview {
            let id = $0.add(candidates[index].url, areaID: area)
            if let position, let index = $0.cards.firstIndex(where: { $0.id == id }) { $0.cards[index].mapPosition = position }
            if let connecting { $0.connect(connecting, id) }
        }
    }

    func overviewAreaMenu(_ id: UUID) {
        guard let area = overviewState?.areas.first(where: { $0.id == id }), let anchor = overviewView?.areas[id] else { return }
        let menu = NSMenu()
        menu.addItem(OverviewMenuItem("添加笔记") { [weak self] in self?.pickOverviewNote(area: id, connecting: nil) })
        menu.addItem(OverviewMenuItem("添加子领域") { [weak self] in self?.editOverviewArea(id) })
        menu.addItem(OverviewMenuItem("重命名") { [weak self] in
            guard let self, let title = self.overviewTextPrompt(title: "领域名称", value: area.title), !title.isEmpty else { return }
            _ = self.changeOverview { state in if let index = state.areas.firstIndex(where: { $0.id == id }) { state.areas[index].title = title } }
        })
        menu.addItem(OverviewMenuItem("移除领域，保留笔记") { [weak self] in
            _ = self?.changeOverview { state in
                state.areas.removeAll { $0.id == id }
                for i in state.areas.indices where state.areas[i].parentID == id { state.areas[i].parentID = nil }
                for i in state.cards.indices where state.cards[i].areaID == id { state.cards[i].areaID = nil }
            }
        })
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.bounds.maxY), in: anchor)
    }

    func overviewCardMenu(_ id: UUID) {
        guard let state = overviewState, let anchor = overviewView?.cards[id] else { return }
        let menu = NSMenu()
        menu.addItem(OverviewMenuItem(overviewView?.selectedID == id ? "收起笔记" : "编辑笔记") { [weak self] in self?.toggleOverviewCard(id) })
        if let url = state.cards.first(where: { $0.id == id })?.url {
            menu.addItem(OverviewMenuItem("查看局部图谱") { [weak self] in self?.showOverviewKnowledgeGraph(focusedOn: url) })
        }
        menu.addItem(OverviewMenuItem("关联笔记…") { [weak self] in self?.pickOverviewNote(area: nil, connecting: id) })
        let areaItem = NSMenuItem(title: "归属", action: nil, keyEquivalent: "")
        let areaMenu = NSMenu()
        let currentArea = state.cards.first { $0.id == id }?.areaID
        let unassigned = OverviewMenuItem("未归属") { [weak self] in
            _ = self?.changeOverview { state in if let index = state.cards.firstIndex(where: { $0.id == id }) { state.cards[index].areaID = nil } }
        }
        unassigned.state = currentArea == nil ? .on : .off; areaMenu.addItem(unassigned)
        let tree = OverviewTree(state)
        for area in state.areas {
            let path = tree.ancestors(of: .area(area.id)).reversed().compactMap { node -> String? in
                if case .area(let id) = node { return state.areas.first { $0.id == id }?.title }; return nil
            } + [area.title]
            let item = OverviewMenuItem(path.joined(separator: " / ")) { [weak self] in
                _ = self?.changeOverview { state in if let index = state.cards.firstIndex(where: { $0.id == id }) { state.cards[index].areaID = area.id } }
            }
            item.state = currentArea == area.id ? .on : .off; areaMenu.addItem(item)
        }
        areaItem.submenu = areaMenu; menu.addItem(areaItem)
        for edge in state.connections where edge.from == id || edge.to == id {
            let other = edge.from == id ? edge.to : edge.from
            let name = state.cards.first { $0.id == other }?.url.deletingPathExtension().lastPathComponent ?? "笔记"
            menu.addItem(OverviewMenuItem("取消关联：" + name) { [weak self] in _ = self?.changeOverview { $0.connections.removeAll { $0 == edge } } })
        }
        menu.addItem(OverviewMenuItem("从总览移除，保留笔记") { [weak self] in
            guard let self, self.commitOverviewEditor() else { return }
            if self.overviewView?.selectedID == id { self.toggleOverviewCard(id) }
            _ = self.changeOverview { $0.removeCard(id) }
        })
        if let event = NSApp.currentEvent, event.type == .rightMouseDown {
            NSMenu.popUpContextMenu(menu, with: event, for: anchor)
        } else { menu.popUp(positioning: nil, at: NSPoint(x: anchor.bounds.width - 130, y: anchor.bounds.height - 32), in: anchor) }
    }

    func remapOverviewAfterSave(previousURL: URL?, savedURL: URL) {
        guard let previousURL, var state = overviewState,
              let id = state.cards.first(where: { $0.url.standardizedFileURL == previousURL.standardizedFileURL })?.id else { return }
        if previousURL.standardizedFileURL != savedURL.standardizedFileURL {
            state.remap(previousURL, to: savedURL)
            do { try noteStore.saveOverview(state); overviewState = state }
            catch { presentErrorAlert(message: "笔记已保存，总览位置未更新", details: error.localizedDescription) }
        }
        overviewView?.invalidatePreview(id)
        refreshOverview()
    }
}
