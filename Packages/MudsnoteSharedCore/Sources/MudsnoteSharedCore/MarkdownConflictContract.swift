import Foundation

/// Shared filename, conflict-copy detection, and title-derivation rules across macOS and iOS.
public enum MarkdownConflictContract: Sendable {
    public static let markdownExtensions: Set<String> = ["md", "markdown"]

    public static func isMarkdownFilename(_ filename: String) -> Bool {
        let ext = (filename as NSString).pathExtension.lowercased()
        return markdownExtensions.contains(ext)
    }

    /// Recognizes conflict copies created by both macOS (`(Mudsnote Conflict ...)`)
    /// and iOS (`(Conflict ...)`).
    public static func isConflictFilename(_ filename: String) -> Bool {
        let lower = filename.lowercased()
        return lower.contains("(mudsnote conflict") || lower.contains("(conflict ")
    }

    /// Produces a safe filesystem filename stem bounded by UTF-8 byte count (default 180 bytes)
    /// without ever mutating or truncating the note's body text.
    public static func sanitizedFilenameStem(
        _ raw: String,
        maxUTF8Bytes: Int = 180,
        fallback: String = "Untitled"
    ) -> String {
        var cleaned = raw
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip leading markdown heading markers for filename stem only.
        while cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Replace filesystem-disallowed characters.
        let forbidden = CharacterSet(charactersIn: "/:\\*?\"<>|\u{0000}")
        cleaned = cleaned.unicodeScalars.map { scalar in
            forbidden.contains(scalar) ? "-" : String(scalar)
        }.joined()
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))

        guard !cleaned.isEmpty else { return fallback }

        if cleaned.utf8.count <= maxUTF8Bytes {
            return cleaned
        }

        // Truncate safely on extended grapheme cluster boundaries.
        var result = ""
        var bytes = 0
        for character in cleaned {
            let charBytes = String(character).utf8.count
            if bytes + charBytes > maxUTF8Bytes {
                break
            }
            result.append(character)
            bytes += charBytes
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: ". -"))
        return trimmed.isEmpty ? fallback : trimmed
    }

    /// Derives a concise note title from a first line without splitting version numbers
    /// (`v1.2.3`), identifiers (`Node.js`), or URLs (`https://example.com/a.html`).
    public static func derivedTitle(fromFirstLine line: String, maxCharacters: Int = 60) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Strip leading markdown heading prefix if present.
        let strippedHeading: String
        if let range = trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
            strippedHeading = String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else {
            strippedHeading = trimmed
        }
        guard !strippedHeading.isEmpty else { return "" }

        // If the entire line is a URL, keep its host + concise path rather than chopping at the first dot.
        if let url = URL(string: strippedHeading),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           let host = url.host, !host.isEmpty {
            let path = url.path == "/" ? "" : url.path
            let concise = (host + path).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return String(concise.prefix(maxCharacters))
        }

        // Split only on real sentence-ending punctuation: CJK sentence marks (`。！？`)
        // or ASCII `.` / `!` / `?` followed by whitespace (never mid-token like `v1.2.3` or `Node.js`).
        var sentenceEnd: String.Index?
        var idx = strippedHeading.startIndex
        while idx < strippedHeading.endIndex {
            let ch = strippedHeading[idx]
            if ch == "。" || ch == "！" || ch == "？" {
                sentenceEnd = idx
                break
            }
            if ch == "." || ch == "!" || ch == "?" {
                let next = strippedHeading.index(after: idx)
                if next == strippedHeading.endIndex || strippedHeading[next].isWhitespace {
                    sentenceEnd = idx
                    break
                }
            }
            idx = strippedHeading.index(after: idx)
        }

        let candidate = sentenceEnd.map { String(strippedHeading[..<$0]) } ?? strippedHeading
        let cleaned = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > maxCharacters else { return cleaned }
        return String(cleaned.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
