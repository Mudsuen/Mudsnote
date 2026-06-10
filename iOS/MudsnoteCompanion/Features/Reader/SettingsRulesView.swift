import SwiftUI

struct SettingsRulesView: View {
    @EnvironmentObject private var appModel: AppModel
    var chooseFolder: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Folder") {
                    HStack {
                        Text("Root")
                        Spacer()
                        if case .ready(let url) = appModel.folderStatus {
                            Text(url.lastPathComponent)
                                .foregroundStyle(MudsnoteColors.muted)
                        }
                    }
                    Button("Choose another folder", action: chooseFolder)
                    Button("Replay pending queue") {
                        appModel.replayQueue()
                    }
                }

                Section("Write rules") {
                    SettingRow(title: "Default target", value: "Inbox.md")
                    SettingRow(title: "Daily path", value: "Daily/yyyy-MM-dd.md")
                    SettingRow(title: "Attachment path", value: "Attachments/yyyy/MM")
                    SettingRow(title: "Image reference", value: "![Image](path)")
                    SettingRow(title: "Audio reference", value: "[Audio](path)")
                    SettingRow(title: "Audio transcription", value: "Placeholder fallback")
                }

                Section("Sync status") {
                    switch appModel.syncStatus {
                    case .idle:
                        SettingRow(title: "Status", value: "Saved")
                    case .pending:
                        SettingRow(title: "Status", value: "Pending")
                    case .conflict:
                        SettingRow(title: "Status", value: "Conflict")
                    }

                    ForEach(appModel.conflictWarnings, id: \.self) { warning in
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(MudsnoteColors.muted)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(MudsnoteColors.canvas)
            .navigationTitle("Settings")
        }
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
