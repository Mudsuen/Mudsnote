import AppKit
import MudsnoteCore

@MainActor final class OverviewActionButton: NSButton {
    var invoke: (() -> Void)?
    init(_ title: String, symbol: String? = nil, action: @escaping () -> Void) {
        super.init(frame: .zero)
        self.title = title
        self.invoke = action
        bezelStyle = .rounded
        font = .systemFont(ofSize: 12)
        target = self
        self.action = #selector(pressed)
        if let symbol { image = NSImage(systemSymbolName: symbol, accessibilityDescription: title); imagePosition = title.isEmpty ? .imageOnly : .imageLeading }
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func pressed() { invoke?() }
}

@MainActor final class OverviewCardView: NSView {
    let cardID: UUID
    let heading = NSTextField(labelWithString: "")
    let preview = NSTextField(wrappingLabelWithString: "")
    let expand: OverviewActionButton
    let more: OverviewActionButton
    var editor: NSView?
    override var isFlipped: Bool { true }
    init(id: UUID, open: @escaping () -> Void, menu: @escaping () -> Void) {
        cardID = id
        expand = OverviewActionButton("编辑", symbol: "arrow.up.left.and.arrow.down.right", action: open)
        more = OverviewActionButton("", symbol: "ellipsis", action: menu)
        more.setAccessibilityLabel("关联与归属")
        more.toolTip = "关联与归属"
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        heading.lineBreakMode = .byTruncatingTail
        preview.font = .systemFont(ofSize: 14)
        preview.textColor = .secondaryLabelColor
        preview.maximumNumberOfLines = 4
        preview.lineBreakMode = .byTruncatingTail
        [heading, preview, expand, more].forEach(addSubview)
        setAccessibilityIdentifier("OverviewCard-" + id.uuidString)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = (editor == nil ? NSColor.separatorColor : NSColor.systemGreen.withAlphaComponent(0.6)).cgColor
    }
    override func layout() {
        super.layout()
        heading.frame = NSRect(x: 16, y: 14, width: bounds.width - 32, height: 22)
        preview.frame = NSRect(x: 16, y: 46, width: bounds.width - 32, height: bounds.height - 92)
        expand.frame = NSRect(x: 12, y: bounds.height - 36, width: 80, height: 26)
        more.frame = NSRect(x: bounds.width - 44, y: bounds.height - 36, width: 32, height: 26)
        editor?.frame = NSRect(x: 4, y: 42, width: bounds.width - 8, height: bounds.height - 84)
    }
    override func mouseDown(with event: NSEvent) { if editor == nil { expand.invoke?() } else { super.mouseDown(with: event) } }
    func embed(_ view: NSView?) {
        editor?.removeFromSuperview()
        editor = view
        if let view { view.translatesAutoresizingMaskIntoConstraints = true; view.autoresizingMask = []; addSubview(view) }
        preview.isHidden = view != nil
        expand.title = view == nil ? "编辑" : "收起"
        expand.setAccessibilityLabel(view == nil ? "展开编辑" : "收起")
        needsLayout = true
        needsDisplay = true
    }
}

@MainActor final class OverviewCanvas: NSView {
    override var isFlipped: Bool { true }
    var lines: [(NSPoint, NSPoint, Bool)] = []
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for (start, end, isCardLink) in lines {
            (isCardLink ? NSColor.systemGreen.withAlphaComponent(0.45) : NSColor.secondaryLabelColor.withAlphaComponent(0.35)).setStroke()
            let path = NSBezierPath()
            path.move(to: start)
            let offset = max(30, abs(end.x - start.x) * 0.45)
            let sign: CGFloat = end.x > start.x ? 1 : -1
            if isCardLink && abs(start.x - end.x) < 1 {
                path.curve(to: end, controlPoint1: NSPoint(x: start.x + 28, y: start.y), controlPoint2: NSPoint(x: end.x + 28, y: end.y))
            } else {
                path.curve(to: end, controlPoint1: NSPoint(x: start.x + sign * offset, y: start.y), controlPoint2: NSPoint(x: end.x - sign * offset, y: end.y))
            }
            path.lineWidth = isCardLink ? 1.5 : 1
            path.stroke()
        }
    }
}

