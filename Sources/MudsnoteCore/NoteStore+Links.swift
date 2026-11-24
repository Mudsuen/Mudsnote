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

struct NoteLinkTarget: Codable, Equatable, Sendable {
    let value: String
    let isWikiLink: Bool
}

final class NoteLinkIndex: @unchecked Sendable {
    let rootsKey: [String]
    let revision: UInt64
    let entriesByPath: [String: NoteSearchIndexEntry]
    let entriesByBasename: [String: [NoteSearchIndexEntry]]
    let entriesBySuffix: [String: [NoteSearchIndexEntry]]
    let incomingByTargetPath: [String: [NoteLinkItem]]

    init(
        rootsKey: [String],
        revision: UInt64,
        entries: [NoteSearchIndexEntry]
    ) {
        self.rootsKey = rootsKey
        self.revision = revision

        var byPath: [String: NoteSearchIndexEntry] = [:]
        var byBasename: [String: [NoteSearchIndexEntry]] = [:]
        var bySuffix: [String: [NoteSearchIndexEntry]] = [:]
        byPath.reserveCapacity(entries.count)
        byBasename.reserveCapacity(entries.count)

        for entry in entries {
            let path = entry.url.standardizedFileURL.path
            byPath[path] = entry
            let basename = entry.url.deletingPathExtension().lastPathComponent.lowercased()
            byBasename[basename, default: []].append(entry)
            let components = entry.url.standardizedFileURL.pathComponents.drop(while: { $0 == "/" })
            if !components.isEmpty {
                for index in components.indices {
                    let suffix = components[index...].joined(separator: "/")
                    bySuffix[suffix, default: []].append(entry)
                }
            }
        }

        self.entriesByPath = byPath
        self.entriesByBasename = byBasename
        self.entriesBySuffix = bySuffix

        var incomingByTarget: [String: [String: NoteLinkItem]] = [:]
        for entry in entries where !entry.linkTargets.isEmpty {
            let sourceURL = entry.url.standardizedFileURL
            let sourcePath = sourceURL.path
            let sourceItem = NoteLinkItem(url: sourceURL, title: entry.title)
            for target in entry.linkTargets {
                guard let resolved = Self.resolveTarget(
                    target,
                    sourceURL: sourceURL,
                    entriesByPath: byPath,
                    entriesByBasename: byBasename,
                    entriesBySuffix: bySuffix
                ) else {
                    continue
                }
                let targetPath = resolved.url.standardizedFileURL.path
                guard targetPath != sourcePath else { continue }
                incomingByTarget[targetPath, default: [:]][sourcePath] = sourceItem
            }
        }

        self.incomingByTargetPath = incomingByTarget.mapValues { itemsByPath in
            itemsByPath.values.sorted(by: Self.sortItems)
        }
    }

    static func resolveTarget(
        _ target: NoteLinkTarget,
        sourceURL: URL,
        entriesByPath: [String: NoteSearchIndexEntry],
        entriesByBasename: [String: [NoteSearchIndexEntry]],
        entriesBySuffix: [String: [NoteSearchIndexEntry]]
    ) -> NoteSearchIndexEntry? {
        if !target.isWikiLink,
           let resolvedURL = MarkdownLocalLinkResolver.fileURL(
               for: target.value,
               relativeTo: sourceURL
           ),
           let entry = entriesByPath[resolvedURL.standardizedFileURL.path] {
            return entry
        }
        guard target.isWikiLink else { return nil }

        var raw = target.value
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? target.value
        raw = raw.removingPercentEncoding ?? raw
        raw = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !raw.isEmpty else { return nil }

        let loweredRaw = raw.lowercased()
        let explicitExtension: String?
        if loweredRaw.hasSuffix(".markdown") {
            raw.removeLast(".markdown".count)
            explicitExtension = "markdown"
        } else if loweredRaw.hasSuffix(".md") {
            raw.removeLast(3)
            explicitExtension = "md"
        } else {
            explicitExtension = nil
        }

        let normalizedTarget = raw.replacingOccurrences(of: "\\", with: "/")
        let extensions = explicitExtension.map { [$0] } ?? ["md", "markdown"]
        for pathExtension in extensions {
            let sourceRelative = sourceURL.deletingLastPathComponent()
                .appendingPathComponent(normalizedTarget)
                .appendingPathExtension(pathExtension)
                .standardizedFileURL.path
            if let exact = entriesByPath[sourceRelative] {
                return exact
            }
        }

        let suffixMatches = extensions.flatMap { pathExtension in
            entriesBySuffix["\(normalizedTarget).\(pathExtension)"] ?? []
        }
        if Set(suffixMatches.map { $0.url.standardizedFileURL.path }).count == 1 {
            return suffixMatches[0]
        }

        let basename = URL(fileURLWithPath: normalizedTarget).lastPathComponent
        let basenameMatches = entriesByBasename[basename.lowercased()] ?? []
        return basenameMatches.count == 1 ? basenameMatches[0] : nil
    }

