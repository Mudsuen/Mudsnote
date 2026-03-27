import AppKit
import CryptoKit
import QuartzCore
import QuickMarkdownCore

@MainActor
func displayPath(_ url: URL) -> String {
    (url.path as NSString).abbreviatingWithTildeInPath
}

func sha256Hex(_ value: String) -> String {
    let digest = SHA256.hash(data: Data(value.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

@MainActor
func chooseDirectory(startingAt directory: URL?) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = "Choose"
    panel.directoryURL = directory

    guard panel.runModal() == .OK else { return nil }
    return panel.url
}

@MainActor
func pin(_ child: NSView, to parent: NSView, insets: NSEdgeInsets = .init(top: 0, left: 0, bottom: 0, right: 0)) {
    child.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: insets.left),
        child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -insets.right),
        child.topAnchor.constraint(equalTo: parent.topAnchor, constant: insets.top),
        child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -insets.bottom)
    ])
}

@MainActor
func insetted(_ content: NSView, padding: NSEdgeInsets) -> NSView {
    let wrapper = NSView()
    wrapper.addSubview(content)
    pin(content, to: wrapper, insets: padding)
    return wrapper
}

@MainActor
func makeModernSurface(
    content: NSView,
    cornerRadius: CGFloat,
    tintColor: NSColor? = nil,
    alpha: CGFloat = 0.88,
    material: NSVisualEffectView.Material = .underWindowBackground
) -> NSView {
    if #available(macOS 26.0, *) {
        let glass = NSGlassEffectView(frame: .zero)
        glass.cornerRadius = cornerRadius
        glass.style = .regular
        glass.tintColor = tintColor
        glass.alphaValue = alpha
        glass.contentView = content
        return glass
    }

    let effect = NSVisualEffectView()
    effect.material = material
    effect.state = .active
    effect.blendingMode = .behindWindow
    effect.alphaValue = alpha
    effect.wantsLayer = true
    effect.layer?.cornerRadius = cornerRadius
    effect.layer?.masksToBounds = true
    effect.layer?.borderWidth = 1
    effect.layer?.borderColor = (tintColor ?? NSColor.white.withAlphaComponent(0.08)).cgColor
    effect.addSubview(content)
    pin(content, to: effect)
    return effect
}

@MainActor
func clampedPanelOpacity(_ rawOpacity: Double) -> CGFloat {
    min(max(CGFloat(rawOpacity), CGFloat(NoteStore.minimumPanelOpacity)), CGFloat(NoteStore.maximumPanelOpacity))
}

@MainActor
func normalizedPanelOpacity(_ rawOpacity: Double) -> CGFloat {
    let clamped = clampedPanelOpacity(rawOpacity)
    let lower = CGFloat(NoteStore.minimumPanelOpacity)
    let upper = CGFloat(NoteStore.maximumPanelOpacity)
    let span = max(upper - lower, 0.01)
    return (clamped - lower) / span
}

@MainActor
func accentSurfaceAlpha(for rawOpacity: Double) -> CGFloat {
    0.84 + (normalizedPanelOpacity(rawOpacity) * 0.10)
}

@MainActor
func primarySurfaceAlpha(for rawOpacity: Double) -> CGFloat {
    0.80 + (normalizedPanelOpacity(rawOpacity) * 0.12)
}

@MainActor
func secondarySurfaceAlpha(for rawOpacity: Double) -> CGFloat {
    0.76 + (normalizedPanelOpacity(rawOpacity) * 0.10)
}

@MainActor
func styleAccentButton(_ button: NSButton) {
    button.bezelStyle = .rounded
    button.controlSize = .large
    button.contentTintColor = .white
    if #available(macOS 13.0, *) {
        button.bezelColor = NSColor(calibratedWhite: 0.20, alpha: 0.96)
    }
}

