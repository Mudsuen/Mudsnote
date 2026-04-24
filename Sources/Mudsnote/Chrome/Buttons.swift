import AppKit

@MainActor
private final class OffsetImageButtonCell: NSButtonCell {
    var imageOffsetY: CGFloat = 0

    override func imageRect(forBounds rect: NSRect) -> NSRect {
        var imageRect = super.imageRect(forBounds: rect)
        imageRect.origin.y += imageOffsetY
        return imageRect
    }
}

@MainActor
func styleAccentButton(_ button: NSButton) {
    button.bezelStyle = .rounded
    button.controlSize = .regular
    button.contentTintColor = .white
    button.imageHugsTitle = true
    if #available(macOS 13.0, *) {
        button.bezelColor = panelAccentColor()
    }
}

@MainActor
func styleSecondaryButton(_ button: NSButton) {
    button.bezelStyle = .rounded
    button.controlSize = .regular
    button.contentTintColor = panelPrimaryTextColor()
    button.imageHugsTitle = true
    if #available(macOS 13.0, *) {
        button.bezelColor = NSColor.controlBackgroundColor.withAlphaComponent(0.9)
    }
}

@MainActor
func styleToolbarButton(_ button: NSButton) {
    button.bezelStyle = .texturedRounded
    button.controlSize = .large
    button.contentTintColor = .white
}

@MainActor
final class HoverToolbarButton: NSButton {
    private var trackingAreaRef: NSTrackingArea?
    private(set) var isHovered = false
    var imageOffsetY: CGFloat = 0 {
        didSet {
            (cell as? OffsetImageButtonCell)?.imageOffsetY = imageOffsetY
            needsDisplay = true
        }
    }
    var preferredSize: NSSize? {
        didSet { invalidateIntrinsicContentSize() }
    }
    var isActive = false { didSet { updateAppearance() } }
    var isWindowFocused = true { didSet { updateAppearance() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let buttonCell = OffsetImageButtonCell()
        buttonCell.imagePosition = .imageOnly
        cell = buttonCell
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

    override var intrinsicContentSize: NSSize {
        preferredSize ?? super.intrinsicContentSize
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        layer?.cornerRadius = 7
        let foregroundColor: NSColor
        let highlightColor: NSColor
        if isActive {
            foregroundColor = .white
            highlightColor = panelAccentColor().withAlphaComponent(isWindowFocused ? 0.90 : 0.72)
        } else if isHovered {
            foregroundColor = panelPrimaryTextColor()
            highlightColor = NSColor.controlBackgroundColor.withAlphaComponent(isWindowFocused ? 0.62 : 0.48)
        } else {
            foregroundColor = isWindowFocused ? panelSecondaryTextColor() : panelTertiaryTextColor()
            highlightColor = panelSubtleFillColor().withAlphaComponent(isWindowFocused ? 0.86 : 0.64)
        }
        layer?.backgroundColor = (isActive || isHovered) ? highlightColor.cgColor : NSColor.clear.cgColor
        layer?.borderWidth = 0
        layer?.borderColor = NSColor.clear.cgColor
        alphaValue = isWindowFocused ? 1.0 : 0.92
        contentTintColor = foregroundColor
        if !title.isEmpty {
            attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: font ?? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
                    .foregroundColor: foregroundColor
                ]
            )
        }
    }
}

@MainActor
struct PillButtonPalette {
    let foreground: NSColor
    let background: NSColor
    let border: NSColor
    let shadowColor: NSColor
    let shadowOpacity: Float
    let shadowRadius: CGFloat
    let shadowOffset: CGSize
}

@MainActor
class ModernPillButton: NSButton {
    private var trackingAreaRef: NSTrackingArea?
    private(set) var isHovered = false
    var isWindowFocused = true { didSet { updateAppearance() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .none
        wantsLayer = true
        isBordered = false
        bezelStyle = .shadowlessSquare
        imageHugsTitle = true
        setButtonType(.momentaryChange)
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
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

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        updateAppearance()
    }

    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func currentPalette() -> PillButtonPalette {
        fatalError("Subclasses must provide a palette")
    }

    func updateAppearance() {
        let palette = currentPalette()
        layer?.cornerRadius = 11
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = palette.background.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = palette.border.cgColor
        layer?.shadowColor = palette.shadowColor.cgColor
        layer?.shadowOpacity = palette.shadowOpacity
        layer?.shadowRadius = palette.shadowRadius
        layer?.shadowOffset = palette.shadowOffset

        alphaValue = isWindowFocused ? 1.0 : 0.94
        contentTintColor = palette.foreground
        image?.isTemplate = true
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: font ?? NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: palette.foreground
            ]
        )
    }
}

