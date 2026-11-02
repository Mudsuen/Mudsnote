import AppKit

@MainActor final class LibraryRailButton: NSButton {
    var invoke: (() -> Void)?
    var selected = false { didSet { contentTintColor = selected ? .labelColor : .secondaryLabelColor; needsDisplay = true; setAccessibilityValue(selected ? "已选中" : "") } }
    private var hovered = false
    private var hoverArea: NSTrackingArea?
    init(title: String, symbol: String, action: @escaping () -> Void) {
        super.init(frame: NSRect(x: 0, y: 0, width: 36, height: 36))
        self.title = ""
        invoke = action
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?.withSymbolConfiguration(.init(pointSize: 20, weight: .regular))
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
    @objc private func pressed() { invoke?() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        if selected || hovered || isHighlighted {
            NSColor.labelColor.withAlphaComponent(selected ? 0.11 : 0.06).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
        }
        super.draw(dirtyRect)
    }
}

@MainActor final class LibraryNavigationRail: NSView {
    override var isFlipped: Bool { true }
    var buttons: [(String, LibraryRailButton)] = []
    var settings: LibraryRailButton?
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.15, alpha: 1).setFill(); bounds.fill()
        NSColor.clear.setFill()
        let inset = max(safeAreaInsets.top, window.map { $0.frame.height - $0.contentLayoutRect.height } ?? 52)
        NSRect(x: bounds.maxX - 1, y: inset, width: 1, height: max(0, bounds.height - inset)).fill()
    }
    override func layout() {
        super.layout()
        let inset = max(safeAreaInsets.top, window.map { $0.frame.height - $0.contentLayoutRect.height } ?? 52)
        for (index, pair) in buttons.enumerated() {
            let gap: CGFloat = index >= 4 ? 12 : 0
            pair.1.frame = NSRect(x: 8, y: inset + 8 + CGFloat(index) * 44 + gap, width: 36, height: 36)
        }
        settings?.frame = NSRect(x: 8, y: bounds.height - 48, width: 36, height: 36)
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
        layer?.backgroundColor = NSColor(calibratedWhite: 0.15, alpha: 1).cgColor
        content.wantsLayer = true
        content.layer?.cornerRadius = 14
        content.layer?.masksToBounds = true
        content.layer?.borderWidth = 0.5
        content.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        let top = content.topAnchor.constraint(equalTo: topAnchor, constant: 44)
        contentTop = top
        NSLayoutConstraint.activate([
            rail.leadingAnchor.constraint(equalTo: leadingAnchor),
            rail.topAnchor.constraint(equalTo: topAnchor),
            rail.bottomAnchor.constraint(equalTo: bottomAnchor),
            rail.widthAnchor.constraint(equalToConstant: 52),
            content.leadingAnchor.constraint(equalTo: rail.trailingAnchor),
            top,
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        let inset = max(28, window.map { $0.frame.height - $0.contentLayoutRect.height } ?? 44)
        if contentTop?.constant != inset { contentTop?.constant = inset }
    }
}
