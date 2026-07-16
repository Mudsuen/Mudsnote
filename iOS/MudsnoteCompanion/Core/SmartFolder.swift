import Foundation

enum SmartFolderMatchMode: String, Codable, CaseIterable, Identifiable {
    case all
    case any

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: String(localized: "All")
        case .any: String(localized: "Any")
        }
    }
}

enum SmartFolderDateFilter: String, Codable, CaseIterable, Identifiable {
    case editedToday
    case editedPast7Days
    case editedPast30Days
    case createdToday
    case createdPast7Days
    case createdPast30Days

    var id: String { rawValue }

    var label: String {
        switch self {
        case .editedToday: String(localized: "Edited Today")
        case .editedPast7Days: String(localized: "Edited in Last 7 Days")
        case .editedPast30Days: String(localized: "Edited in Last 30 Days")
        case .createdToday: String(localized: "Created Today")
        case .createdPast7Days: String(localized: "Created in Last 7 Days")
        case .createdPast30Days: String(localized: "Created in Last 30 Days")
        }
    }

    fileprivate var usesCreationDate: Bool {
        switch self {
        case .createdToday, .createdPast7Days, .createdPast30Days: true
        default: false
        }
    }

    fileprivate var dayCount: Int {
        switch self {
        case .editedToday, .createdToday: 1
        case .editedPast7Days, .createdPast7Days: 7
        case .editedPast30Days, .createdPast30Days: 30
        }
    }
}

enum SmartFolderAttachmentFilter: String, Codable, CaseIterable, Identifiable {
    case withAttachments
    case withoutAttachments

    var id: String { rawValue }

    var label: String {
        switch self {
        case .withAttachments: String(localized: "With Attachments")
        case .withoutAttachments: String(localized: "Without Attachments")
        }
    }
}

enum SmartFolderChecklistFilter: String, Codable, CaseIterable, Identifiable {
    case withChecklist
    case withUncheckedItems
    case withoutChecklist

    var id: String { rawValue }

    var label: String {
        switch self {
        case .withChecklist: String(localized: "With Checklists")
        case .withUncheckedItems: String(localized: "With Unchecked Items")
        case .withoutChecklist: String(localized: "Without Checklists")
        }
    }
}

enum NotesSearchSuggestion: String, CaseIterable, Identifiable {
    case pinned
    case attachments
    case checklists
    case editedToday

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pinned: String(localized: "Pinned")
        case .attachments: String(localized: "With Attachments")
        case .checklists: String(localized: "With Checklists")
        case .editedToday: String(localized: "Edited Today")
        }
    }

    var systemImage: String {
        switch self {
        case .pinned: "pin.fill"
        case .attachments: "paperclip"
        case .checklists: "checklist"
        case .editedToday: "clock"
        }
    }

    var filter: SmartFolderDefinition {
        switch self {
        case .pinned:
            SmartFolderDefinition(name: label, pinned: true)
        case .attachments:
            SmartFolderDefinition(name: label, attachmentFilter: .withAttachments)
        case .checklists:
            SmartFolderDefinition(name: label, checklistFilter: .withChecklist)
        case .editedToday:
            SmartFolderDefinition(name: label, dateFilter: .editedToday)
        }
    }

    func results(
        files: [RecentMarkdownFile],
        memos: [MemoBlock],
        scope: MarkdownSearchScope,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        limit: Int = 80
    ) -> [MarkdownSearchResult] {
        var results: [MarkdownSearchResult] = []
        if scope != .inbox {
            results += files.lazy
                .filter { $0.relativePath != "Inbox.md" }
                .filter { filter.matches(file: $0, now: now, calendar: calendar) }
                .map { file in
                    MarkdownSearchResult(
                        id: "file:\(file.relativePath)",
                        title: file.title,
                        context: file.preview,
                        location: file.relativePath,
                        score: 0,
                        modifiedAt: file.modifiedAt,
                        destination: .file(file)
                    )
                }
        }
        if scope != .notes {
            results += memos.lazy
                .filter { filter.matches(memo: $0, now: now, calendar: calendar) }
                .map { memo in
                    MarkdownSearchResult(
                        id: "memo:\(memo.id)",
                        title: memo.body.split(separator: "\n").first.map(String.init)
                            ?? String(localized: "Untitled memo"),
                        context: memo.preview,
                        location: String(localized: "Inbox"),
                        score: 0,
                        modifiedAt: SmartFolderMemoDate.date(from: memo.dateText) ?? .distantPast,
                        destination: .memo(memo)
                    )
                }
        }
        return results
            .sorted {
                if $0.modifiedAt == $1.modifiedAt { return $0.id < $1.id }
                return $0.modifiedAt > $1.modifiedAt
            }
            .prefix(limit)
            .map { $0 }
    }
}

