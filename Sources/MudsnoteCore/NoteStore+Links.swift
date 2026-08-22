import Foundation

public struct NoteLinkItem: Equatable, Sendable {
    public let url: URL
    public let title: String

    public init(url: URL, title: String) {
        self.url = url
        self.title = title
    }
}

public struct NoteLinkRelations: Equatable, Sendable {
    public let incoming: [NoteLinkItem]
    public let outgoing: [NoteLinkItem]

    public init(incoming: [NoteLinkItem], outgoing: [NoteLinkItem]) {
        self.incoming = incoming
        self.outgoing = outgoing
    }

    public static let empty = NoteLinkRelations(incoming: [], outgoing: [])
}

public enum MarkdownLocalLinkResolver {
    public static func fileURL(for rawValue: String, relativeTo sourceURL: URL) -> URL? {
        var target = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }

        if target.hasPrefix("<"), target.hasSuffix(">"), target.count > 2 {
            target.removeFirst()
            target.removeLast()
        }

        if let url = URL(string: target), url.isFileURL {
            return url.standardizedFileURL
        }

        if let scheme = URL(string: target)?.scheme, !scheme.isEmpty {
            return nil
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
        if target.hasPrefix("~/") {
            resolved = URL(
                fileURLWithPath: NSString(string: target).expandingTildeInPath
            )
        } else if target.hasPrefix("/") {
            resolved = URL(fileURLWithPath: target)
        } else {
            resolved = sourceURL.deletingLastPathComponent().appendingPathComponent(target)
        }

        let fileExtension = resolved.pathExtension.lowercased()
        guard fileExtension == "md" || fileExtension == "markdown" else { return nil }
        return resolved.standardizedFileURL
    }
}

extension NoteStore {
    public func noteMentionSuggestions(
        query: String,
        sourceURL: URL?,
        currentBody: String? = nil,
        limit: Int = 8
    ) -> [NoteLinkItem] {
        guard limit > 0 else { return [] }
        let currentURL = sourceURL?.standardizedFileURL
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var itemsByPath: [String: NoteLinkItem] = [:]
        var orderedPaths: [String] = []

        if trimmedQuery.isEmpty, let currentURL {
            let relations = knowledgeRelations(
                for: currentURL,
                currentBody: currentBody,
                suggestionLimit: limit
            )
            for relation in relations.suggested {
                let path = relation.url.standardizedFileURL.path
                itemsByPath[path] = NoteLinkItem(
                    url: relation.url.standardizedFileURL,
                    title: relation.title
                )
                orderedPaths.append(path)
            }
        }

        let fallbackLimit = max(limit * 3, limit)
        for result in searchNotes(query: trimmedQuery, limit: fallbackLimit) {
            let url = result.url.standardizedFileURL
            guard url != currentURL else { continue }
            if itemsByPath[url.path] == nil {
                itemsByPath[url.path] = NoteLinkItem(url: url, title: result.title)
                orderedPaths.append(url.path)
            }
        }

        return orderedPaths.compactMap { itemsByPath[$0] }
        .prefix(limit)
        .map { $0 }
    }

    public func linkRelations(
        for noteURL: URL,
        currentBody: String? = nil,
        roots: [URL]? = nil
    ) -> NoteLinkRelations {
        let entries = indexedEntries(roots: roots)
        let currentURL = noteURL.standardizedFileURL
        let entriesByPath = Dictionary(uniqueKeysWithValues: entries.map {
            ($0.url.standardizedFileURL.path, $0)
        })

        let body = currentBody
            ?? entriesByPath[currentURL.path]?.body
            ?? (try? loadNote(at: currentURL).body)
            ?? ""
        let outgoing = linkedItems(
            in: body,
            sourceURL: currentURL,
            entriesByPath: entriesByPath,
            excluding: currentURL
        )

        var incomingByPath: [String: NoteLinkItem] = [:]
        for entry in entries where entry.url.standardizedFileURL.path != currentURL.path {
            let linksToCurrentNote = markdownLinkTargets(in: entry.body).contains { target in
                MarkdownLocalLinkResolver.fileURL(for: target, relativeTo: entry.url)?.path == currentURL.path
            }
            if linksToCurrentNote {
                incomingByPath[entry.url.standardizedFileURL.path] = NoteLinkItem(
                    url: entry.url.standardizedFileURL,
                    title: entry.title
                )
            }
        }

        return NoteLinkRelations(
            incoming: incomingByPath.values.sorted(by: noteLinkItemSort),
            outgoing: outgoing
        )
    }

    public func outgoingLinks(
        for noteURL: URL,
        currentBody: String
    ) -> [NoteLinkItem] {
        searchIndexLock.lock()
        let entries = searchIndexSnapshot?.entries ?? []
        searchIndexLock.unlock()
        let entriesByPath = Dictionary(uniqueKeysWithValues: entries.map {
            ($0.url.path, $0)
        })
        let currentURL = noteURL.standardizedFileURL
        return linkedItems(
            in: currentBody,
            sourceURL: currentURL,
            entriesByPath: entriesByPath,
            excluding: currentURL
        )
    }

    private func linkedItems(
        in body: String,
        sourceURL: URL,
        entriesByPath: [String: NoteSearchIndexEntry],
        excluding excludedURL: URL
    ) -> [NoteLinkItem] {
        var itemsByPath: [String: NoteLinkItem] = [:]
        for target in markdownLinkTargets(in: body) {
            guard let url = MarkdownLocalLinkResolver.fileURL(for: target, relativeTo: sourceURL),
                  url.path != excludedURL.path,
                  FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            let title = entriesByPath[url.path]?.title
                ?? url.deletingPathExtension().lastPathComponent
            itemsByPath[url.path] = NoteLinkItem(url: url, title: title)
        }
        return itemsByPath.values.sorted(by: noteLinkItemSort)
    }

    private func markdownLinkTargets(in markdown: String) -> [String] {
        let pattern = #"(?<!!)\[[^\]]*\]\(([^)]+)\)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
        return expression.matches(in: markdown, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let targetRange = Range(match.range(at: 1), in: markdown) else {
                return nil
            }
            var target = String(markdown[targetRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if target.hasPrefix("<"), let closing = target.firstIndex(of: ">") {
                target = String(target[target.index(after: target.startIndex)..<closing])
            } else if let titleRange = target.range(
                of: #"\s+["'][^"']*["']\s*$"#,
                options: .regularExpression
            ) {
                target.removeSubrange(titleRange)
            }
            return target.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func noteLinkItemSort(_ lhs: NoteLinkItem, _ rhs: NoteLinkItem) -> Bool {
        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleOrder == .orderedSame {
            return lhs.url.path.localizedCaseInsensitiveCompare(rhs.url.path) == .orderedAscending
        }
        return titleOrder == .orderedAscending
    }
}
