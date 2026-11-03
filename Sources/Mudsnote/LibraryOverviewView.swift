import AppKit
import MudsnoteCore

@MainActor final class OverviewActionButton: NSButton {
    var invoke: (() -> Void)?
    var doubleClick: ((NSEvent) -> Void)?
    var beginDrag: ((NSEvent) -> Void)?
    var keyHandler: ((NSEvent) -> Bool)?
    var contextAction: (() -> Void)?
    var drawsHoverBackground = true
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
        if drawsHoverBackground && isEnabled && isPointerHovered {
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
    override func mouseDown(with event: NSEvent) {
        guard doubleClick != nil || beginDrag != nil else { super.mouseDown(with: event); return }
        if event.clickCount > 1, let doubleClick { doubleClick(event); return }
        window?.makeFirstResponder(self)
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { invoke?(); return }
            if hypot(next.locationInWindow.x - event.locationInWindow.x, next.locationInWindow.y - event.locationInWindow.y) > 4,
               let beginDrag { beginDrag(next); return }
        }
    }
    override func rightMouseDown(with event: NSEvent) {
        if let contextAction { contextAction() } else { super.rightMouseDown(with: event) }
    }
    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) != true { super.keyDown(with: event) }
    }
}

@MainActor final class OverviewCardView: NSView {
    let cardID: UUID
    let heading = NSTextField(wrappingLabelWithString: "")
    let preview = NSTextField(wrappingLabelWithString: "")
    let association = NSTextField(labelWithString: "未归属")
    let expand: OverviewActionButton
    let more: OverviewActionButton
    let bullet = NSImageView()
    let underline = NSView()
    var editor: NSView?
    var isCompact = false { didSet { needsLayout = true; needsDisplay = true } }
    var isOutline = false
    var mapDepth = 2
    var colors = OverviewColors(dark: true, mapStyle: .ink)
    var nodeActive = false
    var selectNode: (() -> Void)?
    var beginDrag: ((NSEvent) -> Void)?
    var keyHandler: ((NSEvent) -> Bool)?
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
        [bullet, underline].forEach(addSubview)
        focusRingType = .exterior
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityHelp("双击编辑笔记；右键查看关联与归属")
        setAccessibilityIdentifier("OverviewCard-" + id.uuidString)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateLayer() {
        let focused = window?.firstResponder === self
        layer?.backgroundColor = (isPointerHovered && !isCompact ? LibraryNotesPalette.hoverBackground : isCompact && editor == nil ? NSColor.clear
            : isOutline ? colors.outlineBackground : colors.mapBackground).cgColor
        layer?.borderWidth = editor != nil || (isCompact && focused) ? 1 : 0
        layer?.borderColor = colors.mapLine.cgColor
        layer?.cornerRadius = isCompact && editor == nil ? 0 : 8
        if isCompact && editor == nil {
            more.isHidden = true
            expand.isHidden = true
        } else { more.isHidden = false; expand.isHidden = false }
    }
    override func layout() {
        super.layout()
        if isCompact && editor == nil {
            let inset: CGFloat = isOutline ? 31 : mapDepth == 1 ? 16 : 32
            let top: CGFloat = isOutline ? 3 : mapDepth == 1 ? 12 : 11
            heading.frame = NSRect(x: inset, y: top, width: max(0, bounds.width - (isOutline ? 31 : inset * 2)), height: max(1, bounds.height - top * 2))
            heading.cell?.usesSingleLineMode = false
            heading.maximumNumberOfLines = 0
            heading.lineBreakMode = .byWordWrapping
            more.frame = NSRect(x: bounds.width - 34, y: (bounds.height - 26) / 2, width: 28, height: 26)
            expand.frame = NSRect(x: bounds.width - 64, y: (bounds.height - 26) / 2, width: 28, height: 26)
            heading.font = OverviewTypography.font(isOutline || mapDepth == 1 ? 16 : 14, map: !isOutline)
            heading.textColor = isOutline ? colors.text : colors.mapText
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = isOutline ? 25.6 : mapDepth == 1 ? 26 : 22
            paragraph.maximumLineHeight = paragraph.minimumLineHeight
            paragraph.lineBreakMode = .byWordWrapping
            heading.attributedStringValue = NSAttributedString(string: heading.stringValue, attributes: [.font: heading.font!, .foregroundColor: heading.textColor!, .paragraphStyle: paragraph])
            bullet.isHidden = true
            underline.isHidden = true
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
    override func mouseDown(with event: NSEvent) {
        guard editor == nil else { super.mouseDown(with: event); return }
        if event.clickCount > 1 || selectNode == nil { expand.invoke?(); return }
        window?.makeFirstResponder(self)
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { selectNode?(); return }
            if hypot(next.locationInWindow.x - event.locationInWindow.x, next.locationInWindow.y - event.locationInWindow.y) > 4,
               let beginDrag { beginDrag(next); return }
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, bounds.contains(convert(point, from: superview)) else { return nil }
        if isCompact && editor == nil { return self }
        return super.hitTest(point)
    }
    override func accessibilityPerformPress() -> Bool { (selectNode ?? expand.invoke)?(); return true }
    override func rightMouseDown(with event: NSEvent) { more.invoke?() }
    override var acceptsFirstResponder: Bool { editor == nil }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }
    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
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
    var strokeColor = NSColor.gray
    var blankClick: (() -> Void)?
    var draggedNode: ((OverviewNodeID, NSPoint, Bool) -> Bool)?
    var dropRect: NSRect?
    static let dragType = NSPasteboard.PasteboardType("local.mudsnote.overview.node")
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([Self.dragType]) }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with event: NSEvent) {
        guard let scroll = enclosingScrollView, let window else { return }
        let origin = scroll.contentView.bounds.origin
        var panned = false
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { if !panned { blankClick?() }; return }
            guard !isOutline else { continue }
            panned = true
            let dx = (next.locationInWindow.x - event.locationInWindow.x) / scroll.magnification
            let dy = (next.locationInWindow.y - event.locationInWindow.y) / scroll.magnification
            scroll.contentView.scroll(to: NSPoint(x: origin.x - dx, y: origin.y + dy))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let raw = sender.draggingPasteboard.string(forType: Self.dragType), let node = OverviewNodeID(dragString: raw) else { return [] }
        return draggedNode?(node, convert(sender.draggingLocation, from: nil), false) == true ? .move : []
    }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) { dropRect = nil; needsDisplay = true }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { dropRect = nil; needsDisplay = true }
        guard let raw = sender.draggingPasteboard.string(forType: Self.dragType), let node = OverviewNodeID(dragString: raw) else { return false }
        return draggedNode?(node, convert(sender.draggingLocation, from: nil), true) == true
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for (points, accent) in lines {
            guard let first = points.first else { continue }
            strokeColor.withAlphaComponent(accent ? 1 : 0.9).setStroke()
            let path = NSBezierPath()
            path.move(to: first)
            if !isOutline && points.count > 2 {
                for i in 1..<(points.count - 1) {
                    let previous = points[i - 1], current = points[i], next = points[i + 1]
                    let a = hypot(current.x - previous.x, current.y - previous.y), b = hypot(next.x - current.x, next.y - current.y)
                    let radius = min(12, min(a, b) / 2)
                    guard a > 0, b > 0 else { path.line(to: current); continue }
                    let enter = NSPoint(x: current.x + (previous.x - current.x) * radius / a, y: current.y + (previous.y - current.y) * radius / a)
                    let leave = NSPoint(x: current.x + (next.x - current.x) * radius / b, y: current.y + (next.y - current.y) * radius / b)
                    path.line(to: enter); path.curve(to: leave, controlPoint1: current, controlPoint2: current)
                }
                path.line(to: points.last!)
            } else { for point in points.dropFirst() { path.line(to: point) } }
            path.lineWidth = isOutline ? 1 : 2
            if !accent { path.setLineDash([4, 3], count: 2, phase: 0); path.lineWidth = 1 }
            path.lineJoinStyle = .round
            path.stroke()
        }
        if let dropRect {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let path = NSBezierPath(roundedRect: dropRect, xRadius: 4, yRadius: 4)
            path.lineWidth = 2; path.stroke()
        }
    }
}

