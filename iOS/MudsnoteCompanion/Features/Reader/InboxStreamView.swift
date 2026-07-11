import SwiftUI

struct InboxStreamView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationStack {
            List {
                if appModel.inboxItems.isEmpty {
                    EmptyReaderStateView(
                        title: String(localized: "No Memos Yet"),
                        message: String(localized: "Tap the add button to write your first memo to Inbox.md.")
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(MudsnoteColors.canvas)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(appModel.inboxItems) { memo in
                        MemoCardView(memo: memo)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                appModel.selectedMemo = memo
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    appModel.addDefaultTag(to: memo)
                                } label: {
                                    Label("Tag", systemImage: "number")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    appModel.deleteMemo(memo)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    appModel.pinMemo(memo)
                                } label: {
                                    Label("Pin", systemImage: "pin")
                                }
                                .tint(.yellow)
                            }
                            .listRowInsets(.init(top: 6, leading: MudsnoteSpacing.safeHorizontal, bottom: 6, trailing: MudsnoteSpacing.safeHorizontal))
                            .listRowSeparator(.hidden)
                            .listRowBackground(MudsnoteColors.canvas)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable {
                await appModel.refreshInbox()
            }
            .background(MudsnoteColors.canvas)
            .navigationTitle("Inbox")
        }
    }
}

struct MemoCardView: View {
    var memo: MemoBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(memo.dateText)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(MudsnoteColors.muted)
                Spacer()
                if !memo.tags.isEmpty {
                    Text(memo.tags.prefix(2).joined(separator: " "))
                        .font(.caption2)
                        .foregroundStyle(MudsnoteColors.muted)
                        .lineLimit(1)
                }
            }
            Text(memo.preview)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(MudsnoteColors.text)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: MudsnoteRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: MudsnoteRadius.card)
                .stroke(MudsnoteColors.line, lineWidth: 1)
        }
    }
}
