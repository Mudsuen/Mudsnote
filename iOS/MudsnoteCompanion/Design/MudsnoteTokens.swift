import SwiftUI

enum MudsnoteColors {
    static let canvas = Color(hex: 0x050608)
    static let panel = Color(hex: 0x12141A)
    static let card = Color(hex: 0x1A1D24)
    static let line = Color(hex: 0x2A2D35)
    static let text = Color(hex: 0xECEDEF)
    static let muted = Color(hex: 0xA4A7AD)
    static let primary = Color(hex: 0xF2F3F5)
    static let captureAccent = Color(hex: 0x0A84FF)
}

enum MudsnoteRadius {
    static let bottomSheet: CGFloat = 42
    static let panel: CGFloat = 34
    static let card: CGFloat = 24
    static let pill: CGFloat = 999
}

enum MudsnoteSpacing {
    static let safeHorizontal: CGFloat = 24
    static let tapTargetMin: CGFloat = 44
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

struct CapsuleCommandButtonStyle: ButtonStyle {
    var isPrimary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(isPrimary ? .black : MudsnoteColors.text)
            .frame(minHeight: MudsnoteSpacing.tapTargetMin)
            .padding(.horizontal, 16)
            .background(isPrimary ? MudsnoteColors.primary : MudsnoteColors.card)
            .clipShape(Capsule())
            .overlay {
                Capsule().stroke(MudsnoteColors.line.opacity(isPrimary ? 0 : 1), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct IconCircleButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isActive ? .black : MudsnoteColors.text)
            .frame(width: 48, height: 48)
            .background(isActive ? MudsnoteColors.primary : MudsnoteColors.card)
            .clipShape(Circle())
            .overlay {
                Circle().stroke(MudsnoteColors.line, lineWidth: isActive ? 0 : 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct CompactCaptureButtonStyle: ButtonStyle {
    var isActive = false
    var fillsActiveBackground = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(
                isActive
                    ? (fillsActiveBackground ? Color.black : Color.red)
                    : MudsnoteColors.text
            )
            .frame(width: 36, height: 40)
            .background(
                isActive && fillsActiveBackground ? MudsnoteColors.primary : Color.clear,
                in: Capsule()
            )
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.62 : 1)
    }
}
