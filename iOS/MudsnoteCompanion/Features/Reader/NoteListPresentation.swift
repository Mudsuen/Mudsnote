import SwiftUI
import ImageIO
import UIKit

enum NoteSortOrder: String, CaseIterable, Identifiable {
    case modified
    case created
    case title

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .modified: "Date Edited"
        case .created: "Date Created"
        case .title: "Title"
        }
    }

    var dateBasis: NoteDateBasis {
        self == .created ? .created : .modified
    }
}

enum NoteSortDirection: String, CaseIterable, Identifiable {
    case standard
    case reversed

    var id: String { rawValue }

    func label(for order: NoteSortOrder) -> LocalizedStringKey {
        switch (order, self) {
        case (.title, .standard): "Ascending"
        case (.title, .reversed): "Descending"
        case (_, .standard): "Newest First"
        case (_, .reversed): "Oldest First"
        }
    }
}

enum NoteViewStyle: String, CaseIterable, Identifiable {
    case list
    case gallery

    var id: String { rawValue }
}

enum NoteDateBasis {
    case modified
    case created

    func date(for file: RecentMarkdownFile) -> Date {
        if self == .created, file.createdAt != .distantPast {
            return file.createdAt
        }
        return file.modifiedAt
    }
}

struct NoteDateSection: Identifiable, Equatable {
    var id: String
    var title: String?
    var files: [RecentMarkdownFile]
}

enum NoteListPresentation {
    static func sorted(
        _ files: [RecentMarkdownFile],
        by order: NoteSortOrder,
        direction: NoteSortDirection = .standard
    ) -> [RecentMarkdownFile] {
        files.sorted { lhs, rhs in
            let orderedAscending: Bool
            switch order {
            case .modified:
                if lhs.modifiedAt != rhs.modifiedAt {
                    orderedAscending = lhs.modifiedAt > rhs.modifiedAt
                    return direction == .standard ? orderedAscending : !orderedAscending
                }
            case .created:
                let lhsDate = lhs.createdAt == .distantPast ? lhs.modifiedAt : lhs.createdAt
                let rhsDate = rhs.createdAt == .distantPast ? rhs.modifiedAt : rhs.createdAt
                if lhsDate != rhsDate {
                    orderedAscending = lhsDate > rhsDate
                    return direction == .standard ? orderedAscending : !orderedAscending
                }
            case .title:
                let comparison = lhs.title.localizedStandardCompare(rhs.title)
                if comparison != .orderedSame {
                    orderedAscending = comparison == .orderedAscending
                    return direction == .standard ? orderedAscending : !orderedAscending
                }
            }
            orderedAscending = lhs.relativePath.localizedStandardCompare(rhs.relativePath)
                == .orderedAscending
            return direction == .standard ? orderedAscending : !orderedAscending
        }
    }

    static func sections(
        for files: [RecentMarkdownFile],
        sortedBy order: NoteSortOrder,
        direction: NoteSortDirection = .standard,
        groupByDate: Bool,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [NoteDateSection] {
        let ordered = sorted(files, by: order, direction: direction)
        guard groupByDate, order != .title, !ordered.isEmpty else {
            return ordered.isEmpty ? [] : [NoteDateSection(id: "notes", title: nil, files: ordered)]
        }

        var sections: [NoteDateSection] = []
        for file in ordered {
            let date = order.dateBasis.date(for: file)
            let bucket = dateBucket(for: date, now: now, calendar: calendar)
            if sections.last?.id == bucket.id {
                sections[sections.count - 1].files.append(file)
            } else {
                sections.append(NoteDateSection(id: bucket.id, title: bucket.title, files: [file]))
            }
        }
        return sections
    }

    static func dateBucket(
        for date: Date,
        now: Date,
        calendar: Calendar
    ) -> (id: String, title: String) {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        if day >= today {
            return ("today", String(localized: "Today"))
        }
        if day >= (calendar.date(byAdding: .day, value: -1, to: today) ?? today) {
            return ("yesterday", String(localized: "Yesterday"))
        }
        if day >= (calendar.date(byAdding: .day, value: -7, to: today) ?? today) {
            return ("previous-7", String(localized: "Previous 7 Days"))
        }
        if day >= (calendar.date(byAdding: .day, value: -30, to: today) ?? today) {
            return ("previous-30", String(localized: "Previous 30 Days"))
        }
        let components = calendar.dateComponents([.year, .month], from: day)
        let id = String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
        return (id, day.formatted(.dateTime.month(.wide).year()))
    }
}

struct NoteListOptionsMenu: View {
    @Binding var viewStyleRawValue: String
    @Binding var sortOrderRawValue: String
    @Binding var sortDirectionRawValue: String
    @Binding var groupByDate: Bool
    var selectNotes: () -> Void

