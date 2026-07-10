import SwiftUI

struct OnboardingFolderView: View {
    var chooseFolder: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "folder.badge.plus")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(MudsnoteColors.text)
                .frame(width: 86, height: 86)
                .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: 28))
                .overlay {
                    RoundedRectangle(cornerRadius: 28).stroke(MudsnoteColors.line, lineWidth: 1)
                }

            VStack(spacing: 8) {
                Text("选择 Markdown 文件夹")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(MudsnoteColors.text)
                Text("Mudsnote iOS 只写入你授权的 iCloud Drive 文件夹。Markdown 和附件都保留为普通文件。")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(MudsnoteColors.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 310)

            VStack(spacing: 8) {
                RequirementRow(icon: "tray.fill", text: "初始化 Inbox.md")
                RequirementRow(icon: "calendar", text: "创建 Daily 与 Attachments")
                RequirementRow(icon: "arrow.triangle.2.circlepath", text: "启用可靠的待写队列")
            }

            Spacer()

            Button("选择文件夹", action: chooseFolder)
                .buttonStyle(CapsuleCommandButtonStyle(isPrimary: true))
                .padding(.bottom, 28)
        }
        .padding(.horizontal, MudsnoteSpacing.safeHorizontal)
    }
}

struct RequirementRow: View {
    var icon: String
    var text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(.callout, design: .rounded))
            .foregroundStyle(MudsnoteColors.muted)
            .frame(maxWidth: 260, alignment: .leading)
            .padding(.vertical, 4)
    }
}

struct FolderErrorView: View {
    var message: String
    var chooseFolder: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(MudsnoteColors.text)
            Text("无法访问文件夹")
                .font(.headline)
                .foregroundStyle(MudsnoteColors.text)
            Text(message)
                .font(.callout)
                .foregroundStyle(MudsnoteColors.muted)
                .multilineTextAlignment(.center)
            Button("重新选择", action: chooseFolder)
                .buttonStyle(CapsuleCommandButtonStyle(isPrimary: true))
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
