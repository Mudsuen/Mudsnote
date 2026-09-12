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
final class MaterialBackdropView: NSView {
    enum ChromeStyle {
        case standard
        case minimal
    }

    private let blurView = NSVisualEffectView()
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

        layer?.backgroundColor = isLiveResizing ? NSColor.windowBackgroundColor.cgColor : NSColor.clear.cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.18).cgColor
        layer?.shadowOpacity = isLiveResizing ? 0 : 1
        blurView.isHidden = isLiveResizing
        blurView.material = chromeStyle == .minimal ? .underWindowBackground : .popover
        blurView.alphaValue = 0.85 + normalized * 0.15
    }
}
