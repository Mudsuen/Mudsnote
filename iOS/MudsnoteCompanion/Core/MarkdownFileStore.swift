import Foundation

actor MarkdownFileStore {
    private var root: URL?
    private var cachedLibrarySnapshot: MarkdownLibrarySnapshot?
    private let fileManager = FileManager.default

    func configure(root: URL) {
        self.root = root
        cachedLibrarySnapshot = nil
    }

    func loadLibrarySnapshot() throws -> MarkdownLibrarySnapshot {
        guard let root else { throw FolderAccessError.missingFolder }
        let accessed = root.startAccessingSecurityScopedResource()
        defer {
            if accessed { root.stopAccessingSecurityScopedResource() }
        }

        let inboxURL = root.appendingPathComponent("Inbox.md")
        let inboxMarkdown = try String(contentsOf: inboxURL, encoding: .utf8)
        let inboxItems = InboxParser.parse(inboxMarkdown)
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        var markdownFiles: [RecentMarkdownFile] = []
        var attachments: [LibraryAttachment] = []
        var dailyCount = 0
        var templateCount = 0
        var attachmentCount = 0
        var conflictWarnings: [String] = []

        if let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                let relativePath = Self.relativePath(for: url, root: root)
                let lowercasedName = url.lastPathComponent.lowercased()
                if lowercasedName.contains("conflict") || lowercasedName.contains("conflicted copy") {
                    conflictWarnings.append(relativePath)
                }

                guard let values = try? url.resourceValues(forKeys: resourceKeys),
                      values.isRegularFile == true else {
                    continue
                }

                if relativePath.hasPrefix("Attachments/") {
                    attachmentCount += 1
                    attachments.append(LibraryAttachment(
                        id: relativePath,
                        relativePath: relativePath,
                        fileName: url.lastPathComponent,
                        modifiedAt: values.contentModificationDate ?? .distantPast,
                        byteCount: Int64(values.fileSize ?? 0),
                        kind: LibraryAttachment.Kind(fileExtension: url.pathExtension)
                    ))
                }
                guard url.pathExtension.lowercased() == "md" else { continue }
                if relativePath.hasPrefix("Daily/") {
                    dailyCount += 1
                }
                if relativePath.hasPrefix("Templates/") {
                    templateCount += 1
                }
                markdownFiles.append(RecentMarkdownFile(
                    id: relativePath,
                    relativePath: relativePath,
                    title: url.deletingPathExtension().lastPathComponent,
                    modifiedAt: values.contentModificationDate ?? .distantPast
                ))
            }
        }

        let recentFiles = markdownFiles
            .sorted { $0.modifiedAt > $1.modifiedAt }
            .prefix(24)
            .map { $0 }
        let allFiles = markdownFiles.sorted { $0.modifiedAt > $1.modifiedAt }
        let snapshot = MarkdownLibrarySnapshot(
            inboxItems: inboxItems,
            allFiles: allFiles,
            recentFiles: recentFiles,
            attachments: attachments.sorted { $0.modifiedAt > $1.modifiedAt },
            summary: LibrarySummary(
                allNotesCount: markdownFiles.count,
                inboxCount: inboxItems.count,
                dailyCount: dailyCount,
                templateCount: templateCount,
                attachmentCount: attachmentCount
            ),
            conflictWarnings: conflictWarnings.sorted()
        )
        cachedLibrarySnapshot = snapshot
        return snapshot
    }

    func loadInboxDeltaSnapshot() throws -> MarkdownLibrarySnapshot {
        guard let root else { throw FolderAccessError.missingFolder }
        guard var snapshot = cachedLibrarySnapshot else {
            return try loadLibrarySnapshot()
        }
        let accessed = root.startAccessingSecurityScopedResource()
        defer {
            if accessed { root.stopAccessingSecurityScopedResource() }
        }

        let inboxURL = root.appendingPathComponent("Inbox.md")
        let inboxMarkdown = try String(contentsOf: inboxURL, encoding: .utf8)
        let inboxItems = InboxParser.parse(inboxMarkdown)
        let modifiedAt = try inboxURL.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate ?? .distantPast
        let inboxFile = RecentMarkdownFile(
            id: "Inbox.md",
            relativePath: "Inbox.md",
            title: "Inbox",
            modifiedAt: modifiedAt
        )

        snapshot.inboxItems = inboxItems
        snapshot.summary.inboxCount = inboxItems.count
        snapshot.allFiles = (snapshot.allFiles.filter { $0.relativePath != "Inbox.md" } + [inboxFile])
            .sorted { $0.modifiedAt > $1.modifiedAt }
        snapshot.recentFiles = snapshot.allFiles
            .prefix(24)
            .map { $0 }
        cachedLibrarySnapshot = snapshot
        return snapshot
    }

    func loadMarkdownDocument(relativePath: String) throws -> MarkdownDocument {
        guard let root else { throw FolderAccessError.missingFolder }
        let standardizedRoot = root.standardizedFileURL
        let fileURL = root.appendingPathComponent(relativePath).standardizedFileURL
        guard fileURL.pathExtension.lowercased() == "md",
              fileURL.path.hasPrefix(standardizedRoot.path + "/") else {
            throw MarkdownDocumentError.invalidPath
        }
        let accessed = root.startAccessingSecurityScopedResource()
        defer {
            if accessed { root.stopAccessingSecurityScopedResource() }
        }

        return MarkdownDocument(
            id: relativePath,
            title: fileURL.deletingPathExtension().lastPathComponent,
            relativePath: relativePath,
            markdown: try String(contentsOf: fileURL, encoding: .utf8)
        )
    }

    func prepareAttachmentPreview(relativePath: String) throws -> URL {
        guard let root else { throw FolderAccessError.missingFolder }
        let standardizedRoot = root.standardizedFileURL
        let fileURL = root.appendingPathComponent(relativePath).standardizedFileURL
        let attachmentsRoot = root.appendingPathComponent("Attachments", isDirectory: true).standardizedFileURL
        guard fileURL.path.hasPrefix(attachmentsRoot.path + "/"),
              fileURL.path.hasPrefix(standardizedRoot.path + "/") else {
            throw AttachmentPreviewError.invalidPath
        }
        let accessed = root.startAccessingSecurityScopedResource()
        defer {
            if accessed { root.stopAccessingSecurityScopedResource() }
        }
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            throw AttachmentPreviewError.invalidPath
        }

        let previewDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MudsnoteAttachmentPreview", isDirectory: true)
        try? fileManager.removeItem(at: previewDirectory)
        try fileManager.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        let previewURL = previewDirectory.appendingPathComponent(fileURL.lastPathComponent)
        try fileManager.copyItem(at: fileURL, to: previewURL)
        return previewURL
    }

    func applyInboxMutation(_ mutation: InboxMutation) throws {
        guard let root else { throw FolderAccessError.missingFolder }
        let accessed = root.startAccessingSecurityScopedResource()
        defer {
            if accessed { root.stopAccessingSecurityScopedResource() }
        }

        let inboxURL = root.appendingPathComponent("Inbox.md")
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var mutationError: Error?
        coordinator.coordinate(writingItemAt: inboxURL, options: .forMerging, error: &coordinationError) { coordinatedURL in
            do {
                let markdown = try String(contentsOf: coordinatedURL, encoding: .utf8)
                var items = InboxParser.parse(markdown)
                guard let index = items.firstIndex(where: { $0.id == mutation.memoID }) else {
                    throw InboxMutationError.memoNotFound
                }

                switch mutation {
                case .delete:
                    items.remove(at: index)
                case .pin:
                    let item = items.remove(at: index)
                    items.insert(item, at: 0)
                case .addTag(_, let tag):
                    let normalizedTag = tag.hasPrefix("#") ? tag : "#\(tag)"
                    if items[index].body.split(whereSeparator: \.isWhitespace).contains(Substring(normalizedTag)) == false {
                        items[index].body += items[index].body.isEmpty ? normalizedTag : "\n\n\(normalizedTag)"
                    }
                }

                let updatedMarkdown = InboxParser.markdown(forDisplayItems: items)
                try updatedMarkdown.write(to: coordinatedURL, atomically: true, encoding: .utf8)
            } catch {
                mutationError = error
            }
        }

        if let coordinationError { throw coordinationError }
        if let mutationError { throw mutationError }
    }

    func preparePendingWrite(for draft: CaptureDraft, root: URL, now: Date = Date()) async throws -> PendingWrite {
        try CaptureAttachmentPolicy.validate(draft.attachments)
        let attachmentWrites = try attachmentWrites(for: draft.attachments, root: root, now: now)
        let markdown = Self.markdownBlock(
            body: draft.body,
            tags: draft.tags,
            attachmentReferences: zip(attachmentWrites, draft.attachments).map {
                MarkdownAttachmentReference(relativePath: $0.0.relativePath, kind: $0.1.referenceKind)
            },
            attachmentTags: draft.attachments.map(\.markdownTag),
            now: now
        )

        return PendingWrite(
            id: UUID(),
            createdAt: now,
            targetRelativePath: draft.target.relativePath(now: now),
            markdownBlock: markdown,
            attachments: attachmentWrites.map {
                PendingAttachment(relativePath: $0.relativePath, base64Data: $0.data.base64EncodedString())
            }
        )
    }

    func performPendingWrite(_ pending: PendingWrite) async throws {
        guard let root else { throw FolderAccessError.missingFolder }
        let accessed = root.startAccessingSecurityScopedResource()
        defer {
            if accessed { root.stopAccessingSecurityScopedResource() }
        }

        for attachment in pending.attachments {
            let attachmentURL = root.appendingPathComponent(attachment.relativePath)
            try fileManager.createDirectory(
                at: attachmentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = Data(base64Encoded: attachment.base64Data) ?? Data()
            guard !fileManager.fileExists(atPath: attachmentURL.path) else { continue }
            try data.write(to: attachmentURL, options: .atomic)
        }

        let target = root.appendingPathComponent(pending.targetRelativePath)
        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: target.path) {
            try "# \(target.deletingPathExtension().lastPathComponent)\n\n".write(to: target, atomically: true, encoding: .utf8)
        }

        try appendPendingWriteIfNeeded(pending, to: target)
    }

    private func attachmentWrites(for attachments: [CaptureAttachment], root: URL, now: Date) throws -> [(relativePath: String, data: Data)] {
        let month = Self.monthFormatter.string(from: now)
        let timestamp = Self.attachmentFormatter.string(from: now)
        return attachments.enumerated().map { index, attachment in
            let suffix = attachments.count > 1 ? "-\(index + 1)" : ""
            let fileName = "\(attachment.filePrefix)-\(timestamp)\(suffix).\(attachment.preferredExtension)"
            return ("Attachments/\(month)/\(fileName)", attachment.data)
        }
    }

    private func appendPendingWriteIfNeeded(_ pending: PendingWrite, to target: URL) throws {
        let marker = "<!-- mudsnote-write:\(pending.id.uuidString.lowercased()) -->"
        let block = pending.markdownBlock + marker + "\n"
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var writeError: Error?

        coordinator.coordinate(writingItemAt: target, options: .forMerging, error: &coordinationError) { coordinatedURL in
            do {
                var existing = try Data(contentsOf: coordinatedURL)
                if let markerData = marker.data(using: .utf8), existing.range(of: markerData) != nil {
                    return
                }
                guard let blockData = block.data(using: .utf8) else { return }
                existing.append(blockData)
                try existing.write(to: coordinatedURL, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let writeError {
            throw writeError
        }
    }

    private static func relativePath(for url: URL, root: URL) -> String {
        String(url.path.dropFirst(root.path.count + 1))
    }

    static func markdownBlock(
        body: String,
        tags: String,
        attachmentReferences: [MarkdownAttachmentReference],
        attachmentTags: [String],
        now: Date
    ) -> String {
        var lines: [String] = [
            "",
            "## \(memoFormatter.string(from: now))",
            "",
        ]
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty {
            lines.append(trimmedBody)
            lines.append("")
        }
        for reference in attachmentReferences {
            lines.append(reference.markdownLine)
        }
        if !attachmentReferences.isEmpty {
            lines.append("")
        }

        let tagLine = ([tags, attachmentTags.joined(separator: " ")]
            .joined(separator: " ")
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty })
            .joined(separator: " ")
        if !tagLine.isEmpty {
            lines.append(tagLine)
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static let memoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy/MM"
        return formatter
    }()

    private static let attachmentFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

struct RecentMarkdownFile: Identifiable, Equatable {
    var id: String
    var relativePath: String
    var title: String
    var modifiedAt: Date
}

struct MarkdownLibrarySnapshot: Equatable {
    var inboxItems: [MemoBlock]
    var allFiles: [RecentMarkdownFile]
    var recentFiles: [RecentMarkdownFile]
    var attachments: [LibraryAttachment]
    var summary: LibrarySummary
    var conflictWarnings: [String]
}

struct LibraryAttachment: Identifiable, Equatable {
    var id: String
    var relativePath: String
    var fileName: String
    var modifiedAt: Date
    var byteCount: Int64
    var kind: Kind

    enum Kind: Equatable {
        case image
        case audio
        case other

        init(fileExtension: String) {
            switch fileExtension.lowercased() {
            case "png", "jpg", "jpeg", "heic", "gif", "webp", "tif", "tiff":
                self = .image
            case "m4a", "wav", "mp3", "aac", "caf", "aif", "aiff":
                self = .audio
            default:
                self = .other
            }
        }

        var systemImage: String {
            switch self {
            case .image: "photo"
            case .audio: "waveform"
            case .other: "doc"
            }
        }
    }
}

struct MarkdownDocument: Identifiable, Equatable {
    var id: String
    var title: String
    var relativePath: String
    var markdown: String
}

enum MarkdownDocumentError: LocalizedError, Equatable {
    case invalidPath

    var errorDescription: String? {
        String(localized: "This Markdown file is outside the authorized library.")
    }
}

enum AttachmentPreviewError: LocalizedError, Equatable {
    case invalidPath

    var errorDescription: String? {
        String(localized: "This attachment is outside the authorized library.")
    }
}

struct LibrarySummary: Equatable {
    var allNotesCount = 0
    var inboxCount = 0
    var dailyCount = 0
    var templateCount = 0
    var attachmentCount = 0
}

enum InboxMutation: Equatable {
    case delete(memoID: String)
    case pin(memoID: String)
    case addTag(memoID: String, tag: String)

    var memoID: String {
        switch self {
        case .delete(let memoID), .pin(let memoID), .addTag(let memoID, _): memoID
        }
    }
}

enum InboxMutationError: LocalizedError {
    case memoNotFound

    var errorDescription: String? {
        String(localized: "The memo changed before this action completed. Refresh and try again.")
    }
}

extension MarkdownAttachmentReference {
    var markdownLine: String {
        switch kind {
        case .image:
            return "![Image](\(relativePath))"
        case .audio:
            return "[Audio](\(relativePath))"
        }
    }
}
