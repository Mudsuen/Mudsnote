import Foundation

/// Shared query semantics for the index, provisional results and visible highlights.
/// Every term must match; adjacent Latin/CJK runs also form separate terms.
public struct NoteSearchQuery: Sendable {
    public let terms: [String]

    public init(_ text: String) {
        let normalizedText = Self.normalized(text)
        var terms: [String] = []
        var seen = Set<String>()
        var token = ""
        var previousWasCJK: Bool?
        func appendToken() {
            if !token.isEmpty, seen.insert(token).inserted { terms.append(token) }
            token = ""
        }
        for scalar in normalizedText.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                appendToken()
                previousWasCJK = nil
                continue
            }
            let isCJK = (0x3400...0x9FFF).contains(scalar.value)
                || (0x20000...0x323AF).contains(scalar.value)
                || (0x3040...0x30FF).contains(scalar.value)
                || (0xAC00...0xD7AF).contains(scalar.value)
            if !isCJK,
               (CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar)),
               previousWasCJK == true {
                // Do not split CJK-adjacent punctuation (e.g. "苹果，香蕉", "苹果(测试)") into a mandatory literal token.
                appendToken()
                previousWasCJK = nil
                continue
            }
            if let previousWasCJK, previousWasCJK != isCJK {
                appendToken()
            }
            if !isCJK,
               previousWasCJK == nil,
               (CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar)),
               token.isEmpty {
                // Skip leading punctuation before a CJK/word token; fallback handles punctuation-only queries below.
                continue
            }
            token.unicodeScalars.append(scalar)
            previousWasCJK = isCJK
        }
        appendToken()
        if terms.isEmpty {
            let trimmed = normalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                terms = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            }
        }
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
        var lineEnd = NSMaxRange(line)
        while lineEnd > line.location {
            let unit = body.character(at: lineEnd - 1)
            if unit == 0x000A || unit == 0x000D {
                lineEnd -= 1
            } else {
                break
            }
        }
        let start = max(line.location, match.location - 64)
        let end = min(lineEnd, max(start + 180, NSMaxRange(match)))
        let range = body.rangeOfComposedCharacterSequences(for:
            NSRange(location: start, length: max(0, end - start)))
        let excerpt = body.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = MarkdownEditorDocument.previewText(fromMarkdownLine: excerpt) ?? excerpt
        return (start > line.location ? "…" : "") + preview + (end < lineEnd ? "…" : "")
    }
}
