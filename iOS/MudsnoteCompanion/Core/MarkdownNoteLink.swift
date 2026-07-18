import Foundation

enum MarkdownNoteLink {
    private static let linkExpression = try! NSRegularExpression(
        pattern: #"(?<!!)\[[^\]\n]+\]\(([^)\n]+)\)"#
    )

    static func relativeDestination(
        from sourceRelativePath: String,
        to targetRelativePath: String
    ) -> String? {
        guard let source = validatedLibraryPath(sourceRelativePath),
              let target = validatedLibraryPath(targetRelativePath),
              source != target else { return nil }
        let sourceFolder = Array(source.dropLast())
        var commonCount = 0
        while commonCount < sourceFolder.count,
              commonCount < target.count,
              sourceFolder[commonCount] == target[commonCount] {
            commonCount += 1
        }
        let parents = Array(repeating: "..", count: sourceFolder.count - commonCount)
        let remainder = Array(target.dropFirst(commonCount))
        let destination = (parents + remainder)
            .map(encodePathSegment)
            .joined(separator: "/")
        return destination.hasPrefix("../") ? destination : "./\(destination)"
    }

    static func resolvedRelativePath(
        for destination: String,
        from sourceRelativePath: String
    ) -> String? {
        guard let source = validatedLibraryPath(sourceRelativePath) else { return nil }
        var rawDestination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawDestination.isEmpty,
              rawDestination.range(
                of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#,
                options: .regularExpression
              ) == nil,
              !rawDestination.hasPrefix("/") else { return nil }
        if let suffixStart = rawDestination.firstIndex(where: { $0 == "#" || $0 == "?" }) {
            rawDestination = String(rawDestination[..<suffixStart])
        }
        guard let decoded = rawDestination.removingPercentEncoding,
              !decoded.isEmpty else { return nil }

        var components = Array(source.dropLast())
        for component in decoded.split(separator: "/", omittingEmptySubsequences: false) {
            switch component {
            case "", ".":
                continue
            case "..":
                guard !components.isEmpty else { return nil }
                components.removeLast()
            default:
                guard component != "~" else { return nil }
                components.append(String(component))
            }
        }
        guard components.last?.lowercased().hasSuffix(".md") == true else { return nil }
        return components.joined(separator: "/")
    }

    static func rewritingLinks(
        in markdown: String,
        sourceBefore: String,
        sourceAfter: String,
        movedTargetBefore: String,
        movedTargetAfter: String
    ) -> String {
        rewritingLinks(
            in: markdown,
            sourceBefore: sourceBefore,
            sourceAfter: sourceAfter,
            movedPaths: [movedTargetBefore: movedTargetAfter]
        )
    }

    static func rewritingLinks(
        in markdown: String,
        sourceBefore: String,
        sourceAfter: String,
        movedPaths: [String: String]
    ) -> String {
        let source = markdown as NSString
        let matches = linkExpression.matches(
            in: markdown,
            range: NSRange(location: 0, length: source.length)
        )
        var rewritten = markdown as NSString
        for match in matches.reversed() {
            let destinationRange = match.range(at: 1)
            let destination = source.substring(with: destinationRange)
            guard let resolved = resolvedRelativePath(
                for: destination,
                from: sourceBefore
            ) else { continue }
            let targetAfter: String
            if let movedTarget = movedPaths[resolved] {
                targetAfter = movedTarget
            } else if sourceBefore != sourceAfter {
                targetAfter = resolved
            } else {
                continue
            }
            guard let replacement = relativeDestination(
                from: sourceAfter,
                to: targetAfter
            ) else { continue }
            let suffix = destination.firstIndex(where: { $0 == "#" || $0 == "?" })
                .map { String(destination[$0...]) } ?? ""
            rewritten = rewritten.replacingCharacters(
                in: destinationRange,
                with: replacement + suffix
            ) as NSString
        }
        return rewritten as String
    }

    private static func validatedLibraryPath(_ value: String) -> [String]? {
        guard !value.hasPrefix("/") else { return nil }
        let components = value.split(separator: "/").map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              components.last?.lowercased().hasSuffix(".md") == true else { return nil }
        return components
    }

    private static func encodePathSegment(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
