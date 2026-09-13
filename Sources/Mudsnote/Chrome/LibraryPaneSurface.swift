import AppKit

/// Native window material with stable navigation/content contrast in either appearance.
@MainActor
final class LibraryPaneSurface: NSView {
    enum Role { case navigation, document }
    let role: Role
    private let materialView = NSVisualEffectView()
    private let tintView = NSView()

    init(role: Role, providesMaterial: Bool = false) {
        self.role = role
        super.init(frame: .zero)
        materialView.material = .sidebar
        materialView.blendingMode = .behindWindow
        materialView.state = .active
        materialView.isHidden = !providesMaterial
        tintView.wantsLayer = true
        for view in [materialView, tintView] {
            addSubview(view)
            pin(view, to: self)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refreshAppearance),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        refreshAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func refreshAppearance() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        materialView.alphaValue = 1
        let white: CGFloat = opaque ? (dark ? 0.17 : 0.96) : 0
        let alpha: CGFloat = opaque ? 1 : (role == .navigation ? 0.035 : 0)
        tintView.layer?.backgroundColor = NSColor(calibratedWhite: white, alpha: alpha).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }
}

/// Rounded search chrome, preserving NSSearchField editing and keyboard focus.
@MainActor
final class LibrarySearchField: NSSearchField {
    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }
}
