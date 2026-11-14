import AppKit
import MudsnoteCore

@MainActor final class OverviewViewportControls: NSStackView {
    let zoomOut = OverviewActionButton("", symbol: "minus", action: {})
    let zoomValue = OverviewActionButton("100%", action: {})
    let zoomIn = OverviewActionButton("", symbol: "plus", action: {})
    let fit = OverviewActionButton("", symbol: "arrow.up.left.and.arrow.down.right", action: {})
    let center = OverviewActionButton("", symbol: "scope", action: {})

    init() {
        super.init(frame: .zero)
        orientation = .horizontal; alignment = .centerY; spacing = 2
        edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        wantsLayer = true; layer?.cornerRadius = 8; layer?.borderWidth = 1
        identifier = NSUserInterfaceItemIdentifier("OverviewViewportControls")
        for (button, label, width) in [(zoomOut, "缩小", 26.0), (zoomValue, "缩放比例", 48.0),
                                       (zoomIn, "放大", 26.0), (fit, "适应全部内容", 28.0), (center, "回到中心主题", 28.0)] {
            button.setAccessibilityLabel(label); button.toolTip = label
            addArrangedSubview(button)
            button.widthAnchor.constraint(equalToConstant: width).isActive = true
            button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        }
        zoomValue.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    }
    required init?(coder: NSCoder) { fatalError() }

    func bind(to overview: LibraryOverviewView) {
        zoomOut.invoke = { [weak overview] in overview?.changeZoom(by: -0.1) }
        zoomValue.invoke = { [weak overview] in overview?.showZoomPopover() }
        zoomIn.invoke = { [weak overview] in overview?.changeZoom(by: 0.1) }
        fit.invoke = { [weak overview] in overview?.fitToWindow() }
        center.invoke = { [weak overview] in overview?.centerRoot() }
    }

    func sync(overview: LibraryOverviewView) {
        isHidden = overview.presentation != .mindMap
        let scroll = overview.scroll
        let label = "\(Int((scroll.magnification * 100).rounded()))%"
        if zoomValue.title != label { zoomValue.title = label }
        zoomValue.setAccessibilityValue(label)
        zoomOut.isEnabled = scroll.magnification > scroll.minMagnification + 0.001
        zoomIn.isEnabled = scroll.magnification < scroll.maxMagnification - 0.001
        let colors = overview.colors
        layer?.backgroundColor = colors.outlineBackground.cgColor
        layer?.borderColor = colors.guide.cgColor
        for button in [zoomOut, zoomValue, zoomIn, fit, center] { button.contentTintColor = colors.text }
    }
}

