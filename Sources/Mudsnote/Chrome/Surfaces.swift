import AppKit
import QuartzCore
import MudsnoteCore

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
    effect.blendingMode = .withinWindow
    effect.alphaValue = alpha
    effect.wantsLayer = true
    effect.layer?.cornerRadius = cornerRadius
    effect.layer?.masksToBounds = true
    effect.layer?.borderWidth = 1
    effect.layer?.borderColor = (tintColor ?? panelSeparatorColor()).cgColor
    effect.addSubview(content)
    pin(content, to: effect)
    return effect
}

@MainActor
final class GradientBackdropView: NSView {
    enum ChromeStyle {
        case standard
        case minimal
    }

    private let blurView = NSVisualEffectView()
    private let overlayView = NSView()
    private let gradientLayer = CAGradientLayer()
    private let highlightLayer = CALayer()
    private let glowLayer = CALayer()
    private let ambientLayer = CALayer()
    private var currentOpacity: CGFloat
    private var isLiveResizing = false
    var chromeStyle: ChromeStyle = .standard {
        didSet {
            applyAppearance()
            needsLayout = true
        }
    }

    init(frame frameRect: NSRect, panelOpacity: Double = NoteStore.defaultPanelOpacity) {
        currentOpacity = clampedPanelOpacity(panelOpacity)
        super.init(frame: frameRect)
        wantsLayer = true

        let rootLayer = CALayer()
        rootLayer.masksToBounds = false
        rootLayer.cornerRadius = 14
        rootLayer.borderWidth = 1
        rootLayer.borderColor = panelSeparatorColor(alpha: 0.18).cgColor
        rootLayer.shadowColor = NSColor.black.withAlphaComponent(0.22).cgColor
        rootLayer.shadowOpacity = 1
        rootLayer.shadowRadius = 20
        rootLayer.shadowOffset = CGSize(width: 0, height: -4)
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
        blurView.material = .popover
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

        switch chromeStyle {
        case .standard:
            layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.78 + (normalized * 0.08)).cgColor
            layer?.borderColor = panelSeparatorColor(alpha: 0.10 + (normalized * 0.04)).cgColor
            layer?.shadowColor = NSColor.black.withAlphaComponent(0.22).cgColor
            layer?.shadowRadius = 20
            layer?.shadowOffset = CGSize(width: 0, height: -4)
            layer?.shadowOpacity = isLiveResizing ? 0 : 1

            blurView.isHidden = isLiveResizing
            blurView.material = normalized < 0.55 ? .popover : .underWindowBackground
            gradientLayer.colors = [
                NSColor.controlBackgroundColor.withAlphaComponent(0.44 + (normalized * 0.05)).cgColor,
                NSColor.windowBackgroundColor.withAlphaComponent(0.28 + (normalized * 0.05)).cgColor
            ]
        case .minimal:
            layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.90 + (normalized * 0.03)).cgColor
            layer?.borderColor = panelSeparatorColor(alpha: 0.03 + (normalized * 0.015)).cgColor
            layer?.shadowColor = NSColor.black.withAlphaComponent(0.16).cgColor
            layer?.shadowRadius = 26
            layer?.shadowOffset = CGSize(width: 0, height: -7)
            layer?.shadowOpacity = isLiveResizing ? 0 : 1

            blurView.isHidden = isLiveResizing
            blurView.material = normalized < 0.48 ? .hudWindow : .underWindowBackground
            gradientLayer.colors = [
                NSColor.controlBackgroundColor.withAlphaComponent(0.18 + (normalized * 0.02)).cgColor,
                NSColor.windowBackgroundColor.withAlphaComponent(0.10 + (normalized * 0.015)).cgColor
            ]
        }

        highlightLayer.backgroundColor = NSColor.clear.cgColor
        glowLayer.backgroundColor = NSColor.clear.cgColor
        ambientLayer.backgroundColor = NSColor.clear.cgColor
    }
}
