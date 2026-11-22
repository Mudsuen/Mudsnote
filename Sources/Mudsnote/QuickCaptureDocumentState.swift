import Foundation
import MudsnoteCore

struct QuickCaptureDocumentState {
    static let maximumDerivedTitleLength = 80

    let title: String
    let bodyMarkdown: String

    var normalizedTitle: String {
        Self.derivedTitle(from: normalizedBody)
    }

    var normalizedBody: String {
        Self.unifiedMarkdown(legacyTitle: title, bodyMarkdown: bodyMarkdown)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var tags: [String] {
        []
    }

    var document: MarkdownEditorDocument {
        MarkdownEditorDocument(title: normalizedTitle, body: normalizedBody, tags: tags)
    }

    var hasMeaningfulContent: Bool {
        !normalizedTitle.isEmpty || !normalizedBody.isEmpty || !tags.isEmpty
    }

    static func derivedTitle(from markdown: String) -> String {
        let firstContentLine = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let firstContentLine,
              let preview = MarkdownEditorDocument.previewText(fromMarkdownLine: firstContentLine) else {
            return ""
        }

        let normalized = preview
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !normalized.isEmpty else { return "" }

        // Keep URL titles intact (host + concise path) rather than truncating at the first dot.
        if let url = URL(string: normalized),
           let scheme = url.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"),
           let host = url.host, !host.isEmpty {
            let path = url.path == "/" ? "" : url.path
            let concise = (host + path).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return String(concise.prefix(maximumDerivedTitleLength))
        }

        let terminators = Set<Character>([".", "?", "!", "。", "？", "！"])
        let closingPunctuation = Set<Character>(["\"", "'", "”", "’", "」", "』", "》", "】", ")", "）"])
        let characters = Array(normalized)
        var sentenceEnd = characters.endIndex
        for idx in characters.indices {
            let ch = characters[idx]
            guard terminators.contains(ch) else { continue }
            // Do not treat mid-token ASCII dots (e.g., v1.2.3, Node.js, 3.14) as sentence boundaries.
            if ch == "." {
                let nextIndex = characters.index(after: idx)
                if nextIndex < characters.endIndex {
                    let next = characters[nextIndex]
                    if !next.isWhitespace && !terminators.contains(next) && !closingPunctuation.contains(next) {
                        continue
                    }
                }
            }
            var end = characters.index(after: idx)
            while end < characters.endIndex,
                  terminators.contains(characters[end]) || closingPunctuation.contains(characters[end]) {
                end = characters.index(after: end)
            }
            sentenceEnd = end
            break
        }

        return String(characters[..<sentenceEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(maximumDerivedTitleLength)
            .description
    }

    static func unifiedMarkdown(legacyTitle: String, bodyMarkdown: String) -> String {
        let normalizedLegacyTitle = legacyTitle
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !normalizedLegacyTitle.isEmpty else { return bodyMarkdown }

        let normalizedBody = bodyMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBody.isEmpty else { return normalizedLegacyTitle }

        let derivedBodyTitle = derivedTitle(from: normalizedBody)
        if titlesMatch(normalizedLegacyTitle, derivedBodyTitle) {
            return bodyMarkdown
        }
        return normalizedLegacyTitle + "\n\n" + bodyMarkdown
    }

    private static func titlesMatch(_ lhs: String, _ rhs: String) -> Bool {
        func comparable(_ value: String) -> String {
            value
                .trimmingCharacters(in: CharacterSet(
                    charactersIn: " \t\r\n.?!。？！\"'”’」』》】)）"
                ))
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        }
        return !lhs.isEmpty && comparable(lhs) == comparable(rhs)
    }

    static func extractedInlineTags(from text: String) -> [String] {
        []
    }

}