@MainActor final class OverviewZoomController: NSViewController {
    weak var overview: LibraryOverviewView?
    let slider = NSSlider(value: 100, minValue: 20, maxValue: 400, target: nil, action: nil)
    let valueLabel = NSTextField(labelWithString: "100%")
    init(overview: LibraryOverviewView) { self.overview = overview; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() {
        let container = OverviewRailView(frame: NSRect(x: 0, y: 0, width: 296, height: 44))
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        let center = OverviewActionButton("", symbol: "scope") { [weak overview] in overview?.centerRoot() }
        let minus = OverviewActionButton("", symbol: "minus.magnifyingglass") { [weak self] in self?.overview?.changeZoom(by: -0.1); self?.sync() }
        let plus = OverviewActionButton("", symbol: "plus.magnifyingglass") { [weak self] in self?.overview?.changeZoom(by: 0.1); self?.sync() }
        for (button, label) in [(center, "定位到中心主题"), (minus, "缩小"), (plus, "放大")] {
            button.setAccessibilityLabel(label); button.toolTip = label; container.addSubview(button)
        }
        center.frame = NSRect(x: 8, y: 8, width: 28, height: 28)
        minus.frame = NSRect(x: 44, y: 8, width: 28, height: 28)
        plus.frame = NSRect(x: 260, y: 8, width: 28, height: 28)
        slider.frame = NSRect(x: 80, y: 10, width: 120, height: 24)
        slider.isContinuous = true; slider.target = self; slider.action = #selector(changed)
        slider.setAccessibilityLabel("导图缩放比例")
        valueLabel.frame = NSRect(x: 204, y: 14, width: 52, height: 18)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.alignment = .center
        valueLabel.setAccessibilityLabel("当前缩放比例")
        container.addSubview(valueLabel)
        container.addSubview(slider); view = container
        preferredContentSize = container.frame.size; sync()
    }
    func sync() {
        slider.doubleValue = Double((overview?.scroll.magnification ?? 1) * 100)
        valueLabel.stringValue = "\(Int(slider.doubleValue.rounded()))%"
    }
    @objc func changed() { overview?.setZoom(CGFloat(slider.doubleValue) / 100); sync() }
}

extension LibraryOverviewView {
    func setPresentation(_ next: OverviewPresentation) {
        guard presentation != next, owner?.commitOverviewEditor() == true else { return }
        finishCardTransition()
        presentation = next; owner?.noteStore.libraryOverviewModeRawValue = next.rawValue
        zoomPopover.close()
        scroll.magnification = 1; scroll.allowsMagnification = next == .mindMap
        scroll.hasHorizontalScroller = false; scroll.hasVerticalScroller = next == .outline
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
    func setStructure(_ structure: OverviewMapStructure) {
        mapStructure = structure; owner?.noteStore.libraryOverviewMapStructureRawValue = structure.rawValue
        needsLayout = true; layoutSubtreeIfNeeded(); centerRoot()
    }
    func showSettingsMenu() { showControlMenu(makeSettingsMenu(), from: appearanceButton) }
    func makeSettingsMenu() -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        let appearance = NSMenuItem(title: "外观", action: nil, keyEquivalent: "")
        let choices = NSMenu()
        for (mode, label) in [(OverviewAppearance.light, "浅色"), (.dark, "深色"), (.system, "跟随系统")] {
            let item = OverviewMenuItem(label) { [weak self] in self?.setOverviewAppearance(mode) }
            item.state = appearanceMode == mode ? .on : .off; choices.addItem(item)
        }
        appearance.submenu = choices; menu.addItem(appearance)
        if presentation == .mindMap {
            let percent = Int((scroll.magnification * 100).rounded())
            menu.addItem(OverviewMenuItem("缩放（\(percent)%）…") { [weak self] in self?.showZoomPopover() })
            let structure = NSMenuItem(title: "导图结构", action: nil, keyEquivalent: "")
            structure.submenu = makeStructureMenu(); menu.addItem(structure)
        }
        menu.addItem(.separator())
        menu.addItem(OverviewMenuItem("展开全部") { [weak self] in self?.collapsed.removeAll(); self?.needsLayout = true })
        menu.addItem(OverviewMenuItem("折叠全部") { [weak self] in
            guard let self, self.prepareStructureChange() else { return }
            self.collapsed = Set(self.contentIndex.tree.children.keys.filter { $0 != self.focusedRoot })
            self.needsLayout = true
        })
        if focusedRoot != .root { menu.addItem(OverviewMenuItem("返回总览") { [weak self] in self?.focus(.root) }) }
        menu.addItem(.separator())
        let undo = OverviewMenuItem("撤销") { [weak self] in self?.structuralUndo.undo() }
        undo.isEnabled = structuralUndo.canUndo; menu.addItem(undo)
        let redo = OverviewMenuItem("重做") { [weak self] in self?.structuralUndo.redo() }
        redo.isEnabled = structuralUndo.canRedo; menu.addItem(redo)
        return menu
    }
    func makeStructureMenu() -> NSMenu {
        let menu = NSMenu()
        for (structure, label) in [(OverviewMapStructure.balanced, "思维导图 · 左右展开"), (.right, "逻辑图 · 向右展开")] {
            let item = OverviewMenuItem(label) { [weak self] in self?.setStructure(structure) }
            item.state = mapStructure == structure ? .on : .off; menu.addItem(item)
        }
        return menu
    }
    func showControlMenu(_ menu: NSMenu, from button: NSButton) {
        let location = button.convert(NSPoint(x: 0, y: button.bounds.maxY), to: nil)
        if let window = button.window, let event = NSEvent.mouseEvent(
            with: .rightMouseDown, location: location, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        } else {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY), in: button)
        }
    }
    func showZoomPopover() {
        if zoomPopover.isShown { zoomPopover.close(); return }
        let controller = OverviewZoomController(overview: self)
        zoomPopover.contentViewController = controller
        zoomPopover.appearance = effectiveAppearance
        zoomPopover.behavior = .transient; zoomPopover.animates = false
        zoomPopover.show(relativeTo: viewportControls.zoomValue.bounds, of: viewportControls.zoomValue, preferredEdge: .minY)
    }
    func changeZoom(by delta: CGFloat) { setZoom(scroll.magnification + delta) }
    func setZoom(_ value: CGFloat) {
        guard presentation == .mindMap else { return }
        let clip = scroll.contentView
        let offset = plan?.worldOffset ?? .zero
        let worldCenter = CGPoint(x: clip.bounds.midX - offset.x, y: clip.bounds.midY - offset.y)
        updatingViewport = true
        scroll.magnification = min(scroll.maxMagnification, max(scroll.minMagnification, value))
        updatingViewport = false
        centerWorldPoint(worldCenter)
    }
    func centerRoot() {
        guard presentation == .mindMap, let root = plan?.frames[focusedRoot] else { return }
        let offset = plan?.worldOffset ?? .zero
        centerWorldPoint(CGPoint(x: root.midX - offset.x, y: root.midY - offset.y))
    }
    func resetViewport() {
        guard selectedID == nil, cardTransition == nil else { return }
        if presentation == .mindMap { fitToWindow() }
        else { scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView) }
    }
    func fitToWindow() {
        layoutSubtreeIfNeeded()
        guard presentation == .mindMap, let content = plan?.contentBounds else { return }
        let offset = plan?.worldOffset ?? .zero
        let center = CGPoint(x: content.midX - offset.x, y: content.midY - offset.y)
        let viewport = scroll.contentView.frame.size
        setZoom(min(1, min(viewport.width / (content.width + 96), viewport.height / (content.height + 96))))
        centerWorldPoint(center)
    }
    func toggleBranch(_ node: OverviewNodeID) {
        guard node != focusedRoot, commitTopicEditing() else { return }
        finishCardTransition()
        if !collapsed.contains(node), let selectedID, contentIndex.tree.ancestors(of: .card(selectedID)).contains(node) {
            owner?.toggleOverviewCard(selectedID)
            guard self.selectedID == nil else { return }
        }
        owner?.cancelActiveNoteLoad()
        if !collapsed.insert(node).inserted { collapsed.remove(node) }
        activeNode = node; needsLayout = true; layoutSubtreeIfNeeded()
    }
    func revealCard(_ id: UUID) {
        let tree = contentIndex.tree
        let ancestors = tree.ancestors(of: .card(id))
        if focusedRoot != .root && !ancestors.contains(focusedRoot) { focusedRoot = .root; updateBreadcrumbs() }
        for ancestor in ancestors { collapsed.remove(ancestor) }
        activeNode = .card(id)
        setZoom(1)
        if selectedID == id, let editor = owner?.regularEditorView { prepareEditorAppearance(editor) }
        needsLayout = true; layoutSubtreeIfNeeded()
        if presentation == .mindMap, let frame = plan?.frames[.card(id)], let offset = plan?.worldOffset {
            centerWorldPoint(CGPoint(x: frame.midX - offset.x, y: frame.midY - offset.y))
        } else { cards[id]?.scrollToVisible(cards[id]?.bounds ?? .zero) }
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
            if contentIndex.tree.children[node]?.isEmpty == false {
                menu.addItem(OverviewMenuItem(collapsed.contains(node) ? "展开主题" : "折叠主题") { [weak self] in self?.toggleBranch(node) })
            }
            if node != .unassigned {
                menu.addItem(.separator())
                menu.addItem(OverviewMenuItem("从总览移除整支，保留笔记") { [weak self] in self?.removeTopic(node) })
            }
        }
        let host = node == focusedRoot ? rootHost : hosts[node]
        guard let host else { return }
        if let event = NSApp.currentEvent, event.type == .rightMouseDown {
            NSMenu.popUpContextMenu(menu, with: event, for: host)
        } else { menu.popUp(positioning: nil, at: NSPoint(x: host.contentRect.minX, y: host.contentRect.midY), in: host) }
    }

    // Only the shared editor currently embedded in overview gets this override.
    // Restore its original AppKit appearance and layer colors before reparenting.
    func prepareEditorAppearance(_ editor: NSView) {
        restoreEditorAppearance()
        overriddenEditor = editor; editorAppearance = editor.appearance
        editorFooterInset = owner?.editorFooterInsetConstraint?.constant
        owner?.editorFooterInsetConstraint?.constant = 0
        editorRelationsSuppressed = owner?.noteLinksView.isSuppressed
        owner?.noteLinksView.isSuppressed = true
        editor.appearance = NSAppearance(named: colors.dark ? .darkAqua : .aqua)
        let background = presentation == .outline ? colors.outlineBackground : colors.mapBackground
        var stack = [editor]
        while let view = stack.popLast() {
            stack.append(contentsOf: view.subviews)
            if let content = view as? NSStackView, content.identifier?.rawValue == "LibraryEditorStack" {
                editorStackInsets.append((content, content.edgeInsets))
                content.edgeInsets = NSEdgeInsets(top: 0, left: presentation == .outline ? 26 : 12, bottom: 0, right: 12)
            }
            if ["LibraryEditorCreatedDateLabel", "LibraryEditorStatusLabel", "LibraryEditorWordCount"].contains(view.identifier?.rawValue ?? "") {
                editorHiddenViews.append((view, view.isHidden)); view.isHidden = true
            }
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
        for (view, insets) in editorStackInsets { view.edgeInsets = insets }
        for (view, hidden) in editorHiddenViews { view.isHidden = hidden }
        if let editorFooterInset { owner?.editorFooterInsetConstraint?.constant = editorFooterInset }
        if let editorRelationsSuppressed { owner?.noteLinksView.isSuppressed = editorRelationsSuppressed }
        editorFooterInset = nil; editorRelationsSuppressed = nil
        editorLayers.removeAll(); editorClips.removeAll(); overriddenEditor = nil; editorAppearance = nil
        editorStackInsets.removeAll(); editorHiddenViews.removeAll()
    }
}