    var body: some View {
        Menu {
            Button(action: selectNotes) {
                Label("Select Notes", systemImage: "checkmark.circle")
            }
            Divider()
            NoteViewStyleMenuContent(viewStyleRawValue: $viewStyleRawValue)
            Divider()
            NoteListSortMenuContent(
                sortOrderRawValue: $sortOrderRawValue,
                sortDirectionRawValue: $sortDirectionRawValue,
                groupByDate: $groupByDate
            )
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Sort Notes")
        .accessibilityIdentifier("note-list-options")
    }
}

struct HomeNoteOptionsMenu: View {
    @Binding var viewStyleRawValue: String
    @Binding var sortOrderRawValue: String
    @Binding var sortDirectionRawValue: String
    @Binding var groupByDate: Bool
    var selectNotes: () -> Void
    var viewAttachments: () -> Void

    var body: some View {
        HomeNoteOptionsButton(
            viewStyleRawValue: $viewStyleRawValue,
            sortOrderRawValue: $sortOrderRawValue,
            sortDirectionRawValue: $sortDirectionRawValue,
            groupByDate: $groupByDate,
            selectNotes: selectNotes,
            viewAttachments: viewAttachments
        )
        .frame(width: 28, height: 28)
    }
}

struct HomeNoteOptionsButton: UIViewRepresentable {
    @Binding var viewStyleRawValue: String
    @Binding var sortOrderRawValue: String
    @Binding var sortDirectionRawValue: String
    @Binding var groupByDate: Bool
    var selectNotes: () -> Void
    var viewAttachments: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(
            UIImage(
                systemName: "ellipsis",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
            ),
            for: .normal
        )
        button.tintColor = .label
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = String(localized: "More")
        button.accessibilityIdentifier = "home-note-options"
        context.coordinator.updateMenu(on: button, force: true)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateMenu(on: button)
    }

    @MainActor
    final class Coordinator {
        private struct MenuState: Equatable {
            var viewStyleRawValue: String
            var sortOrderRawValue: String
            var sortDirectionRawValue: String
            var groupByDate: Bool
        }

        var parent: HomeNoteOptionsButton
        private var presentedState: MenuState?

        init(parent: HomeNoteOptionsButton) {
            self.parent = parent
        }

        func updateMenu(on button: UIButton, force: Bool = false) {
            let state = MenuState(
                viewStyleRawValue: parent.viewStyleRawValue,
                sortOrderRawValue: parent.sortOrderRawValue,
                sortDirectionRawValue: parent.sortDirectionRawValue,
                groupByDate: parent.groupByDate
            )
            guard force || state != presentedState else { return }
            button.menu = makeMenu(for: state)
            presentedState = state
        }

        private func makeMenu(for state: MenuState) -> UIMenu {
            let viewStyle = NoteViewStyle(rawValue: state.viewStyleRawValue) ?? .gallery
            let sortOrder = NoteSortOrder(rawValue: state.sortOrderRawValue) ?? .modified
            let sortDirection = NoteSortDirection(rawValue: state.sortDirectionRawValue) ?? .standard

            let viewAction = UIAction(
                title: String(localized: viewStyle == .gallery ? "View as List" : "View as Cards"),
                image: UIImage(systemName: viewStyle == .gallery ? "list.bullet" : "square.grid.2x2")
            ) { [weak self] _ in
                self?.parent.viewStyleRawValue = viewStyle == .gallery
                    ? NoteViewStyle.list.rawValue
                    : NoteViewStyle.gallery.rawValue
            }
            let viewGroup = UIMenu(options: .displayInline, children: [viewAction])

            let selectAction = UIAction(
                title: String(localized: "Select Notes"),
                image: UIImage(systemName: "checkmark.circle")
            ) { [weak self] _ in self?.parent.selectNotes() }

            let sortMenu = UIMenu(
                title: String(localized: "Sort By"),
                subtitle: sortSummary(sortOrder),
                image: UIImage(systemName: "arrow.up.arrow.down"),
                children: [sortOrderMenu(selected: sortOrder), sortDirectionMenu(
                    selected: sortDirection,
                    order: sortOrder
                )]
            )
            let groupMenu = UIMenu(
                title: String(localized: "Group By Date"),
                subtitle: state.groupByDate ? String(localized: "On") : String(localized: "Off"),
                image: UIImage(systemName: "calendar"),
                children: groupActions(disabled: sortOrder == .title)
            )
            let attachmentsAction = UIAction(
                title: String(localized: "View Attachments"),
                image: UIImage(systemName: "paperclip")
            ) { [weak self] _ in self?.parent.viewAttachments() }
            let commandGroup = UIMenu(
                options: .displayInline,
                children: [selectAction, sortMenu, groupMenu, attachmentsAction]
            )
            return UIMenu(children: [viewGroup, commandGroup])
        }

        private func sortOrderMenu(selected: NoteSortOrder) -> UIMenu {
            let actions = NoteSortOrder.allCases.map { order in
                UIAction(
                    title: sortOrderTitle(order),
                    state: order == selected ? .on : .off
                ) { [weak self] _ in self?.parent.sortOrderRawValue = order.rawValue }
            }
            return UIMenu(options: .displayInline, children: actions)
        }