    static func sortItems(_ lhs: NoteLinkItem, _ rhs: NoteLinkItem) -> Bool {
        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleOrder == .orderedSame {
            return lhs.url.path.localizedCaseInsensitiveCompare(rhs.url.path) == .orderedAscending
        }
        return titleOrder == .orderedAscending
    }
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
    public func markdownNoteLink(
        from sourceURL: URL,
        to targetURL: URL,
        title: String
    ) -> String {
        let sourceDirectory = sourceURL.deletingLastPathComponent().standardizedFileURL
        let target = targetURL.standardizedFileURL
        var allowedCharacters = CharacterSet.urlPathAllowed
        allowedCharacters.remove(charactersIn: "()[]")
        let rawRelativePath = relativeNoteLinkPath(from: sourceDirectory, to: target)
        let encodedPath = rawRelativePath
            .addingPercentEncoding(withAllowedCharacters: allowedCharacters)
            ?? rawRelativePath
        let escapedTitle = title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "]", with: "\\]")
        return "[\(escapedTitle)](\(encodedPath))"
    }

    func noteLinkTargets(
        in markdown: String,
        cancellationCheck: @Sendable () -> Bool = { false }
    ) -> [NoteLinkTarget] {
        MarkdownNoteReferenceParser.references(
            in: markdown,
            cancellationCheck: cancellationCheck
        ).map {
            NoteLinkTarget(value: $0.destination, isWikiLink: $0.kind == .wiki)
        }
    }

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

        let fallbackLimit = max(limit * 3, limit)
        let results = searchNotes(query: trimmedQuery, limit: fallbackLimit, roots: preferredDirectories)
        for result in results {
            let url = result.url.standardizedFileURL
            guard url != currentURL else { continue }
            if itemsByPath[url.path] == nil {
                itemsByPath[url.path] = NoteLinkItem(url: url, title: result.title)
                orderedPaths.append(url.path)
            }
            if orderedPaths.count >= limit { break }
        }

        return orderedPaths.compactMap { itemsByPath[$0] }
    }

    public func linkRelations(
        for noteURL: URL,
        currentBody: String? = nil,
        roots: [URL]? = nil,
        cancellationCheck: @Sendable () -> Bool = { false }
    ) -> NoteLinkRelations {
        guard !cancellationCheck() else { return .empty }
        let effectiveRoots = roots ?? preferredDirectories
        guard let linkIndex = cachedOrBuiltNoteLinkIndex(
            roots: effectiveRoots,
            cancellationCheck: cancellationCheck
        ) else {
            return .empty
        }
        guard !cancellationCheck() else { return .empty }

        let currentURL = noteURL.standardizedFileURL
        let currentPath = currentURL.path
        let targets: [NoteLinkTarget]
        if let currentBody {
            targets = noteLinkTargets(in: currentBody, cancellationCheck: cancellationCheck)
        } else if let entry = linkIndex.entriesByPath[currentPath] {
            targets = entry.linkTargets
        } else if let loadedBody = try? loadNote(at: currentURL).body {
            targets = noteLinkTargets(in: loadedBody, cancellationCheck: cancellationCheck)
        } else {
            targets = []
        }
        guard !cancellationCheck() else { return .empty }

        var outgoingByPath: [String: NoteLinkItem] = [:]
        for target in targets {
            if let entry = NoteLinkIndex.resolveTarget(
                target,
                sourceURL: currentURL,
                entriesByPath: linkIndex.entriesByPath,
                entriesByBasename: linkIndex.entriesByBasename,
                entriesBySuffix: linkIndex.entriesBySuffix
            ) {
                let targetURL = entry.url.standardizedFileURL
                guard targetURL.path != currentPath else { continue }
                outgoingByPath[targetURL.path] = NoteLinkItem(url: targetURL, title: entry.title)
            } else if !target.isWikiLink,
                      let externalURL = MarkdownLocalLinkResolver.fileURL(for: target.value, relativeTo: currentURL),
                      externalURL.path != currentPath,
                      fileManager.fileExists(atPath: externalURL.path) {
                let title = externalURL.deletingPathExtension().lastPathComponent
                outgoingByPath[externalURL.path] = NoteLinkItem(url: externalURL, title: title)
            }
        }

        let incoming = linkIndex.incomingByTargetPath[currentPath] ?? []
        return NoteLinkRelations(
            incoming: incoming,
            outgoing: outgoingByPath.values.sorted(by: NoteLinkIndex.sortItems)
        )
    }

    public func outgoingLinks(
        for noteURL: URL,
        currentBody: String
    ) -> [NoteLinkItem] {
        searchIndexLock.lock()
        let entries = searchIndexSnapshot?.entries ?? []
        searchIndexLock.unlock()
        let entriesByPath = Dictionary(
            entries.map { ($0.url.standardizedFileURL.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let currentURL = noteURL.standardizedFileURL
        var itemsByPath: [String: NoteLinkItem] = [:]
        for reference in MarkdownNoteReferenceParser.references(in: currentBody) where reference.kind == .markdown {
            guard let url = MarkdownLocalLinkResolver.fileURL(for: reference.destination, relativeTo: currentURL),
                  url.path != currentURL.path,
                  fileManager.fileExists(atPath: url.path) else {
                continue
            }
            let title = entriesByPath[url.path]?.title
                ?? url.deletingPathExtension().lastPathComponent
            itemsByPath[url.path] = NoteLinkItem(url: url, title: title)
        }
        return itemsByPath.values.sorted(by: NoteLinkIndex.sortItems)
    }

    /// Returns candidate note URLs referencing `targetURL` when the in-memory search index
    /// is clean and covers `roots`. Returns `nil` when callers must fall back to a directory scan.
    func indexedReferencingNoteURLs(
        for targetURL: URL,
        in roots: [URL]
    ) -> [URL]? {
        let normalizedRoots = canonicalSearchRoots(roots)
        let expectedRootsKey = normalizedRoots.map(\.path)
        searchIndexLock.lock()
        let snapshot = searchIndexSnapshot
        let requiresFullRefresh = searchIndexRequiresFullRefresh
        let dirtyPaths = dirtySearchIndexPaths
        let revision = searchIndexRevision
        searchIndexLock.unlock()

        guard let snapshot,
              !requiresFullRefresh,
              snapshot.rootsKey == expectedRootsKey else {
            return nil
        }

        noteLinkIndexLock.lock()
        let linkIndex: NoteLinkIndex
        if let cached = cachedNoteLinkIndex,
           cached.rootsKey == expectedRootsKey,
           cached.revision == revision {
            linkIndex = cached
        } else {
            linkIndex = NoteLinkIndex(
                rootsKey: expectedRootsKey,
                revision: revision,
                entries: snapshot.entries
            )
            cachedNoteLinkIndex = linkIndex
        }
        noteLinkIndexLock.unlock()

        let targetPath = targetURL.standardizedFileURL.path
        var urlsByPath: [String: URL] = [:]
        for item in linkIndex.incomingByTargetPath[targetPath] ?? [] {
            urlsByPath[item.url.standardizedFileURL.path] = item.url.standardizedFileURL
        }
        // Include any dirty paths whose on-disk links may not yet be reflected in the snapshot.
        for dirtyPath in dirtyPaths where dirtyPath != targetPath {
            urlsByPath[dirtyPath] = URL(fileURLWithPath: dirtyPath).standardizedFileURL
        }
        return Array(urlsByPath.values)
    }

    private func cachedOrBuiltNoteLinkIndex(
        roots: [URL],
        cancellationCheck: @Sendable () -> Bool
    ) -> NoteLinkIndex? {
        let normalizedRoots = canonicalSearchRoots(roots)
        let rootsKey = normalizedRoots.map(\.path)
        guard let entries = indexedEntries(
            roots: normalizedRoots,
            cancellationCheck: cancellationCheck
        ) else {
            return nil
        }
        guard !cancellationCheck() else { return nil }

        searchIndexLock.lock()
        let currentRevision = searchIndexRevision
        let snapshotRoots = searchIndexSnapshot?.rootsKey
        searchIndexLock.unlock()

        let cacheable = snapshotRoots == rootsKey
        if cacheable {
            noteLinkIndexLock.lock()
            if let cached = cachedNoteLinkIndex,
               cached.rootsKey == rootsKey,
               cached.revision == currentRevision {
                noteLinkIndexLock.unlock()
                return cached
            }
            noteLinkIndexLock.unlock()
        }

        let built = NoteLinkIndex(
            rootsKey: rootsKey,
            revision: currentRevision,
            entries: entries
        )
        if cacheable {
            noteLinkIndexLock.lock()
            cachedNoteLinkIndex = built
            noteLinkIndexLock.unlock()
        }
        return built
    }

    private func relativeNoteLinkPath(from directory: URL, to target: URL) -> String {
        let sourceComponents = directory.standardizedFileURL.pathComponents
        let targetComponents = target.standardizedFileURL.pathComponents
        var sharedCount = 0
        while sharedCount < min(sourceComponents.count, targetComponents.count),
              sourceComponents[sharedCount] == targetComponents[sharedCount] {
            sharedCount += 1
        }
        let upward = Array(repeating: "..", count: sourceComponents.count - sharedCount)
        return (upward + targetComponents.dropFirst(sharedCount)).joined(separator: "/")
    }
}