@MainActor final class OverviewRootTitle: NSTextField {
    var isMap = true
    var pressed: ((NSEvent) -> Void)?
    var contextAction: (() -> Void)?
    var textFrame = NSRect.zero
    override func mouseDown(with event: NSEvent) { pressed?(event) }
    override func rightMouseDown(with event: NSEvent) { contextAction?() }
    override func draw(_ dirtyRect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.minimumLineHeight = isMap ? 38 : 54.4
        paragraph.maximumLineHeight = paragraph.minimumLineHeight
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: textColor ?? NSColor.labelColor, .paragraphStyle: paragraph
        ]
        (stringValue as NSString).draw(with: textFrame == .zero ? bounds : textFrame,
                                      options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes)
    }
}

@MainActor final class LibraryOverviewView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    weak var owner: LibraryWindowController?
    let scroll = NSScrollView()
    let canvas = OverviewCanvas()
    let title = OverviewRootTitle(labelWithString: "我的生活")
    let principles = OverviewDescriptionLabel(wrappingLabelWithString: "")
    let newNote = OverviewActionButton("", symbol: "square.and.pencil", action: {})
    let add = OverviewActionButton("", symbol: "link", action: {})
    let addArea = OverviewActionButton("", symbol: "plus", action: {})
    let appearanceButton = OverviewActionButton("", symbol: "ellipsis", action: {})
    let presentationButton = OverviewActionButton("大纲笔记", symbol: "list.bullet", action: {})
    let breadcrumbScroll = NSScrollView()
    let breadcrumb = NSStackView()
    let mapTools = OverviewRailView()
    let zoomValue = OverviewActionButton("100%", action: {})
    let structureButton = OverviewActionButton("", symbol: "point.3.connected.trianglepath.dotted", action: {})
    let paletteButton = OverviewActionButton("", symbol: "paintpalette", action: {})
    let unassigned = OverviewActionButton("未归属", action: {})
    let topicEditor = NSTextView()
    let zoomPopover = NSPopover()
    let structuralUndo = UndoManager()
    var hosts: [OverviewNodeID: OverviewTopicHost] = [:]
    var rootHost: OverviewTopicHost!
    var collapsed = Set<OverviewNodeID>() {
        didSet { owner?.noteStore.libraryOverviewCollapsedNodes = collapsed.map(\.dragString).sorted() }
    }
    var presentation: OverviewPresentation
    var appearanceMode: OverviewAppearance
    var mapStyle: OverviewMapStyle
    var mapStructure: OverviewMapStructure
    var focusedRoot: OverviewNodeID = .root
    var activeNode: OverviewNodeID?
    var plan: OverviewLayout?
    var initialViewport = true
    var cards: [UUID: OverviewCardView] = [:]
    var areas: [UUID: OverviewActionButton] = [:]
    var previews: [UUID: String] = [:]
    var previewVersions: [UUID: Date] = [:]
    var previewTasks: [UUID: Task<Void, Never>] = [:]
    var selectedID: UUID?
    var state = NoteOverview()
    var topicEdit: (node: OverviewNodeID, details: Bool)?
    var topicSaveWork: DispatchWorkItem?
    var endingTopicEdit = false
    var replayingHistory = false
    var editorAppearance: NSAppearance?
    var overriddenEditor: NSView?
    var editorLayers: [(NSView, CGColor?)] = []
    var editorClips: [(NSClipView, NSColor)] = []

    var colors: OverviewColors {
        let dark = appearanceMode == .dark || (appearanceMode == .system && effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        return OverviewColors(dark: dark, mapStyle: mapStyle)
    }

    init(owner: LibraryWindowController) {
        self.owner = owner
        presentation = OverviewPresentation(rawValue: owner.noteStore.libraryOverviewModeRawValue) ?? .mindMap
        appearanceMode = OverviewAppearance(rawValue: owner.noteStore.libraryOverviewAppearanceRawValue) ?? .system
        mapStyle = OverviewMapStyle(rawValue: owner.noteStore.libraryOverviewMapStyleRawValue) ?? .ink
        mapStructure = OverviewMapStructure(rawValue: owner.noteStore.libraryOverviewMapStructureRawValue) ?? .balanced
        collapsed = Set(owner.noteStore.libraryOverviewCollapsedNodes.compactMap(OverviewNodeID.init(dragString:)))
        super.init(frame: .zero)
        structuralUndo.groupsByEvent = false
        identifier = NSUserInterfaceItemIdentifier("LibraryHomeOverview")
        wantsLayer = true
        topicEditor.isRichText = false; topicEditor.drawsBackground = false
        topicEditor.textContainerInset = .zero; topicEditor.textContainer?.lineFragmentPadding = 0
        topicEditor.delegate = self
        topicEditor.isHidden = true
        topicEditor.setAccessibilityLabel("主题内容")
        topicEditor.setAccessibilityIdentifier("OverviewTopicEditor")
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = presentation == .mindMap
        scroll.scrollerStyle = .overlay; scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false; scroll.drawsBackground = false
        scroll.allowsMagnification = presentation == .mindMap
        scroll.minMagnification = 0.2; scroll.maxMagnification = 4
        scroll.documentView = canvas
        canvas.blankClick = { [weak self] in
            guard let self, self.commitTopicEditing() else { return }
            self.activeNode = nil; self.window?.makeFirstResponder(self); self.needsLayout = true
        }
        canvas.draggedNode = { [weak self] node, point, perform in self?.handleDrop(node, point: point, perform: perform) ?? false }
        addSubview(scroll)
        breadcrumb.orientation = .horizontal; breadcrumb.spacing = 8
        breadcrumbScroll.drawsBackground = false; breadcrumbScroll.hasHorizontalScroller = false
        breadcrumbScroll.documentView = breadcrumb
        mapTools.wantsLayer = true; mapTools.layer?.cornerRadius = 4
        mapTools.layer?.backgroundColor = NSColor.white.cgColor
        mapTools.layer?.shadowColor = NSColor.black.cgColor
        mapTools.layer?.shadowOpacity = 0.08; mapTools.layer?.shadowRadius = 8
        mapTools.appearance = NSAppearance(named: .aqua)
        [zoomValue, structureButton, paletteButton].forEach(mapTools.addSubview)
        structureButton.image = structureButton.image?.withSymbolConfiguration(.init(pointSize: 22, weight: .regular))
        paletteButton.image = paletteButton.image?.withSymbolConfiguration(.init(pointSize: 22, weight: .regular))
        [breadcrumbScroll, presentationButton, mapTools, newNote, add, addArea, appearanceButton].forEach(addSubview)
        rootHost = OverviewTopicHost(node: .root, content: title)
        canvas.addSubview(rootHost)
        rootHost.addSubview(principles)
        canvas.addSubview(topicEditor)
        title.pressed = { [weak self] event in
            guard let self else { return }
            self.select(self.focusedRoot)
            if event.clickCount > 1 || self.presentation == .outline { self.beginTopicEdit(self.focusedRoot) }
        }
        title.contextAction = { [weak self] in self?.showTopicMenu(self?.focusedRoot ?? .root) }
        principles.alignment = .left
        principles.maximumNumberOfLines = 0
        principles.pressed = { [weak self] in self?.beginTopicEdit(self?.focusedRoot ?? .root, details: true) }
        rootHost.addChild.invoke = { [weak self] in self?.createTopic(parent: self?.focusedRoot ?? .root) }
        rootHost.more.invoke = { [weak self] in self?.showTopicMenu(self?.focusedRoot ?? .root) }
        presentationButton.identifier = NSUserInterfaceItemIdentifier("OverviewPresentation")
        presentationButton.invoke = { [weak self] in
            guard let self else { return }; self.setPresentation(self.presentation == .mindMap ? .outline : .mindMap)
        }
        appearanceButton.invoke = { [weak self] in self?.showAppearanceMenu() }
        zoomValue.font = .systemFont(ofSize: 14)
        zoomValue.invoke = { [weak self] in self?.showZoomPopover() }
        structureButton.invoke = { [weak self] in self?.showStructureMenu() }
        paletteButton.invoke = { [weak self] in self?.showPaletteMenu() }
        NotificationCenter.default.addObserver(self, selector: #selector(updateZoomValue), name: NSScrollView.didEndLiveMagnifyNotification, object: scroll)
        for (button, label) in [(newNote, "新建笔记到总览"), (add, "关联笔记"), (addArea, "添加主题"),
                                (appearanceButton, "总览外观与操作"), (zoomValue, "缩放比例"),
                                (structureButton, "导图结构"), (paletteButton, "导图配色")] {
            button.toolTip = label; button.setAccessibilityLabel(label)
        }
        newNote.identifier = NSUserInterfaceItemIdentifier("OverviewNewNote")
        newNote.invoke = { [weak self, weak owner] in owner?.createNoteInOverview(area: self?.insertionArea) }
        add.invoke = { [weak self, weak owner] in owner?.pickOverviewNote(area: self?.insertionArea, connecting: nil) }
        addArea.invoke = { [weak self] in self?.createTopic(parent: self?.focusedRoot ?? .root) }
        unassigned.invoke = { [weak self] in self?.topicPressed(.unassigned) }
        updatePresentationChrome(); applyAppearance()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); applyAppearance() }

    func update(_ state: NoteOverview, notes: [NoteSearchResult]) {
        self.state = state
        let tree = OverviewTree(state)
        if focusedRoot != .root && tree.parents[focusedRoot] == nil { focusedRoot = .root }
        let valid = Set(state.cards.map(\.id))
        for id in Array(cards.keys) where !valid.contains(id) {
            cards.removeValue(forKey: id)?.removeFromSuperview()
            previewTasks.removeValue(forKey: id)?.cancel(); previews[id] = nil; previewVersions[id] = nil
        }
        let areaIDs = Set(state.areas.map(\.id))
        for id in Array(areas.keys) where !areaIDs.contains(id) { areas.removeValue(forKey: id)?.removeFromSuperview() }
        for area in state.areas {
            let node = OverviewNodeID.area(area.id)
            if areas[area.id] == nil {
                let button = OverviewActionButton(area.title) { [weak self] in self?.topicPressed(node) }
                button.drawsHoverBackground = false
                button.doubleClick = { [weak self] _ in self?.beginTopicEdit(node) }
                button.beginDrag = { [weak self] event in self?.startDrag(node, event: event) }
                button.contextAction = { [weak self] in self?.showTopicMenu(node) }
                button.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
                areas[area.id] = button
                attachHost(node, content: button)
            }
            areas[area.id]?.title = area.title
        }
        if hosts[.unassigned] == nil { attachHost(.unassigned, content: unassigned) }
        for card in state.cards {
            let node = OverviewNodeID.card(card.id)
            let view: OverviewCardView
            if let existing = cards[card.id] { view = existing }
            else {
                view = OverviewCardView(id: card.id, open: { [weak owner] in owner?.toggleOverviewCard(card.id) }, menu: { [weak self] in self?.showTopicMenu(node) })
                view.selectNode = { [weak self] in self?.select(node) }
                view.beginDrag = { [weak self] event in self?.startDrag(node, event: event) }
                view.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
                cards[card.id] = view; attachHost(node, content: view)
            }
            let note = notes.first { $0.url.standardizedFileURL == card.url.standardizedFileURL }
            if let note, previewVersions[card.id] != note.modifiedAt { invalidatePreview(card.id); previewVersions[card.id] = note.modifiedAt }
            view.isCompact = true
            view.association.stringValue = state.areas.first { $0.id == card.areaID }?.title ?? "未归属"
            view.association.isHidden = card.areaID == nil
            view.heading.stringValue = note?.title ?? card.url.deletingPathExtension().lastPathComponent
            view.setAccessibilityLabel(view.heading.stringValue)
            view.preview.stringValue = previews[card.id] ?? note?.snippet ?? ""
            if previews[card.id] == nil && previewTasks[card.id] == nil, let store = owner?.noteStore {
                previewTasks[card.id] = Task { [weak self] in
                    let result = await Task.detached { try? store.loadNoteDocument(at: card.url).body }.value
                    guard !Task.isCancelled, let self else { return }
                    self.previewTasks[card.id] = nil
                    self.previews[card.id] = result.map { String($0.prefix(1200)) } ?? "文件暂不可用"
                    self.cards[card.id]?.preview.stringValue = self.previews[card.id] ?? ""
                }
            }
        }
        let validNodes = Set(state.areas.map { OverviewNodeID.area($0.id) } + state.cards.map { .card($0.id) } + [.unassigned])
        for node in Array(hosts.keys) where !validNodes.contains(node) { hosts.removeValue(forKey: node)?.removeFromSuperview() }
        if let activeNode, activeNode != .root && tree.parents[activeNode] == nil { self.activeNode = nil }
        updateBreadcrumbs(); needsLayout = true
    }
    func attachHost(_ node: OverviewNodeID, content: NSView) {
        let host = OverviewTopicHost(node: node, content: content)
        host.fold.invoke = { [weak self] in self?.toggleBranch(node) }
        host.bullet.invoke = { [weak self] in self?.focus(node) }
        host.bullet.beginDrag = { [weak self] event in self?.startDrag(node, event: event) }
        host.detail.pressed = { [weak self] in self?.beginTopicEdit(node, details: true) }
        host.more.invoke = { [weak self] in self?.showTopicMenu(node) }
        host.addChild.invoke = { [weak self] in self?.createTopic(parent: node) }
        hosts[node] = host; canvas.addSubview(host)
    }
    func invalidatePreview(_ id: UUID) { previews[id] = nil; previewTasks.removeValue(forKey: id)?.cancel() }
    func nodeTitle(_ node: OverviewNodeID) -> String {
        switch node {
        case .root: return state.title ?? "我的生活"
        case .unassigned: return "未归属"
        case .area(let id): return state.areas.first { $0.id == id }?.title ?? ""
        case .card(let id): return cards[id]?.heading.stringValue ?? "笔记"
        }
    }
    func nodeDetails(_ node: OverviewNodeID) -> String {
        if node == .root { return state.principles }
        if case .area(let id) = node { return state.areas.first { $0.id == id }?.details ?? "" }
        return ""
    }
    func applyAppearance() {
        let desired: NSAppearance.Name? = appearanceMode == .system ? nil : appearanceMode == .dark ? .darkAqua : .aqua
        if appearance?.name != desired { appearance = desired.flatMap(NSAppearance.init(named:)) }
        layer?.backgroundColor = colors.outlineBackground.cgColor
        if selectedID != nil, let editor = owner?.regularEditorView { prepareEditorAppearance(editor) }
        if rootHost != nil { updateBreadcrumbs() }
        needsLayout = true
    }
    func updatePresentationChrome() {
        let label = presentation == .mindMap ? "大纲笔记" : "思维导图"
        presentationButton.title = label
        presentationButton.image = NSImage(systemSymbolName: presentation == .mindMap ? "list.bullet" : "point.3.connected.trianglepath.dotted", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        presentationButton.setAccessibilityLabel(label); presentationButton.toolTip = label
        mapTools.isHidden = presentation == .outline
    }
    @objc func updateZoomValue() { zoomValue.title = "\(Int((scroll.magnification * 100).rounded()))%" }

    override func layout() {
        super.layout()
        let width = max(1, bounds.width)
        breadcrumbScroll.frame = NSRect(x: 36, y: 16, width: max(1, width - 340), height: 18)
        breadcrumb.frame = NSRect(origin: .zero, size: breadcrumb.fittingSize)
        presentationButton.frame = NSRect(x: width - 271, y: 11, width: 91, height: 26)
        addArea.frame = NSRect(x: width - 166, y: 10, width: 28, height: 28)
        add.frame = NSRect(x: width - 128, y: 10, width: 28, height: 28)
        newNote.frame = NSRect(x: width - 90, y: 10, width: 28, height: 28)
        appearanceButton.frame = NSRect(x: width - 52, y: 10, width: 28, height: 28)
        for button in [presentationButton, addArea, add, newNote, appearanceButton] { button.contentTintColor = colors.detail }
        presentationButton.wantsLayer = true; presentationButton.layer?.cornerRadius = 6
        presentationButton.layer?.backgroundColor = (presentation == .outline ? OverviewColors.accent : colors.dark ? OverviewColors.rgb(51, 51, 51) : OverviewColors.rgb(245, 245, 245)).cgColor
        presentationButton.attributedTitle = NSAttributedString(string: presentationButton.title,
            attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: presentation == .outline ? NSColor.white : colors.text])
        if presentation == .outline { presentationButton.contentTintColor = .white }
        scroll.frame = NSRect(x: 0, y: 48, width: width, height: max(1, bounds.height - 48))
        scroll.wantsLayer = true; scroll.layer?.backgroundColor = (presentation == .outline ? colors.outlineBackground : colors.mapBackground).cgColor
        mapTools.frame = NSRect(x: width - 90, y: 78, width: 60, height: 168)
        zoomValue.frame = NSRect(x: 0, y: 0, width: 60, height: 56)
        structureButton.frame = NSRect(x: 0, y: 56, width: 60, height: 56)
        paletteButton.frame = NSRect(x: 0, y: 112, width: 60, height: 56)
        let viewport = scroll.contentView.frame.size
        let next = OverviewLayout.make(width: viewport.width, height: viewport.height, state: state, selected: selectedID,
            presentation: presentation, collapsed: collapsed, titles: cards.mapValues { $0.heading.stringValue }, root: focusedRoot, structure: mapStructure)
        plan = next
        let tree = OverviewTree(state)
        rootHost.configure(nodeFrame: next.frames[next.root] ?? .zero, presentation: presentation, depth: 0, side: 1,
            colors: colors, active: activeNode == next.root, folded: false, children: tree.children[next.root, default: []].count,
            details: nodeDetails(next.root), allowsChild: next.root != .unassigned)
        title.stringValue = nodeTitle(next.root); title.isMap = presentation == .mindMap
        title.alignment = title.isMap ? .center : .left
        title.font = OverviewTypography.font(title.isMap ? 24 : 34, weight: title.isMap ? .medium : .semibold, map: title.isMap)
        title.textColor = title.isMap ? colors.mapRootText : colors.title
        title.textFrame = rootHost.textRect.offsetBy(dx: -rootHost.contentRect.minX, dy: -rootHost.contentRect.minY)
        title.needsDisplay = true
        principles.stringValue = nodeDetails(next.root)
        principles.font = OverviewTypography.font(14)
        principles.isHidden = principles.stringValue.isEmpty
        let rootRect = rootHost.contentRect
        let detailHeight = OverviewTypography.detailHeight(principles.stringValue, width: rootRect.width - (presentation == .outline ? 0 : 32))
        principles.frame = presentation == .outline
            ? NSRect(x: rootRect.minX, y: rootRect.maxY + 6, width: rootRect.width, height: detailHeight)
            : NSRect(x: rootRect.minX + 16, y: rootHost.textRect.maxY, width: rootRect.width - 32, height: detailHeight)
        if presentation == .outline, !principles.stringValue.isEmpty { rootHost.frame.size.height += detailHeight + 6 }
        let detailParagraph = NSMutableParagraphStyle(); detailParagraph.minimumLineHeight = 24; detailParagraph.maximumLineHeight = 24; detailParagraph.lineBreakMode = .byWordWrapping
        principles.attributedStringValue = NSAttributedString(string: principles.stringValue,
            attributes: [.font: principles.font!, .paragraphStyle: detailParagraph, .foregroundColor: presentation == .outline ? colors.detail : colors.mapRootText.withAlphaComponent(0.7)])
        for (node, host) in hosts {
            guard node != next.root, let rect = next.frames[node] else { host.isHidden = true; continue }
            host.isHidden = false
            let depth = next.depths[node] ?? 1
            host.configure(nodeFrame: rect, presentation: presentation, depth: depth, side: next.sides[node] ?? 1,
                colors: colors, active: activeNode == node, folded: collapsed.contains(node),
                children: tree.children[node, default: []].count, details: nodeDetails(node), allowsChild: node != .unassigned && !isCard(node))
            if let button = host.content as? OverviewActionButton {
                button.alignment = .left; button.font = OverviewTypography.font(presentation == .outline || depth == 1 ? 16 : 14, map: presentation == .mindMap)
                button.cell?.wraps = true; button.cell?.usesSingleLineMode = false; button.lineBreakMode = .byWordWrapping
                let paragraph = NSMutableParagraphStyle(); paragraph.minimumLineHeight = presentation == .outline ? 25.6 : depth == 1 ? 26 : 22; paragraph.maximumLineHeight = paragraph.minimumLineHeight; paragraph.lineBreakMode = .byWordWrapping
                button.attributedTitle = NSAttributedString(string: button.title, attributes: [.font: button.font!, .paragraphStyle: paragraph, .foregroundColor: presentation == .outline ? colors.text : colors.mapText])
                button.setAccessibilityLabel(button.title.isEmpty ? "未命名主题" : button.title)
            }
            if case .card(let id) = node, let card = cards[id] {
                card.isHidden = false; card.isOutline = presentation == .outline; card.mapDepth = depth; card.colors = colors
                card.nodeActive = activeNode == node; card.needsLayout = true; card.needsDisplay = true
                host.bullet.setAccessibilityLabel("打开笔记")
            } else { host.bullet.setAccessibilityLabel("进入主题 " + nodeTitle(node)) }
        }
        canvas.lines = []; canvas.isOutline = presentation == .outline
        canvas.strokeColor = presentation == .outline ? colors.guide : colors.mapLine
        if presentation == .mindMap {
            for (parent, child) in next.links {
                guard let a = next.frames[parent], let b = next.frames[child] else { continue }
                let side = next.sides[child] ?? 1
                let startY = (next.depths[parent] ?? 0) < 2 ? a.midY : a.maxY
                let endY = (next.depths[child] ?? 0) < 2 ? b.midY : b.maxY
                let start = NSPoint(x: side > 0 ? a.maxX : a.minX, y: startY)
                let end = NSPoint(x: side > 0 ? b.minX : b.maxX, y: endY)
                let bend = (start.x + end.x) / 2
                canvas.lines.append(([start, NSPoint(x: bend, y: start.y), NSPoint(x: bend, y: end.y), end], true))
            }
        } else {
            for (node, rect) in next.frames where node != next.root && !collapsed.contains(node) {
                let bottom = tree.descendants(of: node).compactMap { next.frames[$0]?.maxY }.max() ?? rect.maxY
                if bottom > rect.maxY {
                    let x = rect.minX + 12
                    canvas.lines.append(([NSPoint(x: x, y: rect.maxY), NSPoint(x: x, y: bottom)], true))
                }
            }
        }
        if presentation == .mindMap, case .card(let id) = activeNode {
            for edge in state.connections where edge.from == id || edge.to == id {
                guard let a = next.frames[.card(edge.from)], let b = next.frames[.card(edge.to)] else { continue }
                let gutter = next.contentBounds.maxX + 24
                canvas.lines.append(([NSPoint(x: a.maxX, y: a.midY), NSPoint(x: gutter, y: a.midY),
                                      NSPoint(x: gutter, y: b.midY), NSPoint(x: b.maxX, y: b.midY)], false))
            }
        }
        canvas.setFrameSize(next.size); canvas.needsDisplay = true
        layoutTopicEditor()
        if initialViewport, bounds.width > 0, bounds.height > 48 {
            initialViewport = false
            DispatchQueue.main.async { [weak self] in self?.resetViewport() }
        }
    }
    func isCard(_ node: OverviewNodeID) -> Bool { if case .card = node { return true }; return false }
    override func keyDown(with event: NSEvent) { if !handleKey(event) { super.keyDown(with: event) } }
}
