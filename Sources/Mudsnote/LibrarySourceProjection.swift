import Foundation
import MudsnoteCore

func libraryIsInboxNote(_ note: NoteSearchResult) -> Bool {
    note.url.lastPathComponent.localizedCaseInsensitiveCompare("Inbox.md") == .orderedSame
        || note.title.localizedCaseInsensitiveContains("Inbox")
}

struct LibraryFolderRow: Equatable, Sendable {
    let url: URL
    let depth: Int
    let hasChildren: Bool
}

enum LibraryFolderTreeProjection {
    private static let maximumDepth = 3

    static func inserting(
        _ folderURL: URL,
        under parentURL: URL,
        into rows: [LibraryFolderRow]
    ) -> [LibraryFolderRow] {
        let folder = folderURL.standardizedFileURL
        guard !rows.contains(where: { $0.url.path == folder.path }) else {
            return rows
        }

        let parent = parentURL.standardizedFileURL
        let parentIndex = rows.firstIndex(where: { $0.url.path == parent.path })
        let depth = parentIndex.map { rows[$0].depth + 1 } ?? 0
        guard depth <= maximumDepth else { return rows }
        var result = rows
        let row = LibraryFolderRow(url: folder, depth: depth, hasChildren: false)
        result.insert(row, at: insertionIndex(for: row, under: parent, in: result))
        if let parentIndex {
            let parentRow = result[parentIndex]
            result[parentIndex] = LibraryFolderRow(
                url: parentRow.url,
                depth: parentRow.depth,
                hasChildren: true
            )
        }
        return result
    }

    static func renaming(
        _ folderURL: URL,
        to renamedURL: URL,
        in rows: [LibraryFolderRow]
    ) -> [LibraryFolderRow] {
        let oldFolder = folderURL.standardizedFileURL
        let newFolder = renamedURL.standardizedFileURL
        guard let start = rows.firstIndex(where: { $0.url.path == oldFolder.path }) else {
            return rows
        }

        let depth = rows[start].depth
        let end = rows[(start + 1)...].firstIndex(where: { $0.depth <= depth }) ?? rows.endIndex
        let remappedSubtree = rows[start..<end].map { row -> LibraryFolderRow in
            let oldPath = row.url.path
            let suffix = String(oldPath.dropFirst(oldFolder.path.count))
            return LibraryFolderRow(
                url: URL(fileURLWithPath: newFolder.path + suffix, isDirectory: true),
                depth: row.depth,
                hasChildren: row.hasChildren
            )
        }
        var result = rows
        result.removeSubrange(start..<end)
        guard let renamedRoot = remappedSubtree.first else { return result }
        let insertion = insertionIndex(
            for: renamedRoot,
            under: newFolder.deletingLastPathComponent(),
            in: result
        )
        result.insert(contentsOf: remappedSubtree, at: insertion)
        return result
    }

    static func removing(_ folderURL: URL, from rows: [LibraryFolderRow]) -> [LibraryFolderRow] {
        let folderPath = folderURL.standardizedFileURL.path
        guard let removedRow = rows.first(where: { $0.url.path == folderPath }) else { return rows }
        let parentPath = removedRow.url.deletingLastPathComponent().path
        var result = rows.filter { row in
            let path = row.url.path
            return path != folderPath && !path.hasPrefix(folderPath + "/")
        }
        if let parentIndex = result.firstIndex(where: { $0.url.path == parentPath }) {
            let parentRow = result[parentIndex]
            let hasChildren = result.contains { row in
                row.depth == parentRow.depth + 1
                    && row.url.deletingLastPathComponent().path == parentPath
            }
            result[parentIndex] = LibraryFolderRow(
                url: parentRow.url,
                depth: parentRow.depth,
                hasChildren: hasChildren
            )
        }
        return result
    }

    private static func insertionIndex(
        for row: LibraryFolderRow,
        under parentURL: URL,
        in rows: [LibraryFolderRow]
    ) -> Int {
        let parentPath = parentURL.standardizedFileURL.path
        guard let parentIndex = rows.firstIndex(where: {
            $0.url.path == parentPath
        }) else {
            return rows.endIndex
        }

        let parentDepth = rows[parentIndex].depth
        let childDepth = parentDepth + 1
        var cursor = parentIndex + 1
        while cursor < rows.endIndex, rows[cursor].depth > parentDepth {
            if rows[cursor].depth == childDepth,
               row.url.lastPathComponent.localizedCaseInsensitiveCompare(rows[cursor].url.lastPathComponent) == .orderedAscending {
                return cursor
            }
            cursor += 1
        }
        return cursor
    }
}

struct LibrarySourceCountIndex: Sendable {
    let inboxCount: Int
    private let recursiveFolderCounts: [String: Int]
    private let directFolderCounts: [String: Int]
    private let tagCounts: [String: Int]

    init(notes: [NoteSearchResult], folderPaths: Set<String>) {
        var inboxCount = 0
        var recursiveFolderCounts: [String: Int] = [:]
        var directFolderCounts: [String: Int] = [:]
        var tagCounts: [String: Int] = [:]

        for note in notes {
            if libraryIsInboxNote(note) {
                inboxCount += 1
            }

            var directory = note.url.deletingLastPathComponent().standardizedFileURL
            if folderPaths.contains(directory.path) {
                directFolderCounts[directory.path, default: 0] += 1
            }
            while true {
                let path = directory.path
                if folderPaths.contains(path) {
                    recursiveFolderCounts[path, default: 0] += 1
                }
                let parent = directory.deletingLastPathComponent().standardizedFileURL
                guard parent.path != path else { break }
                directory = parent
            }

            let noteTagKeys = Set(note.tags.map(Self.tagKey))
            for key in noteTagKeys {
                tagCounts[key, default: 0] += 1
            }
        }

        self.inboxCount = inboxCount
        self.recursiveFolderCounts = recursiveFolderCounts
        self.directFolderCounts = directFolderCounts
        self.tagCounts = tagCounts
    }

    func count(forFolder url: URL, includingDescendants: Bool = true) -> Int {
        let counts = includingDescendants ? recursiveFolderCounts : directFolderCounts
        return counts[url.standardizedFileURL.path, default: 0]
    }

    func count(forTag tag: String) -> Int {
        tagCounts[Self.tagKey(tag), default: 0]
    }

    private static func tagKey(_ tag: String) -> String {
        tag.folding(options: [.caseInsensitive], locale: .current)
    }
}

enum LibrarySourceSnapshotStabilizer {
    static func needsConfirmation(
        previous: [NoteSearchResult],
        candidate: [NoteSearchResult]
    ) -> Bool {
        guard !previous.isEmpty else { return false }
        let candidatePaths = Set(candidate.map { $0.url.standardizedFileURL.path })
        return previous.contains {
            !candidatePaths.contains($0.url.standardizedFileURL.path)
        }
    }

    static func stabilized(
        previous: [NoteSearchResult],
        firstCandidate: [NoteSearchResult],
        confirmedCandidate: [NoteSearchResult]
    ) -> [NoteSearchResult] {
        needsConfirmation(previous: previous, candidate: firstCandidate)
            ? confirmedCandidate
            : firstCandidate
    }
}
