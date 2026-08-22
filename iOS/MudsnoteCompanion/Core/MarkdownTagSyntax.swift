import Foundation

enum MarkdownTagMutation: Equatable {
    case rename(to: String)
    case delete
}

struct MarkdownTagRewrite: Equatable {
    var markdown: String
    var occurrenceCount: Int
}

enum MarkdownTagSyntax {
    private static let tagExpression = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}_/#(])#([\p{L}\p{N}_][\p{L}\p{N}_-]*)"#
    )
    private static let tagNameExpression = try! NSRegularExpression(
        pattern: #"^[\p{L}\p{N}_][\p{L}\p{N}_-]*$"#
    )

    static func normalizedTag(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard !name.isEmpty else { return nil }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        guard tagNameExpression.firstMatch(in: name, range: range)?.range == range else {
            return nil
        }
        return "#\(name)"
    }

    static func tags(in markdown: String) -> [String] {
        normalizedTags(frontMatterTags(in: markdown)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    static func adding(_ input: String, to markdown: String) -> String? {
        guard let tag = normalizedTag(input) else { return nil }
        var updatedTags = tags(in: markdown)
        if updatedTags.contains(where: { key($0) == key(tag) }) {
            return markdown
        }
        updatedTags.append(tag)
        return replacingFrontMatterTags(in: markdown, with: updatedTags)
    }

    static func rewriting(
        _ markdown: String,
        tag sourceTag: String,
        mutation: MarkdownTagMutation
    ) -> MarkdownTagRewrite? {
        guard let sourceTag = normalizedTag(sourceTag) else { return nil }
        let replacement: String?
        switch mutation {
        case .rename(let input):
            guard let normalized = normalizedTag(input) else { return nil }
            replacement = normalized
        case .delete:
            replacement = nil
        }

        let existing = tags(in: markdown)
        let matching = existing.filter { key($0) == key(sourceTag) }
        let updated = existing.compactMap { tag -> String? in
            guard key(tag) == key(sourceTag) else { return tag }
            return replacement
        }
        let frontMatterRewritten = matching.isEmpty
            ? markdown
            : replacingFrontMatterTags(in: markdown, with: updated)
        let markerRewrite = rewritingMemoTagMarkers(
            in: frontMatterRewritten,
            sourceTag: sourceTag,
            replacement: replacement
        )
        return MarkdownTagRewrite(
            markdown: markerRewrite.markdown,
            occurrenceCount: matching.count + markerRewrite.count
        )
    }

    static func key(_ tag: String) -> String {
        tag.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }

    private static func normalizedTags(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap(normalizedTag).filter {
            seen.insert(key($0)).inserted
        }
    }

    private static func frontMatterTags(in markdown: String) -> [String] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let closing = lines.indices.dropFirst().first(where: {
                  let marker = lines[$0].trimmingCharacters(in: .whitespaces)
                  return marker == "---" || marker == "..."
              })
        else { return [] }
        let metadata = Array(lines[1..<closing])
        guard let tagLine = metadata.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("tags:")
        }) else { return [] }
        let line = metadata[tagLine]
        let value = line.drop(while: { $0 != ":" }).dropFirst()
            .trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("["), value.hasSuffix("]") {
            return value.dropFirst().dropLast().split(separator: ",").map {
                String($0).trimmingCharacters(in: CharacterSet.whitespaces.union(
                    CharacterSet(charactersIn: "\"'")
                ))
            }
        }
        var values: [String] = []
        for candidate in metadata.dropFirst(tagLine + 1) {
            let trimmed = candidate.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") else { break }
            values.append(String(trimmed.dropFirst(2)))
        }
        return values
    }

    private static func replacingFrontMatterTags(
        in markdown: String,
        with tags: [String]
    ) -> String {
        let normalizedMarkdown = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalizedMarkdown.components(separatedBy: "\n")
        let normalized = normalizedTags(tags)
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let closing = lines.indices.dropFirst().first(where: {
               let marker = lines[$0].trimmingCharacters(in: .whitespaces)
               return marker == "---" || marker == "..."
           }) {
            var metadata = Array(lines[1..<closing])
            if let start = metadata.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("tags:")
            }) {
                var end = start + 1
                while end < metadata.count,
                      metadata[end].trimmingCharacters(in: .whitespaces).hasPrefix("- ") {
                    end += 1
                }
                metadata.removeSubrange(start..<end)
                if !normalized.isEmpty {
                    metadata.insert(contentsOf: tagLines(normalized), at: start)
                }
            } else if !normalized.isEmpty {
                metadata.append(contentsOf: tagLines(normalized))
            }
            lines.replaceSubrange(1..<closing, with: metadata)
            return lines.joined(separator: "\n")
        }
        guard !normalized.isEmpty else { return normalizedMarkdown }
        return "---\n\(tagLines(normalized).joined(separator: "\n"))\n---\n\n\(normalizedMarkdown)"
    }

    private static func tagLines(_ tags: [String]) -> [String] {
        ["tags:"] + tags.map { "  - \($0)" }
    }

    private static func rewritingMemoTagMarkers(
        in markdown: String,
        sourceTag: String,
        replacement: String?
    ) -> (markdown: String, count: Int) {
        let prefix = "<!-- mudsnote-tags:"
        var count = 0
        let lines = markdown.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(prefix), trimmed.hasSuffix("-->") else {
                return line
            }
            let values = trimmed.dropFirst(prefix.count).dropLast(3)
                .split(separator: ",")
                .compactMap { normalizedTag(String($0)) }
            var lineCount = 0
            let updated = values.compactMap { tag -> String? in
                guard key(tag) == key(sourceTag) else { return tag }
                count += 1
                lineCount += 1
                return replacement
            }
            guard lineCount > 0 else { return line }
            let indentation = line.prefix { $0 == " " || $0 == "\t" }
            guard !updated.isEmpty else { return "" }
            return "\(indentation)\(prefix) \(updated.joined(separator: ", ")) -->"
        }
        return (lines.joined(separator: "\n"), count)
    }

    private static func mapVisibleLines(
        in markdown: String,
        transform: (String) -> String
    ) -> String {
        var activeFence: Character?
        return markdown.components(separatedBy: "\n").map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = fenceMarker(in: trimmed) {
                if activeFence == nil {
                    activeFence = marker
                } else if activeFence == marker {
                    activeFence = nil
                }
                return line
            }
            return activeFence == nil ? transform(line) : line
        }.joined(separator: "\n")
    }

    private static func forVisibleLine(
        in markdown: String,
        body: (String) -> Void
    ) {
        _ = mapVisibleLines(in: markdown) { line in
            body(line)
            return line
        }
    }

    private static func fenceMarker(in trimmedLine: String) -> Character? {
        guard let marker = trimmedLine.first,
              marker == "`" || marker == "~",
              trimmedLine.prefix(3).allSatisfy({ $0 == marker }) else { return nil }
        return marker
    }

    private static func visibleTagMatches(in line: String) -> [NSTextCheckingResult] {
        let source = line as NSString
        let range = NSRange(location: 0, length: source.length)
        let codeRanges = inlineCodeRanges(in: source)
        return tagExpression.matches(in: line, range: range).filter { match in
            codeRanges.allSatisfy { NSIntersectionRange($0, match.range).length == 0 }
        }
    }

    private static func inlineCodeRanges(in source: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var cursor = 0
        while cursor < source.length {
            let opening = source.range(
                of: "`",
                options: [],
                range: NSRange(location: cursor, length: source.length - cursor)
            )
            guard opening.location != NSNotFound else { break }
            var runLength = 1
            while opening.location + runLength < source.length,
                  source.character(at: opening.location + runLength) == 96 {
                runLength += 1
            }
            let marker = String(repeating: "`", count: runLength)
            let contentStart = opening.location + runLength
            let closing = source.range(
                of: marker,
                options: [],
                range: NSRange(location: contentStart, length: source.length - contentStart)
            )
            guard closing.location != NSNotFound else { break }
            let codeRange = NSRange(
                location: opening.location,
                length: NSMaxRange(closing) - opening.location
            )
            ranges.append(codeRange)
            cursor = NSMaxRange(codeRange)
        }
        return ranges
    }

    private static func isHorizontalWhitespace(_ character: unichar) -> Bool {
        character == 32 || character == 9
    }
}
