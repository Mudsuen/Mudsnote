import Foundation

/// Single cross-platform contract for Markdown attachment destination formatting and lookup.
/// Computes relative paths from a note's parent folder (matching macOS `NoteStore` and standard Markdown)
/// while gracefully resolving legacy iOS vault-root-relative links.
public enum MarkdownAttachmentContract: Sendable {
    private static let allowedPathCharacters: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "()[]#?%")
        return set
    }()

    /// Computes a percent-encoded Markdown destination from a note's vault-relative path
    /// (e.g. `"Work/Sub/plan.md"`) to an attachment's vault-relative path
    /// (e.g. `"Attachments/2026/06/hero photo.png"` -> `"../../Attachments/2026/06/hero%20photo.png"`).
    public static func relativeMarkdownDestination(
        attachmentRelativeToRoot: String,
        noteRelativeToRoot: String,
        percentEncode: Bool = true
    ) -> String {
        let attachmentComponents = splitCleanPath(attachmentRelativeToRoot)
        let noteComponents = splitCleanPath(noteRelativeToRoot)
        let noteDirectoryComponents = Array(noteComponents.dropLast())

        var commonPrefixCount = 0
        while commonPrefixCount < noteDirectoryComponents.count,
              commonPrefixCount < attachmentComponents.count,
              noteDirectoryComponents[commonPrefixCount] == attachmentComponents[commonPrefixCount] {
            commonPrefixCount += 1
        }

        let upwardCount = noteDirectoryComponents.count - commonPrefixCount
        let relativeComponents = Array(repeating: "..", count: upwardCount)
            + attachmentComponents.dropFirst(commonPrefixCount)
        let raw = relativeComponents.joined(separator: "/")
        guard percentEncode else { return raw }
        return encodePathForMarkdown(raw)
    }

    /// Percent-encodes each path component safely without double-encoding `/`.
    public static func encodePathForMarkdown(_ rawPath: String) -> String {
        rawPath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { component -> String in
                let segment = String(component)
                if segment.isEmpty || segment == "." || segment == ".." {
                    return segment
                }
                let decoded = segment.removingPercentEncoding ?? segment
                return decoded.addingPercentEncoding(withAllowedCharacters: allowedPathCharacters) ?? decoded
            }
            .joined(separator: "/")
    }

    /// Converts a raw Markdown attachment destination (which may be note-relative `../Attachments/a.png`,
    /// percent-encoded, or legacy vault-root-relative `Attachments/a.png`) into a normalized
    /// vault-root-relative path (`Attachments/a.png`). Returns nil if it escapes the vault root.
    public static func normalizeVaultRelativePath(
        from rawDestination: String,
        noteRelativeToRoot: String
    ) -> String? {
        let trimmed = rawDestination
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("data:") || lower.hasPrefix("mailto:") {
            return nil
        }

        let decoded = (trimmed.removingPercentEncoding ?? trimmed)
            .replacingOccurrences(of: "\\", with: "/")
        let noteDirComponents = Array(splitCleanPath(noteRelativeToRoot).dropLast())

        if decoded.hasPrefix("/") {
            return nil
        }

        // Legacy iOS notes (and canonical vault-relative inputs) reference `Attachments/...`
        // directly from the vault root even when the note lives inside a subfolder.
        if decoded.hasPrefix("Attachments/") {
            return resolving(components: decoded.split(separator: "/").map(String.init))
        }

        // Resolve relative to the note's directory.
        if let resolved = resolving(components: noteDirComponents + decoded.split(separator: "/").map(String.init)) {
            return resolved
        }
        return nil
    }

    /// Resolves a Markdown attachment target on disk: tries note-relative path first,
    /// then falls back to vault-root-relative path (for legacy iOS notes), enforcing vault containment.
    public static func resolveAttachmentURL(
        rawDestination: String,
        noteURL: URL,
        libraryRoot: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let trimmed = rawDestination
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("data:") || lower.hasPrefix("mailto:") {
            return nil
        }

        let decoded = trimmed.removingPercentEncoding ?? trimmed
        let rootResolved = libraryRoot.resolvingSymlinksInPath().standardizedFileURL
        let rootPrefix = rootResolved.path.hasSuffix("/") ? rootResolved.path : rootResolved.path + "/"

        func contained(_ candidate: URL) -> URL? {
            let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path.hasPrefix(rootPrefix) else { return nil }
            return resolved
        }

        let noteDir = noteURL.deletingLastPathComponent()
        let noteRelative = noteDir.appendingPathComponent(decoded)
        if let safe = contained(noteRelative), fileManager.fileExists(atPath: safe.path) {
            return safe
        }

        let rootRelative = libraryRoot.appendingPathComponent(decoded)
        if let safe = contained(rootRelative), fileManager.fileExists(atPath: safe.path) {
            return safe
        }

        // If neither exists yet on disk, return the note-relative target if safely contained.
        return contained(noteRelative) ?? contained(rootRelative)
    }

    private static func splitCleanPath(_ path: String) -> [String] {
        path.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "." }
    }

    private static func resolving(components: [String]) -> String? {
        var stack: [String] = []
        for component in components {
            if component.isEmpty || component == "." { continue }
            if component == ".." {
                guard !stack.isEmpty else { return nil }
                stack.removeLast()
            } else {
                stack.append(component)
            }
        }
        guard !stack.isEmpty else { return nil }
        return stack.joined(separator: "/")
    }
}
