import AppKit

/// Cached vector masks keep the softly drawn glyphs sharp at every scale.
private enum LibraryRailGlyph {
    @MainActor private static var images: [String: NSImage] = [:]

    @MainActor static func image(_ symbol: String, selected: Bool) -> NSImage? {
        guard ["house", "folder", "clock", "number", "ellipsis"].contains(symbol) else {
            return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
        }
        let key = symbol + (selected ? ":selected" : ":idle")
        if let cached = images[key] { return cached }
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
        case "folder":
            let back = NSBezierPath()
            back.move(to: NSPoint(x: 9.2, y: 6.9))
            back.line(to: NSPoint(x: 10.1, y: 3.8))
            back.curve(to: NSPoint(x: 12.4, y: 2.8), controlPoint1: NSPoint(x: 10.4, y: 2.5), controlPoint2: NSPoint(x: 11.3, y: 2.3))
            back.line(to: NSPoint(x: 19.5, y: 5.4))
            back.curve(to: NSPoint(x: 20.6, y: 7.7), controlPoint1: NSPoint(x: 20.7, y: 5.8), controlPoint2: NSPoint(x: 21, y: 6.6))
            back.line(to: NSPoint(x: 18.1, y: 15.5))
            back.curve(to: NSPoint(x: 15.6, y: 16.5), controlPoint1: NSPoint(x: 17.7, y: 16.7), controlPoint2: NSPoint(x: 16.6, y: 16.9))
            stroke(back)
            let page = NSBezierPath()
            page.move(to: NSPoint(x: 5.4, y: 7.8))
            page.line(to: NSPoint(x: 14.3, y: 6.8))
            page.curve(to: NSPoint(x: 16.2, y: 8.5), controlPoint1: NSPoint(x: 15.6, y: 6.7), controlPoint2: NSPoint(x: 16.1, y: 7.3))
            page.line(to: NSPoint(x: 17.2, y: 18.1))
            page.curve(to: NSPoint(x: 15.6, y: 20), controlPoint1: NSPoint(x: 17.3, y: 19.3), controlPoint2: NSPoint(x: 16.7, y: 19.9))
            page.line(to: NSPoint(x: 6.7, y: 21))
            page.curve(to: NSPoint(x: 4.9, y: 19.3), controlPoint1: NSPoint(x: 5.5, y: 21.1), controlPoint2: NSPoint(x: 5, y: 20.5))
            page.line(to: NSPoint(x: 3.9, y: 9.7))
            page.curve(to: NSPoint(x: 5.4, y: 7.8), controlPoint1: NSPoint(x: 3.8, y: 8.5), controlPoint2: NSPoint(x: 4.2, y: 7.9))
            page.close(); stroke(page)
        case "clock", "number":
            let circle = NSBezierPath()
            circle.move(to: NSPoint(x: 12.2, y: 3.2))
            circle.curve(to: NSPoint(x: 20.6, y: 12.1), controlPoint1: NSPoint(x: 17.4, y: 3), controlPoint2: NSPoint(x: 20.9, y: 7.5))
            circle.curve(to: NSPoint(x: 11.8, y: 20.7), controlPoint1: NSPoint(x: 20.3, y: 17.5), controlPoint2: NSPoint(x: 16.7, y: 20.9))
            circle.curve(to: NSPoint(x: 3.5, y: 12.2), controlPoint1: NSPoint(x: 6.8, y: 20.6), controlPoint2: NSPoint(x: 3.2, y: 17))
            circle.curve(to: NSPoint(x: 12.2, y: 3.2), controlPoint1: NSPoint(x: 3.7, y: 7), controlPoint2: NSPoint(x: 7.3, y: 3.5))
            stroke(circle)
            let inside = NSBezierPath()
            if symbol == "clock" {
                inside.move(to: NSPoint(x: 12, y: 6.5))
                inside.line(to: NSPoint(x: 11.8, y: 12.4))
                inside.line(to: NSPoint(x: 8.4, y: 14.7))
            } else {
                inside.move(to: NSPoint(x: 8.1, y: 8))
                inside.line(to: NSPoint(x: 12.4, y: 7.5))
                inside.line(to: NSPoint(x: 17, y: 12.1))
                inside.curve(to: NSPoint(x: 12.2, y: 17), controlPoint1: NSPoint(x: 17.4, y: 12.8), controlPoint2: NSPoint(x: 13, y: 17.4))
                inside.line(to: NSPoint(x: 7.6, y: 12.4))
                inside.close()
                NSBezierPath(ovalIn: NSRect(x: 9.1, y: 9.1, width: 1.7, height: 1.7)).fill()
            }
            stroke(inside, width: 1.4)
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
        if selected {
            NSColor(srgbRed: 59 / 255, green: 130 / 255, blue: 246 / 255, alpha: 1).setFill()
            let dot = NSRect(x: bounds.width - 13, y: isFlipped ? 5 : bounds.height - 13, width: 8, height: 8)
            NSBezierPath(ovalIn: dot).fill()
        }
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
