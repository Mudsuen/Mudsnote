import AppKit

@MainActor
func panelAccentColor() -> NSColor {
    if #available(macOS 10.14, *) {
        return .controlAccentColor
    }
    return .systemBlue
}

@MainActor
func panelPrimaryTextColor() -> NSColor {
    .labelColor
}

@MainActor
func panelSecondaryTextColor() -> NSColor {
    .secondaryLabelColor
}

@MainActor
func panelTertiaryTextColor() -> NSColor {
    .tertiaryLabelColor
}

@MainActor
func panelSeparatorColor(alpha: CGFloat = 0.82) -> NSColor {
    NSColor.separatorColor.withAlphaComponent(alpha)
}

@MainActor
func panelSubtleFillColor() -> NSColor {
    NSColor.quaternaryLabelColor.withAlphaComponent(0.10)
}