@MainActor
final class HoverToolbarButton: NSButton {
    private var trackingAreaRef: NSTrackingArea?
    private(set) var isHovered = false
    var isActive = false { didSet { updateAppearance() } }
    var isWindowFocused = true { didSet { updateAppearance() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        isBordered = false
        bezelStyle = .shadowlessSquare
        focusRingType = .none
        contentTintColor = NSColor.white.withAlphaComponent(0.74)
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaRef = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    private func updateAppearance() {
        layer?.cornerRadius = 6
        let shouldHighlight = isActive || isHovered
        layer?.backgroundColor = shouldHighlight ? NSColor.white.withAlphaComponent(isWindowFocused ? 0.10 : 0.06).cgColor : NSColor.clear.cgColor
        layer?.borderWidth = shouldHighlight ? 1 : 0
        layer?.borderColor = NSColor.white.withAlphaComponent(isWindowFocused ? 0.12 : 0.07).cgColor
        alphaValue = isWindowFocused ? 1.0 : 0.52
        let baseTint = isActive ? (isWindowFocused ? 0.94 : 0.58) : (isWindowFocused ? 0.74 : 0.38)
        contentTintColor = NSColor.white.withAlphaComponent(baseTint)
    }
}

@MainActor
final class SlimScroller: NSScroller {
    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        8
    }
}

@MainActor
final class FocusAwareAccentButton: NSButton {
    var isWindowFocused = true { didSet { updateAppearance() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .none
        wantsLayer = true
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateAppearance() {
        bezelStyle = .rounded
        contentTintColor = .white
        if #available(macOS 13.0, *) {
            bezelColor = isWindowFocused
                ? NSColor(calibratedWhite: 0.18, alpha: 0.76)
                : NSColor(calibratedWhite: 0.16, alpha: 0.62)
        }
        alphaValue = isWindowFocused ? 1.0 : 0.78
    }
}

@MainActor
func styleSecondaryButton(_ button: NSButton) {
    button.bezelStyle = .rounded
    button.controlSize = .large
    button.contentTintColor = .white
    if #available(macOS 13.0, *) {
        button.bezelColor = NSColor.white.withAlphaComponent(0.06)
    }
}

@MainActor
func styleToolbarButton(_ button: NSButton) {
    button.bezelStyle = .texturedRounded
    button.controlSize = .large
    button.contentTintColor = .white
}

@MainActor
func positionPanelNearTopCenter(_ window: NSWindow, topMargin: CGFloat = 72) {
    let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
    guard let screen else { return }

    let frame = screen.visibleFrame
    let origin = NSPoint(
        x: frame.midX - (window.frame.width / 2),
        y: frame.maxY - window.frame.height - topMargin
    )
    window.setFrameOrigin(origin)
}

@MainActor
func windowAlphaValue(for rawOpacity: Double) -> CGFloat {
    0.84 + (normalizedPanelOpacity(rawOpacity) * 0.12)
}

@MainActor
protocol WindowOpacityAdjusting: AnyObject {
    func updatePanelOpacity(_ opacity: Double)
}

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
    var onEditorCommand: ((NSEvent) -> Bool)?
    var onStandardEditCommand: ((Selector) -> Bool)?
    private let sideResizeHandleWidth: CGFloat = 20
    private let bottomResizeHandleWidth: CGFloat = 20
    private let topResizeHandleWidth: CGFloat = 6

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        animationBehavior = .none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        minSize = NSSize(width: 330, height: 260)
        acceptsMouseMovedEvents = true

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
        if event.type == .leftMouseDown, handleManualResizeIfNeeded(with: event) {
            return
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

    override func mouseMoved(with event: NSEvent) {
        updateCursor(for: event.locationInWindow)
        super.mouseMoved(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(for: event.locationInWindow)
    }

    private func standardEditSelector(for event: NSEvent) -> Selector? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch (modifiers, event.keyCode) {
        case ([.command], 8): return #selector(NSText.copy(_:)) // c
        case ([.command], 7): return #selector(NSText.cut(_:)) // x
        case ([.command], 9): return #selector(NSText.paste(_:)) // v
        case ([.command], 0): return #selector(NSResponder.selectAll(_:)) // a
        case ([.command], 6): return Selector(("undo:")) // z
        case ([.command, .shift], 6): return Selector(("redo:")) // shift+z
        default: return nil
        }
    }

    private func handleManualResizeIfNeeded(with event: NSEvent) -> Bool {
        guard styleMask.contains(.resizable),
              let contentView else { return false }

        let location = event.locationInWindow
        let resizeEdges = resizeEdges(at: location, in: contentView.bounds)
        guard !resizeEdges.isEmpty else { return false }

        performManualResize(from: event, edges: resizeEdges)
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
        view.addCursorRect(NSRect(x: 0, y: 0, width: sideResizeHandleWidth, height: bounds.height), cursor: .resizeLeftRight)
        view.addCursorRect(NSRect(x: bounds.width - sideResizeHandleWidth, y: 0, width: sideResizeHandleWidth, height: bounds.height), cursor: .resizeLeftRight)
        view.addCursorRect(NSRect(x: 0, y: 0, width: bounds.width, height: bottomResizeHandleWidth), cursor: .resizeUpDown)
        view.addCursorRect(NSRect(x: 0, y: bounds.height - topResizeHandleWidth, width: bounds.width, height: topResizeHandleWidth), cursor: .resizeUpDown)
    }

    private func updateCursor(for location: NSPoint) {
        guard let contentView else { return }
        let edges = resizeEdges(at: location, in: contentView.bounds)
        if edges.contains(.left) || edges.contains(.right) {
            NSCursor.resizeLeftRight.set()
        } else if edges.contains(.top) || edges.contains(.bottom) {
            NSCursor.resizeUpDown.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func performManualResize(from initialEvent: NSEvent, edges: ResizeEdge) {
        let initialFrame = frame
        let initialMouseLocation = NSEvent.mouseLocation

        while let nextEvent = nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if nextEvent.type == .leftMouseUp {
                break
            }

            let currentMouseLocation = NSEvent.mouseLocation
            let deltaX = currentMouseLocation.x - initialMouseLocation.x
            let deltaY = currentMouseLocation.y - initialMouseLocation.y
            var nextFrame = initialFrame

            if edges.contains(.left) {
                nextFrame.origin.x += deltaX
                nextFrame.size.width -= deltaX
            }
            if edges.contains(.right) {
                nextFrame.size.width += deltaX
            }
            if edges.contains(.bottom) {
                nextFrame.origin.y += deltaY
                nextFrame.size.height -= deltaY
            }
            if edges.contains(.top) {
                nextFrame.size.height += deltaY
            }

            if nextFrame.size.width < minSize.width {
                if edges.contains(.left) {
                    nextFrame.origin.x = initialFrame.maxX - minSize.width
                }
                nextFrame.size.width = minSize.width
            }

            if nextFrame.size.height < minSize.height {
                if edges.contains(.bottom) {
                    nextFrame.origin.y = initialFrame.maxY - minSize.height
                }
                nextFrame.size.height = minSize.height
            }

            setFrame(nextFrame, display: true)
        }
    }
}

@MainActor
private final class HitCatchingView: NSView {
    private weak var panel: QuickEntryPanel?

    init(panel: QuickEntryPanel, frame: NSRect) {
        self.panel = panel
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        return super.hitTest(point) ?? self
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        panel?.installCursorRects(in: self)
    }
}

@MainActor
final class DragHandleView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

@MainActor
final class GradientBackdropView: NSView {
    private let blurView = NSVisualEffectView()
    private let overlayView = NSView()
    private let gradientLayer = CAGradientLayer()
    private let highlightLayer = CALayer()
    private let glowLayer = CALayer()
    private let ambientLayer = CALayer()
    private var currentOpacity: CGFloat
    private var isLiveResizing = false

    init(frame frameRect: NSRect, panelOpacity: Double = NoteStore.defaultPanelOpacity) {
        currentOpacity = clampedPanelOpacity(panelOpacity)
        super.init(frame: frameRect)
        wantsLayer = true

        let rootLayer = CALayer()
        rootLayer.masksToBounds = false
        rootLayer.cornerRadius = 14
        rootLayer.borderWidth = 1
        rootLayer.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        rootLayer.shadowColor = NSColor.black.withAlphaComponent(0.48).cgColor
        rootLayer.shadowOpacity = 1
        rootLayer.shadowRadius = 28
        rootLayer.shadowOffset = CGSize(width: 0, height: -10)
        rootLayer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "shadowPath": NSNull(),
            "shadowOpacity": NSNull(),
            "backgroundColor": NSNull(),
            "borderColor": NSNull()
        ]
        layer = rootLayer

        blurView.state = .active
        blurView.blendingMode = .behindWindow
        blurView.material = .hudWindow
        blurView.alphaValue = 1
        blurView.wantsLayer = true
        addSubview(blurView)
        pin(blurView, to: self)

        overlayView.wantsLayer = true
        overlayView.layer = CALayer()
        addSubview(overlayView)
        pin(overlayView, to: self)

        gradientLayer.startPoint = CGPoint(x: 0, y: 1)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0)
        highlightLayer.backgroundColor = NSColor.white.withAlphaComponent(0.09).cgColor
        overlayView.layer?.addSublayer(gradientLayer)
        overlayView.layer?.addSublayer(glowLayer)
        overlayView.layer?.addSublayer(ambientLayer)
        overlayView.layer?.addSublayer(highlightLayer)
        applyAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = 14
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 14, cornerHeight: 14, transform: nil)
        blurView.layer?.cornerRadius = 14
        blurView.layer?.masksToBounds = true
        overlayView.layer?.cornerRadius = 14
        overlayView.layer?.masksToBounds = true
        gradientLayer.frame = overlayView.bounds

