import SwiftUI

struct TargetMenuView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Menu {
            Button {
                appModel.draft.target = .inbox
            } label: {
                Label("Inbox.md", systemImage: "tray.fill")
            }

            Button {
                appModel.draft.target = .daily(Date())
            } label: {
                Label("Daily", systemImage: "calendar")
            }

            if !appModel.recentFiles.isEmpty {
                Section("Recent") {
                    ForEach(appModel.recentFiles.prefix(6)) { file in
                        Button {
                            appModel.draft.target = .recent(file.relativePath)
                        } label: {
                            Label(file.title, systemImage: "doc.text")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                Text(appModel.draft.target.compactLabel)
                    .lineLimit(1)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(MudsnoteColors.text)
            .padding(.horizontal, 12)
            .frame(height: 42)
            .frame(maxWidth: 104)
            .background(MudsnoteColors.card, in: Capsule())
            .overlay {
                Capsule().stroke(MudsnoteColors.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("保存目标 \(appModel.draft.target.compactLabel)")
    }
}

private extension CaptureTarget {
    var compactLabel: String {
        switch self {
        case .inbox:
            return "Inbox"
        case .daily:
            return "Daily"
        case .recent(let path):
            return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        }
    }
}
