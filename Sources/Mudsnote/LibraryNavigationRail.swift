import AppKit

/// Native symbols match the compact document navigation in the reference.
@MainActor private enum LibraryRailGlyph {
    static func image(_ symbol: String, selected: Bool) -> NSImage? {
        let names = ["house": "square.grid.2x2", "folder": "folder.fill", "clock": "clock.fill", "star": "star.fill"]
        return NSImage(systemSymbolName: names[symbol] ?? symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
    }
}

@MainActor final class LibraryRailButton: NSButton {
    let symbolName: String
    var invoke: (() -> Void)?
    var selected = false {
        didSet {
            image = LibraryRailGlyph.image(symbolName, selected: selected)
            updateTint()
            needsDisplay = true
            setAccessibilityValue(selected ? "已选中" : "")
        }
    }
    private var hovered = false { didSet { updateTint(); needsDisplay = true } }
    private var hoverArea: NSTrackingArea?
    init(title: String, symbol: String, action: @escaping () -> Void) {
        symbolName = symbol
        super.init(frame: NSRect(x: 0, y: 0, width: 36, height: 36))
        self.title = ["首页": "总览", "资料库": "我的文档", "最近笔记": "最近编辑"][title] ?? title
        alignment = .left
        imagePosition = .imageLeading
        font = .systemFont(ofSize: 13, weight: .regular)
        invoke = action
        image = LibraryRailGlyph.image(symbol, selected: false)
        contentTintColor = .secondaryLabelColor
        imageScaling = .scaleNone
        isBordered = false
        bezelStyle = .shadowlessSquare
        setButtonType(.momentaryChange)
        focusRingType = .exterior
        toolTip = self.title
        setAccessibilityLabel(self.title)
        target = self
        self.action = #selector(pressed)
    }
    required init?(coder: NSCoder) { fatalError() }
    private func updateTint() {
        contentTintColor = selected || hovered || isHighlighted ? .labelColor : .secondaryLabelColor
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: font ?? NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ])
    }
    func setPointerHovered(_ isHovered: Bool) {
        guard hovered != isHovered else { return }
        hovered = isHovered
    }
    @objc private func pressed() { invoke?() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area); hoverArea = area
        hovered = LibraryPointerTracking.containsPointer(in: self)
        needsDisplay = true
    }
    override func mouseEntered(with event: NSEvent) { setPointerHovered(LibraryPointerTracking.contains(self, event: event)) }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        updateTint()
        if selected || hovered || isHighlighted {
            (selected ? LibraryNotesPalette.selectionBackground : LibraryNotesPalette.hoverBackground).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
        super.draw(dirtyRect)
    }
}

@MainActor final class LibraryNavigationRail: NSView {
    override var isFlipped: Bool { true }
    var buttons: [(String, LibraryRailButton)] = []
    var settings: LibraryRailButton?
    override func draw(_ dirtyRect: NSRect) {
        LibraryNotesPalette.sidebarBackground.setFill()
        bounds.fill()
    }
    override func layout() {
        super.layout()
        for (index, pair) in buttons.enumerated() {
            pair.1.frame = NSRect(x: 12, y: CGFloat(index) * 32, width: max(1, bounds.width - 24), height: 30)
        }
        settings?.frame = NSRect(x: 12, y: CGFloat(buttons.count) * 32, width: max(1, bounds.width - 24), height: 30)
    }
    func select(_ name: String) {
        for (key, button) in buttons { button.selected = key == name }
    }
}

@MainActor final class LibraryShellView: NSView {
    override var isFlipped: Bool { true }
    let content: NSView
    var contentTop: NSLayoutConstraint?
    init(content: NSView) {
        self.content = content
        super.init(frame: .zero)
        addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = LibraryNotesPalette.shellBackground.cgColor
        content.wantsLayer = true
        content.layer?.cornerRadius = 0
        content.layer?.masksToBounds = true
        content.layer?.borderWidth = 0
        content.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        let top = content.topAnchor.constraint(equalTo: topAnchor, constant: 44)
        contentTop = top
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            top,
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        let inset = max(44, window.map { $0.frame.height - $0.contentLayoutRect.height } ?? 44)
        if contentTop?.constant != inset { contentTop?.constant = inset }
    }
}