struct SmartFolderDefinition: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var matchMode: SmartFolderMatchMode
    var includedTags: [String]
    var excludedTags: [String]
    var dateFilter: SmartFolderDateFilter?
    var attachmentFilter: SmartFolderAttachmentFilter?
    var checklistFilter: SmartFolderChecklistFilter?
    var pinned: Bool?

    init(
        id: UUID = UUID(),
        name: String,
        matchMode: SmartFolderMatchMode = .all,
        includedTags: [String] = [],
        excludedTags: [String] = [],
        dateFilter: SmartFolderDateFilter? = nil,
        attachmentFilter: SmartFolderAttachmentFilter? = nil,
        checklistFilter: SmartFolderChecklistFilter? = nil,
        pinned: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.matchMode = matchMode
        self.includedTags = includedTags
        self.excludedTags = excludedTags
        self.dateFilter = dateFilter
        self.attachmentFilter = attachmentFilter
        self.checklistFilter = checklistFilter
        self.pinned = pinned
    }

    var filterCount: Int {
        includedTags.count
            + excludedTags.count
            + (dateFilter == nil ? 0 : 1)
            + (attachmentFilter == nil ? 0 : 1)
            + (checklistFilter == nil ? 0 : 1)
            + (pinned == nil ? 0 : 1)
    }

    var hasFilters: Bool { filterCount > 0 }

    var normalized: SmartFolderDefinition? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              trimmedName.count <= 80,
              !trimmedName.contains("/"),
              !trimmedName.contains(":"),
              !trimmedName.contains("\n") else { return nil }
        let included = Self.normalizedTags(includedTags)
        let includedKeys = Set(included.map(Self.tagKey))
        let excluded = Self.normalizedTags(excludedTags)
            .filter { !includedKeys.contains(Self.tagKey($0)) }
        var result = self
        result.name = trimmedName
        result.includedTags = included
        result.excludedTags = excluded
        return result.hasFilters ? result : nil
    }

    func matches(
        file: RecentMarkdownFile,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        matches(
            tags: file.tags,
            createdAt: file.createdAt == .distantPast ? file.modifiedAt : file.createdAt,
            modifiedAt: file.modifiedAt,
            hasAttachments: file.hasAttachments,
            hasChecklist: file.hasChecklist,
            hasUncheckedChecklist: file.hasUncheckedChecklist,
            isPinned: file.isPinned,
            now: now,
            calendar: calendar
        )
    }

    func matches(
        memo: MemoBlock,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let timestamp = SmartFolderMemoDate.date(from: memo.dateText) ?? .distantPast
        return matches(
            tags: memo.tags,
            createdAt: timestamp,
            modifiedAt: timestamp,
            hasAttachments: memo.hasAttachments,
            hasChecklist: memo.hasChecklist,
            hasUncheckedChecklist: memo.hasUncheckedChecklist,
            isPinned: false,
            now: now,
            calendar: calendar
        )
    }

    private func matches(
        tags: [String],
        createdAt: Date,
        modifiedAt: Date,
        hasAttachments: Bool,
        hasChecklist: Bool,
        hasUncheckedChecklist: Bool,
        isPinned: Bool,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        let tagKeys = Set(tags.map(Self.tagKey))
        guard excludedTags.allSatisfy({ !tagKeys.contains(Self.tagKey($0)) }) else {
            return false
        }

        var conditions = includedTags.map { tagKeys.contains(Self.tagKey($0)) }
        if let dateFilter {
            let date = dateFilter.usesCreationDate ? createdAt : modifiedAt
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(
                byAdding: .day,
                value: -(dateFilter.dayCount - 1),
                to: today
            ) ?? today
            conditions.append(date >= start && date <= now)
        }
        if let attachmentFilter {
            conditions.append(
                attachmentFilter == .withAttachments ? hasAttachments : !hasAttachments
            )
        }
        if let checklistFilter {
            switch checklistFilter {
            case .withChecklist: conditions.append(hasChecklist)
            case .withUncheckedItems: conditions.append(hasUncheckedChecklist)
            case .withoutChecklist: conditions.append(!hasChecklist)
            }
        }
        if let pinned {
            conditions.append(isPinned == pinned)
        }

        guard !conditions.isEmpty else {
            return !excludedTags.isEmpty
        }
        switch matchMode {
        case .all: return conditions.allSatisfy { $0 }
        case .any: return conditions.contains(true)
        }
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap(MarkdownTagSyntax.normalizedTag).filter { tag in
            seen.insert(tagKey(tag)).inserted
        }
    }

    static func tagKey(_ tag: String) -> String {
        tag.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }
}

enum SmartFolderStoreError: LocalizedError, Equatable {
    case invalidDefinition
    case duplicateName
    case notFound
    case damagedConfiguration

    var errorDescription: String? {
        switch self {
        case .invalidDefinition:
            String(localized: "Choose a name and at least one Smart Folder filter.")
        case .duplicateName:
            String(localized: "A Smart Folder with this name already exists.")
        case .notFound:
            String(localized: "This Smart Folder is no longer available.")
        case .damagedConfiguration:
            String(localized: "Smart Folder settings could not be read.")
        }
    }
}

private enum SmartFolderMemoDate {
    static func date(from value: String) -> Date? {
        formatter.date(from: value)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
