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

    public init(
        currentLayer: KnowledgeLayer?,
        parents: [KnowledgeRelationItem],
        children: [KnowledgeRelationItem],
        related: [KnowledgeRelationItem],
        suggested: [KnowledgeRelationItem]
    ) {
        self.currentLayer = currentLayer
        self.parents = parents
        self.children = children
        self.related = related
        self.suggested = suggested
    }

    public static let empty = KnowledgeRelations(
        currentLayer: nil,
        parents: [],
        children: [],
        related: [],
        suggested: []
    )
}

private struct KnowledgeLinkTarget {
    let value: String
    let isWikiLink: Bool
}

extension NoteStore {
    public func knowledgeRelations(
        for noteURL: URL,
        currentBody: String? = nil,
        roots: [URL]? = nil,
        suggestionLimit: Int = 5,
        cancellationCheck: @Sendable () -> Bool = { false }
    ) -> KnowledgeRelations {
        guard !cancellationCheck() else { return .empty }
        guard let entries = indexedEntries(
            roots: roots,
            cancellationCheck: cancellationCheck
        ) else {
            return .empty
        }
        let currentURL = noteURL.standardizedFileURL
        let entriesByPath = Dictionary(uniqueKeysWithValues: entries.map {
            ($0.url.standardizedFileURL.path, $0)
        })
        let entriesByBasename = Dictionary(grouping: entries) {
            $0.url.deletingPathExtension().lastPathComponent.lowercased()
        }
        let currentEntry = entriesByPath[currentURL.path]
        let body = currentBody
            ?? currentEntry?.body
            ?? (try? loadNote(at: currentURL).body)
            ?? ""
        let currentLayer = currentEntry?.knowledgeLayer

        let outgoingEntries = resolvedKnowledgeLinkEntries(
            in: body,
            sourceURL: currentURL,
            entriesByPath: entriesByPath,
            entriesByBasename: entriesByBasename,
            excluding: currentURL
        )
        var incomingEntriesByPath: [String: NoteSearchIndexEntry] = [:]
        for entry in entries where entry.url.standardizedFileURL.path != currentURL.path {
            guard !cancellationCheck() else { return .empty }
            let targets = resolvedKnowledgeLinkEntries(
                in: entry.body,
                sourceURL: entry.url,
                entriesByPath: entriesByPath,
                entriesByBasename: entriesByBasename,
                excluding: entry.url
            )
            if targets.contains(where: { $0.url.standardizedFileURL.path == currentURL.path }) {
                incomingEntriesByPath[entry.url.standardizedFileURL.path] = entry
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
            among: entries,
            excluding: explicitPaths,
            limit: max(suggestionLimit, 0),
            cancellationCheck: cancellationCheck
        )

        return KnowledgeRelations(
            currentLayer: currentLayer,
            parents: parentsByPath.values.sorted(by: knowledgeItemSort),
            children: childrenByPath.values.sorted(by: knowledgeItemSort),
            related: relatedByPath.values.sorted(by: knowledgeItemSort),
            suggested: suggested
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

    private func resolvedKnowledgeLinkEntries(
        in markdown: String,
        sourceURL: URL,
        entriesByPath: [String: NoteSearchIndexEntry],
        entriesByBasename: [String: [NoteSearchIndexEntry]],
        excluding excludedURL: URL
    ) -> [NoteSearchIndexEntry] {
        var matchesByPath: [String: NoteSearchIndexEntry] = [:]
        for target in knowledgeLinkTargets(in: markdown) {
            guard let entry = resolveKnowledgeLink(
                target,
                sourceURL: sourceURL,
                entriesByPath: entriesByPath,
                entriesByBasename: entriesByBasename
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
        entriesByBasename: [String: [NoteSearchIndexEntry]]
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

        let suffixMatches = entriesByPath.values.filter { entry in
            extensions.contains { pathExtension in
                entry.url.standardizedFileURL.path.hasSuffix(
                    "/\(normalizedTarget).\(pathExtension)"
                )
            }
        }
        if suffixMatches.count == 1 {
            return suffixMatches[0]
        }

        let basename = URL(fileURLWithPath: normalizedTarget).lastPathComponent
        let basenameMatches = entriesByBasename[basename.lowercased()] ?? []
        return basenameMatches.count == 1 ? basenameMatches[0] : nil
    }

    private func knowledgeLinkTargets(in markdown: String) -> [KnowledgeLinkTarget] {
        var targets: [KnowledgeLinkTarget] = []
        if let expression = try? NSRegularExpression(
            pattern: #"(?<!!)\[[^\]]*\]\(([^)]+)\)"#
        ) {
            let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
            targets += expression.matches(in: markdown, range: range).compactMap { match in
                guard match.numberOfRanges > 1,
                      let targetRange = Range(match.range(at: 1), in: markdown) else {
                    return nil
                }
                var value = String(markdown[targetRange])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if value.hasPrefix("<"), let closing = value.firstIndex(of: ">") {
                    value = String(value[value.index(after: value.startIndex)..<closing])
                } else if let titleRange = value.range(
                    of: #"\s+["'][^"']*["']\s*$"#,
                    options: .regularExpression
                ) {
                    value.removeSubrange(titleRange)
                }
                return KnowledgeLinkTarget(
                    value: value.trimmingCharacters(in: .whitespacesAndNewlines),
                    isWikiLink: false
                )
            }
        }

        if let expression = try? NSRegularExpression(pattern: #"(?<!!)\[\[([^\]\n]+)\]\]"#) {
            let range = NSRange(markdown.startIndex..<markdown.endIndex, in: markdown)
            targets += expression.matches(in: markdown, range: range).compactMap { match in
                guard match.numberOfRanges > 1,
                      let targetRange = Range(match.range(at: 1), in: markdown) else {
                    return nil
                }
                let value = String(markdown[targetRange])
                    .split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                    .first
                    .map(String.init)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return value.isEmpty ? nil : KnowledgeLinkTarget(value: value, isWikiLink: true)
            }
        }
        return targets
    }

    private func suggestedKnowledgeRelations(
        for currentEntry: NoteSearchIndexEntry?,
        body: String,
        among entries: [NoteSearchIndexEntry],
        excluding excludedPaths: Set<String>,
        limit: Int,
        cancellationCheck: @Sendable () -> Bool
    ) -> [KnowledgeRelationItem] {
        guard limit > 0 else { return [] }
        let currentTitle = currentEntry?.title ?? ""
        let currentTags = meaningfulKnowledgeTags(currentEntry?.tags ?? [])
        let currentTokens = knowledgeTokens(in: "\(currentTitle)\n\(body)")
        guard !currentTags.isEmpty || currentTokens.count >= 2 else { return [] }

        var candidates: [KnowledgeRelationItem] = []
        for entry in entries where !excludedPaths.contains(entry.url.standardizedFileURL.path) {
            guard !cancellationCheck() else { return [] }
            let candidateTags = meaningfulKnowledgeTags(entry.tags)
            let sharedTags = currentTags.intersection(candidateTags)
            let candidateTokens = knowledgeTokens(in: "\(entry.title)\n\(entry.body)")
            let sharedTokens = currentTokens.intersection(candidateTokens)
            let tokenContainment: Double
            let smallerTokenCount = min(currentTokens.count, candidateTokens.count)
            if smallerTokenCount == 0 {
                tokenContainment = 0
            } else {
                tokenContainment = Double(sharedTokens.count) / Double(smallerTokenCount)
            }
            let tagScore = min(Double(sharedTags.count) * 0.28, 0.56)
            let score = tagScore + min(tokenContainment * 0.72, 0.72)
            guard score >= 0.22 else { continue }

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

    private func meaningfulKnowledgeTags(_ tags: [String]) -> Set<String> {
        let ignored = Set([
            "notion", "flomo", "apple-notes", "模板",
            "层级/点", "层级/线", "层级/面", "层级/体",
            "layer/point", "layer/line", "layer/plane", "layer/body"
        ])
        return Set(tags.compactMap {
            let normalized = $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.isEmpty || ignored.contains(normalized) ? nil : normalized
        })
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
