import AppKit
import MudsnoteCore

@MainActor enum OverviewPalette {
    static let accent = NSColor(srgbRed: 0.36, green: 0.29, blue: 0.78, alpha: 1)
    static let line = NSColor(srgbRed: 0.56, green: 0.48, blue: 0.79, alpha: 1)
    static let topicBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.18, green: 0.17, blue: 0.23, alpha: 1)
            : NSColor(srgbRed: 0.96, green: 0.95, blue: 0.99, alpha: 1)
    }
}

@MainActor final class OverviewActionButton: NSButton {
    var invoke: (() -> Void)?
    private var hoverTrackingArea: NSTrackingArea?
    private(set) var isPointerHovered = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
        isPointerHovered = LibraryPointerTracking.containsPointer(in: self)
        needsDisplay = true
    }
    override func mouseEntered(with event: NSEvent) { setPointerHovered(LibraryPointerTracking.contains(self, event: event)) }
    override func mouseExited(with event: NSEvent) { isPointerHovered = false; needsDisplay = true }
    func setPointerHovered(_ hovered: Bool) {
        guard isPointerHovered != hovered else { return }
        isPointerHovered = hovered
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        if isEnabled && isPointerHovered {
            NSColor.labelColor.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).fill()
        }
        super.draw(dirtyRect)
    }
    init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        super.init(frame: .zero)
        self.title = title
        self.invoke = action
        bezelStyle = .rounded
        isBordered = false
        font = .systemFont(ofSize: 12)
        target = self
        self.action = #selector(pressed)
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
            imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        }
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func pressed() { invoke?() }
}

