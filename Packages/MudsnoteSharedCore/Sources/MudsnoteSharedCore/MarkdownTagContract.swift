import Foundation

/// Single cross-platform contract for Markdown tags, YAML frontmatter serialization,
/// and inline tag extraction shared by macOS and iOS.
public enum MarkdownTagContract: Sendable {
    public struct InlineExtraction: Equatable, Sendable {
        public let body: String
        /// Canonical bare tag names (without leading `#`), deduplicated case-insensitively.
        public let bareTags: [String]
        public let occurrenceCount: Int

        public init(body: String, bareTags: [String], occurrenceCount: Int) {
            self.body = body
            self.bareTags = bareTags
            self.occurrenceCount = occurrenceCount
        }
    }

    private static let inlineTagRegex = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}_/#(])#([\p{L}\p{N}_][\p{L}\p{N}_-]*(?:/[\p{L}\p{N}_][\p{L}\p{N}_-]*)*)(?![\p{L}\p{N}_/-])"#
    )
    private static let canonicalNameRegex = try! NSRegularExpression(
        pattern: #"^[\p{L}\p{N}_][\p{L}\p{N}_-]*(?:/[\p{L}\p{N}_][\p{L}\p{N}_-]*)*$"#
    )
    private static let hexColorRegex = try! NSRegularExpression(
        pattern: #"^(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"#
    )
    private static let digitsOnlyRegex = try! NSRegularExpression(
        pattern: #"^[0-9]+$"#
    )

    public static func tagKey(_ tag: String) -> String {
        stripSingleLeadingHash(tag).folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    /// Strips at most one leading `#` after trimming whitespace and optional YAML quotes.
    /// Preserves trailing `#` in tags such as `C#`.
    public static func stripSingleLeadingHash(_ input: String) -> String {
        var trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2,
           (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\""))
            || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            trimmed = String(trimmed.dropFirst().dropLast())
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed.hasPrefix("#") {
            return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    /// Validates a canonical hierarchical tag name (without `#`).
    public static func normalizedBareTag(_ input: String) -> String? {
        let name = stripSingleLeadingHash(input)
        guard !name.isEmpty else { return nil }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        guard canonicalNameRegex.firstMatch(in: name, range: range)?.range == range else {
            return nil
        }
        return name
    }

    /// Validates a canonical hierarchical tag formatted with leading `#`.
    public static func normalizedHashTag(_ input: String) -> String? {
        guard let bare = normalizedBareTag(input) else { return nil }
        return "#\(bare)"
    }

    /// Returns true for `#123`, `#fff`, `#ff00aa`, `#11223344` so inline body
    /// extraction never mistakes numeric references or CSS hex colors for tags.
    public static func isIgnoredInlineHashToken(_ bareName: String) -> Bool {
        let range = NSRange(bareName.startIndex..<bareName.endIndex, in: bareName)
        if digitsOnlyRegex.firstMatch(in: bareName, range: range)?.range == range {
            return true
        }
        if hexColorRegex.firstMatch(in: bareName, range: range)?.range == range {
            // Only ignore hex-like tokens when they contain at least one digit OR
            // are 6/8 hex chars (so short alphabetic words like #ace or #dad stay valid tags).
            let hasDigit = bareName.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
            if hasDigit || bareName.count == 6 || bareName.count == 8 {
                return true
            }
        }
        return false
    }

    public static func deduplicatedBareTags(_ values: [String], strict: Bool = false) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in values {
            let candidate: String? = strict ? normalizedBareTag(raw) : {
                let stripped = stripSingleLeadingHash(raw)
                return stripped.isEmpty ? nil : stripped
            }()
            guard let tag = candidate else { continue }
            if seen.insert(tagKey(tag)).inserted {
                result.append(tag)
            }
        }
        return result
    }

    /// Formats a YAML scalar safely. Never emits a bare `#...` comment.
    public static func yamlSafeTagScalar(_ rawTag: String) -> String {
        let bare = stripSingleLeadingHash(rawTag)
        let needsQuoting = bare.isEmpty
            || bare.hasPrefix("#")
            || bare.hasPrefix("&")
            || bare.hasPrefix("*")
            || bare.hasPrefix("!")
            || bare.hasPrefix("@")
            || bare.hasPrefix("`")
            || bare.hasPrefix("{")
            || bare.hasPrefix("[")
            || bare.hasPrefix("'")
            || bare.hasPrefix("\"")
            || bare.contains(": ")
            || bare.contains(" #")
        guard needsQuoting else { return bare }
        let escaped = bare
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Canonical YAML `tags:` block lines (`tags:` followed by `  - tag`).
    public static func yamlTagLines(for tags: [String], strict: Bool = false) -> [String] {
        let normalized = deduplicatedBareTags(tags, strict: strict)
        guard !normalized.isEmpty else { return [] }
        return ["tags:"] + normalized.map { "  - \(yamlSafeTagScalar($0))" }
    }

    /// Extracts YAML frontmatter closing line index if present.
    public static func frontMatterClosingIndex(in lines: [String]) -> Int? {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        return lines.indices.dropFirst().first { index in
            let marker = lines[index].trimmingCharacters(in: .whitespaces)
            return marker == "---" || marker == "..."
        }
    }

    /// Strips leading YAML frontmatter block cleanly (e.g., for PDF export or preview).
    public static func stripYAMLFrontMatter(from markdown: String) -> String {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard let closing = frontMatterClosingIndex(in: lines) else {
            return normalized
        }
        let remainder = lines.dropFirst(closing + 1)
            .drop(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        return remainder.joined(separator: "\n")
    }

    /// Parses bare tags from YAML frontmatter (supports inline `[a, b]`, single value,
    /// multiline `- a`, legacy `- #a`, and quoted values).
    public static func frontMatterBareTags(in markdown: String, strict: Bool = false) -> [String] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        guard let closing = frontMatterClosingIndex(in: lines) else { return [] }
        let metadata = Array(lines[1..<closing])
        guard let tagLine = metadata.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("tags:")
        }) else { return [] }

        let line = metadata[tagLine]
        let value = line.drop(while: { $0 != ":" }).dropFirst()
            .trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("["), value.hasSuffix("]") {
            let items = value.dropFirst().dropLast().split(separator: ",").map(String.init)
            return deduplicatedBareTags(items, strict: strict)
        }
        if !value.isEmpty {
            return deduplicatedBareTags([value], strict: strict)
        }
        var values: [String] = []
        for candidate in metadata.dropFirst(tagLine + 1) {
            let trimmed = candidate.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") else { break }
            values.append(String(trimmed.dropFirst(2)))
        }
        return deduplicatedBareTags(values, strict: strict)
    }

    /// Replaces or inserts the `tags:` section in YAML frontmatter using standard YAML (`  - tag`).
    public static func replacingFrontMatterTags(
        in markdown: String,
        with tags: [String],
        strict: Bool = false
    ) -> String {
        let normalizedMarkdown = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalizedMarkdown.components(separatedBy: "\n")
        let tagBlock = yamlTagLines(for: tags, strict: strict)

        if let closing = frontMatterClosingIndex(in: lines) {
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
                if !tagBlock.isEmpty {
                    metadata.insert(contentsOf: tagBlock, at: start)
                }
            } else if !tagBlock.isEmpty {
                metadata.append(contentsOf: tagBlock)
            }
            lines.replaceSubrange(1..<closing, with: metadata)
            return lines.joined(separator: "\n")
        }

        guard !tagBlock.isEmpty else { return normalizedMarkdown }
        return "---\n\(tagBlock.joined(separator: "\n"))\n---\n\n\(normalizedMarkdown)"
    }

    /// Extracts inline `#tags` from Markdown body while ignoring fenced code blocks,
    /// inline code spans, URLs, numeric references (`#123`), and CSS hex colors (`#ff00aa`).
    public static func extractingInlineTags(from body: String) -> InlineExtraction {
        var found: [String] = []
        var occurrenceCount = 0
        var activeFence: Character?
        var activeFenceLength = 0

        let lines = body.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        let transformedLines = lines.map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let first = trimmed.first, first == "`" || first == "~" {
                let runLength = trimmed.prefix(while: { $0 == first }).count
                if runLength >= 3 {
                    if let active = activeFence {
                        if active == first, runLength >= activeFenceLength,
                           trimmed.dropFirst(runLength).trimmingCharacters(in: .whitespaces).isEmpty {
                            activeFence = nil
                            activeFenceLength = 0
                        }
                    } else {
                        activeFence = first
                        activeFenceLength = runLength
                    }
                    return line
                }
            }
            guard activeFence == nil else { return line }

            let source = line as NSString
            let fullRange = NSRange(location: 0, length: source.length)
            let codeRanges = inlineCodeRanges(in: source)
            let matches = inlineTagRegex.matches(in: line, range: fullRange).filter { match in
                guard codeRanges.allSatisfy({ NSIntersectionRange($0, match.range).length == 0 }) else {
                    return false
                }
                guard match.numberOfRanges > 1 else { return false }
                let bareName = source.substring(with: match.range(at: 1))
                return !isIgnoredInlineHashToken(bareName)
            }
            guard !matches.isEmpty else { return line }

            let mutable = NSMutableString(string: line)
            for match in matches.reversed() {
                let bareName = source.substring(with: match.range(at: 1))
                if let valid = normalizedBareTag(bareName) {
                    found.append(valid)
                    occurrenceCount += 1
                    mutable.replaceCharacters(in: match.range, with: "")
                }
            }
            return cleanedLineAfterInlineTagRemoval(mutable as String)
        }

        return InlineExtraction(
            body: transformedLines.joined(separator: "\n"),
            bareTags: deduplicatedBareTags(found.reversed(), strict: true),
            occurrenceCount: occurrenceCount
        )
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
            if closing.location == NSNotFound {
                break
            }
            let spanEnd = NSMaxRange(closing)
            ranges.append(NSRange(location: opening.location, length: spanEnd - opening.location))
            cursor = spanEnd
        }
        return ranges
    }

    private static func cleanedLineAfterInlineTagRemoval(_ line: String) -> String {
        let trimmedTrailing = line.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression)
        if trimmedTrailing.trimmingCharacters(in: .whitespaces).isEmpty {
            return ""
        }
        let collapsed = trimmedTrailing.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
        return collapsed.replacingOccurrences(of: #" +([,.;:!?，。；：！？])"#, with: "$1", options: .regularExpression)
    }
}
