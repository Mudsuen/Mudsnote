import SwiftUI

struct TargetMenuView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Menu {
            if !appModel.recentCaptureFolders.isEmpty {
                Section("Recently Used") {
                    ForEach(appModel.recentCaptureFolders) { folder in
                        Button {
                            appModel.selectCaptureFolder(folder.relativePath)
                        } label: {
                            Label(folder.name, systemImage: "clock.fill")
                        }
                        .accessibilityIdentifier(
                            "recent-capture-folder-\(folder.relativePath)"
                        )
                    }
                }
            }

            Button {
                appModel.selectCaptureFolder(nil)
            } label: {
                Label("Top Level", systemImage: "folder")
            }

            if !appModel.allFolders.isEmpty {
                Section("Create New Note In") {
                    ForEach(appModel.allFolders) { folder in
                        Button {
                            appModel.selectCaptureFolder(folder.relativePath)
                        } label: {
                            Label(folder.name, systemImage: "folder.fill")
                        }
                        .accessibilityIdentifier("capture-target-folder-\(folder.relativePath)")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                Text(appModel.draft.target.compactLabel)
                    .lineLimit(1)
            }
            .font(.system(.caption, design: .default, weight: .semibold))
            .foregroundStyle(MudsnoteColors.text)
            .padding(.horizontal, 5)
            .frame(width: 72, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            String(
                format: String(localized: "New note in %@"),
                locale: .current,
                appModel.draft.target.compactLabel
            )
        )
        .accessibilityValue(appModel.draft.target.compactLabel)
        .accessibilityIdentifier("capture-target-menu")
    }
}

private extension CaptureTarget {
    var compactLabel: String {
        label
    }
}