@MainActor final class LibraryOverviewView: NSView {
    override var isFlipped: Bool { true }
    weak var owner: LibraryWindowController?
    let scroll = NSScrollView()
    let canvas = OverviewCanvas()
    let title = NSTextField(labelWithString: "我的总览")
    let principles = OverviewActionButton("", action: {})
    let add = OverviewActionButton("添加笔记", symbol: "plus", action: {})
    let addArea = OverviewActionButton("添加领域", symbol: "square.grid.2x2", action: {})
    let root = NSTextField(labelWithString: "我的生活")
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
        title.font = .systemFont(ofSize: 25, weight: .bold)
        root.font = .systemFont(ofSize: 16, weight: .semibold)
        root.alignment = .center
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.drawsBackground = false
        scroll.documentView = canvas
        addSubview(scroll)
        [title, principles, add, addArea, root].forEach(canvas.addSubview)
        principles.invoke = { [weak owner] in owner?.editOverviewPrinciples() }
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
                button.font = .systemFont(ofSize: 14, weight: .semibold)
                button.isBordered = false
                button.wantsLayer = true
                button.layer?.cornerRadius = 12
                button.layer?.borderWidth = 1
                button.layer?.borderColor = NSColor.separatorColor.cgColor
                button.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
                let symbols = ["搞钱": "chart.bar", "健康": "heart", "关系": "person.2", "内在世界": "leaf"]
                button.image = NSImage(systemSymbolName: symbols[area.title] ?? "square.grid.2x2", accessibilityDescription: nil)
                button.imagePosition = .imageAbove
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
        let width = max(660, bounds.width)
        let cardWidth: CGFloat = min(390, (width - 280) / 2)
        title.frame = NSRect(x: 30, y: 24, width: 230, height: 42)
        principles.frame = NSRect(x: 30, y: 80, width: width - 60, height: 38)
        add.frame = NSRect(x: width - 138, y: 28, width: 108, height: 30)
        addArea.frame = NSRect(x: width - 258, y: 28, width: 110, height: 30)
        var leftY: CGFloat = 160
        var rightY: CGFloat = 160
        canvas.lines = []
        var centers: [UUID: NSPoint] = [:]
        for (index, area) in state.areas.enumerated() {
            let left = index % 2 == 0
            let startY = left ? leftY : rightY
            let group = state.cards.filter { $0.areaID == area.id }
            var y = startY
            for card in group {
                let height: CGFloat = selectedID == card.id ? 380 : 154
                let x: CGFloat = left ? 28 : width - cardWidth - 28
                cards[card.id]?.frame = NSRect(x: x, y: y, width: selectedID == card.id ? max(300, cardWidth) : cardWidth, height: height)
                y += height + 18
            }
            let centerY = startY + max(90, y - startY) / 2
            let groupWidth = group.contains(where: { $0.id == selectedID }) ? max(300, cardWidth) : cardWidth
            let x: CGFloat = left ? groupWidth + 42 : width - cardWidth - 134
            areas[area.id]?.frame = NSRect(x: x, y: centerY - 35, width: 92, height: 70)
            centers[area.id] = NSPoint(x: x + 46, y: centerY)
            for card in group {
                guard let frame = cards[card.id]?.frame else { continue }
                canvas.lines.append((NSPoint(x: left ? frame.maxX : frame.minX, y: frame.midY), NSPoint(x: left ? x : x + 92, y: centerY), false))
            }
            if left { leftY = max(y, startY + 170) + 50 } else { rightY = max(y, startY + 170) + 50 }
        }
        let centerY = max(270, min(leftY, rightY) / 2 + 26)
        root.frame = NSRect(x: width / 2 - 44, y: centerY, width: 88, height: 36)
        for area in state.areas {
            guard let center = centers[area.id] else { continue }
            let parent = area.parentID.flatMap { centers[$0] } ?? NSPoint(x: root.frame.midX, y: root.frame.midY)
            canvas.lines.append((parent, center, false))
        }
        var looseY = max(leftY, rightY) + 16
        for card in state.cards where card.areaID == nil || !state.areas.contains(where: { $0.id == card.areaID }) {
            let height: CGFloat = selectedID == card.id ? 380 : 154
            cards[card.id]?.frame = NSRect(x: 28, y: looseY, width: selectedID == card.id ? max(300, cardWidth) : cardWidth, height: height)
            looseY += height + 18
        }
        for edge in state.connections {
            guard let a = cards[edge.from]?.frame, let b = cards[edge.to]?.frame else { continue }
            canvas.lines.append((NSPoint(x: a.maxX, y: a.midY), NSPoint(x: abs(a.minX - b.minX) < 1 ? b.maxX : b.minX, y: b.midY), true))
        }
        let contentWidth = max(width, (cards.values.map { $0.frame.maxX }.max() ?? width - 28) + 28)
        canvas.setFrameSize(NSSize(width: contentWidth, height: max(bounds.height, looseY + 32)))
        canvas.needsDisplay = true
    }
}
