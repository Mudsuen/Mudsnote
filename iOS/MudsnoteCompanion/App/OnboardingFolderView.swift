import SwiftUI

struct OnboardingFolderView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var chooseFolder: () -> Void

    @ViewBuilder
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView {
                VStack(spacing: 24) {
                    onboardingContent
                    chooseButton
                }
                .padding(.vertical, 24)
                .padding(.horizontal, MudsnoteSpacing.safeHorizontal)
            }
        } else {
            VStack(spacing: 24) {
                Spacer()
                onboardingContent
                Spacer()
                chooseButton
                    .padding(.bottom, 28)
            }
            .padding(.horizontal, MudsnoteSpacing.safeHorizontal)
        }
    }

    private var onboardingContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(MudsnoteColors.text)
                .frame(width: 86, height: 86)
                .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: 28))
                .overlay {
                    RoundedRectangle(cornerRadius: 28).stroke(MudsnoteColors.line, lineWidth: 1)
                }

            VStack(spacing: 8) {
                Text("Choose a Markdown Folder")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(MudsnoteColors.text)
                Text("Mudsnote only writes to the iCloud Drive folder you authorize. Markdown and attachments remain ordinary files.")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(MudsnoteColors.muted)
                    .multilineTextAlignment(.center)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 310)

            VStack(spacing: 8) {
                RequirementRow(icon: "paperclip", text: String(localized: "Create Attachments folder"))
                RequirementRow(icon: "arrow.triangle.2.circlepath", text: String(localized: "Enable the durable pending queue"))
            }
        }
    }

    private var chooseButton: some View {
        Button(action: chooseFolder) {
            Text("Choose Folder")
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .buttonStyle(CapsuleCommandButtonStyle(isPrimary: true))
        .accessibilityIdentifier("choose-folder-button")
    }
}

struct RequirementRow: View {
    var icon: String
    var text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(.callout, design: .rounded))
            .foregroundStyle(MudsnoteColors.muted)
            .frame(maxWidth: 310, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)
    }
}

struct FolderErrorView: View {
    var message: String
    var chooseFolder: () -> Void
    var forgetFolder: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(MudsnoteColors.text)
            Text("Folder Unavailable")
                .font(.headline)
                .foregroundStyle(MudsnoteColors.text)
            Text(message)
                .font(.callout)
                .foregroundStyle(MudsnoteColors.muted)
                .multilineTextAlignment(.center)
            Button("Choose Again", action: chooseFolder)
                .buttonStyle(CapsuleCommandButtonStyle(isPrimary: true))
                .accessibilityIdentifier("choose-folder-again-button")
            Button("Clear Old Permission", action: forgetFolder)
                .buttonStyle(CapsuleCommandButtonStyle(isPrimary: false))
                .accessibilityIdentifier("clear-folder-permission-button")
        }
        .padding(.horizontal, MudsnoteSpacing.safeHorizontal)
    }
}

struct StatusToastView: View {
    var toast: StatusToast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
            Text(toast.message)
            Spacer()
        }
        .font(.system(.callout, design: .rounded, weight: .semibold))
        .foregroundStyle(toast.style == .saved ? .black : MudsnoteColors.text)
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(background, in: Capsule())
        .overlay {
            Capsule().stroke(MudsnoteColors.line.opacity(toast.style == .saved ? 0 : 1), lineWidth: 1)
        }
    }

    private var icon: String {
        switch toast.style {
        case .saved:
            return "checkmark"
        case .pending:
            return "clock"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    private var background: Color {
        switch toast.style {
        case .saved:
            return MudsnoteColors.primary
        case .pending:
            return MudsnoteColors.card
        case .error:
            return Color(red: 0.26, green: 0.08, blue: 0.08)
        }
    }
}
