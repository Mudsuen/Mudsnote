import AppKit

/// Keep native search/cancel controls and field-editor behavior inside rounded chrome.
@MainActor final class LibrarySearchField: NSSearchField {
    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                   xRadius: 9, yRadius: 9)
        NSColor.textBackgroundColor.withAlphaComponent(0.65).setFill()
        outline.fill()
        NSColor.separatorColor.withAlphaComponent(0.35).setStroke()
        outline.lineWidth = 1
        outline.stroke()
        super.draw(dirtyRect)
    }
}
