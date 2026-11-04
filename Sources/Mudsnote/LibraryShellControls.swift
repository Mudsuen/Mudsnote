import AppKit

/// Unclipped AppKit views can have a visibleRect larger than their own bounds.
/// Hover feedback must satisfy both rectangles, including after a relayout.
@MainActor enum LibraryPointerTracking {
    static func contains(_ view: NSView, event: NSEvent) -> Bool {
        guard let window = view.window, event.window === window else { return false }
        return contains(view, location: event.locationInWindow)
    }

    static func containsPointer(in view: NSView) -> Bool {
        guard let window = view.window else { return false }
        return contains(view, location: window.mouseLocationOutsideOfEventStream)
    }

    private static func contains(_ view: NSView, location: NSPoint) -> Bool {
        let point = view.convert(location, from: nil)
        return !view.isHiddenOrHasHiddenAncestor
            && view.bounds.contains(point) && view.visibleRect.contains(point)
    }
}

@MainActor final class LibraryWorkspaceSplitView: NSSplitView {
    override var dividerColor: NSColor { LibraryNotesPalette.separator }
    private var preferredSidebarWidth: NSLayoutConstraint?

    override func setPosition(_ position: CGFloat, ofDividerAt dividerIndex: Int) {
        super.setPosition(position, ofDividerAt: dividerIndex)
        guard dividerIndex == 0, let sidebar = arrangedSubviews.first, !sidebar.isHidden else { return }
        // The split controller is embedded in an Auto Layout shell. A frame-only
        // divider change otherwise snaps back to minimum width on the next pass.
        if preferredSidebarWidth == nil {
            let constraint = sidebar.widthAnchor.constraint(equalToConstant: sidebar.frame.width)
            constraint.priority = NSLayoutConstraint.Priority(rawValue: 251)
            constraint.isActive = true
            preferredSidebarWidth = constraint
        } else {
            preferredSidebarWidth?.constant = sidebar.frame.width
        }
    }
}

/// A compact compose action sharing the sidebar heading with search.
@MainActor final class SidebarNewNoteButton: NSButton {
    let glyph = NSImageView()
    var invoke: (() -> Void)?
    private var hoverArea: NSTrackingArea?
    private(set) var isPointerHovered = false

    init(action: @escaping () -> Void) {
        super.init(frame: .zero)
        invoke = action
        title = ""; image = nil; isBordered = false
        setButtonType(.momentaryChange)
        imageScaling = .scaleNone
        focusRingType = .exterior
        toolTip = "新建笔记"
        setAccessibilityLabel("新建笔记")
        target = self; self.action = #selector(pressed)
        glyph.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "新建笔记")?.withSymbolConfiguration(.init(pointSize: 16, weight: .light))
        glyph.contentTintColor = .labelColor
        glyph.imageScaling = .scaleNone
        glyph.setAccessibilityElement(false)
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)
        NSLayoutConstraint.activate([
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 18),
            glyph.heightAnchor.constraint(equalToConstant: 18)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: 28, height: 28) }
    @objc private func pressed() { invoke?() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.contains(convert(point, from: superview)) else { return nil }
        return self
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area); hoverArea = area
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
        if isEnabled && (isPointerHovered || isHighlighted) {
            NSColor.labelColor.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).fill()
        }
        super.draw(dirtyRect)
    }
}

/// Static text deliberately isn't an NSControl: native toolbar control tinting
/// must not turn the current-page label into a disabled-looking button.
@MainActor final class ToolbarPageTitleView: NSView {
    let text: String
    let font = NSFont.systemFont(ofSize: 16, weight: .medium)
    init(text: String) {
        self.text = text
        super.init(frame: NSRect(x: 0, y: 0, width: 160, height: 28))
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(text)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: 160, height: 28) }
    override var mouseDownCanMoveWindow: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let height = (text as NSString).size(withAttributes: attributes).height
        (text as NSString).draw(in: NSRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height), withAttributes: attributes)
    }
}
