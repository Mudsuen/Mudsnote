import AppKit

/// Fixed optical bounds and one stroke weight, matching the supplied rail video.
/// Keep navigation meaning independent of the SF Symbol's natural bounding box.
@MainActor private enum LibraryRailGlyph {
    static func image(_ symbol: String, selected: Bool) -> NSImage? {
        guard ["house", "folder", "clock", "star"].contains(symbol) else {
            return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let path = NSBezierPath()
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            switch symbol {
            case "house":
                path.move(to: NSPoint(x: 2, y: 8))
                path.line(to: NSPoint(x: 9, y: 2.5))
                path.line(to: NSPoint(x: 16, y: 8))
                if selected {
                    path.line(to: NSPoint(x: 15, y: 8))
                    path.line(to: NSPoint(x: 15, y: 15.5))
                    path.line(to: NSPoint(x: 11, y: 15.5))
                    path.line(to: NSPoint(x: 11, y: 10.5))
                    path.line(to: NSPoint(x: 7, y: 10.5))
                    path.line(to: NSPoint(x: 7, y: 15.5))
                    path.line(to: NSPoint(x: 3, y: 15.5))
                    path.line(to: NSPoint(x: 3, y: 8))
                    path.close()
                    path.fill()
                } else {
                    path.move(to: NSPoint(x: 4, y: 7))
                    for point in [NSPoint(x: 4, y: 15.5), NSPoint(x: 7, y: 15.5),
                                  NSPoint(x: 7, y: 10.5), NSPoint(x: 11, y: 10.5),
                                  NSPoint(x: 11, y: 15.5), NSPoint(x: 14, y: 15.5),
                                  NSPoint(x: 14, y: 7)] { path.line(to: point) }
                }
            case "folder":
                let back = NSBezierPath(roundedRect: NSRect(x: 6, y: 2, width: 9.5, height: 12), xRadius: 2, yRadius: 2)
                let rotation = AffineTransform(translationByX: 10.75, byY: 8)
                var transform = rotation
                transform.rotate(byDegrees: 16)
                transform.translate(x: -10.75, y: -8)
                back.transform(using: transform)
                path.append(back)
                path.appendRoundedRect(NSRect(x: 2.5, y: 5, width: 10, height: 11), xRadius: 2, yRadius: 2)
            case "clock":
                path.appendOval(in: NSRect(x: 2, y: 2, width: 14, height: 14))
                path.move(to: NSPoint(x: 9, y: 4.5))
                path.line(to: NSPoint(x: 9, y: 9))
                path.line(to: NSPoint(x: 6, y: 10.5))
            default:
                for index in 0..<10 {
                    let angle = CGFloat(index) * .pi / 5 - .pi / 2
                    let radius: CGFloat = index.isMultiple(of: 2) ? 7.5 : 3.4
                    let point = NSPoint(x: 9 + cos(angle) * radius, y: 9 + sin(angle) * radius)
                    if index == 0 { path.move(to: point) } else { path.line(to: point) }
                }
                path.close()
                if selected { path.fill() }
            }
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

@MainActor final class LibraryRailButton: NSButton, LibraryPointerFeedback {
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
        LibraryPointerTracking.register(self)
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
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
        hovered = window.map { !isHiddenOrHasHiddenAncestor && visibleRect.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        needsDisplay = true
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
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
