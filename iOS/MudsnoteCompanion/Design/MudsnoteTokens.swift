import SwiftUI

enum MudsnoteColors {
    static let canvas = Color.black
    static let panel = Color(hex: 0x080808)
    static let card = Color.white.opacity(0.10)
    static let line = Color.white.opacity(0.22)
    static let text = Color(hex: 0xF7F7F7)
    static let muted = Color(hex: 0xB8B8BD)
    static let primary = Color(hex: 0xF7F7F7)
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

extension View {
    @ViewBuilder
    func mudsnoteGlassSurface<S: Shape>(
        in shape: S,
        tint: Color = MudsnoteColors.card.opacity(0.58)
    ) -> some View {
        if #available(iOS 26.0, *) {
            background(tint, in: shape)
                .glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .background(tint, in: shape)
        }
    }
}

struct MudsnoteReaderSheetBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.055),
                    Color.black.opacity(0.98),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityIdentifier("note-reader-surface")
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
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
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
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
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
            .frame(width: 36, height: 36)
            .background(
                isActive && fillsActiveBackground ? MudsnoteColors.primary : Color.clear,
                in: Capsule()
            )
            .frame(width: 36, height: CaptureCommandMetrics.minimumHitHeight)
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

enum CaptureCommandMetrics {
    static let saveVisualWidth: CGFloat = 52
    static let saveVisualHeight: CGFloat = 32
    static let minimumHitHeight: CGFloat = MudsnoteSpacing.tapTargetMin
}

struct CaptureSaveButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isActive ? Color.black : MudsnoteColors.muted)
            .frame(
                width: CaptureCommandMetrics.saveVisualWidth,
                height: CaptureCommandMetrics.saveVisualHeight
            )
            .mudsnoteGlassSurface(
                in: Capsule(),
                tint: isActive
                    ? MudsnoteColors.primary.opacity(0.82)
                    : MudsnoteColors.card.opacity(0.32)
            )
            .overlay {
                Capsule()
                    .stroke(MudsnoteColors.line.opacity(isActive ? 0.35 : 0.7), lineWidth: 0.75)
            }
            .frame(
                width: CaptureCommandMetrics.saveVisualWidth,
                height: CaptureCommandMetrics.minimumHitHeight
            )
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
