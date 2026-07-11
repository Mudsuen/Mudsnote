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
                    SettingRow(title: String(localized: "Default target"), value: "Inbox.md")
                    SettingRow(title: String(localized: "Daily path"), value: "Daily/yyyy-MM-dd.md")
                    SettingRow(title: String(localized: "Attachment path"), value: "Attachments/yyyy/MM")
                    SettingRow(title: String(localized: "Image reference"), value: "![Image](path)")
                    SettingRow(title: String(localized: "Audio reference"), value: "[Audio](path)")
                    SettingRow(title: String(localized: "Audio transcription"), value: String(localized: "Placeholder fallback"))
                }

                Section("Sync status") {
                    switch appModel.syncStatus {
                    case .idle:
                        SettingRow(title: String(localized: "Status"), value: String(localized: "Saved"))
                    case .pending:
                        SettingRow(title: String(localized: "Status"), value: String(localized: "Pending"))
                    case .conflict:
                        SettingRow(title: String(localized: "Status"), value: String(localized: "Conflict"))
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
