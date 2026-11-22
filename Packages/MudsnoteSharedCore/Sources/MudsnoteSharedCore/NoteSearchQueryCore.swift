import Foundation

/// Shared CJK/Latin search tokenizer and highlight range helper across macOS and iOS.
public enum NoteSearchTokenizer: Sendable {
    public static func normalized(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    public static func terms(from text: String) -> [String] {
        let normalizedText = normalized(text)
        var terms: [String] = []
        var seen = Set<String>()
        var token = ""
        var previousWasCJK: Bool?

        func appendToken() {
            if !token.isEmpty, seen.insert(token).inserted {
                terms.append(token)
            }
            token = ""
        }

        for scalar in normalizedText.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                appendToken()
                previousWasCJK = nil
                continue
            }
            let isCJK = (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
                || (0x20000...0x323AF).contains(scalar.value)
                || (0x3040...0x30FF).contains(scalar.value)
                || (0xAC00...0xD7AF).contains(scalar.value)

            if !isCJK,
               (CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar)),
               previousWasCJK == true {
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
        return terms
    }

    public static func matchRanges(in text: String, terms: [String]) -> [NSRange] {
        let nsText = text as NSString
        var ranges: [NSRange] = []
        for term in terms where !term.isEmpty {
            var start = 0
            while start < nsText.length {
                let match = nsText.range(
                    of: term,
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    range: NSRange(location: start, length: nsText.length - start)
                )
                guard match.location != NSNotFound, match.length > 0 else { break }
                ranges.append(match)
                start = NSMaxRange(match)
            }
        }
        return ranges
    }
}
