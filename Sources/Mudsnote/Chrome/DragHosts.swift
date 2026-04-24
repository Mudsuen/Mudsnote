import AppKit
import QuartzCore

/// `WindowMoveBackgroundView` reports itself as the hit target for empty areas
/// so that clicks do not fall through the borderless panel, while still allowing
/// the user to drag the whole window by its background.
@MainActor
class WindowMoveBackgroundView: NSView {
    private var dragStartScreenPoint: NSPoint?
    private var dragStartWindowOrigin: NSPoint?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        return super.hitTest(point) ?? self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            super.mouseDown(with: event)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        if !window.isKeyWindow {
            window.makeKeyAndOrderFront(nil)
        }

        dragStartScreenPoint = NSEvent.mouseLocation
        dragStartWindowOrigin = window.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            let window,
            let dragStartScreenPoint,
            let dragStartWindowOrigin
        else {
            super.mouseDragged(with: event)
            return
        }

        let currentMouseLocation = NSEvent.mouseLocation
        let deltaX = currentMouseLocation.x - dragStartScreenPoint.x
        let deltaY = currentMouseLocation.y - dragStartScreenPoint.y
        window.setFrameOrigin(
            NSPoint(
                x: dragStartWindowOrigin.x + deltaX,
                y: dragStartWindowOrigin.y + deltaY
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        dragStartScreenPoint = nil
        dragStartWindowOrigin = nil
        super.mouseUp(with: event)
    }
}

/// `SubviewPassthroughView` returns `nil` for hit tests on its own blank areas
/// so the window beneath stays interactive; but still forwards hits to any
/// real subview drawn on top.
@MainActor
class SubviewPassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

@MainActor
final class FocusProxyContainerView: NSView {
    var onFocusRequested: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        let hit = super.hitTest(point)
        return hit === self ? self : hit
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        if let onFocusRequested {
            onFocusRequested()
            return
        }
        super.mouseDown(with: event)
    }
}

@MainActor
final class FocusableTextField: NSTextField {
    func activateEditing(placingCaretAtEnd: Bool) {
        guard let window else { return }
        if window.firstResponder !== currentEditor() {
            window.makeFirstResponder(self)
        }

        selectText(nil)
        guard placingCaretAtEnd, let editor = currentEditor() else { return }
        editor.selectedRange = NSRange(location: stringValue.utf16.count, length: 0)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let wasEditing = window?.firstResponder === currentEditor()
        if !wasEditing {
            activateEditing(placingCaretAtEnd: true)
            return
        }
        super.mouseDown(with: event)
    }
}

@MainActor
final class FocusableTitleTextView: NSTextView {
    var onTextInputStateChanged: (() -> Void)?

    @discardableResult
    func activateEditing(placingCaretAtEnd: Bool) -> Bool {
        guard let window else { return false }
        _ = window.makeFirstResponder(nil)
        if window.firstResponder !== self {
            guard window.makeFirstResponder(self) else { return false }
        }
        guard placingCaretAtEnd else { return true }
        setSelectedRange(NSRange(location: string.utf16.count, length: 0))
        scrollRangeToVisible(selectedRange())
        return true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        if let window, window.firstResponder !== self {
            window.makeFirstResponder(self)
        }
        super.mouseDown(with: event)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        onTextInputStateChanged?()
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onTextInputStateChanged?()
    }

    override func unmarkText() {
        super.unmarkText()
        onTextInputStateChanged?()
    }
}

@MainActor
final class TitleEditorProxyView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

@MainActor
final class DragHandleView: WindowMoveBackgroundView {
    private let handleLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false
        handleLayer.cornerRadius = 1.5
        layer?.addSublayer(handleLayer)
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        handleLayer.frame = CGRect(x: bounds.midX - 22, y: bounds.midY - 1.5, width: 44, height: 3)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }

    private func updateAppearance() {
        handleLayer.backgroundColor = panelTertiaryTextColor().withAlphaComponent(0.42).cgColor
    }
}

@MainActor
final class PassthroughOverlayView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
