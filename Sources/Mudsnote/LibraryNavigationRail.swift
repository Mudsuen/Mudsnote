import AppKit

/// Use the system's vector outlines and optical hinting at every backing scale.
/// Selection is carried by tint/backplate, preserving one light stroke weight.
@MainActor private enum LibraryRailGlyph {
    static func image(_ symbol: String, selected: Bool) -> NSImage? {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 18, weight: .light))
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
        self.title = ""
        invoke = action
        image = LibraryRailGlyph.image(symbol, selected: false)
        contentTintColor = .secondaryLabelColor
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        isBordered = false
        bezelStyle = .shadowlessSquare
        setButtonType(.momentaryChange)
        focusRingType = .exterior
        toolTip = title
        setAccessibilityLabel(title)
        target = self
        self.action = #selector(pressed)
    }
    required init?(coder: NSCoder) { fatalError() }
    private func updateTint() {
        contentTintColor = selected || hovered || isHighlighted ? .labelColor : .secondaryLabelColor
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
        LibraryNotesPalette.shellBackground.setFill()
        bounds.fill()
    }
    override func layout() {
        super.layout()
        let inset = max(44, max(safeAreaInsets.top, window.map { $0.frame.height - $0.contentLayoutRect.height } ?? 44))
        for (index, pair) in buttons.enumerated() {
            pair.1.frame = NSRect(x: (bounds.width - 36) / 2, y: inset + 4 + CGFloat(index) * 44, width: 36, height: 36)
        }
        settings?.frame = NSRect(x: (bounds.width - 36) / 2, y: bounds.height - 48, width: 36, height: 36)
    }
    func select(_ name: String) {
        for (key, button) in buttons { button.selected = key == name }
    }
}

@MainActor final class LibraryShellView: NSView {
    override var isFlipped: Bool { true }
    let rail: NSView
    let content: NSView
    var contentTop: NSLayoutConstraint?
    init(rail: NSView, content: NSView) {
        self.rail = rail; self.content = content
        super.init(frame: .zero)
        addSubview(rail); addSubview(content)
        rail.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = LibraryNotesPalette.shellBackground.cgColor
        content.wantsLayer = true
        content.layer?.cornerRadius = 10
        content.layer?.masksToBounds = true
        content.layer?.borderWidth = 0
        content.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        let top = content.topAnchor.constraint(equalTo: topAnchor, constant: 44)
        contentTop = top
        NSLayoutConstraint.activate([
            rail.leadingAnchor.constraint(equalTo: leadingAnchor),
            rail.topAnchor.constraint(equalTo: topAnchor),
            rail.bottomAnchor.constraint(equalTo: bottomAnchor),
            rail.widthAnchor.constraint(equalToConstant: 50),
            content.leadingAnchor.constraint(equalTo: rail.trailingAnchor),
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