@MainActor
final class FocusAwareAccentButton: ModernPillButton {
    override func currentPalette() -> PillButtonPalette {
        let accent = panelAccentColor()
        let foreground = NSColor.white.withAlphaComponent(isEnabled ? 0.98 : 0.72)
        let background: NSColor
        let border: NSColor

        if !isEnabled {
            background = accent.withAlphaComponent(0.34)
            border = .clear
        } else if isHighlighted {
            background = accent.withAlphaComponent(isWindowFocused ? 0.80 : 0.62)
            border = .clear
        } else if isHovered {
            background = accent.withAlphaComponent(isWindowFocused ? 0.96 : 0.72)
            border = .clear
        } else {
            background = accent.withAlphaComponent(isWindowFocused ? 0.88 : 0.68)
            border = .clear
        }

        return PillButtonPalette(
            foreground: foreground,
            background: background,
            border: border,
            shadowColor: NSColor.black.withAlphaComponent(isWindowFocused ? 0.18 : 0.10),
            shadowOpacity: isWindowFocused ? 1 : 0.82,
            shadowRadius: isHovered ? 8 : 6,
            shadowOffset: CGSize(width: 0, height: -1)
        )
    }
}

@MainActor
final class FocusAwareSecondaryButton: ModernPillButton {
    override func currentPalette() -> PillButtonPalette {
        let foreground: NSColor
        let background: NSColor
        let border: NSColor

        if !isEnabled {
            foreground = panelTertiaryTextColor()
            background = NSColor.controlBackgroundColor.withAlphaComponent(0.42)
            border = .clear
        } else if isHighlighted {
            foreground = panelPrimaryTextColor()
            background = NSColor.controlBackgroundColor.withAlphaComponent(isWindowFocused ? 0.98 : 0.82)
            border = .clear
        } else if isHovered {
            foreground = panelPrimaryTextColor()
            background = NSColor.controlBackgroundColor.withAlphaComponent(isWindowFocused ? 0.78 : 0.62)
            border = .clear
        } else {
            foreground = isWindowFocused ? panelPrimaryTextColor() : panelSecondaryTextColor()
            background = NSColor.controlBackgroundColor.withAlphaComponent(isWindowFocused ? 0.72 : 0.58)
            border = .clear
        }

        return PillButtonPalette(
            foreground: foreground,
            background: background,
            border: border,
            shadowColor: NSColor.black.withAlphaComponent(isWindowFocused ? 0.05 : 0.02),
            shadowOpacity: isWindowFocused ? 1 : 0.7,
            shadowRadius: isHovered ? 4 : 2,
            shadowOffset: CGSize(width: 0, height: -1)
        )
    }
}

@MainActor
final class FocusAwareGhostButton: NSButton {
    private var trackingAreaRef: NSTrackingArea?
    private(set) var isHovered = false
    var isWindowFocused = true { didSet { updateAppearance() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .none
        wantsLayer = true
        isBordered = false
        bezelStyle = .shadowlessSquare
        imageHugsTitle = true
        setButtonType(.momentaryChange)
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
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

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func updateAppearance() {
        let foreground: NSColor
        let background: NSColor

        if isHighlighted {
            foreground = panelPrimaryTextColor()
            background = NSColor.controlBackgroundColor.withAlphaComponent(isWindowFocused ? 0.72 : 0.56)
        } else if isHovered {
            foreground = panelPrimaryTextColor()
            background = NSColor.controlBackgroundColor.withAlphaComponent(isWindowFocused ? 0.54 : 0.40)
        } else {
            foreground = isWindowFocused ? panelSecondaryTextColor() : panelTertiaryTextColor()
            background = .clear
        }

        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = background.cgColor
        layer?.borderWidth = 0
        layer?.shadowOpacity = 0
        alphaValue = isWindowFocused ? 1.0 : 0.92
        contentTintColor = foreground
        image?.isTemplate = true
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: font ?? NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: foreground
            ]
        )
    }
}
