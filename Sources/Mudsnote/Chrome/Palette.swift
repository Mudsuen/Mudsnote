import AppKit

@MainActor
enum MudsnoteThemeColor: String, CaseIterable {
    case classicYellow
    case ocean
    case violet
    case teal
    case coral
    case rose
    case gray
    case black

    init(identifier: String) {
        self = Self(rawValue: identifier) ?? .ocean
    }

    var title: String {
        switch self {
        case .classicYellow: return "经典黄"
        case .ocean: return "海湾蓝"
        case .violet: return "靛紫"
        case .teal: return "松石"
        case .coral: return "珊瑚"
        case .rose: return "玫瑰"
        case .gray: return "石墨灰"
        case .black: return "炭黑"
        }
    }

    var foregroundColor: NSColor {
        switch self {
        case .classicYellow:
            return NSColor(calibratedRed: 1.0, green: 0.72, blue: 0.16, alpha: 1)
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
        case .gray:
            return NSColor(calibratedWhite: 0.62, alpha: 1)
        case .black:
            return NSColor(calibratedWhite: 0.24, alpha: 1)
        }
    }

    var noteSelectionColor: NSColor {
        switch self {
        case .classicYellow:
            return NSColor(calibratedRed: 0.492, green: 0.377, blue: 0.09, alpha: 0.96)
        case .black:
            return NSColor(calibratedWhite: 0.115, alpha: 0.98)
        default:
            return foregroundColor.blended(withFraction: 0.48, of: .black)?
                .withAlphaComponent(0.94) ?? foregroundColor.withAlphaComponent(0.78)
        }
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