        private func sortDirectionMenu(
            selected: NoteSortDirection,
            order: NoteSortOrder
        ) -> UIMenu {
            let actions = NoteSortDirection.allCases.map { direction in
                UIAction(
                    title: sortDirectionTitle(direction, order: order),
                    state: direction == selected ? .on : .off
                ) { [weak self] _ in
                    self?.parent.sortDirectionRawValue = direction.rawValue
                }
            }
            return UIMenu(options: .displayInline, children: actions)
        }

        private func groupActions(disabled: Bool) -> [UIMenuElement] {
            [true, false].map { value in
                UIAction(
                    title: value ? String(localized: "On") : String(localized: "Off"),
                    attributes: disabled ? .disabled : [],
                    state: parent.groupByDate == value ? .on : .off
                ) { [weak self] _ in self?.parent.groupByDate = value }
            }
        }

        private func sortSummary(_ order: NoteSortOrder) -> String {
            switch order {
            case .modified: String(localized: "Default (Date Edited)")
            case .created: String(localized: "Date Created")
            case .title: String(localized: "Title")
            }
        }

        private func sortOrderTitle(_ order: NoteSortOrder) -> String {
            switch order {
            case .modified: String(localized: "Date Edited")
            case .created: String(localized: "Date Created")
            case .title: String(localized: "Title")
            }
        }

        private func sortDirectionTitle(
            _ direction: NoteSortDirection,
            order: NoteSortOrder
        ) -> String {
            switch (order, direction) {
            case (.title, .standard): String(localized: "Ascending")
            case (.title, .reversed): String(localized: "Descending")
            case (_, .standard): String(localized: "Newest First")
            case (_, .reversed): String(localized: "Oldest First")
            }
        }
    }
}

struct NoteViewStyleMenuContent: View {
    @Binding var viewStyleRawValue: String

    private var viewStyle: NoteViewStyle {
        NoteViewStyle(rawValue: viewStyleRawValue) ?? .list
    }

    var body: some View {
        Button {
            viewStyleRawValue = viewStyle == .list
                ? NoteViewStyle.gallery.rawValue
                : NoteViewStyle.list.rawValue
        } label: {
            Label(
                viewStyle == .list ? "View as Gallery" : "View as List",
                systemImage: viewStyle == .list ? "square.grid.2x2" : "list.bullet"
            )
        }
        .accessibilityIdentifier("toggle-note-view-style")
    }
}

struct NoteListSortMenuContent: View {
    @Binding var sortOrderRawValue: String
    @Binding var sortDirectionRawValue: String
    @Binding var groupByDate: Bool

    private var sortOrder: NoteSortOrder {
        NoteSortOrder(rawValue: sortOrderRawValue) ?? .modified
    }

    var body: some View {
        Picker("Sort By", selection: $sortOrderRawValue) {
            ForEach(NoteSortOrder.allCases) { order in
                Text(order.label).tag(order.rawValue)
            }
        }
        Picker("Order", selection: $sortDirectionRawValue) {
            ForEach(NoteSortDirection.allCases) { direction in
                Text(direction.label(for: sortOrder)).tag(direction.rawValue)
            }
        }
        Toggle("Group By Date", isOn: $groupByDate)
            .disabled(sortOrder == .title)
    }
}

struct NoteListSearchResultsView: View {
    var query: String
    var results: [MarkdownSearchResult]
    var isPending: Bool
    var open: (MarkdownSearchResult) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if isPending {
                    ProgressView("Searching…")
                        .frame(maxWidth: .infinity)
                        .padding(32)
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                } else {
                    ForEach(results) { result in
                        Button {
                            open(result)
                        } label: {
                            SearchResultRow(result: result, query: query)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("list-search-result-\(result.id)")

                        if result.id != results.last?.id {
                            Divider().padding(.leading, 18)
                        }
                    }
                }
            }
            .background(
                results.isEmpty ? Color.clear : MudsnoteColors.card,
                in: RoundedRectangle(cornerRadius: MudsnoteRadius.card)
            )
            .overlay {
                if !results.isEmpty {
                    RoundedRectangle(cornerRadius: MudsnoteRadius.card)
                        .stroke(MudsnoteColors.line, lineWidth: 1)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("note-list-search-results")
    }
}

func localizedNoteCount(_ count: Int) -> String {
    let format = count == 1
        ? String(localized: "note.count.format")
        : String(localized: "notes.count.format")
    return String(format: format, locale: .current, count)
}

struct NotesListCountLabel: View {
    var count: Int

    var body: some View {
        Text(localizedNoteCount(count))
        .font(.subheadline)
        .foregroundStyle(MudsnoteColors.muted)
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
        .accessibilityIdentifier("note-list-count")
    }
}

struct NoteListPaginationFooter: View {
    var pageToken: Int
    var loadMore: () -> Void

    var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .accessibilityLabel("Loading More Notes")
            .accessibilityIdentifier("note-list-load-more")
            .id(pageToken)
            .task {
                await Task.yield()
                loadMore()
            }
    }
}

struct NotesListSectionHeader: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.system(.title3, design: .rounded, weight: .bold))
            .foregroundStyle(MudsnoteColors.text)
            .textCase(nil)
            .padding(.bottom, 4)
            .listRowInsets(
                EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0)
            )
            .accessibilityAddTraits(.isHeader)
    }
}
