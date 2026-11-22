import Foundation

public enum KnowledgeLayer: String, Codable, CaseIterable, Sendable {
    case point
    case line
    case plane
    case body

    public var displayName: String {
        switch self {
        case .point: return "点"
        case .line: return "线"
        case .plane: return "面"
        case .body: return "体"
        }
    }

    public var nextHigher: KnowledgeLayer? {
        switch self {
        case .point: return .line
        case .line: return .plane
        case .plane: return .body
        case .body: return nil
        }
    }

    var rank: Int {
        switch self {
        case .point: return 0
        case .line: return 1
        case .plane: return 2
        case .body: return 3
        }
    }

    static func parse(sourceContents: String, tags: [String]) -> KnowledgeLayer? {
        let normalizedTags = Set(tags.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        for layer in KnowledgeLayer.allCases {
            let aliases = layer.aliases
            if !normalizedTags.isDisjoint(with: aliases) {
                return layer
            }
        }

        guard let frontMatter = frontMatter(in: sourceContents) else { return nil }
        if let rawLayer = scalarValue(for: "layer", in: frontMatter),
           let layer = layer(for: rawLayer) {
            return layer
        }
        return nil
    }

    private var aliases: Set<String> {
        switch self {
        case .point: return ["层级/点", "layer/point"]
        case .line: return ["层级/线", "layer/line"]
        case .plane: return ["层级/面", "layer/plane"]
        case .body: return ["层级/体", "layer/body"]
        }
    }

    private static func layer(for rawValue: String) -> KnowledgeLayer? {
        let value = rawValue
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            .lowercased()
        switch value {
        case "point", "点": return .point
        case "line", "线": return .line
        case "plane", "面": return .plane
        case "body", "体": return .body
        default: return nil
        }
    }

    private static func frontMatter(in source: String) -> [Substring]? {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else { return nil }
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        guard let closing = lines.dropFirst().firstIndex(of: "---") else { return nil }
        return Array(lines[1..<closing])
    }

    private static func scalarValue(for key: String, in lines: [Substring]) -> String? {
        for line in lines {
            let text = String(line)
            guard text.first?.isWhitespace != true,
                  let colon = text.firstIndex(of: ":") else {
                continue
            }
            let candidateKey = text[..<colon]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard candidateKey == key else { continue }
            return String(text[text.index(after: colon)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}

public struct KnowledgeRelationItem: Equatable, Sendable {
    public let url: URL
    public let title: String
    public let layer: KnowledgeLayer?
    public let reason: String?
    public let score: Double?

    public init(
        url: URL,
        title: String,
        layer: KnowledgeLayer? = nil,
        reason: String? = nil,
        score: Double? = nil
    ) {
        self.url = url
        self.title = title
        self.layer = layer
        self.reason = reason
        self.score = score
    }
}

public struct KnowledgeRelations: Equatable, Sendable {
    public let currentLayer: KnowledgeLayer?
    public let parents: [KnowledgeRelationItem]
    public let children: [KnowledgeRelationItem]
    public let related: [KnowledgeRelationItem]
    public let suggested: [KnowledgeRelationItem]
    public let outgoing: [KnowledgeRelationItem]
    public let incoming: [KnowledgeRelationItem]

    public init(
        currentLayer: KnowledgeLayer?,
        parents: [KnowledgeRelationItem],
        children: [KnowledgeRelationItem],
        related: [KnowledgeRelationItem],
        suggested: [KnowledgeRelationItem],
        outgoing: [KnowledgeRelationItem] = [],
        incoming: [KnowledgeRelationItem] = []
    ) {
        self.currentLayer = currentLayer
        self.parents = parents
        self.children = children
        self.related = related
        self.suggested = suggested
        self.outgoing = outgoing
        self.incoming = incoming
    }

    public static let empty = KnowledgeRelations(
        currentLayer: nil,
        parents: [],
        children: [],
        related: [],
        suggested: []
    )
}

public enum KnowledgeGraphScope: Equatable, Sendable {
    case global
    case local(focus: URL, depth: Int)
}

public enum KnowledgeGraphEdgeKind: String, Equatable, Sendable {
    case hierarchy
    case related
}

public struct KnowledgeGraphNode: Equatable, Hashable, Sendable {
    public let url: URL
    public let title: String
    public let layer: KnowledgeLayer?
    public let linkCount: Int

    public init(
        url: URL,
        title: String,
        layer: KnowledgeLayer?,
        linkCount: Int
    ) {
        self.url = url
        self.title = title
        self.layer = layer
        self.linkCount = linkCount
    }
}

public struct KnowledgeGraphEdge: Equatable, Hashable, Sendable {
    public let sourceURL: URL
    public let targetURL: URL
    public let kind: KnowledgeGraphEdgeKind

    public init(
        sourceURL: URL,
        targetURL: URL,
        kind: KnowledgeGraphEdgeKind
    ) {
        self.sourceURL = sourceURL
        self.targetURL = targetURL
        self.kind = kind
    }
}

public struct KnowledgeGraphSnapshot: Equatable, Sendable {
    public let nodes: [KnowledgeGraphNode]
    public let edges: [KnowledgeGraphEdge]
    public let focusedURL: URL?
    public let sourceRevision: UInt64

    public init(
        nodes: [KnowledgeGraphNode],
        edges: [KnowledgeGraphEdge],
        focusedURL: URL?,
        sourceRevision: UInt64 = 0
    ) {
        self.nodes = nodes
        self.edges = edges
        self.focusedURL = focusedURL
        self.sourceRevision = sourceRevision
    }

    public static let empty = KnowledgeGraphSnapshot(
        nodes: [],
        edges: [],
        focusedURL: nil,
        sourceRevision: 0
    )
}

struct KnowledgeLinkTarget: Codable, Equatable, Sendable {
    let value: String
    let isWikiLink: Bool
}

final class KnowledgeDerivedIndex: @unchecked Sendable {
    let rootsKey: [String]
    let revision: UInt64
    let includesArchived: Bool
    let ignoredTags: Set<String>
    let entries: [NoteSearchIndexEntry]
    let entriesByPath: [String: NoteSearchIndexEntry]
    let entriesByBasename: [String: [NoteSearchIndexEntry]]
    let entriesBySuffix: [String: [NoteSearchIndexEntry]]
    let allEdges: [KnowledgeGraphEdge]
    let adjacency: [String: Set<String>]
    let incomingByTargetPath: [String: [NoteSearchIndexEntry]]
    let distinctiveTokensByPath: [String: Set<String>]
    let tokenDocumentFrequency: [String: Int]
    let commonTokenThreshold: Int
    let meaningfulTagsByPath: [String: Set<String>]
    let pathsByTag: [String: Set<String>]
    let pathsByToken: [String: Set<String>]

    init(
        rootsKey: [String],
        revision: UInt64,
        includesArchived: Bool,
        ignoredTags: Set<String>,
        entries: [NoteSearchIndexEntry],
        entriesByPath: [String: NoteSearchIndexEntry],
        entriesByBasename: [String: [NoteSearchIndexEntry]],
        entriesBySuffix: [String: [NoteSearchIndexEntry]],
        allEdges: [KnowledgeGraphEdge],
        adjacency: [String: Set<String>],
        incomingByTargetPath: [String: [NoteSearchIndexEntry]],
        distinctiveTokensByPath: [String: Set<String>],
        tokenDocumentFrequency: [String: Int],
        commonTokenThreshold: Int,
        meaningfulTagsByPath: [String: Set<String>],
        pathsByTag: [String: Set<String>],
        pathsByToken: [String: Set<String>]
    ) {
        self.rootsKey = rootsKey
        self.revision = revision
        self.includesArchived = includesArchived
        self.ignoredTags = ignoredTags
        self.entries = entries
        self.entriesByPath = entriesByPath
        self.entriesByBasename = entriesByBasename
        self.entriesBySuffix = entriesBySuffix
        self.allEdges = allEdges
        self.adjacency = adjacency
        self.incomingByTargetPath = incomingByTargetPath
        self.distinctiveTokensByPath = distinctiveTokensByPath
        self.tokenDocumentFrequency = tokenDocumentFrequency
        self.commonTokenThreshold = commonTokenThreshold
        self.meaningfulTagsByPath = meaningfulTagsByPath
        self.pathsByTag = pathsByTag
        self.pathsByToken = pathsByToken
    }
}

extension NoteStore {
    private func knowledgeDerivedIndex(
        for readView: (entries: [NoteSearchIndexEntry], rootsKey: [String], revision: UInt64),
        includesArchived: Bool,
        cancellationCheck: @Sendable () -> Bool
    ) -> KnowledgeDerivedIndex? {
        let ignored = effectiveIgnoredKnowledgeTags()
        knowledgeDerivedIndexLock.lock()
        if let cached = cachedKnowledgeDerivedIndex,
           cached.rootsKey == readView.rootsKey,
           cached.revision == readView.revision,
           cached.includesArchived == includesArchived,
           cached.ignoredTags == ignored {
            knowledgeDerivedIndexLock.unlock()
            return cached
        }
        knowledgeDerivedIndexLock.unlock()

        let entries = includesArchived ? readView.entries : knowledgeEligibleEntries(readView.entries)
        let entriesByPath = Dictionary(
            entries.map { ($0.url.standardizedFileURL.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let entriesByBasename = Dictionary(grouping: entries) {
            $0.url.deletingPathExtension().lastPathComponent.lowercased()
        }
        let entriesBySuffix = knowledgeEntriesBySuffix(entries)

        var uniqueEdges = Set<KnowledgeGraphEdge>()
        var adjacency: [String: Set<String>] = [:]
        var incomingByTargetPath: [String: [NoteSearchIndexEntry]] = [:]

        for entry in entries {
            guard !cancellationCheck() else { return nil }
            let sourceURL = entry.url.standardizedFileURL
            let targets = resolvedKnowledgeLinkEntries(
                entry.knowledgeLinkTargets,
                sourceURL: sourceURL,
                entriesByPath: entriesByPath,
                entriesByBasename: entriesByBasename,
                entriesBySuffix: entriesBySuffix,
                excluding: sourceURL
            )
            for target in targets {
                let edge = knowledgeGraphEdge(from: entry, to: target)
                uniqueEdges.insert(edge)
                let targetPath = target.url.standardizedFileURL.path
                incomingByTargetPath[targetPath, default: []].append(entry)
            }
        }

        let allEdges = uniqueEdges.sorted(by: knowledgeGraphEdgeSort)
        for edge in allEdges {
            let sourcePath = edge.sourceURL.standardizedFileURL.path
            let targetPath = edge.targetURL.standardizedFileURL.path
            adjacency[sourcePath, default: []].insert(targetPath)
            adjacency[targetPath, default: []].insert(sourcePath)
        }

        var rawTokensByPath: [String: Set<String>] = [:]
        rawTokensByPath.reserveCapacity(entries.count)
        var tokenDocumentFrequency: [String: Int] = [:]
        var meaningfulTagsByPath: [String: Set<String>] = [:]
        meaningfulTagsByPath.reserveCapacity(entries.count)
        var pathsByTag: [String: Set<String>] = [:]

        for entry in entries {
            guard !cancellationCheck() else { return nil }
            let path = entry.url.standardizedFileURL.path
            let tokens = knowledgeTokens(in: "\(entry.title)\n\(entry.body)")
            rawTokensByPath[path] = tokens
            for token in tokens {
                tokenDocumentFrequency[token, default: 0] += 1
            }
            let tags = meaningfulKnowledgeTags(entry.tags, ignored: ignored)
            meaningfulTagsByPath[path] = tags
            for tag in tags {
                pathsByTag[tag, default: []].insert(path)
            }
        }

        let commonTokenThreshold = max(2, entries.count / 2)
        var distinctiveTokensByPath: [String: Set<String>] = [:]
        distinctiveTokensByPath.reserveCapacity(entries.count)
        var pathsByToken: [String: Set<String>] = [:]
        for (path, rawTokens) in rawTokensByPath {
            let distinctive = rawTokens.filter {
                tokenDocumentFrequency[$0, default: 0] <= commonTokenThreshold
            }
            distinctiveTokensByPath[path] = distinctive
            for token in distinctive {
                pathsByToken[token, default: []].insert(path)
            }
        }

        let derived = KnowledgeDerivedIndex(
            rootsKey: readView.rootsKey,
            revision: readView.revision,
            includesArchived: includesArchived,
            ignoredTags: ignored,
            entries: entries,
            entriesByPath: entriesByPath,
            entriesByBasename: entriesByBasename,
            entriesBySuffix: entriesBySuffix,
            allEdges: allEdges,
            adjacency: adjacency,
            incomingByTargetPath: incomingByTargetPath,
            distinctiveTokensByPath: distinctiveTokensByPath,
            tokenDocumentFrequency: tokenDocumentFrequency,
            commonTokenThreshold: commonTokenThreshold,
            meaningfulTagsByPath: meaningfulTagsByPath,
            pathsByTag: pathsByTag,
            pathsByToken: pathsByToken
        )

        knowledgeDerivedIndexLock.lock()
        cachedKnowledgeDerivedIndex = derived
        knowledgeDerivedIndexLock.unlock()
        return derived
    }

    public func knowledgeGraphSnapshot(
        scope: KnowledgeGraphScope,
        roots: [URL]? = nil,
        includesUnlinkedAndArchivedNotes: Bool = false,
        cancellationCheck: @Sendable () -> Bool = { false }
    ) -> KnowledgeGraphSnapshot {
        guard !cancellationCheck(),
              let readView = indexedReadView(
                roots: roots,
                cancellationCheck: cancellationCheck
              ),
              let derived = knowledgeDerivedIndex(
                for: readView,
                includesArchived: includesUnlinkedAndArchivedNotes,
                cancellationCheck: cancellationCheck
              ) else {
            return .empty
        }

        let entriesByPath = derived.entriesByPath
        let allEdges = derived.allEdges
        let focusedURL: URL?
        let includedPaths: Set<String>
        switch scope {
        case .global:
            focusedURL = nil
            includedPaths = includesUnlinkedAndArchivedNotes ? Set(entriesByPath.keys) : Set(allEdges.flatMap {
                [$0.sourceURL.standardizedFileURL.path, $0.targetURL.standardizedFileURL.path]
            })
        case .local(let focus, let requestedDepth):
            let focusURL = focus.standardizedFileURL
            focusedURL = focusURL
            guard entriesByPath[focusURL.path] != nil else {
                return KnowledgeGraphSnapshot(
                    nodes: [],
                    edges: [],
                    focusedURL: focusURL,
                    sourceRevision: readView.revision
                )
            }
            var visited = Set([focusURL.path])
            var frontier = Set([focusURL.path])
            for _ in 0..<max(0, requestedDepth) {
                guard !cancellationCheck() else { return .empty }
                guard !frontier.isEmpty else { break }
                var next = Set<String>()
                for path in frontier {
                    next.formUnion(derived.adjacency[path] ?? [])
                }
                next.subtract(visited)
                visited.formUnion(next)
                frontier = next
            }
            includedPaths = visited
        }

        let edges = allEdges.filter {
            includedPaths.contains($0.sourceURL.standardizedFileURL.path)
                && includedPaths.contains($0.targetURL.standardizedFileURL.path)
        }
        var degreeByPath: [String: Int] = [:]
        for edge in edges {
            degreeByPath[edge.sourceURL.standardizedFileURL.path, default: 0] += 1
            degreeByPath[edge.targetURL.standardizedFileURL.path, default: 0] += 1
        }
        let nodes = includedPaths.compactMap { path -> KnowledgeGraphNode? in
            guard let entry = entriesByPath[path] else { return nil }
            return KnowledgeGraphNode(
                url: entry.url.standardizedFileURL,
                title: entry.title,
                layer: entry.knowledgeLayer,
                linkCount: degreeByPath[path, default: 0]
            )
        }.sorted(by: knowledgeGraphNodeSort)

        guard !cancellationCheck(),
              isCurrentIndexedReadView(
                rootsKey: readView.rootsKey,
                revision: readView.revision
              ) else {
            return .empty
        }
        return KnowledgeGraphSnapshot(
            nodes: nodes,
            edges: edges,
            focusedURL: focusedURL,
            sourceRevision: readView.revision
        )
    }

    public func knowledgeRelations(
        for noteURL: URL,
        currentBody: String? = nil,
        roots: [URL]? = nil,
        suggestionLimit: Int = 5,
        cancellationCheck: @Sendable () -> Bool = { false }
    ) -> KnowledgeRelations {
        guard !cancellationCheck() else { return .empty }
        guard let readView = indexedReadView(
            roots: roots,
            cancellationCheck: cancellationCheck
        ),
        let derived = knowledgeDerivedIndex(
            for: readView,
            includesArchived: false,
            cancellationCheck: cancellationCheck
        ) else {
            return .empty
        }
        let currentURL = noteURL.standardizedFileURL
        let entriesByPath = derived.entriesByPath
        let currentEntry = entriesByPath[currentURL.path]
        let body = currentBody
            ?? currentEntry?.body
            ?? (try? loadNote(at: currentURL).body)
            ?? ""
        let currentLayer = currentEntry?.knowledgeLayer

        let outgoingTargets: [KnowledgeLinkTarget] = if currentBody == nil, let currentEntry {
            currentEntry.knowledgeLinkTargets
        } else {
            knowledgeLinkTargets(in: body, cancellationCheck: cancellationCheck)
        }
        let outgoingEntries = resolvedKnowledgeLinkEntries(
            outgoingTargets,
            sourceURL: currentURL,
            entriesByPath: entriesByPath,
            entriesByBasename: derived.entriesByBasename,
            entriesBySuffix: derived.entriesBySuffix,
            excluding: currentURL
        )
        var incomingEntriesByPath: [String: NoteSearchIndexEntry] = [:]
        for entry in derived.incomingByTargetPath[currentURL.path] ?? [] {
            let path = entry.url.standardizedFileURL.path
            if path != currentURL.path {
                incomingEntriesByPath[path] = entry
            }
        }

        var parentsByPath: [String: KnowledgeRelationItem] = [:]
        var childrenByPath: [String: KnowledgeRelationItem] = [:]
        var relatedByPath: [String: KnowledgeRelationItem] = [:]

        for entry in outgoingEntries {
            categorizeExplicitKnowledgeRelation(
                entry,
                currentLayer: currentLayer,
                parents: &parentsByPath,
                children: &childrenByPath,
                related: &relatedByPath
            )
        }
        for entry in incomingEntriesByPath.values {
            categorizeExplicitKnowledgeRelation(
                entry,
                currentLayer: currentLayer,
                parents: &parentsByPath,
                children: &childrenByPath,
                related: &relatedByPath
            )
        }

        let explicitPaths = Set(
            Array(parentsByPath.keys)
                + Array(childrenByPath.keys)
                + Array(relatedByPath.keys)
                + [currentURL.path]
        )
        let suggested = suggestedKnowledgeRelations(
            for: currentEntry,
            body: body,
            derived: derived,
            excluding: explicitPaths,
            limit: max(suggestionLimit, 0),
            cancellationCheck: cancellationCheck
        )

        return KnowledgeRelations(
            currentLayer: currentLayer,
            parents: parentsByPath.values.sorted(by: knowledgeItemSort),
            children: childrenByPath.values.sorted(by: knowledgeItemSort),
            related: relatedByPath.values.sorted(by: knowledgeItemSort),
            suggested: suggested,
            outgoing: outgoingEntries.map {
                KnowledgeRelationItem(url: $0.url.standardizedFileURL, title: $0.title, layer: $0.knowledgeLayer)
            }.sorted(by: knowledgeItemSort),
            incoming: incomingEntriesByPath.values.map {
                KnowledgeRelationItem(url: $0.url.standardizedFileURL, title: $0.title, layer: $0.knowledgeLayer)
            }.sorted(by: knowledgeItemSort)
        )
    }

    public func markdownKnowledgeLink(
        from sourceURL: URL,
        to targetURL: URL,
        title: String
    ) -> String {
        let sourceDirectory = sourceURL.deletingLastPathComponent().standardizedFileURL
        let target = targetURL.standardizedFileURL
        var allowedCharacters = CharacterSet.urlPathAllowed
        allowedCharacters.remove(charactersIn: "()[]")
        let rawRelativePath = relativePath(from: sourceDirectory, to: target)
        let relativePath = rawRelativePath
            .addingPercentEncoding(withAllowedCharacters: allowedCharacters)
            ?? rawRelativePath
        let escapedTitle = title
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "]", with: "\\]")
        return "[\(escapedTitle)](\(relativePath))"
    }

    private func categorizeExplicitKnowledgeRelation(
        _ entry: NoteSearchIndexEntry,
        currentLayer: KnowledgeLayer?,
        parents: inout [String: KnowledgeRelationItem],
        children: inout [String: KnowledgeRelationItem],
        related: inout [String: KnowledgeRelationItem]
    ) {
        let item = KnowledgeRelationItem(
            url: entry.url.standardizedFileURL,
            title: entry.title,
            layer: entry.knowledgeLayer
        )
        let path = item.url.path
        guard let currentLayer, let otherLayer = entry.knowledgeLayer,
              currentLayer != otherLayer else {
            related[path] = item
            return
        }

        let otherIsHigher = otherLayer.rank > currentLayer.rank
        if otherIsHigher {
            parents[path] = item
        } else {
            children[path] = item
        }
    }

    private func knowledgeGraphEdge(
        from source: NoteSearchIndexEntry,
        to target: NoteSearchIndexEntry
    ) -> KnowledgeGraphEdge {
        let sourceURL = source.url.standardizedFileURL
        let targetURL = target.url.standardizedFileURL
        if let sourceLayer = source.knowledgeLayer,
           let targetLayer = target.knowledgeLayer,
           sourceLayer != targetLayer {
            if sourceLayer.rank < targetLayer.rank {
                return KnowledgeGraphEdge(
                    sourceURL: sourceURL,
                    targetURL: targetURL,
                    kind: .hierarchy
                )
            }
            return KnowledgeGraphEdge(
                sourceURL: targetURL,
                targetURL: sourceURL,
                kind: .hierarchy
            )
        }
        let pathOrder = sourceURL.path.localizedCaseInsensitiveCompare(targetURL.path)
        if pathOrder == .orderedAscending
            || (pathOrder == .orderedSame && sourceURL.path < targetURL.path) {
            return KnowledgeGraphEdge(
                sourceURL: sourceURL,
                targetURL: targetURL,
                kind: .related
            )
        }
        return KnowledgeGraphEdge(
            sourceURL: targetURL,
            targetURL: sourceURL,
            kind: .related
        )
    }

    private func knowledgeGraphEdgeSort(
        _ lhs: KnowledgeGraphEdge,
        _ rhs: KnowledgeGraphEdge
    ) -> Bool {
        let sourceOrder = lhs.sourceURL.path.localizedCaseInsensitiveCompare(rhs.sourceURL.path)
        if sourceOrder != .orderedSame {
            return sourceOrder == .orderedAscending
        }
        let targetOrder = lhs.targetURL.path.localizedCaseInsensitiveCompare(rhs.targetURL.path)
        if targetOrder != .orderedSame {
            return targetOrder == .orderedAscending
        }
        return lhs.kind.rawValue < rhs.kind.rawValue
    }

    private func knowledgeGraphNodeSort(
        _ lhs: KnowledgeGraphNode,
        _ rhs: KnowledgeGraphNode
    ) -> Bool {
        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleOrder == .orderedSame {
            return lhs.url.path.localizedCaseInsensitiveCompare(rhs.url.path) == .orderedAscending
        }
        return titleOrder == .orderedAscending
    }

    private func resolvedKnowledgeLinkEntries(
        _ targets: [KnowledgeLinkTarget],
        sourceURL: URL,
        entriesByPath: [String: NoteSearchIndexEntry],
        entriesByBasename: [String: [NoteSearchIndexEntry]],
        entriesBySuffix: [String: [NoteSearchIndexEntry]],
        excluding excludedURL: URL
    ) -> [NoteSearchIndexEntry] {
        var matchesByPath: [String: NoteSearchIndexEntry] = [:]
        for target in targets {
            guard let entry = resolveKnowledgeLink(
                target,
                sourceURL: sourceURL,
                entriesByPath: entriesByPath,
                entriesByBasename: entriesByBasename,
                entriesBySuffix: entriesBySuffix
            ), entry.url.standardizedFileURL.path != excludedURL.standardizedFileURL.path else {
                continue
            }
            matchesByPath[entry.url.standardizedFileURL.path] = entry
        }
        return Array(matchesByPath.values)
    }

    private func resolveKnowledgeLink(
        _ target: KnowledgeLinkTarget,
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

    private func knowledgeEntriesBySuffix(
        _ entries: [NoteSearchIndexEntry]
    ) -> [String: [NoteSearchIndexEntry]] {
        var result: [String: [NoteSearchIndexEntry]] = [:]
        for entry in entries {
            let components = entry.url.standardizedFileURL.pathComponents
                .drop(while: { $0 == "/" })
            guard !components.isEmpty else { continue }
            for index in components.indices {
                let suffix = components[index...].joined(separator: "/")
                result[suffix, default: []].append(entry)
            }
        }
        return result
    }

    func knowledgeLinkTargets(
        in markdown: String,
        cancellationCheck: @Sendable () -> Bool = { false }
    ) -> [KnowledgeLinkTarget] {
        MarkdownNoteReferenceParser.references(
            in: markdown,
            cancellationCheck: cancellationCheck
        ).map {
            KnowledgeLinkTarget(value: $0.destination, isWikiLink: $0.kind == .wiki)
        }
    }

    private func suggestedKnowledgeRelations(
        for currentEntry: NoteSearchIndexEntry?,
        body: String,
        derived: KnowledgeDerivedIndex,
        excluding excludedPaths: Set<String>,
        limit: Int,
        cancellationCheck: @Sendable () -> Bool
    ) -> [KnowledgeRelationItem] {
        guard limit > 0 else { return [] }
        let currentTitle = currentEntry?.title ?? ""
        let currentTags: Set<String>
        if let currentEntry, let cached = derived.meaningfulTagsByPath[currentEntry.url.standardizedFileURL.path] {
            currentTags = cached
        } else {
            currentTags = meaningfulKnowledgeTags(currentEntry?.tags ?? [], ignored: derived.ignoredTags)
        }

        let currentTokens: Set<String>
        if let currentEntry,
           body == currentEntry.body,
           let cachedTokens = derived.distinctiveTokensByPath[currentEntry.url.standardizedFileURL.path] {
            currentTokens = cachedTokens
        } else {
            currentTokens = knowledgeTokens(in: "\(currentTitle)\n\(body)").filter {
                derived.tokenDocumentFrequency[$0, default: 0] <= derived.commonTokenThreshold
            }
        }
        guard !currentTags.isEmpty || currentTokens.count >= 2 else { return [] }

        // Gather only candidate paths sharing at least 1 meaningful tag or >= 2 distinctive tokens.
        var candidatePaths = Set<String>()
        for tag in currentTags {
            if let matches = derived.pathsByTag[tag] {
                candidatePaths.formUnion(matches)
            }
        }
        var sharedTokenCounts: [String: Int] = [:]
        for token in currentTokens {
            if let matches = derived.pathsByToken[token] {
                for path in matches where !excludedPaths.contains(path) {
                    let count = sharedTokenCounts[path, default: 0] + 1
                    sharedTokenCounts[path] = count
                    if count >= 2 {
                        candidatePaths.insert(path)
                    }
                }
            }
        }
        candidatePaths.subtract(excludedPaths)

        var candidates: [KnowledgeRelationItem] = []
        for path in candidatePaths {
            guard !cancellationCheck() else { return [] }
            guard let entry = derived.entriesByPath[path] else { continue }
            let candidateTags = derived.meaningfulTagsByPath[path] ?? []
            let sharedTags = currentTags.intersection(candidateTags)
            let candidateTokens = derived.distinctiveTokensByPath[path] ?? []
            let sharedTokenCount = sharedTokenCounts[path] ?? currentTokens.intersection(candidateTokens).count
            let tokenSimilarity: Double
            let unionTokenCount = currentTokens.count + candidateTokens.count - sharedTokenCount
            if unionTokenCount == 0 {
                tokenSimilarity = 0
            } else {
                tokenSimilarity = Double(sharedTokenCount) / Double(unionTokenCount)
            }
            guard !sharedTags.isEmpty || sharedTokenCount >= 2 else { continue }
            let tagScore = min(Double(sharedTags.count) * 0.34, 0.68)
            let score = tagScore + min(tokenSimilarity * 0.55, 0.55)
            guard score >= 0.25 else { continue }

            let reason: String
            if !sharedTags.isEmpty {
                reason = "共同标签：\(sharedTags.sorted().prefix(2).joined(separator: "、"))"
            } else {
                reason = "内容关键词相近"
            }
            candidates.append(KnowledgeRelationItem(
                url: entry.url.standardizedFileURL,
                title: entry.title,
                layer: entry.knowledgeLayer,
                reason: reason,
                score: score
            ))
        }
        return candidates
            .sorted {
                if $0.score == $1.score {
                    return knowledgeItemSort($0, $1)
                }
                return ($0.score ?? 0) > ($1.score ?? 0)
            }
            .prefix(limit)
            .map { $0 }
    }

    private func effectiveIgnoredKnowledgeTags() -> Set<String> {
        Set(ignoredKnowledgeTags.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }.filter { !$0.isEmpty })
    }

    private func meaningfulKnowledgeTags(_ tags: [String], ignored: Set<String>) -> Set<String> {
        Set(tags.compactMap {
            let normalized = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.isEmpty || ignored.contains(normalized) ? nil : normalized
        })
    }

    private func knowledgeEligibleEntries(
        _ entries: [NoteSearchIndexEntry]
    ) -> [NoteSearchIndexEntry] {
        guard !includesArchivedNotesInKnowledge else { return entries }
        return entries.filter { !isArchivedNote(at: $0.url) }
    }

    private func knowledgeTokens(in text: String) -> Set<String> {
        let limited = String(text.prefix(12_000)).lowercased()
        var tokens = Set<String>()
        var word = ""
        var chineseCharacters: [Character] = []

        func flushWord() {
            if word.count >= 2 {
                tokens.insert(word)
            }
            word.removeAll(keepingCapacity: true)
        }

        func flushChinese() {
            guard chineseCharacters.count >= 2 else {
                chineseCharacters.removeAll(keepingCapacity: true)
                return
            }
            for index in 0..<(chineseCharacters.count - 1) {
                tokens.insert(String(chineseCharacters[index...index + 1]))
            }
            chineseCharacters.removeAll(keepingCapacity: true)
        }

        for character in limited {
            if character.unicodeScalars.allSatisfy({ scalar in
                (0x4E00...0x9FFF).contains(Int(scalar.value))
            }) {
                flushWord()
                chineseCharacters.append(character)
            } else if character.isLetter || character.isNumber {
                flushChinese()
                word.append(character)
            } else {
                flushWord()
                flushChinese()
            }
            if tokens.count >= 800 { break }
        }
        flushWord()
        flushChinese()
        return tokens
    }

    private func relativePath(from directory: URL, to target: URL) -> String {
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

    private func knowledgeItemSort(
        _ lhs: KnowledgeRelationItem,
        _ rhs: KnowledgeRelationItem
    ) -> Bool {
        let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleOrder == .orderedSame {
            return lhs.url.path.localizedCaseInsensitiveCompare(rhs.url.path) == .orderedAscending
        }
        return titleOrder == .orderedAscending
    }
}
