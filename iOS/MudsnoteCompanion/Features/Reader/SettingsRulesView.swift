import SwiftUI

struct SettingsRulesView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isDiscardRecoveryPresented = false
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

                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Protected Quick Draft")
                        Text("An unfinished quick note stays in protected app storage and is excluded from device backups until submitted.")
                            .font(.caption)
                            .foregroundStyle(MudsnoteColors.muted)
                    }
                } icon: {
                    Image(systemName: "lock.doc")
                        .foregroundStyle(MudsnoteColors.primary)
                }
            }

            Section("Privacy") {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No Mudsnote Account")
                        Text("Mudsnote does not upload your notes. Sync and backup behavior follows the folder provider you choose.")
                            .font(.caption)
                            .foregroundStyle(MudsnoteColors.muted)
                    }
                } icon: {
                    Image(systemName: "hand.raised")
                        .foregroundStyle(MudsnoteColors.primary)
                }
            }

            if let issue = appModel.draftRecoveryIssue {
                Section("Quick Note Recovery") {
                    Label(issue, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(MudsnoteColors.muted)
                    Button("Try Recovery Again") {
                        appModel.retryCaptureDraftRecovery()
                    }
                    Button("Discard Unrecoverable Draft", role: .destructive) {
                        isDiscardRecoveryPresented = true
                    }
                }
            }

            if appModel.syncStatus != .idle || !appModel.conflictWarnings.isEmpty {
                Section("Needs Attention") {
                    if appModel.syncStatus == .pending {
                        Label("Some captures are waiting to be saved.", systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(MudsnoteColors.muted)
                        Button("Replay pending queue") {
                            appModel.replayQueue()
                        }
                    }

                    if !appModel.conflictFiles.isEmpty {
                        NavigationLink {
                            ConflictResolutionView()
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Review Conflicts")
                                    Text("Conflict copies are preserved until you review them.")
                                        .font(.caption)
                                        .foregroundStyle(MudsnoteColors.muted)
                                }
                            } icon: {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .accessibilityIdentifier("review-conflicts-link")
                    }

                    ForEach(appModel.recoveryWarnings, id: \.self) { warning in
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
        .alert("Discard Unrecoverable Draft?", isPresented: $isDiscardRecoveryPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Discard", role: .destructive) {
                appModel.discardUnrecoverableCaptureDraft()
            }
        } message: {
            Text("This removes only the damaged app-private quick note recovery data. Notes already saved in your selected folder are not changed.")
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}

private struct ConflictResolutionView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var conflictToDelete: RecentMarkdownFile?

    var body: some View {
        List {
            Section {
                Text("Conflict copies are kept as separate Markdown files so no version is overwritten. Open one to review it, then keep it as a normal note or move it to Recently Deleted.")
                    .font(.subheadline)
                    .foregroundStyle(MudsnoteColors.muted)
            }

            if appModel.conflictFiles.isEmpty {
                ContentUnavailableView(
                    "No Conflicts",
                    systemImage: "checkmark.circle",
                    description: Text("All detected conflict copies have been reviewed.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section("Conflict Copies") {
                    ForEach(appModel.conflictFiles) { file in
                        HStack(spacing: 12) {
                            Button {
                                appModel.openFile(file)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "doc.badge.ellipsis")
                                        .foregroundStyle(.orange)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(file.title)
                                            .foregroundStyle(MudsnoteColors.text)
                                            .lineLimit(1)
                                        Text(file.relativePath)
                                            .font(.caption)
                                            .foregroundStyle(MudsnoteColors.muted)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("conflict-file-row-\(file.relativePath)")

                            Menu {
                                Button {
                                    appModel.keepConflictCopy(file)
                                } label: {
                                    Label("Keep as Separate Note", systemImage: "checkmark.circle")
                                }
                                Button(role: .destructive) {
                                    conflictToDelete = file
                                } label: {
                                    Label("Move to Recently Deleted", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title3)
                                    .foregroundStyle(MudsnoteColors.muted)
                                    .frame(width: 36, height: 36)
                            }
                            .accessibilityIdentifier("conflict-actions-\(file.relativePath)")
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(MudsnoteColors.canvas)
        .navigationTitle("Conflicts")
        .refreshable { await appModel.refreshInbox() }
        .confirmationDialog(
            "Move Conflict to Recently Deleted?",
            isPresented: Binding(
                get: { conflictToDelete != nil },
                set: { if !$0 { conflictToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move to Recently Deleted", role: .destructive) {
                guard let file = conflictToDelete else { return }
                appModel.moveToRecentlyDeleted(file)
                conflictToDelete = nil
            }
            Button("Cancel", role: .cancel) { conflictToDelete = nil }
        } message: {
            Text("You can restore this conflict copy later from Recently Deleted.")
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
