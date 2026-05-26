import AppKit

@MainActor
func panelAccentColor() -> NSColor {
    .controlAccentColor
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