        highlightLayer.frame = CGRect(x: 0, y: overlayView.bounds.height - 1, width: overlayView.bounds.width, height: 1)
        glowLayer.frame = CGRect(x: overlayView.bounds.width - 240, y: overlayView.bounds.height - 190, width: 250, height: 250)
        glowLayer.cornerRadius = 140
        ambientLayer.frame = CGRect(x: -36, y: -64, width: 220, height: 190)
        ambientLayer.cornerRadius = 110
    }

    func updatePanelOpacity(_ opacity: Double) {
        currentOpacity = clampedPanelOpacity(opacity)
        applyAppearance()
    }

    func setLiveResizing(_ resizing: Bool) {
        isLiveResizing = resizing
        applyAppearance()
    }

    private func applyAppearance() {
        let opacity = currentOpacity
        let lower = CGFloat(NoteStore.minimumPanelOpacity)
        let upper = CGFloat(NoteStore.maximumPanelOpacity)
        let normalized = (opacity - lower) / max(upper - lower, 0.01)

        layer?.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 0.92 + (normalized * 0.04)).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.06 + (normalized * 0.04)).cgColor
        layer?.shadowOpacity = isLiveResizing ? 0 : 1

        blurView.isHidden = isLiveResizing
        blurView.material = normalized < 0.55 ? .hudWindow : .sidebar

        gradientLayer.colors = [
            NSColor(calibratedWhite: 0.08, alpha: 0.92 + (normalized * 0.04)).cgColor,
            NSColor(calibratedWhite: 0.12, alpha: 0.96 + (normalized * 0.03)).cgColor
        ]
        highlightLayer.backgroundColor = NSColor.white.withAlphaComponent(0.04 + (normalized * 0.02)).cgColor
        glowLayer.backgroundColor = NSColor.clear.cgColor
        ambientLayer.backgroundColor = NSColor.clear.cgColor
    }
}
