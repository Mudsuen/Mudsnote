import AppKit
import MudsnoteCore

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
    var editor: NSView?
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
        setAccessibilityIdentifier("OverviewCard-" + id.uuidString)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateLayer() {
        layer?.backgroundColor = (isPointerHovered
            ? LibraryNotesPalette.hoverBackground : LibraryNotesPalette.cardBackground).cgColor
        layer?.borderWidth = editor == nil ? 0 : 1
        layer?.borderColor = LibraryNotesPalette.separator.cgColor
    }
    override func layout() {
        super.layout()
        heading.frame = NSRect(x: 16, y: 14, width: bounds.width - 32, height: 22)
        preview.frame = NSRect(x: 16, y: 46, width: bounds.width - 32, height: bounds.height - 92)
        expand.frame = NSRect(x: 12, y: bounds.height - 36, width: editor == nil ? 28 : 52, height: 26)
        more.frame = NSRect(x: bounds.width - 44, y: bounds.height - 36, width: 32, height: 26)
        association.frame = NSRect(x: editor == nil ? 48 : 72, y: bounds.height - 32, width: max(0, bounds.width - 120), height: 18)
        editor?.frame = NSRect(x: 4, y: 10, width: bounds.width - 8, height: bounds.height - 52)
    }
    override func mouseDown(with event: NSEvent) { if editor == nil { expand.invoke?() } else { super.mouseDown(with: event) } }
    func embed(_ view: NSView?) {
        editor?.removeFromSuperview()
        editor = view
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
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for (points, accent) in lines {
            guard let first = points.first else { continue }
            NSColor.secondaryLabelColor.withAlphaComponent(accent ? 0.65 : 0.22).setStroke()
            let path = NSBezierPath()
            path.move(to: first)
            for point in points.dropFirst() { path.line(to: point) }
            path.lineWidth = accent ? 1.25 : 1
            path.lineJoinStyle = .round
            path.stroke()
        }
    }
}

@MainActor final class LibraryOverviewView: NSView {
    override var isFlipped: Bool { true }
    weak var owner: LibraryWindowController?
    let scroll = NSScrollView()
    let canvas = OverviewCanvas()
    let title = NSTextField(labelWithString: "我的生活")
    let principles = OverviewActionButton("", action: {})
    let newNote = OverviewActionButton("新建卡片", symbol: "square.and.pencil", action: {})
    let add = OverviewActionButton("关联笔记", symbol: "plus", action: {})
    let addArea = OverviewActionButton("添加领域", symbol: "square.grid.2x2", action: {})
    var cards: [UUID: OverviewCardView] = [:]
    var areas: [UUID: OverviewActionButton] = [:]
    var previews: [UUID: String] = [:]
    var previewVersions: [UUID: Date] = [:]
    var previewTasks: [UUID: Task<Void, Never>] = [:]
    var selectedID: UUID?
    var state = NoteOverview()

