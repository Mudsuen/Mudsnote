import AppKit

/// `QuickEntryPanel` is the borderless floating-panel workhorse behind quick
/// capture, floating note, and search. It adds manual edge-resize, keyboard
/// routing for the editor (via `onEditorCommand`/`onStandardEditCommand`), and
/// a handful of app-level shortcuts (Cmd-S, Cmd-F, Escape).
///
/// `HitCatchingView` lives beside the panel so that `installCursorRects` can
/// stay `fileprivate` — cursor-rect setup is a tight coupling between panel
/// and its root content view, not a public building block.
@MainActor
final class QuickEntryPanel: NSPanel {
    private struct ResizeEdge: OptionSet {
        let rawValue: Int

        static let left = ResizeEdge(rawValue: 1 << 0)
        static let right = ResizeEdge(rawValue: 1 << 1)
        static let bottom = ResizeEdge(rawValue: 1 << 2)
        static let top = ResizeEdge(rawValue: 1 << 3)
    }

    var onCommandS: (() -> Void)?
    var onCommandF: (() -> Void)?
    var onEscape: (() -> Void)?
    var onLeftMouseDownPreflight: ((NSEvent) -> Void)?
    var onEditorCommand: ((NSEvent) -> Bool)?
    var onStandardEditCommand: ((Selector) -> Bool)?
    private let sideResizeHandleWidth: CGFloat = 8
    private let bottomResizeHandleWidth: CGFloat = 6
    private let topResizeHandleWidth: CGFloat = 4

