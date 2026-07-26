import AppKit

@MainActor
enum MudsnoteThemeColor: String, CaseIterable {
    case ocean
    case violet
    case teal
    case coral
    case rose

    init(identifier: String) {
        self = Self(rawValue: identifier) ?? .ocean
    }

    var title: String {
        switch self {
        case .ocean: return "海湾蓝"
        case .violet: return "靛紫"
        case .teal: return "松石"
        case .coral: return "珊瑚"
        case .rose: return "玫瑰"
        }
    }

    var foregroundColor: NSColor {
        switch self {
        case .ocean:
            return NSColor(calibratedRed: 0.49, green: 0.70, blue: 1.0, alpha: 1)
        case .violet:
            return NSColor(calibratedRed: 0.73, green: 0.62, blue: 1.0, alpha: 1)
        case .teal:
            return NSColor(calibratedRed: 0.42, green: 0.84, blue: 0.78, alpha: 1)
        case .coral:
            return NSColor(calibratedRed: 1.0, green: 0.58, blue: 0.50, alpha: 1)
        case .rose:
            return NSColor(calibratedRed: 0.97, green: 0.61, blue: 0.78, alpha: 1)
        }
    }

    var sourceSelectionBackgroundColor: NSColor {
        switch self {
        case .ocean:
            return NSColor(calibratedRed: 0.10, green: 0.20, blue: 0.34, alpha: 0.94)
        case .violet:
            return NSColor(calibratedRed: 0.22, green: 0.15, blue: 0.36, alpha: 0.94)
        case .teal:
            return NSColor(calibratedRed: 0.08, green: 0.26, blue: 0.25, alpha: 0.94)
        case .coral:
            return NSColor(calibratedRed: 0.35, green: 0.15, blue: 0.13, alpha: 0.94)
        case .rose:
            return NSColor(calibratedRed: 0.33, green: 0.13, blue: 0.23, alpha: 0.94)
        }
    }

    var noteSelectionBackgroundColor: NSColor {
        switch self {
        case .ocean:
            return NSColor(calibratedRed: 0.12, green: 0.25, blue: 0.44, alpha: 0.96)
        case .violet:
            return NSColor(calibratedRed: 0.30, green: 0.21, blue: 0.46, alpha: 0.96)
        case .teal:
            return NSColor(calibratedRed: 0.10, green: 0.34, blue: 0.32, alpha: 0.96)
        case .coral:
            return NSColor(calibratedRed: 0.45, green: 0.20, blue: 0.17, alpha: 0.96)
        case .rose:
            return NSColor(calibratedRed: 0.42, green: 0.18, blue: 0.30, alpha: 0.96)
        }
    }

    var selectedCountColor: NSColor {
        foregroundColor.blended(withFraction: 0.32, of: .white)?.withAlphaComponent(0.68)
            ?? foregroundColor.withAlphaComponent(0.68)
    }

    var swatchImage: NSImage {
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size)
        image.lockFocus()
        foregroundColor.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

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