    init(owner: LibraryWindowController) {
        self.owner = owner
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("LibraryHomeOverview")
        principles.isBordered = false
        principles.alignment = .left
        principles.font = .systemFont(ofSize: 12)
        principles.lineBreakMode = .byTruncatingTail
        addArea.title = "领域"
        title.font = .systemFont(ofSize: 18, weight: .medium)
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.verticalScroller?.controlSize = .small
        scroll.hasHorizontalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.drawsBackground = false
        scroll.documentView = canvas
        addSubview(scroll)
        [title, principles, newNote, add, addArea].forEach(canvas.addSubview)
        principles.invoke = { [weak owner] in owner?.editOverviewPrinciples() }
        newNote.identifier = NSUserInterfaceItemIdentifier("OverviewNewNote")
        newNote.invoke = { [weak owner] in owner?.createNoteInOverview() }
        add.invoke = { [weak owner] in owner?.pickOverviewNote(area: nil, connecting: nil) }
        addArea.invoke = { [weak owner] in owner?.editOverviewArea(nil) }
    }
    required init?(coder: NSCoder) { fatalError() }
    func update(_ state: NoteOverview, notes: [NoteSearchResult]) {
        self.state = state
        principles.title = "宗旨   " + state.principles
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
            view.association.stringValue = state.areas.first(where: { $0.id == card.areaID })?.title ?? "未归属"
            view.association.isHidden = card.areaID == nil
            view.heading.stringValue = note?.title ?? card.url.deletingPathExtension().lastPathComponent
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
        needsLayout = true
    }
    func invalidatePreview(_ id: UUID) {
        previews[id] = nil
        previewTasks.removeValue(forKey: id)?.cancel()
    }
    override func layout() {
        super.layout()
        scroll.frame = bounds
        let width = max(1, scroll.contentSize.width)
        let plan = OverviewLayout.make(width: width, height: bounds.height, state: state, selected: selectedID)
        title.frame = NSRect(x: 20, y: 12, width: max(1, width - 316), height: 32)
        principles.frame = NSRect(x: 20, y: 50, width: max(1, width - 40), height: 26)
        add.frame = NSRect(x: width - 118, y: 14, width: 98, height: 28)
        newNote.frame = NSRect(x: width - 228, y: 14, width: 102, height: 28)
        addArea.frame = NSRect(x: width - 310, y: 14, width: 74, height: 28)
        for (id, frame) in plan.areas { areas[id]?.frame = frame }
        for (id, frame) in plan.cards { cards[id]?.frame = frame }
        canvas.lines = []
        for area in state.areas {
            guard let rect = plan.areas[area.id] else { continue }
            guard let parentID = area.parentID, let parent = plan.areas[parentID] else { continue }
            let start = NSPoint(x: parent.midX, y: parent.maxY)
            let end = NSPoint(x: rect.midX, y: rect.minY)
            let midY = (start.y + end.y) / 2
            canvas.lines.append(([start, NSPoint(x: start.x, y: midY), NSPoint(x: end.x, y: midY), end], false))
        }
        // Focus reveals ownership without drawing long lines across unrelated
        // text. Each card always exposes its area label, including unassigned.
        if let selectedID, let card = state.cards.first(where: { $0.id == selectedID }),
           let areaID = card.areaID, let source = plan.areas[areaID], let rect = plan.cards[selectedID] {
            let left = rect.midX < width / 2
            let gutter: CGFloat = left ? 5 : width - 5
            let start = NSPoint(x: source.midX, y: source.maxY)
            let end = NSPoint(x: left ? rect.minX : rect.maxX, y: rect.minY + 12)
            let band = (plan.areas.values.map(\.maxY).max() ?? source.maxY) + 6
            canvas.lines.append(([start, NSPoint(x: start.x, y: band), NSPoint(x: gutter, y: band), NSPoint(x: gutter, y: end.y), end], true))
        }
        for (index, edge) in state.connections.enumerated() {
            guard let a = plan.cards[edge.from], let b = plan.cards[edge.to] else { continue }
            let leftA = a.midX < width / 2
            let leftB = b.midX < width / 2
            let points: [NSPoint]
            if abs(a.midY - b.midY) < 1 && leftA != leftB {
                points = [NSPoint(x: leftA ? a.maxX : a.minX, y: a.midY), NSPoint(x: leftB ? b.maxX : b.minX, y: b.midY)]
            } else if leftA == leftB || plan.columns == 1 {
                let x: CGFloat = leftA ? 9 : width - 9
                let start = NSPoint(x: leftA ? a.minX : a.maxX, y: a.midY)
                let end = NSPoint(x: leftB ? b.minX : b.maxX, y: b.midY)
                points = [start, NSPoint(x: x, y: start.y), NSPoint(x: x, y: end.y), end]
            } else {
                let x = width / 2 + CGFloat(index % 3 - 1) * 4
                let start = NSPoint(x: leftA ? a.maxX : a.minX, y: a.midY)
                let end = NSPoint(x: leftB ? b.maxX : b.minX, y: b.midY)
                points = [start, NSPoint(x: x, y: start.y), NSPoint(x: x, y: end.y), end]
            }
            canvas.lines.append((points, selectedID == nil || selectedID == edge.from || selectedID == edge.to))
        }
        canvas.setFrameSize(plan.size)
        canvas.needsDisplay = true
        // Clamp a formerly wide canvas after resizing without discarding its
        // vertical position or moving the insertion point in the inline editor.
        if scroll.contentView.bounds.origin.x != 0 {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.contentView.bounds.origin.y))
        }
    }
}
