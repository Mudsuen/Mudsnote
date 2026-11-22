import Foundation
import MudsnoteSharedCore

/// Shared query semantics for the index, provisional results and visible highlights.
/// Every term must match; adjacent Latin/CJK runs also form separate terms.
public struct NoteSearchQuery: Sendable {
    public let terms: [String]

    public init(_ text: String) {
        self.terms = NoteSearchTokenizer.terms(from: text)
    }

    static func normalized(_ text: String) -> String {
        NoteSearchTokenizer.normalized(text)
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
        NoteSearchTokenizer.matchRanges(in: text, terms: terms)
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