@MainActor final class OverviewCardView: NSView {
    let cardID: UUID
    let heading = NSTextField(labelWithString: "")
    let preview = NSTextField(wrappingLabelWithString: "")
    let association = NSTextField(labelWithString: "未归属")
    let expand: OverviewActionButton
    let more: OverviewActionButton
    let bullet = NSImageView()
    let underline = NSView()
    var editor: NSView?
    var isCompact = false { didSet { needsLayout = true; needsDisplay = true } }
    var isOutline = false
    private var hoverTrackingArea: NSTrackingArea?
    private(set) var isPointerHovered = false
    override var wantsUpdateLayer: Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
        isPointerHovered = LibraryPointerTracking.containsPointer(in: self)
        needsDisplay = true
    }
    override func mouseEntered(with event: NSEvent) { setPointerHovered(LibraryPointerTracking.contains(self, event: event)) }
    override func mouseExited(with event: NSEvent) { isPointerHovered = false; needsDisplay = true }
    func setPointerHovered(_ hovered: Bool) {
        guard isPointerHovered != hovered else { return }
        isPointerHovered = hovered
        needsDisplay = true
    }
    override var isFlipped: Bool { true }
    init(id: UUID, open: @escaping () -> Void, menu: @escaping () -> Void) {
        cardID = id
        expand = OverviewActionButton("", symbol: "square.and.pencil", action: open)
        expand.setAccessibilityLabel("编辑笔记")
        expand.toolTip = "编辑笔记"
        more = OverviewActionButton("", symbol: "ellipsis", action: menu)
        more.setAccessibilityLabel("关联与归属")
        more.toolTip = "关联与归属"
        super.init(frame: .zero)
        wantsLayer = true
        clipsToBounds = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 0
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        heading.lineBreakMode = .byTruncatingTail
        preview.font = .systemFont(ofSize: 14)
        preview.textColor = .secondaryLabelColor
        preview.maximumNumberOfLines = 4
        preview.lineBreakMode = .byTruncatingTail
        association.font = .systemFont(ofSize: 11)
        association.textColor = .tertiaryLabelColor
        association.lineBreakMode = .byTruncatingTail
        [heading, preview, expand, more, association].forEach(addSubview)
        bullet.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 5, weight: .regular))
        bullet.contentTintColor = .secondaryLabelColor
        bullet.setAccessibilityElement(false)
        underline.wantsLayer = true
        underline.layer?.backgroundColor = OverviewPalette.line.cgColor
        [bullet, underline].forEach(addSubview)
        focusRingType = .exterior
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityHelp("点击编辑笔记；右键查看关联与归属")
        setAccessibilityIdentifier("OverviewCard-" + id.uuidString)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateLayer() {
        let focused = window?.firstResponder === self
        layer?.backgroundColor = (isPointerHovered
            ? LibraryNotesPalette.hoverBackground : (isCompact && editor == nil ? .clear : LibraryNotesPalette.cardBackground)).cgColor
        layer?.borderWidth = editor != nil || (isCompact && focused) ? 1 : 0
        layer?.borderColor = OverviewPalette.line.cgColor
        layer?.cornerRadius = isCompact && editor == nil ? 0 : 8
        if isCompact && editor == nil {
            more.isHidden = !isPointerHovered && !focused
            expand.isHidden = true
            heading.frame.size.width = max(0, bounds.width - (isPointerHovered || focused ? 40 : 16) - (isOutline ? 12 : 0))
        } else { more.isHidden = false; expand.isHidden = false }
    }
    override func layout() {
        super.layout()
        if isCompact && editor == nil {
            heading.frame = NSRect(x: isOutline ? 22 : 10, y: (bounds.height - 22) / 2, width: max(0, bounds.width - (isOutline ? 30 : 18)), height: 22)
            more.frame = NSRect(x: bounds.width - 34, y: (bounds.height - 26) / 2, width: 28, height: 26)
            expand.frame = NSRect(x: bounds.width - 64, y: (bounds.height - 26) / 2, width: 28, height: 26)
            heading.font = .systemFont(ofSize: isOutline ? 16 : 15, weight: .regular)
            bullet.isHidden = !isOutline
            bullet.frame = NSRect(x: 2, y: bounds.midY - 3, width: 6, height: 6)
            underline.isHidden = isOutline
            underline.frame = NSRect(x: 0, y: bounds.height - 1.5, width: bounds.width, height: 1.5)
            preview.isHidden = true
            association.isHidden = true
            return
        }
        bullet.isHidden = true; underline.isHidden = true
        heading.frame = NSRect(x: 16, y: 14, width: bounds.width - 32, height: 22)
        preview.frame = NSRect(x: 16, y: 46, width: bounds.width - 32, height: bounds.height - 92)
        expand.frame = NSRect(x: 12, y: bounds.height - 36, width: editor == nil ? 28 : 52, height: 26)
        more.frame = NSRect(x: bounds.width - 44, y: bounds.height - 36, width: 32, height: 26)
        association.frame = NSRect(x: editor == nil ? 48 : 72, y: bounds.height - 32, width: max(0, bounds.width - 120), height: 18)
        editor?.frame = NSRect(x: 4, y: 10, width: bounds.width - 8, height: bounds.height - 52)
    }
    override func mouseDown(with event: NSEvent) { if editor == nil { expand.invoke?() } else { super.mouseDown(with: event) } }
    override func accessibilityPerformPress() -> Bool { expand.invoke?(); return true }
    override func rightMouseDown(with event: NSEvent) { more.invoke?() }
    override var acceptsFirstResponder: Bool { editor == nil }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
    override func keyDown(with event: NSEvent) {
        if [36, 49, 76].contains(event.keyCode), editor == nil { expand.invoke?() }
        else { super.keyDown(with: event) }
    }
    func embed(_ view: NSView?) {
        editor?.removeFromSuperview()
        editor = view
        setAccessibilityElement(view == nil)
        if let view { view.translatesAutoresizingMaskIntoConstraints = true; view.autoresizingMask = []; view.clipsToBounds = true; addSubview(view) }
        heading.isHidden = view != nil
        preview.isHidden = view != nil
        expand.title = view == nil ? "" : "收起"
        expand.imagePosition = view == nil ? .imageOnly : .imageLeading
        expand.setAccessibilityLabel(view == nil ? "编辑笔记" : "收起")
        expand.toolTip = view == nil ? "编辑笔记" : "收起"
        needsLayout = true
        needsDisplay = true
    }
}

