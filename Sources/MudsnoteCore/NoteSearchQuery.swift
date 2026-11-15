import Foundation

/// Shared query semantics for the index, provisional results and visible highlights.
/// Every term must match; adjacent Latin/CJK runs also form separate terms.
public struct NoteSearchQuery: Sendable {
    public let terms: [String]

    public init(_ text: String) {
        var terms: [String] = []
        var seen = Set<String>()
        var token = ""
        var previousWasCJK: Bool?
        func appendToken() {
            if !token.isEmpty, seen.insert(token).inserted { terms.append(token) }
            token = ""
        }
        for scalar in Self.normalized(text).unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                appendToken()
                previousWasCJK = nil
                continue
            }
            let isCJK = (0x3400...0x9FFF).contains(scalar.value)
                || (0x20000...0x323AF).contains(scalar.value)
                || (0x3040...0x30FF).contains(scalar.value)
                || (0xAC00...0xD7AF).contains(scalar.value)
            if let previousWasCJK, previousWasCJK != isCJK { appendToken() }
            token.unicodeScalars.append(scalar)
            previousWasCJK = isCJK
        }
        appendToken()
        self.terms = terms
    }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
    }

    public func matches(title: String, body: String, tags: [String]) -> Bool {
        guard !terms.isEmpty else { return true }
        let title = Self.normalized(title)
        let body = Self.normalized(body)
        let tags = tags.map(Self.normalized)
        return terms.allSatisfy { term in
            title.contains(term) || body.contains(term) || tags.contains { $0.contains(term) }
        }
    }

    public func matchRanges(in text: String) -> [NSRange] {
        let text = text as NSString
        var ranges: [NSRange] = []
        for term in terms {
            var start = 0
            while start < text.length {
                let match = text.range(of: term,
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    range: NSRange(location: start, length: text.length - start))
                guard match.location != NSNotFound, match.length > 0 else { break }
                ranges.append(match)
                start = NSMaxRange(match)
            }
        }
        return ranges
    }

    func snippet(in body: String, fallback: @autoclosure () -> String) -> String {
        let body = body as NSString
        // Read only the first matching line; do not split and normalize every
        // line of every result, especially for long imported notes.
        var firstMatch: NSRange?
        for term in terms {
            let match = body.range(of: term,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive])
            if match.location != NSNotFound, match.location < (firstMatch?.location ?? Int.max) {
                firstMatch = match
            }
        }
        guard let match = firstMatch else { return fallback() }
        let line = body.lineRange(for: match)
        let start = max(line.location, match.location - 64)
        let end = min(NSMaxRange(line), max(start + 180, NSMaxRange(match)))
        let range = body.rangeOfComposedCharacterSequences(for:
            NSRange(location: start, length: end - start))
        let excerpt = body.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = MarkdownEditorDocument.previewText(fromMarkdownLine: excerpt) ?? excerpt
        return (start > line.location ? "…" : "") + preview + (end < NSMaxRange(line) ? "…" : "")
    }
}
