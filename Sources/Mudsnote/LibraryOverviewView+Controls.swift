import AppKit
import MudsnoteCore

@MainActor final class OverviewZoomController: NSViewController {
    weak var overview: LibraryOverviewView?
    let slider = NSSlider(value: 100, minValue: 20, maxValue: 400, target: nil, action: nil)
    init(overview: LibraryOverviewView) { self.overview = overview; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() {
        let container = OverviewRailView(frame: NSRect(x: 0, y: 0, width: 244, height: 44))
        container.appearance = NSAppearance(named: .aqua)
        let center = OverviewActionButton("", symbol: "scope") { [weak overview] in overview?.centerRoot() }
        let minus = OverviewActionButton("", symbol: "minus.magnifyingglass") { [weak self] in self?.overview?.changeZoom(by: -0.1); self?.sync() }
        let plus = OverviewActionButton("", symbol: "plus.magnifyingglass") { [weak self] in self?.overview?.changeZoom(by: 0.1); self?.sync() }
        for (button, label) in [(center, "定位到中心主题"), (minus, "缩小"), (plus, "放大")] {
            button.setAccessibilityLabel(label); button.toolTip = label; container.addSubview(button)
        }
        center.frame = NSRect(x: 8, y: 8, width: 28, height: 28)
        minus.frame = NSRect(x: 44, y: 8, width: 28, height: 28)
        plus.frame = NSRect(x: 208, y: 8, width: 28, height: 28)
        slider.frame = NSRect(x: 80, y: 10, width: 120, height: 24)
        slider.isContinuous = true; slider.target = self; slider.action = #selector(changed)
        slider.setAccessibilityLabel("导图缩放比例")
        container.addSubview(slider); view = container
        preferredContentSize = container.frame.size; sync()
    }
    func sync() { slider.doubleValue = Double((overview?.scroll.magnification ?? 1) * 100) }
    @objc func changed() { overview?.setZoom(CGFloat(slider.doubleValue) / 100) }
}

extension LibraryOverviewView {
    func setPresentation(_ next: OverviewPresentation) {
        guard presentation != next, owner?.commitOverviewEditor() == true else { return }
        presentation = next; owner?.noteStore.libraryOverviewModeRawValue = next.rawValue
        zoomPopover.close()
        scroll.magnification = 1; scroll.allowsMagnification = next == .mindMap
        scroll.hasHorizontalScroller = next == .mindMap
        updatePresentationChrome(); applyAppearance(); needsLayout = true; layoutSubtreeIfNeeded()
        if let selectedID {
            revealCard(selectedID)
            if let owner { window?.makeFirstResponder(owner.editorTextView) }
        } else { resetViewport() }
    }
    func setOverviewAppearance(_ mode: OverviewAppearance) {
        appearanceMode = mode; owner?.noteStore.libraryOverviewAppearanceRawValue = mode.rawValue
        applyAppearance(); updateBreadcrumbs()
    }
    func setMapStyle(_ style: OverviewMapStyle) {
        mapStyle = style; owner?.noteStore.libraryOverviewMapStyleRawValue = style.rawValue
        applyAppearance()
    }
    func setStructure(_ structure: OverviewMapStructure) {
        mapStructure = structure; owner?.noteStore.libraryOverviewMapStructureRawValue = structure.rawValue
        needsLayout = true; layoutSubtreeIfNeeded(); centerRoot()
    }
    func showAppearanceMenu() {
        let menu = NSMenu(); menu.autoenablesItems = false
        let appearance = NSMenuItem(title: "外观", action: nil, keyEquivalent: "")
        let choices = NSMenu()
        for (mode, label) in [(OverviewAppearance.light, "浅色"), (.dark, "深色"), (.system, "跟随系统")] {
            let item = OverviewMenuItem(label) { [weak self] in self?.setOverviewAppearance(mode) }
            item.state = appearanceMode == mode ? .on : .off; choices.addItem(item)
        }
        appearance.submenu = choices; menu.addItem(appearance)
        menu.addItem(.separator())
        menu.addItem(OverviewMenuItem("展开全部") { [weak self] in self?.collapsed.removeAll(); self?.needsLayout = true })
        menu.addItem(OverviewMenuItem("折叠全部") { [weak self] in
            guard let self, self.prepareStructureChange() else { return }
            self.collapsed = Set(OverviewTree(self.state).children.keys.filter { $0 != self.focusedRoot })
            self.needsLayout = true
        })
        if focusedRoot != .root { menu.addItem(OverviewMenuItem("返回总览") { [weak self] in self?.focus(.root) }) }
        menu.addItem(.separator())
        let undo = OverviewMenuItem("撤销") { [weak self] in self?.structuralUndo.undo() }
        undo.isEnabled = structuralUndo.canUndo; menu.addItem(undo)
        let redo = OverviewMenuItem("重做") { [weak self] in self?.structuralUndo.redo() }
        redo.isEnabled = structuralUndo.canRedo; menu.addItem(redo)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: appearanceButton.bounds.maxY), in: appearanceButton)
    }
    func showPaletteMenu() {
        let menu = NSMenu()
        for (style, label) in [(OverviewMapStyle.ink, "墨稿 · 浅色"), (.focus, "焦点 · 深色")] {
            let item = OverviewMenuItem(label) { [weak self] in self?.setMapStyle(style) }
            item.state = mapStyle == style ? .on : .off; menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: paletteButton.bounds.maxY), in: paletteButton)
    }
    func showStructureMenu() {
        let menu = NSMenu()
        for (structure, label) in [(OverviewMapStructure.balanced, "思维导图 · 左右展开"), (.right, "逻辑图 · 向右展开")] {
            let item = OverviewMenuItem(label) { [weak self] in self?.setStructure(structure) }
            item.state = mapStructure == structure ? .on : .off; menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: structureButton.bounds.maxY), in: structureButton)
    }
    func showZoomPopover() {
        if zoomPopover.isShown { zoomPopover.close(); return }
        let controller = OverviewZoomController(overview: self)
        zoomPopover.contentViewController = controller
        zoomPopover.behavior = .transient; zoomPopover.animates = false
        zoomPopover.show(relativeTo: zoomValue.bounds, of: zoomValue, preferredEdge: .minX)
    }
    func changeZoom(by delta: CGFloat) { setZoom(scroll.magnification + delta) }
    func setZoom(_ value: CGFloat) {
        scroll.magnification = min(scroll.maxMagnification, max(scroll.minMagnification, value))
        updateZoomValue()
    }
    func centerRoot() {
        guard presentation == .mindMap, let root = plan?.frames[focusedRoot] else { return }
        let clip = scroll.contentView
        clip.scroll(to: NSPoint(x: root.midX - clip.bounds.width / 2, y: root.midY - clip.bounds.height / 2))
        scroll.reflectScrolledClipView(clip); updateZoomValue()
    }
    func resetViewport() {
        guard selectedID == nil else { return }
        if presentation == .mindMap { centerRoot() }
        else { scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView) }
    }
    func fitToWindow() {
        guard presentation == .mindMap, let content = plan?.contentBounds else { return }
        let viewport = scroll.contentView.frame.size
        setZoom(min(1, min(viewport.width / (content.width + 96), viewport.height / (content.height + 96))))
        let clip = scroll.contentView
        clip.scroll(to: NSPoint(x: content.midX - clip.bounds.width / 2, y: content.midY - clip.bounds.height / 2))
        scroll.reflectScrolledClipView(clip)
    }
    func toggleBranch(_ node: OverviewNodeID) {
        guard node != focusedRoot, commitTopicEditing() else { return }
        if !collapsed.contains(node), let selectedID, OverviewTree(state).ancestors(of: .card(selectedID)).contains(node) {
            owner?.toggleOverviewCard(selectedID)
            guard self.selectedID == nil else { return }
        }
        owner?.cancelActiveNoteLoad()
        if !collapsed.insert(node).inserted { collapsed.remove(node) }
        activeNode = node; needsLayout = true; layoutSubtreeIfNeeded()
    }
    func revealCard(_ id: UUID) {
        let tree = OverviewTree(state)
        let ancestors = tree.ancestors(of: .card(id))
        if focusedRoot != .root && !ancestors.contains(focusedRoot) { focusedRoot = .root; updateBreadcrumbs() }
        for ancestor in ancestors { collapsed.remove(ancestor) }
        activeNode = .card(id)
        scroll.magnification = 1; updateZoomValue()
        if let editor = owner?.regularEditorView { prepareEditorAppearance(editor) }
        needsLayout = true; layoutSubtreeIfNeeded()
        cards[id]?.scrollToVisible(cards[id]?.bounds ?? .zero)
    }

    func showTopicMenu(_ node: OverviewNodeID) {
        guard select(node) else { return }
        if case .card(let id) = node { owner?.overviewCardMenu(id); return }
        let menu = NSMenu(); menu.autoenablesItems = false
        if node != .unassigned {
            menu.addItem(OverviewMenuItem("编辑主题") { [weak self] in self?.beginTopicEdit(node) })
            menu.addItem(OverviewMenuItem("编辑描述") { [weak self] in self?.beginTopicEdit(node, details: true) })
            menu.addItem(OverviewMenuItem("添加子主题") { [weak self] in self?.createTopic(parent: node) })
            if node != focusedRoot { menu.addItem(OverviewMenuItem("添加同级主题") { [weak self] in self?.createSibling(of: node) }) }
        }
        menu.addItem(OverviewMenuItem("关联笔记…") { [weak self] in
            let area: UUID? = { if case .area(let id) = node { return id }; return nil }()
            self?.owner?.pickOverviewNote(area: area, connecting: nil)
        })
        if node != focusedRoot {
            menu.addItem(.separator())
            menu.addItem(OverviewMenuItem("进入主题") { [weak self] in self?.focus(node) })
            if OverviewTree(state).children[node]?.isEmpty == false {
                menu.addItem(OverviewMenuItem(collapsed.contains(node) ? "展开主题" : "折叠主题") { [weak self] in self?.toggleBranch(node) })
            }
            if node != .unassigned {
                menu.addItem(.separator())
                menu.addItem(OverviewMenuItem("从总览移除整支，保留笔记") { [weak self] in self?.removeTopic(node) })
            }
        }
        let host = node == focusedRoot ? rootHost : hosts[node]
        guard let host else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: host.contentRect.minX, y: host.contentRect.midY), in: host)
    }

    // Only the shared editor currently embedded in overview gets this override.
    // Restore its original AppKit appearance and layer colors before reparenting.
    func prepareEditorAppearance(_ editor: NSView) {
        restoreEditorAppearance()
        overriddenEditor = editor; editorAppearance = editor.appearance
        editor.appearance = NSAppearance(named: presentation == .mindMap ? (mapStyle == .ink ? .aqua : .darkAqua) : colors.dark ? .darkAqua : .aqua)
        let background = presentation == .outline ? colors.outlineBackground : colors.mapBackground
        var stack = [editor]
        while let view = stack.popLast() {
            stack.append(contentsOf: view.subviews)
            if let clip = view as? NSClipView { editorClips.append((clip, clip.backgroundColor)); clip.backgroundColor = background }
            if let layer = view.layer, let color = layer.backgroundColor,
               color == LibraryNotesPalette.editorBackground.cgColor || color == LibraryNotesPalette.cardBackground.cgColor {
                editorLayers.append((view, color)); layer.backgroundColor = background.cgColor
            }
        }
    }
    func restoreEditorAppearance() {
        overriddenEditor?.appearance = editorAppearance
        for (view, color) in editorLayers { view.layer?.backgroundColor = color }
        for (view, color) in editorClips { view.backgroundColor = color }
        editorLayers.removeAll(); editorClips.removeAll(); overriddenEditor = nil; editorAppearance = nil
    }
}
