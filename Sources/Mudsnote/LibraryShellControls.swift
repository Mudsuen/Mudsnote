import AppKit

@MainActor protocol LibraryPointerFeedback: AnyObject {
    func setPointerHovered(_ hovered: Bool)
}

/// Reconcile tracking areas after layout changes and pointer warps as well as
/// ordinary enter/exit events. Weak participants do not retain closed windows.
@MainActor enum LibraryPointerTracking {
    private static let views = NSHashTable<NSView>.weakObjects()
    private static var monitor: Any?

    static func register(_ view: NSView) {
        views.add(view)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [
            .mouseEntered, .mouseExited, .mouseMoved,
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .rightMouseDragged
        ]) { event in
            MainActor.assumeIsolated {
                for view in views.allObjects {
                    guard let feedback = view as? any LibraryPointerFeedback else { continue }
                    let inside = event.window === view.window
                        && !view.isHiddenOrHasHiddenAncestor
                        && view.visibleRect.contains(view.convert(event.locationInWindow, from: nil))
                    feedback.setPointerHovered(inside)
                }
            }
            return event
        }
    }
}

@MainActor final class LibraryWorkspaceSplitView: NSSplitView {
    override var dividerColor: NSColor { LibraryNotesPalette.separator }
}

/// The sidebar action lays out its content as views; NSButtonCell never measures
/// or wraps the title. The button remains the one keyboard/AX/hit-test target.
@MainActor final class SidebarNewNoteButton: NSButton, LibraryPointerFeedback {
    let glyph = NSImageView()
    let label = NSTextField(labelWithString: "新建笔记")
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
        glyph.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "新建笔记")?.withSymbolConfiguration(.init(pointSize: 16, weight: .regular))
        glyph.contentTintColor = .labelColor
        glyph.imageScaling = .scaleNone
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.cell?.wraps = false
        label.cell?.usesSingleLineMode = true
        for view in [glyph, label] {
            view.setAccessibilityElement(false)
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            glyph.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 18),
            glyph.heightAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: glyph.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        LibraryPointerTracking.register(self)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 32) }
    @objc private func pressed() { invoke?() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.contains(convert(point, from: superview)) else { return nil }
        return self
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
        isPointerHovered = window.map { !isHiddenOrHasHiddenAncestor && visibleRect.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        needsDisplay = true
    }
    override func mouseEntered(with event: NSEvent) { isPointerHovered = true; needsDisplay = true }
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