    private var activeResizeEdges: ResizeEdge = []
    private var resizeInitialFrame: NSRect = .zero
    private var resizeInitialMouseScreen: NSPoint = .zero

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        animationBehavior = .utilityWindow
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        // Window dragging is handled explicitly by `WindowMoveBackgroundView`;
        // keeping AppKit's background-drag path enabled causes the borderless
        // panel to fight the custom resize path near the edges.
        isMovableByWindowBackground = false
        minSize = NSSize(width: 300, height: 260)
        let rootContentView = HitCatchingView(panel: self, frame: NSRect(origin: .zero, size: size))
        rootContentView.wantsLayer = true
        rootContentView.layerContentsRedrawPolicy = .onSetNeedsDisplay
        rootContentView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.001).cgColor
        rootContentView.layer?.cornerRadius = 14
        rootContentView.layer?.masksToBounds = true
        contentView = rootContentView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if !isKeyWindow {
                NSApp.activate(ignoringOtherApps: true)
                makeKeyAndOrderFront(nil)
            }
            onLeftMouseDownPreflight?(event)
            if beginManualResizeIfNeeded(with: event) {
                return
            }
        case .leftMouseDragged:
            if continueManualResize(with: event) {
                return
            }
        case .leftMouseUp:
            if endManualResizeIfActive() {
                super.sendEvent(event)
                return
            }
        default:
            break
        }

        guard event.type == .keyDown else {
            super.sendEvent(event)
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if modifiers == [.command], event.keyCode == 1 {
            onCommandS?()
            return
        }

        if modifiers == [.command], event.keyCode == 3 {
            onCommandF?()
            return
        }

        if let selector = standardEditSelector(for: event), onStandardEditCommand?(selector) == true {
            return
        }

        if onEditorCommand?(event) == true {
            return
        }

        if modifiers.isEmpty, event.keyCode == 53 {
            onEscape?()
            return
        }

        super.sendEvent(event)
    }

    private func standardEditSelector(for event: NSEvent) -> Selector? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch (modifiers, event.keyCode) {
        case ([.command], 8): return #selector(NSText.copy(_:)) // c
        case ([.command], 7): return #selector(NSText.cut(_:)) // x
        case ([.command], 9): return #selector(NSText.paste(_:)) // v
        case ([.command], 0): return #selector(NSResponder.selectAll(_:)) // a
        case ([.command], 6): return #selector(UndoManager.undo) // z
        case ([.command, .shift], 6): return #selector(UndoManager.redo) // shift+z
        default: return nil
        }
    }

    private func beginManualResizeIfNeeded(with event: NSEvent) -> Bool {
        guard let contentView else { return false }

        let location = event.locationInWindow
        let edges = resizeEdges(at: location, in: contentView.bounds)
        guard !edges.isEmpty else { return false }

        activeResizeEdges = edges
        resizeInitialFrame = frame
        resizeInitialMouseScreen = convertPoint(toScreen: location)
        return true
    }

    private func continueManualResize(with event: NSEvent) -> Bool {
        guard !activeResizeEdges.isEmpty else { return false }

        let currentMouseScreen = NSEvent.mouseLocation
        let deltaX = currentMouseScreen.x - resizeInitialMouseScreen.x
        let deltaY = currentMouseScreen.y - resizeInitialMouseScreen.y
        var nextFrame = resizeInitialFrame

        if activeResizeEdges.contains(.left) {
            nextFrame.origin.x = resizeInitialFrame.origin.x + deltaX
            nextFrame.size.width = resizeInitialFrame.size.width - deltaX
        }
        if activeResizeEdges.contains(.right) {
            nextFrame.size.width = resizeInitialFrame.size.width + deltaX
        }
        if activeResizeEdges.contains(.bottom) {
            nextFrame.origin.y = resizeInitialFrame.origin.y + deltaY
            nextFrame.size.height = resizeInitialFrame.size.height - deltaY
        }
        if activeResizeEdges.contains(.top) {
            nextFrame.size.height = resizeInitialFrame.size.height + deltaY
        }

        if nextFrame.size.width < minSize.width {
            if activeResizeEdges.contains(.left) {
                nextFrame.origin.x = resizeInitialFrame.maxX - minSize.width
            }
            nextFrame.size.width = minSize.width
        }

        if nextFrame.size.height < minSize.height {
            if activeResizeEdges.contains(.bottom) {
                nextFrame.origin.y = resizeInitialFrame.maxY - minSize.height
            }
            nextFrame.size.height = minSize.height
        }

        setFrame(nextFrame, display: true)
        return true
    }

    private func endManualResizeIfActive() -> Bool {
        guard !activeResizeEdges.isEmpty else { return false }
        activeResizeEdges = []
        return true
    }

    private func resizeEdges(at point: NSPoint, in bounds: NSRect) -> ResizeEdge {
        var edges: ResizeEdge = []
        if point.x <= sideResizeHandleWidth { edges.insert(.left) }
        if point.x >= bounds.width - sideResizeHandleWidth { edges.insert(.right) }
        if point.y <= bottomResizeHandleWidth { edges.insert(.bottom) }
        if point.y >= bounds.height - topResizeHandleWidth { edges.insert(.top) }
        return edges
    }

    fileprivate func installCursorRects(in view: NSView) {
        let bounds = view.bounds
        let sideHeight = max(bounds.height - bottomResizeHandleWidth - topResizeHandleWidth, 0)
        let horizontalWidth = max(bounds.width - (sideResizeHandleWidth * 2), 0)

        if sideHeight > 0 {
            view.addCursorRect(
                NSRect(x: 0, y: bottomResizeHandleWidth, width: sideResizeHandleWidth, height: sideHeight),
                cursor: .resizeLeftRight
            )
            view.addCursorRect(
                NSRect(x: bounds.width - sideResizeHandleWidth, y: bottomResizeHandleWidth, width: sideResizeHandleWidth, height: sideHeight),
                cursor: .resizeLeftRight
            )
        }

        if horizontalWidth > 0 {
            view.addCursorRect(
                NSRect(x: sideResizeHandleWidth, y: 0, width: horizontalWidth, height: bottomResizeHandleWidth),
                cursor: .resizeUpDown
            )
            view.addCursorRect(
                NSRect(x: sideResizeHandleWidth, y: bounds.height - topResizeHandleWidth, width: horizontalWidth, height: topResizeHandleWidth),
                cursor: .resizeUpDown
            )
        }
    }

}

@MainActor
private final class HitCatchingView: WindowMoveBackgroundView {
    private weak var panel: QuickEntryPanel?

    init(panel: QuickEntryPanel, frame: NSRect) {
        self.panel = panel
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        panel?.installCursorRects(in: self)
    }
}
