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
            Image(systemName: "folder")
        }
        .buttonStyle(IconCircleButtonStyle())
    }
}
