import SwiftUI

struct SettingsRulesView: View {
    @EnvironmentObject private var appModel: AppModel
    var chooseFolder: () -> Void

    var body: some View {
        List {
            Section("Library") {
                HStack {
                    Label("Folder", systemImage: "folder")
                    Spacer()
                    if case .ready(let url) = appModel.folderStatus {
                        Text(url.lastPathComponent)
                            .foregroundStyle(MudsnoteColors.muted)
                            .lineLimit(1)
                    }
                }
                Button("Choose Another Folder", action: chooseFolder)
            }

            Section("Storage") {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Local Markdown")
                        Text("Notes and attachments stay in your selected folder.")
                            .font(.caption)
                            .foregroundStyle(MudsnoteColors.muted)
                    }
                } icon: {
                    Image(systemName: "internaldrive")
                        .foregroundStyle(MudsnoteColors.primary)
                }
            }

            if appModel.syncStatus != .idle || !appModel.conflictWarnings.isEmpty {
                Section("Needs Attention") {
                    if appModel.syncStatus == .pending {
                        Label("Some captures are waiting to be saved.", systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(MudsnoteColors.muted)
                    }
                    Button("Replay pending queue") {
                        appModel.replayQueue()
                    }

                    ForEach(appModel.conflictWarnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                    }
                }
            }

            Section("About") {
                SettingRow(title: String(localized: "Version"), value: appVersion)
            }
        }
        .scrollContentBackground(.hidden)
        .background(MudsnoteColors.canvas)
        .navigationTitle("Settings")
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}

struct SettingRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(MudsnoteColors.muted)
                .multilineTextAlignment(.trailing)
        }
    }
}
