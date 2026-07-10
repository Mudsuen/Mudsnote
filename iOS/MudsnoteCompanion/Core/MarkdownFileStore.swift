import Foundation

actor MarkdownFileStore {
    private var root: URL?
    private let fileManager = FileManager.default

    func configure(root: URL) {
        self.root = root
    }

    func preparePendingWrite(for draft: CaptureDraft, root: URL, now: Date = Date()) async throws -> PendingWrite {
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

    static func recentFiles(in root: URL) throws -> [RecentMarkdownFile] {
        let accessed = root.startAccessingSecurityScopedResource()
        defer {
            if accessed { root.stopAccessingSecurityScopedResource() }
        }

        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item -> RecentMarkdownFile? in
            guard let url = item as? URL, url.pathExtension == "md" else { return nil }
            let values = try url.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true else { return nil }
            let relative = String(url.path.dropFirst(root.path.count + 1))
            return RecentMarkdownFile(
                id: relative,
                relativePath: relative,
                title: url.deletingPathExtension().lastPathComponent,
                modifiedAt: values.contentModificationDate ?? .distantPast
            )
        }
        .sorted { $0.modifiedAt > $1.modifiedAt }
        .prefix(24)
        .map { $0 }
    }

    static func conflictWarnings(in root: URL) throws -> [String] {
        let accessed = root.startAccessingSecurityScopedResource()
        defer {
            if accessed { root.stopAccessingSecurityScopedResource() }
        }

        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return enumerator.compactMap { item in
            guard let url = item as? URL else { return nil }
            let name = url.lastPathComponent.lowercased()
            guard name.contains("conflict") || name.contains("conflicted copy") else { return nil }
            return String(url.path.dropFirst(root.path.count + 1))
        }
    }

    static func librarySummary(in root: URL, inboxCount: Int, allNotesCount: Int) throws -> LibrarySummary {
        let accessed = root.startAccessingSecurityScopedResource()
        defer {
            if accessed { root.stopAccessingSecurityScopedResource() }
        }

        return LibrarySummary(
            allNotesCount: allNotesCount,
            inboxCount: inboxCount,
            dailyCount: countFiles(in: root.appendingPathComponent("Daily"), extensions: ["md"]),
            templateCount: countFiles(in: root.appendingPathComponent("Templates"), extensions: ["md"]),
            attachmentCount: countFiles(in: root.appendingPathComponent("Attachments"), extensions: nil)
        )
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

    private static func countFiles(in folder: URL, extensions allowedExtensions: Set<String>?) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        return enumerator.reduce(into: 0) { count, item in
            guard let url = item as? URL else { return }
            if let allowedExtensions, !allowedExtensions.contains(url.pathExtension.lowercased()) {
                return
            }
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                count += 1
            }
        }
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
