import Foundation
import MudsnoteCore

enum LibraryNoteListRow {
    case group(title: String)
    case note(NoteSearchResult)

    var note: NoteSearchResult? {
        guard case .note(let note) = self else { return nil }
        return note
    }
}

enum LibraryNoteSortOrder: Int {
    case dateEdited = 0
    case title = 1
    case dateCreated = 2
}

enum LibraryNoteListProjection {
    static func upsertByModifiedDate(
        _ note: NoteSearchResult,
        into snapshot: inout [NoteSearchResult],
        replacingPaths: Set<String>,
        limit: Int
    ) {
        guard limit > 0 else {
            snapshot.removeAll(keepingCapacity: true)
            return
        }

        snapshot.removeAll { existing in
            replacingPaths.contains(existing.url.path)
        }

        var lowerBound = 0
        var upperBound = snapshot.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if snapshot[middle].modifiedAt > note.modifiedAt {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        snapshot.insert(note, at: lowerBound)

        if snapshot.count > limit {
            snapshot.removeLast(snapshot.count - limit)
        }
    }

    static func rows(
        for notes: [NoteSearchResult],
        sortOrder: LibraryNoteSortOrder,
        groupsByDate: Bool,
        includesPinnedGroup: Bool,
        pinnedPaths: Set<String>,
        now: Date = Date(),
        preservesInputOrder: Bool = false,
        calendar: Calendar = .current
    ) -> [LibraryNoteListRow] {
        let preparedNotes = notes.map(PreparedNote.init)
        let orderedNotes = preservesInputOrder
            ? preparedNotes
            : sorted(preparedNotes, by: sortOrder)
        let canShowPinnedGroup = !preservesInputOrder && includesPinnedGroup

        var pinnedNotes: [PreparedNote] = []
        var unpinnedNotes: [PreparedNote] = []
        pinnedNotes.reserveCapacity(min(orderedNotes.count, pinnedPaths.count))
        unpinnedNotes.reserveCapacity(orderedNotes.count)
        for note in orderedNotes {
            if canShowPinnedGroup, pinnedPaths.contains(note.standardizedPath) {
                pinnedNotes.append(note)
            } else {
                unpinnedNotes.append(note)
            }
        }

        var rows: [LibraryNoteListRow] = []
        rows.reserveCapacity(notes.count + 6)
        if !pinnedNotes.isEmpty {
            rows.append(.group(title: "Pinned"))
            rows.append(contentsOf: pinnedNotes.map { .note($0.note) })
        }

        guard groupsByDate else {
            rows.append(contentsOf: unpinnedNotes.map { .note($0.note) })
            return rows
        }

        let notesForGrouping: [PreparedNote]
        if !preservesInputOrder, sortOrder == .title {
            notesForGrouping = unpinnedNotes.sorted { lhs, rhs in
                if lhs.note.modifiedAt != rhs.note.modifiedAt {
                    return lhs.note.modifiedAt > rhs.note.modifiedAt
                }
                return lhs.standardizedPath < rhs.standardizedPath
            }
        } else {
            notesForGrouping = unpinnedNotes
        }

        var groupOrder: [String] = []
        var groupedNotes: [String: [PreparedNote]] = [:]
        for note in notesForGrouping {
            let groupDate = sortOrder == .dateCreated ? note.note.createdAt : note.note.modifiedAt
            let group = groupTitle(for: groupDate, now: now, calendar: calendar)
            if groupedNotes[group] == nil {
                groupOrder.append(group)
            }
            groupedNotes[group, default: []].append(note)
        }

        for group in groupOrder {
            rows.append(.group(title: group))
            var notesInGroup = groupedNotes[group] ?? []
            if !preservesInputOrder, sortOrder == .title {
                notesInGroup = sorted(notesInGroup, by: sortOrder)
            }
            rows.append(contentsOf: notesInGroup.map { .note($0.note) })
        }
        return rows
    }

    private struct PreparedNote {
        let note: NoteSearchResult
        let standardizedPath: String

        init(_ note: NoteSearchResult) {
            self.note = note
            standardizedPath = note.url.standardizedFileURL.path
        }
    }

    private static func sorted(
        _ notes: [PreparedNote],
        by sortOrder: LibraryNoteSortOrder
    ) -> [PreparedNote] {
        notes.sorted { lhs, rhs in
            switch sortOrder {
            case .dateEdited:
                if lhs.note.modifiedAt != rhs.note.modifiedAt {
                    return lhs.note.modifiedAt > rhs.note.modifiedAt
                }
            case .dateCreated:
                if lhs.note.createdAt != rhs.note.createdAt {
                    return lhs.note.createdAt > rhs.note.createdAt
                }
            case .title:
                let titleComparison = lhs.note.title.localizedCaseInsensitiveCompare(rhs.note.title)
                if titleComparison != .orderedSame {
                    return titleComparison == .orderedAscending
                }
                if lhs.note.modifiedAt != rhs.note.modifiedAt {
                    return lhs.note.modifiedAt > rhs.note.modifiedAt
                }
            }
            return lhs.standardizedPath < rhs.standardizedPath
        }
    }

    private static func groupTitle(for date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }

        let startOfToday = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        let daysAgo = calendar.dateComponents([.day], from: startOfDate, to: startOfToday).day ?? 0
        if (2...7).contains(daysAgo) {
            return "Previous 7 Days"
        }
        if (8...30).contains(daysAgo) {
            return "Previous 30 Days"
        }
        return String(calendar.component(.year, from: date))
    }
}