@MainActor final class OverviewCanvas: NSView {
    override var isFlipped: Bool { true }
    var lines: [([NSPoint], Bool)] = []
    var isOutline = false
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for (points, accent) in lines {
            guard let first = points.first else { continue }
            (isOutline ? NSColor.separatorColor : OverviewPalette.line.withAlphaComponent(accent ? 1 : 0.85)).setStroke()
            let path = NSBezierPath()
            path.move(to: first)
            if points.count == 4 {
                path.curve(to: points[3], controlPoint1: points[1], controlPoint2: points[2])
            } else {
                for point in points.dropFirst() { path.line(to: point) }
            }
            path.lineWidth = isOutline ? 1 : 1.5
            path.lineJoinStyle = .round
            path.stroke()
        }
    }
}

@MainActor final class OverviewRootTitle: NSTextField {
    override func draw(_ dirtyRect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: textColor ?? NSColor.labelColor, .paragraphStyle: paragraph
        ]
        let height = (stringValue as NSString).size(withAttributes: attributes).height
        (stringValue as NSString).draw(in: NSRect(x: 0, y: (bounds.height - height) / 2,
                                                 width: bounds.width, height: height), withAttributes: attributes)
    }
}

@MainActor final class LibraryOverviewView: NSView {
    override var isFlipped: Bool { true }
    weak var owner: LibraryWindowController?
    let scroll = NSScrollView()
    let canvas = OverviewCanvas()
    let title = OverviewRootTitle(labelWithString: "我的生活")
    let principles = OverviewActionButton("", action: {})
    let newNote = OverviewActionButton("", symbol: "square.and.pencil", action: {})
    let add = OverviewActionButton("", symbol: "link", action: {})
    let addArea = OverviewActionButton("", symbol: "plus", action: {})
    let presentationButton = OverviewActionButton("大纲笔记", symbol: "list.bullet", action: {})
    let breadcrumb = NSTextField(labelWithString: "总览  /  我的生活")
    let mapTools = OverviewRailView()
    let zoomValue = OverviewActionButton("100%", action: {})
    let zoomIn = OverviewActionButton("", symbol: "plus", action: {})
    let zoomOut = OverviewActionButton("", symbol: "minus", action: {})
    let fit = OverviewActionButton("", symbol: "arrow.up.left.and.arrow.down.right", action: {})
    let unassigned = OverviewActionButton("未归属", action: {})
    var disclosures: [OverviewNodeID: OverviewActionButton] = [:]
    var branchBullets: [OverviewNodeID: NSImageView] = [:]
    var collapsed = Set<OverviewNodeID>()
    private(set) var presentation: OverviewPresentation
    private var needsInitialFit = true
    private var planSize = NSSize.zero
    var cards: [UUID: OverviewCardView] = [:]
    var areas: [UUID: OverviewActionButton] = [:]
    var previews: [UUID: String] = [:]
    var previewVersions: [UUID: Date] = [:]
    var previewTasks: [UUID: Task<Void, Never>] = [:]
    var selectedID: UUID?
    var state = NoteOverview()

