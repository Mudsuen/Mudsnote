import AppKit

/// Cached vector glyphs keep the rail sharp at every scale.
private enum LibraryRailGlyph {
    @MainActor private static var images: [String: NSImage] = [:]

    @MainActor static func image(_ symbol: String, selected: Bool) -> NSImage? {
        let key = symbol + (selected ? ":selected" : ":idle")
        if let cached = images[key] { return cached }
        if symbol != "house" && symbol != "ellipsis" {
            let name = selected && ["folder", "clock"].contains(symbol) ? symbol + ".fill" : symbol
            let weight: NSFont.Weight = selected && symbol == "number" ? .semibold : .regular
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 18, weight: weight))
            if let image { images[key] = image }
            return image
        }
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: true) { _ in
            NSGraphicsContext.saveGraphicsState()
            let opticalScale = NSAffineTransform()
            opticalScale.translateX(by: 12, yBy: 12)
            opticalScale.scale(by: 0.9)
            opticalScale.translateX(by: -12, yBy: -12)
            opticalScale.concat()
            draw(symbol, selected: selected)
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = true
        images[key] = image
        return image
    }

    private static func draw(_ symbol: String, selected: Bool) {
        NSColor.black.setFill(); NSColor.black.setStroke()
        func stroke(_ path: NSBezierPath, width: CGFloat = 1.6) {
            path.lineWidth = selected ? width + 0.15 : width
            path.lineCapStyle = .round; path.lineJoinStyle = .round
            path.stroke()
        }
        switch symbol {
        case "house":
            let house = NSBezierPath()
            house.move(to: NSPoint(x: 3.3, y: 10.5))
            house.curve(to: NSPoint(x: 10.7, y: 4.2), controlPoint1: NSPoint(x: 5.2, y: 8.8), controlPoint2: NSPoint(x: 8.7, y: 5.5))
            house.curve(to: NSPoint(x: 13.1, y: 4.3), controlPoint1: NSPoint(x: 11.5, y: 3.6), controlPoint2: NSPoint(x: 12.2, y: 3.7))
            house.line(to: NSPoint(x: 20.8, y: 10.3))
            house.curve(to: NSPoint(x: 19.2, y: 12), controlPoint1: NSPoint(x: 22, y: 11.3), controlPoint2: NSPoint(x: 21, y: 12.8))
            house.line(to: NSPoint(x: 19, y: 18.8))
            house.curve(to: NSPoint(x: 17.3, y: 20.2), controlPoint1: NSPoint(x: 19, y: 19.8), controlPoint2: NSPoint(x: 18.4, y: 20.3))
            house.line(to: NSPoint(x: 14.5, y: 20.2))
            house.line(to: NSPoint(x: 14.5, y: 16))
            house.curve(to: NSPoint(x: 9.7, y: 15.9), controlPoint1: NSPoint(x: 14.4, y: 12.9), controlPoint2: NSPoint(x: 9.5, y: 12.9))
            house.line(to: NSPoint(x: 9.7, y: 20.2))
            house.line(to: NSPoint(x: 6.5, y: 20.1))
            house.curve(to: NSPoint(x: 5, y: 18.6), controlPoint1: NSPoint(x: 5.4, y: 20.1), controlPoint2: NSPoint(x: 4.9, y: 19.5))
            house.line(to: NSPoint(x: 5.1, y: 12))
            house.curve(to: NSPoint(x: 3.3, y: 10.5), controlPoint1: NSPoint(x: 2.2, y: 12.6), controlPoint2: NSPoint(x: 2, y: 11.6))
            house.close()
            if selected { house.fill() } else { stroke(house, width: 1.45) }
        case "ellipsis":
            for x: CGFloat in [6.3, 12, 17.7] {
                NSBezierPath(ovalIn: NSRect(x: x - 1.4, y: 10.6, width: 2.8, height: 2.8)).fill()
            }
        default: break
        }
    }
}

@MainActor final class LibraryRailButton: NSButton {
    let symbolName: String
    var invoke: (() -> Void)?
    var selected = false {
        didSet {
            guard selected != oldValue else { return }
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
        contentTintColor = selected ? NSColor.labelColor.withAlphaComponent(1)
            : hovered || isHighlighted ? .labelColor : NSColor.secondaryLabelColor.withAlphaComponent(0.5)
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
            NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
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
