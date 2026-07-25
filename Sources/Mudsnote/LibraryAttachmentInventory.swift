import Foundation
import MudsnoteCore

enum LibraryAttachmentState: Int, Sendable, CaseIterable {
    case missing
    case unreferenced
    case referenced

    var title: String {
        switch self {
        case .missing:
            return "缺失"
        case .unreferenced:
            return "未引用"
        case .referenced:
            return "已引用"
        }
    }
}

struct LibraryAttachmentItem: Equatable, Sendable {
    let url: URL
    let state: LibraryAttachmentState
    let byteCount: Int64?
    let referencingNotes: [URL]

    var filename: String {
        url.lastPathComponent
    }

    var referenceSummary: String {
        switch state {
        case .missing:
            return referencingNotes.count == 1
                ? "1 篇笔记中的链接失效"
                : "\(referencingNotes.count) 篇笔记中的链接失效"
        case .unreferenced:
            return "没有笔记引用"
        case .referenced:
            return referencingNotes.count == 1
                ? "1 篇笔记引用"
                : "\(referencingNotes.count) 篇笔记引用"
        }
    }
}

enum LibraryAttachmentInventory {
    private static let noteExtensions = Set(["md", "markdown", "txt"])

    static func build(
        roots: [URL],
        fileManager: FileManager = .default
    ) -> [LibraryAttachmentItem] {
        let roots = deduplicatedRoots(roots)
        var noteURLs: [URL] = []
        var attachmentURLsByPath: [String: URL] = [:]

        for root in roots {
            collectFiles(
                under: root,
                fileManager: fileManager,
                noteURLs: &noteURLs,
                attachmentURLsByPath: &attachmentURLsByPath
            )
        }

        var referencingNotesByAttachmentPath: [String: Set<URL>] = [:]
        for noteURL in noteURLs {
            guard let markdown = try? String(contentsOf: noteURL, encoding: .utf8) else {
                continue
            }
            for target in localAttachmentTargets(in: markdown) {
                guard let attachmentURL = managedAttachmentURL(
                    for: target,
                    relativeTo: noteURL,
                    inside: roots
                ) else {
                    continue
                }
                referencingNotesByAttachmentPath[
                    attachmentURL.standardizedFileURL.path,
                    default: []
                ].insert(noteURL.standardizedFileURL)
            }
        }

        let allPaths = Set(attachmentURLsByPath.keys)
            .union(referencingNotesByAttachmentPath.keys)
        return allPaths.compactMap { path -> LibraryAttachmentItem? in
            let url = attachmentURLsByPath[path] ?? URL(fileURLWithPath: path)
            let references = referencingNotesByAttachmentPath[path, default: []]
                .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            let exists = attachmentURLsByPath[path] != nil
            let state: LibraryAttachmentState = exists
                ? (references.isEmpty ? .unreferenced : .referenced)
                : .missing
            let byteCount = exists
                ? (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                    .flatMap { $0.map(Int64.init) }
                : nil
            return LibraryAttachmentItem(
                url: url,
                state: state,
                byteCount: byteCount,
                referencingNotes: references
            )
        }.sorted(by: attachmentSort)
    }

    static func localAttachmentTargets(in markdown: String) -> [String] {
        var targets: [String] = []
        var cursor = markdown.startIndex
        while cursor < markdown.endIndex,
              let opener = markdown[cursor...].range(of: "](") {
            var targetStart = opener.upperBound
            while targetStart < markdown.endIndex, markdown[targetStart].isWhitespace {
                targetStart = markdown.index(after: targetStart)
            }
            guard targetStart < markdown.endIndex else { break }

            if markdown[targetStart] == "<" {
                let valueStart = markdown.index(after: targetStart)
                if let closing = unescapedCharacter(">", in: markdown, from: valueStart) {
                    targets.append(String(markdown[valueStart..<closing]))
                    cursor = markdown.index(after: closing)
                    continue
                }
            } else if let parsed = bareDestination(in: markdown, from: targetStart) {
                targets.append(parsed.value)
                cursor = parsed.end
                continue
            }
            cursor = opener.upperBound
        }
        return targets
    }

    private static func collectFiles(
        under root: URL,
        fileManager: FileManager,
        noteURLs: inout [URL],
        attachmentURLsByPath: inout [String: URL]
    ) {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return
        }

        while let url = enumerator.nextObject() as? URL {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]) else {
                continue
            }
            if values.isDirectory == true,
               url.lastPathComponent.caseInsensitiveCompare(NoteStore.attachmentDirectoryName) == .orderedSame {
                collectAttachmentFiles(
                    under: url,
                    fileManager: fileManager,
                    into: &attachmentURLsByPath
                )
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true,
                  noteExtensions.contains(url.pathExtension.lowercased()) else {
                continue
            }
            noteURLs.append(url.standardizedFileURL)
        }
    }

    private static func collectAttachmentFiles(
        under directory: URL,
        fileManager: FileManager,
        into urlsByPath: inout [String: URL]
    ) {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return
        }
        while let url = enumerator.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                continue
            }
            let standardizedURL = url.standardizedFileURL
            urlsByPath[standardizedURL.path] = standardizedURL
        }
    }

    private static func managedAttachmentURL(
        for rawTarget: String,
        relativeTo noteURL: URL,
        inside roots: [URL]
    ) -> URL? {
        var target = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }
        if let titleRange = target.range(
            of: #"\s+["'][^"']*["']\s*$"#,
            options: .regularExpression
        ) {
            target.removeSubrange(titleRange)
        }
        target = target
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? target
        target = target
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? target
        target = target.removingPercentEncoding ?? target
        guard !target.isEmpty else { return nil }

        let resolved: URL
        if let parsed = URL(string: target), parsed.isFileURL {
            resolved = parsed.standardizedFileURL
        } else if URL(string: target)?.scheme != nil {
            return nil
        } else if target.hasPrefix("/") {
            resolved = URL(fileURLWithPath: target).standardizedFileURL
        } else {
            resolved = noteURL.deletingLastPathComponent()
                .appendingPathComponent(target)
                .standardizedFileURL
        }

        guard resolved.pathComponents.contains(where: {
            $0.caseInsensitiveCompare(NoteStore.attachmentDirectoryName) == .orderedSame
        }) else {
            return nil
        }
        guard roots.contains(where: {
            let rootPath = $0.standardizedFileURL.path
            return resolved.path == rootPath || resolved.path.hasPrefix(rootPath + "/")
        }) else {
            return nil
        }
        return resolved
    }

    private static func bareDestination(
        in markdown: String,
        from start: String.Index
    ) -> (value: String, end: String.Index)? {
        var cursor = start
        var depth = 0
        var escaped = false
        while cursor < markdown.endIndex {
            let character = markdown[cursor]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                if depth == 0 {
                    return (String(markdown[start..<cursor]), markdown.index(after: cursor))
                }
                depth -= 1
            } else if character == "\n" {
                return nil
            }
            cursor = markdown.index(after: cursor)
        }
        return nil
    }

    private static func unescapedCharacter(
        _ character: Character,
        in string: String,
        from start: String.Index
    ) -> String.Index? {
        var cursor = start
        var escaped = false
        while cursor < string.endIndex {
            let current = string[cursor]
            if escaped {
                escaped = false
            } else if current == "\\" {
                escaped = true
            } else if current == character {
                return cursor
            } else if current == "\n" {
                return nil
            }
            cursor = string.index(after: cursor)
        }
        return nil
    }

    private static func deduplicatedRoots(_ roots: [URL]) -> [URL] {
        let sorted = roots.map(\.standardizedFileURL).sorted {
            $0.path.count < $1.path.count
        }
        var retained: [URL] = []
        for root in sorted where !retained.contains(where: {
            root.path == $0.path || root.path.hasPrefix($0.path + "/")
        }) {
            retained.append(root)
        }
        return retained
    }

    private static func attachmentSort(
        _ lhs: LibraryAttachmentItem,
        _ rhs: LibraryAttachmentItem
    ) -> Bool {
        if lhs.state != rhs.state {
            return lhs.state.rawValue < rhs.state.rawValue
        }
        let nameOrder = lhs.filename.localizedCaseInsensitiveCompare(rhs.filename)
        if nameOrder != .orderedSame {
            return nameOrder == .orderedAscending
        }
        return lhs.url.path.localizedStandardCompare(rhs.url.path) == .orderedAscending
    }
}