    init(owner: LibraryWindowController) {
        self.owner = owner
        presentation = OverviewPresentation(rawValue: owner.noteStore.libraryOverviewModeRawValue) ?? .mindMap
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("LibraryHomeOverview")
        principles.isBordered = false
        principles.alignment = .left
        principles.font = .systemFont(ofSize: 12)
        principles.lineBreakMode = .byTruncatingTail
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.alignment = .center
        title.wantsLayer = true
        title.layer?.cornerRadius = 8
        title.layer?.backgroundColor = LibraryNotesPalette.cardBackground.cgColor
        title.lineBreakMode = .byTruncatingTail
        breadcrumb.font = .systemFont(ofSize: 12)
        breadcrumb.textColor = .secondaryLabelColor
        presentationButton.identifier = NSUserInterfaceItemIdentifier("OverviewPresentation")
        presentationButton.invoke = { [weak self] in
            guard let self else { return }
            self.setPresentation(self.presentation == .mindMap ? .outline : .mindMap)
        }
        mapTools.wantsLayer = true
        mapTools.layer?.cornerRadius = 6
        mapTools.layer?.borderWidth = 1
        mapTools.layer?.borderColor = NSColor.separatorColor.cgColor
        mapTools.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        zoomValue.font = .systemFont(ofSize: 11)
        zoomValue.invoke = { [weak self] in self?.showZoomMenu() }
        zoomIn.invoke = { [weak self] in self?.changeZoom(by: 0.1) }
        zoomOut.invoke = { [weak self] in self?.changeZoom(by: -0.1) }
        for (button, label) in [(zoomValue, "缩放比例"), (zoomIn, "放大"), (zoomOut, "缩小")] {
            button.toolTip = label
            button.setAccessibilityLabel(label)
        }
        [zoomValue, zoomOut, zoomIn, fit].forEach(mapTools.addSubview)
        NotificationCenter.default.addObserver(self, selector: #selector(updateZoomValue), name: NSScrollView.didEndLiveMagnifyNotification, object: scroll)
        for (button, label) in [(newNote, "新建卡片"), (add, "关联笔记"), (addArea, "添加领域"), (fit, "适应窗口")] {
            button.toolTip = label
            button.setAccessibilityLabel(label)
        }
        fit.invoke = { [weak self] in self?.fitToWindow() }
        unassigned.invoke = { [weak owner] in owner?.pickOverviewNote(area: nil, connecting: nil) }
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.verticalScroller?.controlSize = .small
        scroll.hasHorizontalScroller = presentation == .mindMap
        scroll.allowsMagnification = presentation == .mindMap
        scroll.minMagnification = 0.35
        scroll.maxMagnification = 2
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.drawsBackground = false
        scroll.documentView = canvas
        addSubview(scroll)
        [breadcrumb, presentationButton, mapTools, newNote, add, addArea].forEach(addSubview)
        [title, principles, unassigned].forEach(canvas.addSubview)
        updatePresentationChrome()
        principles.invoke = { [weak owner] in owner?.editOverviewPrinciples() }
        newNote.identifier = NSUserInterfaceItemIdentifier("OverviewNewNote")
        newNote.invoke = { [weak owner] in owner?.createNoteInOverview() }
        add.invoke = { [weak owner] in owner?.pickOverviewNote(area: nil, connecting: nil) }
        addArea.invoke = { [weak owner] in owner?.editOverviewArea(nil) }
    }
    required init?(coder: NSCoder) { fatalError() }
    func update(_ state: NoteOverview, notes: [NoteSearchResult]) {
        self.state = state
        principles.title = state.principles
        principles.toolTip = state.principles
        let valid = Set(state.cards.map(\.id))
        for id in Array(cards.keys) where !valid.contains(id) {
            cards.removeValue(forKey: id)?.removeFromSuperview()
            previewTasks.removeValue(forKey: id)?.cancel()
            previews.removeValue(forKey: id)
            previewVersions.removeValue(forKey: id)
        }
        let areaIDs = Set(state.areas.map(\.id))
        for id in Array(areas.keys) where !areaIDs.contains(id) { areas.removeValue(forKey: id)?.removeFromSuperview() }
        for area in state.areas {
            if areas[area.id] == nil {
                let button = OverviewActionButton(area.title) { [weak owner] in owner?.overviewAreaMenu(area.id) }
                button.font = .systemFont(ofSize: 12, weight: .medium)
                button.isBordered = false
                areas[area.id] = button
                canvas.addSubview(button)
            }
            areas[area.id]?.title = area.title
        }
        for card in state.cards {
            let view: OverviewCardView
            if let existing = cards[card.id] { view = existing }
            else {
                view = OverviewCardView(id: card.id, open: { [weak owner] in owner?.toggleOverviewCard(card.id) }, menu: { [weak owner] in owner?.overviewCardMenu(card.id) })
                cards[card.id] = view
                canvas.addSubview(view)
            }
            let note = notes.first { $0.url.standardizedFileURL == card.url.standardizedFileURL }
            if let note, previewVersions[card.id] != note.modifiedAt {
                invalidatePreview(card.id)
                previewVersions[card.id] = note.modifiedAt
            }
            view.isCompact = true
            view.isOutline = presentation == .outline
            view.association.stringValue = state.areas.first(where: { $0.id == card.areaID })?.title ?? "未归属"
            view.association.isHidden = card.areaID == nil
            view.heading.stringValue = note?.title ?? card.url.deletingPathExtension().lastPathComponent
            view.setAccessibilityLabel(view.heading.stringValue)
            view.preview.stringValue = previews[card.id] ?? note?.snippet ?? "点击打开笔记"
            if previews[card.id] == nil && previewTasks[card.id] == nil, let store = owner?.noteStore {
                previewTasks[card.id] = Task { [weak self] in
                    let result = await Task.detached { try? store.loadNoteDocument(at: card.url).body }.value
                    guard !Task.isCancelled, let self else { return }
                    self.previewTasks[card.id] = nil
                    self.previews[card.id] = result.map { String($0.prefix(1200)) } ?? "文件暂不可用，可从菜单重新关联"
                    self.cards[card.id]?.preview.stringValue = self.previews[card.id] ?? ""
                }
            }
        }
        let tree = OverviewTree(state)
        let branchNodes = Set(state.areas.map { OverviewNodeID.area($0.id) }).union([.unassigned])
        for node in Array(branchBullets.keys) where !branchNodes.contains(node) {
            branchBullets.removeValue(forKey: node)?.removeFromSuperview()
        }
        for node in branchNodes where branchBullets[node] == nil {
            let bullet = NSImageView()
            bullet.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 5, weight: .regular))
            bullet.contentTintColor = .secondaryLabelColor
            bullet.setAccessibilityElement(false)
            branchBullets[node] = bullet
            canvas.addSubview(bullet)
        }
        let branches = Set(tree.children.keys.filter { $0 != .root })
        for node in Array(disclosures.keys) where !branches.contains(node) {
            disclosures.removeValue(forKey: node)?.removeFromSuperview()
        }
        for node in branches where disclosures[node] == nil {
            let disclosure = OverviewActionButton("", symbol: "chevron.down") { [weak self] in self?.toggleBranch(node) }
            disclosures[node] = disclosure
            canvas.addSubview(disclosure)
        }
        needsLayout = true
    }
    func invalidatePreview(_ id: UUID) {
        previews[id] = nil
        previewTasks.removeValue(forKey: id)?.cancel()
    }
    private func updatePresentationChrome() {
        let label = presentation == .mindMap ? "大纲笔记" : "思维导图"
        presentationButton.title = label
        presentationButton.image = NSImage(systemSymbolName: presentation == .mindMap ? "list.bullet" : "point.3.connected.trianglepath.dotted", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        presentationButton.setAccessibilityLabel(label)
        presentationButton.toolTip = label
        mapTools.isHidden = presentation == .outline
    }

    @objc private func updateZoomValue() {
        zoomValue.title = "\(Int((scroll.magnification * 100).rounded()))%"
    }

    private func changeZoom(by delta: CGFloat) {
        scroll.magnification = min(scroll.maxMagnification, max(scroll.minMagnification, scroll.magnification + delta))
        updateZoomValue()
    }

    private func showZoomMenu() {
        let menu = NSMenu()
        for percent in [50, 75, 100, 125, 150, 200] {
            menu.addItem(OverviewMenuItem("\(percent)%") { [weak self] in
                self?.scroll.magnification = CGFloat(percent) / 100
                self?.updateZoomValue()
            })
        }
        menu.addItem(.separator())
        menu.addItem(OverviewMenuItem("适应窗口") { [weak self] in self?.fitToWindow() })
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: zoomValue.bounds.maxY), in: zoomValue)
    }

    func setPresentation(_ next: OverviewPresentation) {
        guard presentation != next else { return }
        guard owner?.commitOverviewEditor() == true else { return }
        presentation = next
        updatePresentationChrome()
        owner?.noteStore.libraryOverviewModeRawValue = next.rawValue
        scroll.magnification = 1
        scroll.allowsMagnification = next == .mindMap
        scroll.hasHorizontalScroller = next == .mindMap
        cards.values.forEach { $0.isOutline = next == .outline; $0.needsDisplay = true }
        needsLayout = true
        layoutSubtreeIfNeeded()
        if let selectedID {
            revealCard(selectedID)
            if let owner { window?.makeFirstResponder(owner.editorTextView) }
        }
        else if next == .mindMap { fitToWindow() }
        else { scroll.contentView.scroll(to: .zero) }
    }

    func toggleBranch(_ node: OverviewNodeID) {
        if !collapsed.contains(node), let selectedID,
           OverviewTree(state).ancestors(of: .card(selectedID)).contains(node) {
            owner?.toggleOverviewCard(selectedID)
            guard self.selectedID == nil else { return }
        }
        if !collapsed.insert(node).inserted { collapsed.remove(node) }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func revealCard(_ id: UUID) {
        for ancestor in OverviewTree(state).ancestors(of: .card(id)) { collapsed.remove(ancestor) }
        scroll.magnification = 1
        updateZoomValue()
        needsLayout = true
        layoutSubtreeIfNeeded()
        cards[id]?.scrollToVisible(cards[id]?.bounds ?? .zero)
    }

    func fitToWindow() {
        guard presentation == .mindMap, planSize.width > 0, planSize.height > 0 else { return }
        let viewport = scroll.contentView.frame.size
        scroll.magnification = max(scroll.minMagnification, min(1, min(viewport.width / planSize.width, viewport.height / planSize.height)))
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        updateZoomValue()
    }

    override func layout() {
        super.layout()
        let width = max(1, bounds.width)
        breadcrumb.frame = NSRect(x: 20, y: 14, width: max(1, width - 250), height: 20)
        presentationButton.frame = NSRect(x: width - 220, y: 8, width: 100, height: 28)
        addArea.frame = NSRect(x: width - 112, y: 8, width: 28, height: 28)
        add.frame = NSRect(x: width - 76, y: 8, width: 28, height: 28)
        newNote.frame = NSRect(x: width - 40, y: 8, width: 28, height: 28)
        scroll.frame = NSRect(x: 0, y: 44, width: width, height: max(1, bounds.height - 44))
        mapTools.frame = NSRect(x: width - 62, y: 62, width: 46, height: 96)
        zoomValue.frame = NSRect(x: 2, y: 4, width: 42, height: 24)
        zoomOut.frame = NSRect(x: 1, y: 33, width: 22, height: 24)
        zoomIn.frame = NSRect(x: 23, y: 33, width: 22, height: 24)
        fit.frame = NSRect(x: 8, y: 65, width: 30, height: 24)
        let viewport = scroll.contentView.frame.size
        let plan = OverviewLayout.make(width: viewport.width, height: viewport.height, state: state, selected: selectedID,
                                       presentation: presentation, collapsed: collapsed, titles: cards.mapValues { $0.heading.stringValue })
        planSize = plan.size
        title.frame = plan.frames[.root] ?? .zero
        title.alignment = presentation == .mindMap ? .center : .left
        title.font = .systemFont(ofSize: presentation == .mindMap ? 18 : 28, weight: .semibold)
        title.textColor = presentation == .mindMap ? .white : .labelColor
        title.layer?.backgroundColor = (presentation == .mindMap ? OverviewPalette.accent : NSColor.clear).cgColor
        title.needsDisplay = true
        let root = title.frame
        principles.frame = NSRect(x: root.minX, y: root.maxY + 10,
                                  width: presentation == .mindMap ? 184 : root.width, height: 24)
        principles.font = .systemFont(ofSize: presentation == .mindMap ? 11 : 13)
        func placeBranch(_ button: OverviewActionButton, node: OverviewNodeID) {
            guard let frame = plan.frames[node] else {
                button.isHidden = true; disclosures[node]?.isHidden = true; branchBullets[node]?.isHidden = true
                return
            }
            button.isHidden = false
            let hasChildren = disclosures[node] != nil
            let isMap = presentation == .mindMap
            button.alignment = isMap ? .center : .left
            button.font = .systemFont(ofSize: isMap ? 15 : 16, weight: .regular)
            button.attributedTitle = NSAttributedString(string: button.title, attributes: [.font: button.font!, .foregroundColor: NSColor.labelColor])
            button.frame = isMap ? frame : NSRect(x: frame.minX + 20, y: frame.minY, width: max(1, frame.width - 20), height: frame.height)
            button.lineBreakMode = .byTruncatingTail
            button.wantsLayer = true
            button.layer?.backgroundColor = (isMap ? OverviewPalette.topicBackground : NSColor.clear).cgColor
            button.layer?.borderWidth = isMap ? 1.5 : 0
            button.layer?.borderColor = OverviewPalette.line.cgColor
            button.layer?.cornerRadius = 7
            button.image = nil
            branchBullets[node]?.isHidden = isMap
            branchBullets[node]?.frame = NSRect(x: frame.minX + 2, y: frame.midY - 3, width: 6, height: 6)
            if let disclosure = disclosures[node] {
                disclosure.isHidden = false
                disclosure.frame = NSRect(x: isMap ? frame.maxX + 6 : frame.minX - 16, y: frame.midY - 10, width: 20, height: 20)
                let isCollapsed = collapsed.contains(node)
                disclosure.title = isMap && isCollapsed ? String(OverviewTree(state).children[node, default: []].count) : ""
                disclosure.imagePosition = isMap && isCollapsed ? .noImage : .imageOnly
                disclosure.image = isMap && isCollapsed ? nil : NSImage(systemSymbolName: isMap ? "minus.circle" : (isCollapsed ? "chevron.right" : "chevron.down"), accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: isMap ? 12 : 8, weight: .regular))
                disclosure.contentTintColor = isMap ? OverviewPalette.line : .tertiaryLabelColor
                disclosure.setAccessibilityLabel((isCollapsed ? "展开" : "收起") + button.title)
                disclosure.toolTip = (isCollapsed ? "展开" : "收起") + button.title
            }
            button.setAccessibilityValue(hasChildren ? (collapsed.contains(node) ? "已收起" : "已展开") : "")
        }
        for (id, button) in areas { placeBranch(button, node: .area(id)) }
        placeBranch(unassigned, node: .unassigned)
        for (id, card) in cards {
            card.isHidden = plan.cards[id] == nil
            if let frame = plan.cards[id] { card.frame = frame }
        }
        canvas.lines = []
        canvas.isOutline = presentation == .outline
        for (parent, child) in plan.links {
            guard let a = plan.frames[parent], let b = plan.frames[child] else { continue }
            if presentation == .mindMap {
                let start = NSPoint(x: a.maxX + (disclosures[parent] == nil ? 0 : 27), y: a.midY)
                let endY: CGFloat
                if case .card(let id) = child, id != selectedID { endY = b.maxY - 1.5 }
                else { endY = b.midY }
                let end = NSPoint(x: b.minX, y: endY)
                let mid = (start.x + end.x) / 2
                canvas.lines.append(([start, NSPoint(x: mid, y: start.y), NSPoint(x: mid, y: end.y), end], false))
            } else if parent != .root {
                let x = a.minX + 5
                // Outline guides stay in the indentation gutter.
                canvas.lines.append(([NSPoint(x: x, y: a.maxY), NSPoint(x: x, y: b.midY)], false))
            }
        }
        // Show cross-note relationships only for the active node so ownership
        // branches remain readable. The existing relationship menu owns edits.
        if presentation == .mindMap, let selectedID {
            for edge in state.connections where edge.from == selectedID || edge.to == selectedID {
                guard let a = plan.cards[edge.from], let b = plan.cards[edge.to] else { continue }
                let x = max(a.maxX, b.maxX) + 12
                canvas.lines.append(([NSPoint(x: a.maxX, y: a.midY), NSPoint(x: x, y: a.midY),
                                      NSPoint(x: x, y: b.midY), NSPoint(x: b.maxX, y: b.midY)], true))
            }
        }
        canvas.setFrameSize(plan.size)
        canvas.needsDisplay = true
        if needsInitialFit, bounds.width > 0, bounds.height > 44 {
            needsInitialFit = false
            DispatchQueue.main.async { [weak self] in
                guard let self, self.selectedID == nil else { return }
                self.fitToWindow()
            }
        }
    }
}
