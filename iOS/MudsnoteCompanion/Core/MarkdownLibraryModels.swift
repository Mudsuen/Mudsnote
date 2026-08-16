import Foundation

struct RecentMarkdownFile: Identifiable, Equatable {
    var id: String
    var relativePath: String
    var title: String
    var modifiedAt: Date
    var createdAt: Date = .distantPast
    var preview = ""
    var galleryImagePath: String?
    var galleryChecklistItems: [MarkdownGalleryChecklistItem] = []
    var hasAttachments = false
    var hasChecklist = false
    var hasUncheckedChecklist = false
    var isPinned = false
    var tags: [String] = []
    var isContentLoaded = true
}

struct MarkdownGalleryChecklistItem: Equatable {
    var text: String
    var isChecked: Bool
}

struct MarkdownListMetadata: Equatable {
    var title: String
    var preview: String
    var galleryImagePath: String?
    var galleryChecklistItems: [MarkdownGalleryChecklistItem]
    var hasAttachments: Bool
    var hasChecklist: Bool
    var hasUncheckedChecklist: Bool
    var tags: [String] = []
    var attachmentPaths: [String] = []

    static func extract(from markdown: String, fallbackTitle: String) -> MarkdownListMetadata {
        let lines = visibleMarkdownLines(from: markdown)
        let headingTitle = lines.enumerated().lazy.compactMap { index, line -> (Int, String)? in
            let value = line.trimmingCharacters(in: .whitespaces)
            guard value.hasPrefix("# ") else { return nil }
            let heading = String(value.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return heading.isEmpty ? nil : (index, heading)
        }.first
        let plainTitle = lines.enumerated().lazy.compactMap { index, line -> (Int, String)? in
            var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty,
                  !value.hasPrefix("#"),
                  !value.hasPrefix("<!--"),
                  !value.hasPrefix("!["),
                  !(value.hasPrefix("[") && value.contains("](Attachments/")),
                  !value.hasPrefix("---") else { return nil }
            value = value.replacingOccurrences(
                of: #"^(?:[-*+]\s+\[[ xX]\]\s*|[-*+]\s+|>\s*|\d+[.)]\s+)"#,
                with: "",
                options: .regularExpression
            )
            value = value.replacingOccurrences(
                of: #"</?(?:u|mark)>"#,
                with: "",
                options: .regularExpression
            )
            value = value.replacingOccurrences(
                of: #"[*_`~]"#,
                with: "",
                options: .regularExpression
            )
            return value.isEmpty ? nil : (index, String(value.prefix(120)))
        }.first
        let titleMatch = headingTitle ?? plainTitle
        let title = titleMatch?.1 ?? fallbackTitle

        var previewParts: [String] = []
        for (index, line) in lines.enumerated() {
            if index == titleMatch?.0 { continue }
            var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty,
                  !value.hasPrefix("#"),
                  !value.hasPrefix("<!--"),
                  !value.hasPrefix("!["),
                  !(value.hasPrefix("[") && value.contains("](Attachments/")),
                  !value.hasPrefix("---") else { continue }
            value = value.replacingOccurrences(
                of: #"^(?:[-*+]\s+\[[ xX]\]\s*|[-*+]\s+|>\s*|\d+[.)]\s+)"#,
                with: "",
                options: .regularExpression
            )
            value = value.replacingOccurrences(
                of: #"</?(?:u|mark)>"#,
                with: "",
                options: .regularExpression
            )
            value = value.replacingOccurrences(
                of: #"[*_`~]"#,
                with: "",
                options: .regularExpression
            )
            guard !value.isEmpty, !value.hasPrefix("#") else { continue }
            previewParts.append(value)
            if previewParts.joined(separator: "\n").count >= 180 { break }
        }
        let joinedPreview = previewParts.joined(separator: "\n")
        let preview = String(joinedPreview.prefix(180))
        let galleryImagePath = MarkdownAttachmentSearch.relativePaths(in: markdown).first {
            LibraryAttachment.Kind(fileExtension: ($0 as NSString).pathExtension) == .image
        }
        let galleryChecklistItems = lines.compactMap(Self.galleryChecklistItem(from:)).prefix(4)
        return MarkdownListMetadata(
            title: title,
            preview: preview,
            galleryImagePath: galleryImagePath,
            galleryChecklistItems: Array(galleryChecklistItems),
            hasAttachments: markdown.contains("![") || markdown.contains("](Attachments/"),
            hasChecklist: lines.contains { line in
                line.range(
                    of: #"^\s*[-*+]\s+\[[ xX]\]\s+"#,
                    options: .regularExpression
                ) != nil
            },
            hasUncheckedChecklist: lines.contains { line in
                line.range(
                    of: #"^\s*[-*+]\s+\[ \]\s+"#,
                    options: .regularExpression
                ) != nil
            },
            tags: MarkdownTagSyntax.tags(in: markdown),
            attachmentPaths: MarkdownAttachmentSearch.relativePaths(in: markdown)
        )
    }

    private static func galleryChecklistItem(from line: String) -> MarkdownGalleryChecklistItem? {
        let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let markers: [(String, Bool)] = [
            ("- [ ] ", false), ("* [ ] ", false), ("+ [ ] ", false),
            ("- [x] ", true), ("* [x] ", true), ("+ [x] ", true),
            ("- [X] ", true), ("* [X] ", true), ("+ [X] ", true),
        ]
        guard let marker = markers.first(where: { value.hasPrefix($0.0) }) else { return nil }
        var text = value.dropFirst(marker.0.count).trimmingCharacters(in: .whitespaces)
        text = text.replacingOccurrences(
            of: #"</?(?:u|mark)>|[*_`~]"#,
            with: "",
            options: .regularExpression
        )
        guard !text.isEmpty else { return nil }
        return MarkdownGalleryChecklistItem(text: text, isChecked: marker.1)
    }

    private static func visibleMarkdownLines(from markdown: String) -> [String] {
        var sourceLines = markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        if sourceLines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---",
           let closingIndex = sourceLines.indices.dropFirst().first(where: {
               let marker = sourceLines[$0]
                   .trimmingCharacters(in: .whitespacesAndNewlines)
               return marker == "---" || marker == "..."
           }) {
            sourceLines.removeFirst(closingIndex + 1)
        }
        var visible: [String] = []
        var activeFence: Character?
        for line in sourceLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = trimmed.first,
               (marker == "`" || marker == "~"),
               trimmed.prefix(3).allSatisfy({ $0 == marker }) {
                if activeFence == nil {
                    activeFence = marker
                } else if activeFence == marker {
                    activeFence = nil
                }
                continue
            }
            if activeFence == nil {
                visible.append(line)
            }
        }
        return visible
    }
}

struct MarkdownLibrarySnapshot: Equatable {
    var inboxItems: [MemoBlock]
    var allFiles: [RecentMarkdownFile]
    var recentFiles: [RecentMarkdownFile]
    var hasMoreFiles: Bool = false
    var folders: [LibraryFolderNode]
    var trashedFiles: [TrashedMarkdownFile]
    var attachments: [LibraryAttachment]
    var smartFolders: [SmartFolderDefinition]
    var summary: LibrarySummary
    var conflictWarnings: [String]
}
