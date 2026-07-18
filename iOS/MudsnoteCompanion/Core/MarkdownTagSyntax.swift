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
        var seen = Set<String>()
        var tags: [String] = []
        forVisibleLine(in: markdown) { line in
            for match in visibleTagMatches(in: line) {
                let tag = (line as NSString).substring(with: match.range)
                if seen.insert(key(tag)).inserted {
                    tags.append(tag)
                }
            }
        }
        return tags.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
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

        var occurrenceCount = 0
        let rewritten = mapVisibleLines(in: markdown) { line in
            let source = line as NSString
            let matches = visibleTagMatches(in: line).filter {
                key(source.substring(with: $0.range)) == key(sourceTag)
            }
            guard !matches.isEmpty else { return line }
            occurrenceCount += matches.count

            var output = ""
            var cursor = 0
            for match in matches {
                if match.range.location > cursor {
                    output += source.substring(
                        with: NSRange(location: cursor, length: match.range.location - cursor)
                    )
                }
                cursor = NSMaxRange(match.range)
                if let replacement {
                    output += replacement
                } else if cursor < source.length,
                          isHorizontalWhitespace(source.character(at: cursor)) {
                    cursor += 1
                } else if output.last == " " || output.last == "\t" {
                    output.removeLast()
                }
            }
            if cursor < source.length {
                output += source.substring(
                    with: NSRange(location: cursor, length: source.length - cursor)
                )
            }
            return output
        }
        return MarkdownTagRewrite(markdown: rewritten, occurrenceCount: occurrenceCount)
    }

    static func key(_ tag: String) -> String {
        tag.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
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
