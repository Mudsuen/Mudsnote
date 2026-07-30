import CryptoKit
import Foundation

actor MarkdownFileStore {
    private struct SearchCacheEntry {
        var modifiedAt: Date
        var byteCount: Int
        var markdown: String
    }

    private struct ListMetadataCacheEntry {
        var modifiedAt: Date
        var byteCount: Int
        var metadata: MarkdownListMetadata
    }

    private struct MarkdownLinkRewriteBackup {
        var url: URL
        var relativePath: String
        var data: Data
    }

    private struct MarkdownTagRewriteBackup {
        var url: URL
        var relativePath: String
        var original: Data
        var updated: Data
    }

    private struct SmartFolderConfiguration: Codable {
        var version: Int
        var folders: [SmartFolderDefinition]
    }

    private var root: URL?
    private var cachedLibrarySnapshot: MarkdownLibrarySnapshot?
    private var searchCache: [String: SearchCacheEntry] = [:]
    private var listMetadataCache: [String: ListMetadataCacheEntry] = [:]
    private let fileManager = FileManager.default
    private let attachmentTextIndex: AttachmentTextIndex

    init(attachmentTextIndex: AttachmentTextIndex = AttachmentTextIndex()) {
        self.attachmentTextIndex = attachmentTextIndex
    }

    func configure(root: URL) {
        self.root = root
        cachedLibrarySnapshot = nil
        searchCache = [:]
        listMetadataCache = [:]
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
        let resourceKeys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .creationDateKey,
            .fileSizeKey,
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]
        var markdownFiles: [RecentMarkdownFile] = []
        var folderPaths = Set<String>()
        var attachments: [LibraryAttachment] = []
        var attachmentOwners = Self.inboxAttachmentOwners(in: inboxItems)
        var dailyCount = 0
        var attachmentCount = 0
        var conflictWarnings: [String] = []

        if let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                let relativePath = Self.relativePath(for: url, root: root)
                guard let values = try? url.resourceValues(forKeys: resourceKeys) else {
                    continue
                }
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }
                if values.isDirectory == true {
                    folderPaths.insert(relativePath)
                    continue
                }
                guard values.isRegularFile == true else { continue }

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
                if Self.isConflictCopyPath(relativePath) {
                    conflictWarnings.append(relativePath)
                }
                if relativePath.hasPrefix("Daily/") {
                    dailyCount += 1
                }
                let modifiedAt = values.contentModificationDate ?? .distantPast
                let byteCount = values.fileSize ?? 0
                let listMetadata = try metadataForList(
                    relativePath: relativePath,
                    url: url,
                    modifiedAt: modifiedAt,
                    byteCount: byteCount
                )
                if relativePath != "Inbox.md" {
                    let owner = LibraryAttachment.Owner(
                        id: "file:\(relativePath)",
                        title: listMetadata.title,
                        destination: .file(relativePath)
                    )
                    for attachmentPath in listMetadata.attachmentPaths {
                        attachmentOwners[attachmentPath, default: []].append(owner)
                    }
                }
                markdownFiles.append(RecentMarkdownFile(
                    id: relativePath,
                    relativePath: relativePath,
                    title: listMetadata.title,
                    modifiedAt: modifiedAt,
                    createdAt: values.creationDate ?? modifiedAt,
                    preview: listMetadata.preview,
                    galleryImagePath: listMetadata.galleryImagePath,
                    galleryChecklistItems: listMetadata.galleryChecklistItems,
                    hasAttachments: listMetadata.hasAttachments,
                    hasChecklist: listMetadata.hasChecklist,
                    hasUncheckedChecklist: listMetadata.hasUncheckedChecklist,
                    tags: listMetadata.tags
                ))
            }
        }

        for index in attachments.indices {
            attachments[index].owners = attachmentOwners[attachments[index].relativePath] ?? []
        }

        let storedPinnedPaths = try loadPinnedPaths(root: root)
        let activePaths = Set(markdownFiles.map(\.relativePath))
        listMetadataCache = listMetadataCache.filter { activePaths.contains($0.key) }
        let pinnedPaths = storedPinnedPaths.intersection(activePaths)
        if pinnedPaths != storedPinnedPaths {
            try savePinnedPaths(pinnedPaths, root: root)
        }
        for index in markdownFiles.indices {
            markdownFiles[index].isPinned = pinnedPaths.contains(markdownFiles[index].relativePath)
        }
        let recentFiles = markdownFiles
            .sorted(by: Self.notesOrder)
            .prefix(24)
            .map { $0 }
        let allFiles = markdownFiles.sorted(by: Self.notesOrder)
        let trashedFiles = try loadTrashedFiles(root: root)
        // Smart Folders are optional metadata. A damaged configuration must not
        // make the Markdown library unavailable; mutations still use the strict
        // loader below and preserve the unreadable file until the user repairs it.
        let smartFolders = (try? loadSmartFolders(root: root)) ?? []
        let snapshot = MarkdownLibrarySnapshot(
            inboxItems: inboxItems,
            allFiles: allFiles,
            recentFiles: recentFiles,
            folders: LibraryFolderNode.makeTree(
                directoryPaths: folderPaths,
                files: markdownFiles
            ),
            trashedFiles: trashedFiles,
            attachments: attachments.sorted { $0.modifiedAt > $1.modifiedAt },
            smartFolders: smartFolders,
            summary: LibrarySummary(
                allNotesCount: markdownFiles.count,
                inboxCount: inboxItems.count,
                dailyCount: dailyCount,
                attachmentCount: attachmentCount,
                recentlyDeletedCount: trashedFiles.count
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
        let inboxValues = try inboxURL.resourceValues(
            forKeys: [.contentModificationDateKey, .creationDateKey]
        )
        let modifiedAt = inboxValues.contentModificationDate ?? .distantPast
        let metadata = MarkdownListMetadata.extract(
            from: inboxMarkdown,
            fallbackTitle: String(localized: "Inbox")
        )
        let inboxFile = RecentMarkdownFile(
            id: "Inbox.md",
            relativePath: "Inbox.md",
            title: metadata.title,
            modifiedAt: modifiedAt,
            createdAt: inboxValues.creationDate ?? modifiedAt,
            preview: metadata.preview,
            galleryImagePath: metadata.galleryImagePath,
            galleryChecklistItems: metadata.galleryChecklistItems,
            hasAttachments: metadata.hasAttachments,
            hasChecklist: metadata.hasChecklist,
            hasUncheckedChecklist: metadata.hasUncheckedChecklist,
            tags: metadata.tags
        )

        snapshot.inboxItems = inboxItems
        let inboxOwners = Self.inboxAttachmentOwners(in: inboxItems)
        for index in snapshot.attachments.indices {
            let fileOwners = snapshot.attachments[index].owners.filter {
                if case .file = $0.destination { return true }
                return false
            }
            snapshot.attachments[index].owners = fileOwners
                + (inboxOwners[snapshot.attachments[index].relativePath] ?? [])
        }
        snapshot.summary.inboxCount = inboxItems.count
        snapshot.allFiles = (snapshot.allFiles.filter { $0.relativePath != "Inbox.md" } + [inboxFile])
            .sorted(by: Self.notesOrder)
        snapshot.recentFiles = snapshot.allFiles
            .prefix(24)
            .map { $0 }
        cachedLibrarySnapshot = snapshot
        return snapshot
    }

    func setPinned(_ isPinned: Bool, relativePath: String) throws {
        guard let root else { throw FolderAccessError.missingFolder }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        guard Self.isPinnableNotePath(relativePath),
              let url = AuthorizedLibraryPath.resolve(relativePath, within: root),
              url.pathExtension.lowercased() == "md",
              fileManager.fileExists(atPath: url.path) else {
            throw MarkdownLifecycleError.noteNotFound
        }
        var pins = try loadPinnedPaths(root: root)
        if isPinned {
            pins.insert(relativePath)
        } else {
            pins.remove(relativePath)
        }
        try savePinnedPaths(pins, root: root)
        cachedLibrarySnapshot = nil
    }

    func createSmartFolder(_ definition: SmartFolderDefinition) throws -> SmartFolderDefinition {
        guard let root else { throw FolderAccessError.missingFolder }
        guard let normalized = definition.normalized else {
            throw SmartFolderStoreError.invalidDefinition
        }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        var folders = try loadSmartFolders(root: root)
        guard !folders.contains(where: { Self.sameSmartFolderName($0.name, normalized.name) }) else {
            throw SmartFolderStoreError.duplicateName
        }
        folders.append(normalized)
        folders.sort(by: Self.smartFolderOrder)
        try saveSmartFolders(folders, root: root)
        cachedLibrarySnapshot?.smartFolders = folders
        return normalized
    }

    func updateSmartFolder(_ definition: SmartFolderDefinition) throws -> SmartFolderDefinition {
        guard let root else { throw FolderAccessError.missingFolder }
        guard let normalized = definition.normalized else {
            throw SmartFolderStoreError.invalidDefinition
        }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        var folders = try loadSmartFolders(root: root)
        guard let index = folders.firstIndex(where: { $0.id == normalized.id }) else {
            throw SmartFolderStoreError.notFound
        }
        guard !folders.contains(where: {
            $0.id != normalized.id && Self.sameSmartFolderName($0.name, normalized.name)
        }) else { throw SmartFolderStoreError.duplicateName }
        folders[index] = normalized
        folders.sort(by: Self.smartFolderOrder)
        try saveSmartFolders(folders, root: root)
        cachedLibrarySnapshot?.smartFolders = folders
        return normalized
    }

    func deleteSmartFolder(id: UUID) throws {
        guard let root else { throw FolderAccessError.missingFolder }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        var folders = try loadSmartFolders(root: root)
        let originalCount = folders.count
        folders.removeAll(where: { $0.id == id })
        guard folders.count != originalCount else {
            throw SmartFolderStoreError.notFound
        }
        try saveSmartFolders(folders, root: root)
        cachedLibrarySnapshot?.smartFolders = folders
    }

    func setPinned(_ isPinned: Bool, relativePaths: [String]) throws {
        guard let root else { throw FolderAccessError.missingFolder }
        let paths = Array(Set(relativePaths)).sorted()
        guard !paths.isEmpty else { return }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        for relativePath in paths {
            guard Self.isPinnableNotePath(relativePath),
                  let url = AuthorizedLibraryPath.resolve(relativePath, within: root),
                  url.pathExtension.lowercased() == "md",
                  fileManager.fileExists(atPath: url.path) else {
                throw MarkdownLifecycleError.noteNotFound
            }
        }
        var pins = try loadPinnedPaths(root: root)
        if isPinned {
            pins.formUnion(paths)
        } else {
            pins.subtract(paths)
        }
        try savePinnedPaths(pins, root: root)
        cachedLibrarySnapshot = nil
    }

    func createMarkdownDocument(inFolder relativeFolderPath: String? = nil) throws -> MarkdownDocument {
        guard let root else { throw FolderAccessError.missingFolder }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        let directory = try userFolderURL(
            relativePath: relativeFolderPath,
            root: root,
            allowRoot: true
        )
        let destination = uniqueMarkdownURL(
            for: directory.appendingPathComponent("Untitled Note.md")
        )
        try Data().write(to: destination, options: .withoutOverwriting)
        let relativePath = Self.relativePath(for: destination, root: root)
        invalidateAfterMutation(relativePaths: [relativePath])
        return MarkdownDocument(
            id: relativePath,
            title: destination.deletingPathExtension().lastPathComponent,
            relativePath: relativePath,
            markdown: "",
            modifiedAt: modificationDate(for: destination),
            isNew: true
        )
    }

    func finalizeNewMarkdownDocument(
        relativePath: String,
        markdown: String,
        expectedMarkdown: String
    ) throws -> MarkdownDocument {
        let saved = try saveMarkdownDocument(
            relativePath: relativePath,
            markdown: markdown,
            expectedMarkdown: expectedMarkdown
        )
        guard let root,
              Self.isGeneratedUntitledNotePath(relativePath),
              let source = AuthorizedLibraryPath.resolve(relativePath, within: root) else {
            return saved
        }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        let preferredStem = Self.portableNoteFilenameStem(from: markdown)
        guard preferredStem != source.deletingPathExtension().lastPathComponent else {
            return saved
        }
        let destination = uniqueMarkdownURL(
            for: source.deletingLastPathComponent().appendingPathComponent("\(preferredStem).md")
        )
        do {
            try coordinatedMove(from: source, to: destination)
            let renamedPath = Self.relativePath(for: destination, root: root)
            invalidateAfterMutation(relativePaths: [relativePath, renamedPath])
            return MarkdownDocument(
                id: renamedPath,
                title: preferredStem,
                relativePath: renamedPath,
                markdown: markdown,
                modifiedAt: modificationDate(for: destination) ?? saved.modifiedAt
            )
        } catch {
            return saved
        }
    }

    func discardEmptyNewMarkdownDocument(relativePath: String) throws {
        guard let root,
              Self.isGeneratedUntitledNotePath(relativePath),
              let url = AuthorizedLibraryPath.resolve(relativePath, within: root) else { return }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        guard fileManager.fileExists(atPath: url.path),
              try Data(contentsOf: url).isEmpty else { return }
        try fileManager.removeItem(at: url)
        invalidateAfterMutation(relativePaths: [relativePath])
    }

    func loadMarkdownDocument(relativePath: String) throws -> MarkdownDocument {
        guard let root else { throw FolderAccessError.missingFolder }
        guard let fileURL = AuthorizedLibraryPath.resolve(relativePath, within: root),
              fileURL.pathExtension.lowercased() == "md" else {
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
            markdown: try String(contentsOf: fileURL, encoding: .utf8),
            modifiedAt: modificationDate(for: fileURL)
        )
    }

    func search(
        query: String,
        scope: MarkdownSearchScope = .all,
        limit: Int = 80
    ) async throws -> [MarkdownSearchResult] {
        guard let root else { throw FolderAccessError.missingFolder }
        let terms = MarkdownSearch.normalizedTerms(query)
        guard !terms.isEmpty else { return [] }
        let files: [RecentMarkdownFile]
        if let cachedLibrarySnapshot {
            files = cachedLibrarySnapshot.allFiles
        } else {
            files = try loadLibrarySnapshot().allFiles
        }
        let accessed = root.startAccessingSecurityScopedResource()
        defer {
            if accessed { root.stopAccessingSecurityScopedResource() }
        }

        var matches: [MarkdownSearchResult] = []
        var activePaths = Set<String>()
        for file in files {
            try Task.checkCancellation()
            activePaths.insert(file.relativePath)
            if scope == .notes, file.relativePath == "Inbox.md" { continue }
            if scope == .inbox, file.relativePath != "Inbox.md" { continue }
            guard let url = AuthorizedLibraryPath.resolve(file.relativePath, within: root) else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modifiedAt = values?.contentModificationDate ?? file.modifiedAt
            let byteCount = values?.fileSize ?? 0
            let markdown: String
            if let cached = searchCache[file.relativePath],
               cached.modifiedAt == modifiedAt,
               cached.byteCount == byteCount {
                markdown = cached.markdown
            } else {
                markdown = try boundedSearchText(from: url)
                if byteCount <= 256 * 1_024 {
                    searchCache[file.relativePath] = SearchCacheEntry(
                        modifiedAt: modifiedAt,
                        byteCount: byteCount,
                        markdown: markdown
                    )
                    trimSearchCacheIfNeeded()
                } else {
                    searchCache.removeValue(forKey: file.relativePath)
                }
            }

            if file.relativePath == "Inbox.md" {
                for memo in InboxParser.parse(markdown) {
                    if let result = MarkdownSearch.match(memo: memo, terms: terms) {
                        matches.append(result)
                        continue
                    }
                    let attachments = try await searchableAttachmentDocuments(
                        in: memo.body,
                        root: root
                    )
                    if let result = MarkdownSearch.match(
                        memo: memo,
                        terms: terms,
                        attachmentDocuments: attachments
                    ) {
                        matches.append(result)
                    }
                }
            } else if let result = MarkdownSearch.match(
                file: file,
                markdown: markdown,
                terms: terms
            ) {
                matches.append(result)
            } else {
                let attachments = try await searchableAttachmentDocuments(
                    in: markdown,
                    root: root
                )
                if let result = MarkdownSearch.match(
                    file: file,
                    markdown: markdown,
                    terms: terms,
                    attachmentDocuments: attachments
                ) {
                    matches.append(result)
                }
            }
        }
        searchCache = searchCache.filter { activePaths.contains($0.key) }

        return matches
            .sorted {
                if $0.score == $1.score { return $0.modifiedAt > $1.modifiedAt }
                return $0.score > $1.score
            }
            .prefix(limit)
            .map { $0 }
    }

    private func searchableAttachmentDocuments(
        in markdown: String,
        root: URL
    ) async throws -> [AttachmentSearchDocument] {
        var documents: [AttachmentSearchDocument] = []
        for relativePath in MarkdownAttachmentSearch.relativePaths(in: markdown) {
            try Task.checkCancellation()
            do {
                if let text = try await attachmentTextIndex.text(
                    relativePath: relativePath,
                    root: root
                ) {
                    documents.append(AttachmentSearchDocument(
                        relativePath: relativePath,
                        text: text
                    ))
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A damaged or unsupported attachment must not make note search fail.
                continue
            }
        }
        return documents
    }

    func attachmentSearchDocuments(in markdown: String) async throws -> [AttachmentSearchDocument] {
        guard let root else { throw FolderAccessError.missingFolder }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        return try await searchableAttachmentDocuments(in: markdown, root: root)
    }

    func prepareAttachmentPreview(relativePath: String) throws -> PreparedAttachmentPreview {
        guard let root else { throw FolderAccessError.missingFolder }
        guard let fileURL = AuthorizedLibraryPath.resolve(
            relativePath,
            within: root,
            constrainedTo: "Attachments"
        ) else {
            throw AttachmentPreviewError.invalidPath
        }
        let accessed = root.startAccessingSecurityScopedResource()
        defer {
            if accessed { root.stopAccessingSecurityScopedResource() }
        }
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true,
              let byteCount = values.fileSize,
              byteCount > 0,
              byteCount <= CaptureAttachmentPolicy.maximumFileBytes else {
            throw AttachmentPreviewError.invalidPath
        }

        let originalData = try Data(contentsOf: fileURL, options: .mappedIfSafe)

        let previewDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MudsnoteAttachmentPreview", isDirectory: true)
        try? fileManager.removeItem(at: previewDirectory)
        try fileManager.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        let previewURL = previewDirectory.appendingPathComponent(fileURL.lastPathComponent)
        try originalData.write(to: previewURL, options: .atomic)
        return PreparedAttachmentPreview(
            url: previewURL,
            relativePath: relativePath,
            originalDigest: Data(SHA256.hash(data: originalData))
        )
    }

    func commitEditedAttachmentPreview(
        _ preview: PreparedAttachmentPreview,
        editedURL: URL
    ) throws -> Bool {
        guard let root else { throw FolderAccessError.missingFolder }
        guard preview.isPDF,
              editedURL.pathExtension.lowercased() == "pdf",
              let targetURL = AuthorizedLibraryPath.resolve(
                preview.relativePath,
                within: root,
                constrainedTo: "Attachments"
              ),
              targetURL.pathExtension.lowercased() == "pdf" else {
            throw AttachmentPreviewError.unsupportedEditing
        }

        let editedValues = try editedURL.resourceValues(
            forKeys: [.isRegularFileKey, .fileSizeKey]
        )
        guard editedValues.isRegularFile == true,
              let editedByteCount = editedValues.fileSize,
              editedByteCount > 0,
              editedByteCount <= CaptureAttachmentPolicy.maximumFileBytes else {
            throw AttachmentPreviewError.invalidPath
        }
        let editedData = try Data(contentsOf: editedURL, options: .mappedIfSafe)
        guard Data(SHA256.hash(data: editedData)) != preview.originalDigest else {
            return false
        }

        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var updateError: Error?
        coordinator.coordinate(
            writingItemAt: targetURL,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                let currentData = try Data(contentsOf: coordinatedURL, options: .mappedIfSafe)
                guard Data(SHA256.hash(data: currentData)) == preview.originalDigest else {
                    throw AttachmentPreviewError.changedExternally
                }
                try editedData.write(to: coordinatedURL, options: .atomic)
            } catch {
                updateError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let updateError { throw updateError }

        cachedLibrarySnapshot = nil
        searchCache.removeAll(keepingCapacity: true)
        return true
    }

    func loadAttachmentThumbnailData(relativePath: String) throws -> Data {
        guard let root else { throw FolderAccessError.missingFolder }
        guard let fileURL = AuthorizedLibraryPath.resolve(
            relativePath,
            within: root,
            constrainedTo: "Attachments"
        ) else {
            throw AttachmentPreviewError.invalidPath
        }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true,
              (values.fileSize ?? 0) <= CaptureAttachmentPolicy.maximumImageBytes else {
            throw AttachmentPreviewError.invalidPath
        }
        return try Data(contentsOf: fileURL, options: .mappedIfSafe)
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
                case .replaceBody(_, let expectedBody, let newBody):
                    guard items[index].body == expectedBody else {
                        throw InboxMutationError.memoChanged
                    }
                    items[index].body = newBody.trimmingCharacters(in: .whitespacesAndNewlines)
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

    func mutateTag(
        _ sourceTagInput: String,
        mutation: MarkdownTagMutation
    ) throws -> MarkdownTagMutationResult {
        guard let sourceTag = MarkdownTagSyntax.normalizedTag(sourceTagInput) else {
            throw MarkdownTagMutationError.invalidTag
        }
        let replacementTag: String?
        switch mutation {
        case .rename(let input):
            guard let normalized = MarkdownTagSyntax.normalizedTag(input) else {
                throw MarkdownTagMutationError.invalidTag
            }
            replacementTag = normalized
        case .delete:
            replacementTag = nil
        }
        guard let root else { throw FolderAccessError.missingFolder }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { throw MarkdownTagMutationError.notFound }

        var occurrenceCount = 0
        var updates: [MarkdownTagRewriteBackup] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isDirectory != true,
                  values.isRegularFile == true,
                  url.pathExtension.lowercased() == "md" else { continue }
            let original = try Data(contentsOf: url, options: .mappedIfSafe)
            guard let markdown = String(data: original, encoding: .utf8),
                  let rewrite = MarkdownTagSyntax.rewriting(
                    markdown,
                    tag: sourceTag,
                    mutation: mutation
                  ) else { continue }
            occurrenceCount += rewrite.occurrenceCount
            guard rewrite.markdown != markdown,
                  let updated = rewrite.markdown.data(using: .utf8) else { continue }
            updates.append(MarkdownTagRewriteBackup(
                url: url,
                relativePath: Self.relativePath(for: url, root: root),
                original: original,
                updated: updated
            ))
        }
        guard occurrenceCount > 0 else { throw MarkdownTagMutationError.notFound }

        var written: [MarkdownTagRewriteBackup] = []
        do {
            for update in updates {
                try coordinatedReplaceTagData(
                    at: update.url,
                    relativePath: update.relativePath,
                    expected: update.original,
                    replacement: update.updated
                )
                written.append(update)
            }
        } catch {
            var rollbackFailed = false
            for update in written.reversed() {
                do {
                    try coordinatedReplaceTagData(
                        at: update.url,
                        relativePath: update.relativePath,
                        expected: update.updated,
                        replacement: update.original
                    )
                } catch {
                    rollbackFailed = true
                }
            }
            if rollbackFailed { throw MarkdownTagMutationError.rollbackFailed }
            throw error
        }

        let changedPaths = updates.map(\.relativePath)
        cachedLibrarySnapshot = nil
        for path in changedPaths {
            searchCache.removeValue(forKey: path)
            listMetadataCache.removeValue(forKey: path)
        }
        return MarkdownTagMutationResult(
            sourceTag: sourceTag,
            replacementTag: replacementTag,
            changedPaths: changedPaths,
            occurrenceCount: occurrenceCount
        )
    }

    func preparePendingWrite(for draft: CaptureDraft, root: URL, now: Date = Date()) async throws -> PendingWrite {
        guard draft.canSend else { throw CaptureDraftError.empty }
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

    func saveMarkdownDocument(
        relativePath: String,
        markdown: String,
        expectedMarkdown: String
    ) throws -> MarkdownDocument {
        guard let root else { throw FolderAccessError.missingFolder }
        guard let fileURL = AuthorizedLibraryPath.resolve(relativePath, within: root),
              fileURL.pathExtension.lowercased() == "md" else {
            throw MarkdownDocumentError.invalidPath
        }
        let accessed = root.startAccessingSecurityScopedResource()
        defer {
            if accessed { root.stopAccessingSecurityScopedResource() }
        }

        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var saveError: Error?
        coordinator.coordinate(writingItemAt: fileURL, options: .forMerging, error: &coordinationError) { coordinatedURL in
            do {
                let current = try String(contentsOf: coordinatedURL, encoding: .utf8)
                guard current == expectedMarkdown else {
                    throw MarkdownDocumentError.changedExternally
                }
                try markdown.write(to: coordinatedURL, atomically: true, encoding: .utf8)
            } catch {
                saveError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let saveError { throw saveError }
        cachedLibrarySnapshot = nil
        searchCache.removeValue(forKey: relativePath)
        listMetadataCache.removeValue(forKey: relativePath)
        return MarkdownDocument(
            id: relativePath,
            title: fileURL.deletingPathExtension().lastPathComponent,
            relativePath: relativePath,
            markdown: markdown,
            modifiedAt: modificationDate(for: fileURL) ?? Date()
        )
    }

    func attachToMarkdownDocument(
        relativePath: String,
        markdown: String,
        expectedMarkdown: String,
        attachment: CaptureAttachment,
        now: Date = Date()
    ) throws -> MarkdownDocument {
        guard let root else { throw FolderAccessError.missingFolder }
        try CaptureAttachmentPolicy.validate([attachment])
        let requestedWrite = try attachmentWrites(for: [attachment], root: root, now: now)[0]
        guard let requestedURL = AuthorizedLibraryPath.resolve(
            requestedWrite.relativePath,
            within: root,
            constrainedTo: "Attachments"
        ) else {
            throw PendingWriteValidationError.invalidAttachmentPath
        }
        let destination = uniqueAttachmentDestination(for: requestedURL, root: root)
        let destinationPath = Self.relativePath(for: destination, root: root)
        let reference = MarkdownAttachmentReference(
            relativePath: destinationPath,
            kind: attachment.referenceKind
        )
        let separator = markdown.isEmpty || markdown.hasSuffix("\n") ? "" : "\n"
        let updatedMarkdown = markdown + separator + reference.markdownLine + "\n"

        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try requestedWrite.data.write(to: destination, options: .withoutOverwriting)
        do {
            return try saveMarkdownDocument(
                relativePath: relativePath,
                markdown: updatedMarkdown,
                expectedMarkdown: expectedMarkdown
            )
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    func removeAttachmentFromMarkdownDocument(
        relativePath: String,
        markdown: String,
        expectedMarkdown: String,
        attachmentLine: String
    ) throws -> MarkdownDocument {
        var lines = markdown.components(separatedBy: .newlines)
        guard let index = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == attachmentLine.trimmingCharacters(in: .whitespaces)
        }) else {
            throw MarkdownDocumentError.attachmentReferenceNotFound
        }
        lines.remove(at: index)
        return try saveMarkdownDocument(
            relativePath: relativePath,
            markdown: lines.joined(separator: "\n"),
            expectedMarkdown: expectedMarkdown
        )
    }

    func renameAttachmentInMarkdownDocument(
        relativePath: String,
        markdown: String,
        expectedMarkdown: String,
        attachmentLine: String,
        attachmentRelativePath: String,
        to name: String
    ) throws -> MarkdownDocument {
        guard let root else { throw FolderAccessError.missingFolder }
        guard markdown.components(separatedBy: .newlines).contains(where: {
            $0.trimmingCharacters(in: .whitespaces)
                == attachmentLine.trimmingCharacters(in: .whitespaces)
        }), attachmentLine.contains(attachmentRelativePath) else {
            throw MarkdownDocumentError.attachmentReferenceNotFound
        }
        guard let source = AuthorizedLibraryPath.resolve(
            attachmentRelativePath,
            within: root,
            constrainedTo: "Attachments"
        ), fileManager.fileExists(atPath: source.path) else {
            throw MarkdownDocumentError.attachmentReferenceNotFound
        }
        let baseName = try Self.validatedAttachmentBaseName(
            name,
            preservingExtension: source.pathExtension
        )
        let requested = source.deletingLastPathComponent()
            .appendingPathComponent(baseName)
            .appendingPathExtension(source.pathExtension)
        if requested.standardizedFileURL == source.standardizedFileURL {
            let documentURL = AuthorizedLibraryPath.resolve(relativePath, within: root)
            return MarkdownDocument(
                id: relativePath,
                title: ((relativePath as NSString).lastPathComponent as NSString).deletingPathExtension,
                relativePath: relativePath,
                markdown: markdown,
                modifiedAt: documentURL.flatMap(modificationDate(for:))
            )
        }

        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        if try attachmentIsReferencedOutsideDocument(
            attachmentRelativePath,
            documentRelativePath: relativePath,
            root: root
        ) {
            throw MarkdownDocumentError.attachmentReferencedElsewhere
        }
        let destination = uniqueAttachmentDestination(for: requested, root: root)
        let destinationPath = Self.relativePath(for: destination, root: root)
        let renamedLine = Self.renamedAttachmentLine(
            attachmentLine,
            oldPath: attachmentRelativePath,
            newPath: destinationPath
        )
        let updatedMarkdown = markdown.components(separatedBy: .newlines).map { line in
            if line.trimmingCharacters(in: .whitespaces)
                == attachmentLine.trimmingCharacters(in: .whitespaces) {
                return renamedLine
            }
            return line.replacingOccurrences(of: attachmentRelativePath, with: destinationPath)
        }.joined(separator: "\n")

        try coordinatedMove(from: source, to: destination)
        do {
            return try saveMarkdownDocument(
                relativePath: relativePath,
                markdown: updatedMarkdown,
                expectedMarkdown: expectedMarkdown
            )
        } catch {
            try? coordinatedMove(from: destination, to: source)
            throw error
        }
    }

    func duplicateMarkdownDocument(
        relativePath: String,
        now: Date = Date()
    ) throws -> RecentMarkdownFile {
        guard let root else { throw FolderAccessError.missingFolder }
        guard Self.isMutableNotePath(relativePath),
              let source = AuthorizedLibraryPath.resolve(relativePath, within: root),
              source.pathExtension.lowercased() == "md",
              (try? source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw MarkdownLifecycleError.protectedNote
        }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        guard fileManager.fileExists(atPath: source.path) else {
            throw MarkdownLifecycleError.noteNotFound
        }
        let stem = source.deletingPathExtension().lastPathComponent
        let requested = source.deletingLastPathComponent()
            .appendingPathComponent("\(stem) Copy.md")
        let destination = uniqueMarkdownURL(for: requested)
        try coordinatedCopy(from: source, to: destination)
        do {
            try fileManager.setAttributes(
                [.creationDate: now, .modificationDate: now],
                ofItemAtPath: destination.path
            )
            let duplicated = try recentFile(at: destination, root: root)
            invalidateAfterMutation(relativePaths: [duplicated.relativePath])
            return duplicated
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    func renameMarkdownDocument(
        relativePath: String,
        to name: String
    ) throws -> RecentMarkdownFile {
        guard let root else { throw FolderAccessError.missingFolder }
        guard Self.isMutableNotePath(relativePath),
              let source = AuthorizedLibraryPath.resolve(relativePath, within: root),
              source.pathExtension.lowercased() == "md" else {
            throw MarkdownLifecycleError.protectedNote
        }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        guard fileManager.fileExists(atPath: source.path) else {
            throw MarkdownLifecycleError.noteNotFound
        }

        let stem = try Self.validatedNoteName(name)
        if source.deletingPathExtension().lastPathComponent == stem {
            return try recentFile(at: source, root: root)
        }
        let requested = source.deletingLastPathComponent()
            .appendingPathComponent("\(stem).md")
        let destination = uniqueMarkdownURL(for: requested)
        let destinationPath = Self.relativePath(for: destination, root: root)
        try coordinatedMove(from: source, to: destination)
        var linkBackups: [MarkdownLinkRewriteBackup] = []
        do {
            linkBackups = try rewriteNoteLinksAfterMove(
                from: relativePath,
                to: destinationPath,
                root: root
            )
            try replacePinnedPath(relativePath, with: destinationPath, root: root)
            let renamed = try recentFile(at: destination, root: root)
            invalidateAfterMutation(
                relativePaths: [relativePath, destinationPath] + linkBackups.map(\.relativePath)
            )
            return renamed
        } catch {
            restoreMarkdownLinkRewrites(linkBackups)
            try? coordinatedMove(from: destination, to: source)
            throw error
        }
    }

    func keepConflictCopy(relativePath: String) throws -> RecentMarkdownFile {
        guard let root else { throw FolderAccessError.missingFolder }
        guard Self.isMutableNotePath(relativePath),
              Self.isConflictCopyPath(relativePath),
              let source = AuthorizedLibraryPath.resolve(relativePath, within: root),
              source.pathExtension.lowercased() == "md" else {
            throw MarkdownLifecycleError.invalidConflictCopy
        }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        guard fileManager.fileExists(atPath: source.path) else {
            throw MarkdownLifecycleError.noteNotFound
        }
        let recoveredStem = Self.recoveredConflictStem(
            source.deletingPathExtension().lastPathComponent
        )
        let requested = source.deletingLastPathComponent()
            .appendingPathComponent("\(recoveredStem).md")
        let destination = uniqueMarkdownURL(for: requested)
        let destinationPath = Self.relativePath(for: destination, root: root)
        try coordinatedMove(from: source, to: destination)
        do {
            try replacePinnedPath(relativePath, with: destinationPath, root: root)
            let recovered = try recentFile(at: destination, root: root)
            invalidateAfterMutation(relativePaths: [relativePath, destinationPath])
            return recovered
        } catch {
            try? coordinatedMove(from: destination, to: source)
            throw error
        }
    }

    @discardableResult
    func trashMarkdownDocument(
        relativePath: String,
        now: Date = Date()
    ) throws -> TrashedMarkdownFile {
        guard let root else { throw FolderAccessError.missingFolder }
        guard Self.isTrashableNotePath(relativePath),
              let source = AuthorizedLibraryPath.resolve(relativePath, within: root),
              source.pathExtension.lowercased() == "md" else {
            throw MarkdownLifecycleError.protectedNote
        }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        guard fileManager.fileExists(atPath: source.path) else {
            throw MarkdownLifecycleError.noteNotFound
        }

        let trashID = UUID().uuidString.lowercased()
        let trashRoot = root.appendingPathComponent(".mudsnote/Trash", isDirectory: true)
        try fileManager.createDirectory(at: trashRoot, withIntermediateDirectories: true)
        let trashedFile = trashRoot.appendingPathComponent("\(trashID).md")
        let metadataURL = trashRoot.appendingPathComponent("\(trashID).json")
        let metadata = TrashedMarkdownMetadata(
            id: trashID,
            originalRelativePath: relativePath,
            title: source.deletingPathExtension().lastPathComponent,
            trashedAt: now,
            wasPinned: try loadPinnedPaths(root: root).contains(relativePath)
        )
        try JSONEncoder.mudsnote.encode(metadata).write(to: metadataURL, options: .atomic)
        do {
            try coordinatedMove(from: source, to: trashedFile)
            try removePinnedPath(relativePath, root: root)
        } catch {
            if fileManager.fileExists(atPath: trashedFile.path),
               !fileManager.fileExists(atPath: source.path) {
                try? coordinatedMove(from: trashedFile, to: source)
            }
            try? fileManager.removeItem(at: metadataURL)
            throw error
        }
        invalidateAfterMutation(relativePaths: [relativePath])
        return TrashedMarkdownFile(
            id: trashID,
            originalRelativePath: relativePath,
            title: metadata.title,
            trashedAt: now
        )
    }

    func trashMarkdownDocuments(
        relativePaths: [String],
        now: Date = Date()
    ) throws -> [TrashedMarkdownFile] {
        guard let root else { throw FolderAccessError.missingFolder }
        let paths = Array(Set(relativePaths)).sorted()
        guard !paths.isEmpty else { return [] }
        for relativePath in paths {
            guard Self.isTrashableNotePath(relativePath),
                  let source = AuthorizedLibraryPath.resolve(relativePath, within: root),
                  source.pathExtension.lowercased() == "md",
                  fileManager.fileExists(atPath: source.path) else {
                throw MarkdownLifecycleError.protectedNote
            }
        }

        var trashed: [TrashedMarkdownFile] = []
        do {
            for path in paths {
                trashed.append(try trashMarkdownDocument(relativePath: path, now: now))
            }
            return trashed
        } catch {
            var rollbackFailed = false
            for item in trashed.reversed() {
                do {
                    _ = try restoreTrashedMarkdownDocument(id: item.id)
                } catch {
                    rollbackFailed = true
                }
            }
            if rollbackFailed { throw MarkdownLifecycleError.batchRollbackFailed }
            throw error
        }
    }

    func createFolder(named name: String, parentRelativePath: String? = nil) throws -> LibraryFolderNode {
        guard let root else { throw FolderAccessError.missingFolder }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        let folderName = try Self.validatedFolderName(name)
        let parent = try userFolderURL(relativePath: parentRelativePath, root: root, allowRoot: true)
        let requested = parent.appendingPathComponent(folderName, isDirectory: true)
        let destination = uniqueFolderURL(for: requested)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        cachedLibrarySnapshot = nil
        let relativePath = Self.relativePath(for: destination, root: root)
        return LibraryFolderNode(
            relativePath: relativePath,
            name: destination.lastPathComponent,
            directNoteCount: 0,
            totalNoteCount: 0,
            children: []
        )
    }

    func renameFolder(relativePath: String, to name: String) throws -> String {
        guard let root else { throw FolderAccessError.missingFolder }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        let source = try userFolderURL(relativePath: relativePath, root: root)
        let folderName = try Self.validatedFolderName(name)
        if source.lastPathComponent == folderName { return relativePath }
        let notePaths = try markdownNotePaths(at: source, root: root)
        let requested = source.deletingLastPathComponent()
            .appendingPathComponent(folderName, isDirectory: true)
        let destination = uniqueFolderURL(for: requested)
        try coordinatedMove(from: source, to: destination)
        let newRelativePath = Self.relativePath(for: destination, root: root)
        let movedPaths = Dictionary(uniqueKeysWithValues: notePaths.map { path in
            (path, newRelativePath + path.dropFirst(relativePath.count))
        })
        var linkBackups: [MarkdownLinkRewriteBackup] = []
        do {
            linkBackups = try rewriteNoteLinksAfterMoves(movedPaths, root: root)
            try rewriteTrashedOriginalPathPrefix(
                from: relativePath,
                to: newRelativePath,
                root: root
            )
            try rewritePinnedPathPrefix(from: relativePath, to: newRelativePath, root: root)
        } catch {
            restoreMarkdownLinkRewrites(linkBackups)
            try? rewriteTrashedOriginalPathPrefix(
                from: newRelativePath,
                to: relativePath,
                root: root
            )
            try? coordinatedMove(from: destination, to: source)
            throw error
        }
        invalidatePathPrefix(relativePath)
        invalidateAfterMutation(relativePaths: linkBackups.map(\.relativePath))
        return newRelativePath
    }

    func moveFolder(relativePath: String, toParent targetParent: String?) throws -> String {
        guard let root else { throw FolderAccessError.missingFolder }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        let source = try userFolderURL(relativePath: relativePath, root: root)
        if let targetParent,
           targetParent == relativePath || targetParent.hasPrefix(relativePath + "/") {
            throw MarkdownLifecycleError.invalidFolder
        }
        let targetDirectory = try userFolderURL(
            relativePath: targetParent,
            root: root,
            allowRoot: true
        )
        if source.deletingLastPathComponent().standardizedFileURL == targetDirectory.standardizedFileURL {
            return relativePath
        }
        let notePaths = try markdownNotePaths(at: source, root: root)
        let requested = targetDirectory.appendingPathComponent(
            source.lastPathComponent,
            isDirectory: true
        )
        let destination = uniqueFolderURL(for: requested)
        try coordinatedMove(from: source, to: destination)
        let newRelativePath = Self.relativePath(for: destination, root: root)
        let movedPaths = Dictionary(uniqueKeysWithValues: notePaths.map { path in
            (path, newRelativePath + path.dropFirst(relativePath.count))
        })
        var linkBackups: [MarkdownLinkRewriteBackup] = []
        do {
            linkBackups = try rewriteNoteLinksAfterMoves(movedPaths, root: root)
            try rewriteTrashedOriginalPathPrefix(
                from: relativePath,
                to: newRelativePath,
                root: root
            )
            try rewritePinnedPathPrefix(from: relativePath, to: newRelativePath, root: root)
        } catch {
            restoreMarkdownLinkRewrites(linkBackups)
            try? rewriteTrashedOriginalPathPrefix(
                from: newRelativePath,
                to: relativePath,
                root: root
            )
            try? rewritePinnedPathPrefix(from: newRelativePath, to: relativePath, root: root)
            try? coordinatedMove(from: destination, to: source)
            throw error
        }
        invalidatePathPrefix(relativePath)
        invalidatePathPrefix(newRelativePath)
        invalidateAfterMutation(relativePaths: linkBackups.map(\.relativePath))
        return newRelativePath
    }

    func moveMarkdownDocument(
        relativePath: String,
        toFolder targetFolder: String?
    ) throws -> RecentMarkdownFile {
        guard let root else { throw FolderAccessError.missingFolder }
        guard Self.isMutableNotePath(relativePath),
              let source = AuthorizedLibraryPath.resolve(relativePath, within: root),
              source.pathExtension.lowercased() == "md" else {
            throw MarkdownLifecycleError.protectedNote
        }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        guard fileManager.fileExists(atPath: source.path) else {
            throw MarkdownLifecycleError.noteNotFound
        }
        let targetDirectory = try userFolderURL(
            relativePath: targetFolder,
            root: root,
            allowRoot: true
        )
        if source.deletingLastPathComponent().standardizedFileURL == targetDirectory.standardizedFileURL {
            return try recentFile(at: source, root: root)
        }
        let destination = uniqueMarkdownURL(
            for: targetDirectory.appendingPathComponent(source.lastPathComponent)
        )
        try coordinatedMove(from: source, to: destination)
        var linkBackups: [MarkdownLinkRewriteBackup] = []
        do {
            let moved = try recentFile(at: destination, root: root)
            linkBackups = try rewriteNoteLinksAfterMove(
                from: relativePath,
                to: moved.relativePath,
                root: root
            )
            try replacePinnedPath(relativePath, with: moved.relativePath, root: root)
            invalidateAfterMutation(
                relativePaths: [relativePath, moved.relativePath] + linkBackups.map(\.relativePath)
            )
            return moved
        } catch {
            restoreMarkdownLinkRewrites(linkBackups)
            try? coordinatedMove(from: destination, to: source)
            throw error
        }
    }

    func moveMarkdownDocuments(
        relativePaths: [String],
        toFolder targetFolder: String?
    ) throws -> [RecentMarkdownFile] {
        guard let root else { throw FolderAccessError.missingFolder }
        let paths = Array(Set(relativePaths)).sorted()
        guard !paths.isEmpty else { return [] }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        let targetDirectory = try userFolderURL(
            relativePath: targetFolder,
            root: root,
            allowRoot: true
        )
        let sources: [(path: String, url: URL)] = try paths.map { path in
            guard Self.isMutableNotePath(path),
                  let source = AuthorizedLibraryPath.resolve(path, within: root),
                  source.pathExtension.lowercased() == "md" else {
                throw MarkdownLifecycleError.protectedNote
            }
            guard fileManager.fileExists(atPath: source.path) else {
                throw MarkdownLifecycleError.noteNotFound
            }
            return (path, source)
        }
        let originalPins = try loadPinnedPaths(root: root)
        var moves: [(source: URL, destination: URL, oldPath: String, newPath: String)] = []
        var destinations: [URL] = []
        var linkBackups: [MarkdownLinkRewriteBackup] = []

        do {
            for item in sources {
                if item.url.deletingLastPathComponent().standardizedFileURL
                    == targetDirectory.standardizedFileURL {
                    destinations.append(item.url)
                    continue
                }
                let destination = uniqueMarkdownURL(
                    for: targetDirectory.appendingPathComponent(item.url.lastPathComponent)
                )
                try coordinatedMove(from: item.url, to: destination)
                let newPath = Self.relativePath(for: destination, root: root)
                moves.append((item.url, destination, item.path, newPath))
                destinations.append(destination)
            }
            linkBackups = try rewriteNoteLinksAfterMoves(
                Dictionary(uniqueKeysWithValues: moves.map { ($0.oldPath, $0.newPath) }),
                root: root
            )
            var updatedPins = originalPins
            for move in moves where updatedPins.remove(move.oldPath) != nil {
                updatedPins.insert(move.newPath)
            }
            if updatedPins != originalPins {
                try savePinnedPaths(updatedPins, root: root)
            }
            let moved = try destinations.map { try recentFile(at: $0, root: root) }
            invalidateAfterMutation(
                relativePaths: moves.flatMap { [$0.oldPath, $0.newPath] }
                    + linkBackups.map(\.relativePath)
            )
            return moved
        } catch {
            var rollbackFailed = false
            restoreMarkdownLinkRewrites(linkBackups)
            for move in moves.reversed() {
                do {
                    try coordinatedMove(from: move.destination, to: move.source)
                } catch {
                    rollbackFailed = true
                }
            }
            do {
                try savePinnedPaths(originalPins, root: root)
            } catch {
                rollbackFailed = true
            }
            invalidateAfterMutation(
                relativePaths: moves.flatMap { [$0.oldPath, $0.newPath] }
                    + linkBackups.map(\.relativePath)
            )
            if rollbackFailed { throw MarkdownLifecycleError.batchRollbackFailed }
            throw error
        }
    }

    func trashFolder(relativePath: String, now: Date = Date()) throws {
        guard let root else { throw FolderAccessError.missingFolder }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        let folder = try userFolderURL(relativePath: relativePath, root: root)
        let inventory = try folderDeletionInventory(at: folder, root: root)
        var trashed: [TrashedMarkdownFile] = []
        do {
            for notePath in inventory.notePaths {
                trashed.append(try trashMarkdownDocument(relativePath: notePath, now: now))
            }
            for directory in inventory.directoriesDeepestFirst {
                let remaining = try fileManager.contentsOfDirectory(atPath: directory.path)
                guard remaining.isEmpty else {
                    throw MarkdownLifecycleError.folderContainsUnsupportedItems
                }
                try fileManager.removeItem(at: directory)
            }
        } catch {
            for item in trashed.reversed() {
                _ = try? restoreTrashedMarkdownDocument(id: item.id)
            }
            throw error
        }
        invalidatePathPrefix(relativePath)
    }

    func restoreTrashedMarkdownDocument(id: String) throws -> RecentMarkdownFile {
        guard let root else { throw FolderAccessError.missingFolder }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        let item = try trashItem(id: id, root: root)
        guard Self.isTrashableNotePath(item.originalRelativePath),
              let requestedDestination = AuthorizedLibraryPath.resolve(item.originalRelativePath, within: root) else {
            throw MarkdownLifecycleError.invalidTrashMetadata
        }
        let destination = uniqueMarkdownURL(for: requestedDestination)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try coordinatedMove(from: item.fileURL, to: destination)
        let relativePath = Self.relativePath(for: destination, root: root)
        do {
            if item.wasPinned {
                try addPinnedPath(relativePath, root: root)
            }
            try fileManager.removeItem(at: item.metadataURL)
        } catch {
            if item.wasPinned {
                try? removePinnedPath(relativePath, root: root)
            }
            try? coordinatedMove(from: destination, to: item.fileURL)
            throw error
        }
        invalidateAfterMutation(relativePaths: [relativePath])
        let modifiedAt = try destination.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate ?? .distantPast
        return RecentMarkdownFile(
            id: relativePath,
            relativePath: relativePath,
            title: destination.deletingPathExtension().lastPathComponent,
            modifiedAt: modifiedAt
        )
    }

    func restoreTrashedMarkdownDocuments(ids: [String]) throws -> [RecentMarkdownFile] {
        guard let root else { throw FolderAccessError.missingFolder }
        let normalizedIDs = Array(Set(ids.map { $0.lowercased() })).sorted()
        guard !normalizedIDs.isEmpty else { return [] }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }

        let items = try normalizedIDs.map { id in
            let item = try trashItem(id: id, root: root)
            guard Self.isTrashableNotePath(item.originalRelativePath),
                  let requestedDestination = AuthorizedLibraryPath.resolve(
                    item.originalRelativePath,
                    within: root
                  ) else {
                throw MarkdownLifecycleError.invalidTrashMetadata
            }
            return (
                item: item,
                requestedDestination: requestedDestination,
                metadata: try Data(contentsOf: item.metadataURL)
            )
        }
        let originalPins = try loadPinnedPaths(root: root)
        var moves: [(source: URL, destination: URL, relativePath: String)] = []
        var removedMetadata: [(url: URL, data: Data)] = []

        do {
            for entry in items {
                let destination = uniqueMarkdownURL(for: entry.requestedDestination)
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try coordinatedMove(from: entry.item.fileURL, to: destination)
                moves.append((
                    entry.item.fileURL,
                    destination,
                    Self.relativePath(for: destination, root: root)
                ))
            }

            var updatedPins = originalPins
            for (index, move) in moves.enumerated() where items[index].item.wasPinned {
                updatedPins.insert(move.relativePath)
            }
            if updatedPins != originalPins {
                try savePinnedPaths(updatedPins, root: root)
            }

            for entry in items {
                try fileManager.removeItem(at: entry.item.metadataURL)
                removedMetadata.append((entry.item.metadataURL, entry.metadata))
            }

            let restored = try moves.map { try recentFile(at: $0.destination, root: root) }
            invalidateAfterMutation(relativePaths: moves.map { $0.relativePath })
            return restored
        } catch {
            var rollbackFailed = false
            for metadata in removedMetadata.reversed() {
                do {
                    try metadata.data.write(to: metadata.url, options: .atomic)
                } catch {
                    rollbackFailed = true
                }
            }
            for move in moves.reversed() {
                do {
                    try coordinatedMove(from: move.destination, to: move.source)
                } catch {
                    rollbackFailed = true
                }
            }
            do {
                try savePinnedPaths(originalPins, root: root)
            } catch {
                rollbackFailed = true
            }
            if rollbackFailed { throw MarkdownLifecycleError.batchRollbackFailed }
            throw error
        }
    }

    func permanentlyDeleteTrashedMarkdownDocument(id: String) throws {
        guard let root else { throw FolderAccessError.missingFolder }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }
        let item = try trashItem(id: id, root: root)
        try fileManager.removeItem(at: item.fileURL)
        do {
            try fileManager.removeItem(at: item.metadataURL)
        } catch {
            // A missing payload is ignored by inventory and can be cleaned on refresh.
            throw error
        }
        cachedLibrarySnapshot = nil
    }

    func permanentlyDeleteTrashedMarkdownDocuments(ids: [String]) throws {
        guard let root else { throw FolderAccessError.missingFolder }
        let normalizedIDs = Array(Set(ids.map { $0.lowercased() })).sorted()
        guard !normalizedIDs.isEmpty else { return }
        let accessed = root.startAccessingSecurityScopedResource()
        defer { if accessed { root.stopAccessingSecurityScopedResource() } }

        let items = try normalizedIDs.map { try trashItem(id: $0, root: root) }
        let trashRoot = root.appendingPathComponent(".mudsnote/Trash", isDirectory: true)
        let staging = trashRoot.appendingPathComponent(
            ".delete-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        var moves: [(source: URL, destination: URL)] = []

        do {
            for item in items {
                for source in [item.fileURL, item.metadataURL] {
                    let destination = staging.appendingPathComponent(source.lastPathComponent)
                    try coordinatedMove(from: source, to: destination)
                    moves.append((source, destination))
                }
            }
            try fileManager.removeItem(at: staging)
            cachedLibrarySnapshot = nil
        } catch {
            var rollbackFailed = false
            for move in moves.reversed() where fileManager.fileExists(atPath: move.destination.path) {
                do {
                    try coordinatedMove(from: move.destination, to: move.source)
                } catch {
                    rollbackFailed = true
                }
            }
            if fileManager.fileExists(atPath: staging.path) {
                do {
                    try fileManager.removeItem(at: staging)
                } catch {
                    rollbackFailed = true
                }
            }
            if rollbackFailed { throw MarkdownLifecycleError.batchRollbackFailed }
            throw error
        }
    }

    private func loadTrashedFiles(root: URL) throws -> [TrashedMarkdownFile] {
        let trashRoot = root.appendingPathComponent(".mudsnote/Trash", isDirectory: true)
        guard fileManager.fileExists(atPath: trashRoot.path) else { return [] }
        try recoverInterruptedPermanentDeletes(in: trashRoot)
        let urls = try fileManager.contentsOfDirectory(
            at: trashRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { metadataURL -> TrashedMarkdownFile? in
                guard let data = try? Data(contentsOf: metadataURL),
                      let metadata = try? JSONDecoder.mudsnote.decode(
                        TrashedMarkdownMetadata.self,
                        from: data
                      ),
                      UUID(uuidString: metadata.id) != nil,
                      metadata.id == metadataURL.deletingPathExtension().lastPathComponent.lowercased()
                else { return nil }
                let fileURL = trashRoot.appendingPathComponent("\(metadata.id).md")
                guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
                return TrashedMarkdownFile(
                    id: metadata.id,
                    originalRelativePath: metadata.originalRelativePath,
                    title: metadata.title,
                    trashedAt: metadata.trashedAt
                )
            }
            .sorted { $0.trashedAt > $1.trashedAt }
    }

    private func recoverInterruptedPermanentDeletes(in trashRoot: URL) throws {
        let contents = try fileManager.contentsOfDirectory(
            at: trashRoot,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        for staging in contents where staging.lastPathComponent.hasPrefix(".delete-") {
            guard (try staging.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true else {
                continue
            }
            let stagedFiles = try fileManager.contentsOfDirectory(
                at: staging,
                includingPropertiesForKeys: nil
            )
            for source in stagedFiles {
                let destination = trashRoot.appendingPathComponent(source.lastPathComponent)
                guard !fileManager.fileExists(atPath: destination.path) else { continue }
                try coordinatedMove(from: source, to: destination)
            }
            try fileManager.removeItem(at: staging)
        }
    }

    private func trashItem(id: String, root: URL) throws -> (
        originalRelativePath: String,
        wasPinned: Bool,
        fileURL: URL,
        metadataURL: URL
    ) {
        guard UUID(uuidString: id) != nil else {
            throw MarkdownLifecycleError.invalidTrashMetadata
        }
        let trashRoot = root.appendingPathComponent(".mudsnote/Trash", isDirectory: true)
        let metadataURL = trashRoot.appendingPathComponent("\(id.lowercased()).json")
        let fileURL = trashRoot.appendingPathComponent("\(id.lowercased()).md")
        guard let metadataData = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder.mudsnote.decode(
                TrashedMarkdownMetadata.self,
                from: metadataData
              ),
              metadata.id == id.lowercased(),
              fileManager.fileExists(atPath: fileURL.path) else {
            throw MarkdownLifecycleError.noteNotFound
        }
        return (metadata.originalRelativePath, metadata.wasPinned ?? false, fileURL, metadataURL)
    }

    private func coordinatedMove(from source: URL, to destination: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var moveError: Error?
        coordinator.coordinate(
            writingItemAt: source,
            options: .forMoving,
            error: &coordinationError
        ) { coordinatedSource in
            do {
                try fileManager.moveItem(at: coordinatedSource, to: destination)
            } catch {
                moveError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let moveError { throw moveError }
    }

    private func coordinatedReplaceTagData(
        at url: URL,
        relativePath: String,
        expected: Data,
        replacement: Data
    ) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var writeError: Error?
        coordinator.coordinate(
            writingItemAt: url,
            options: .forMerging,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                let current = try Data(contentsOf: coordinatedURL, options: .mappedIfSafe)
                guard current == expected else {
                    throw MarkdownTagMutationError.changedExternally(relativePath)
                }
                try replacement.write(to: coordinatedURL, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    private func coordinatedCopy(from source: URL, to destination: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var copyError: Error?
        coordinator.coordinate(
            readingItemAt: source,
            options: .withoutChanges,
            writingItemAt: destination,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedSource, coordinatedDestination in
            do {
                try fileManager.copyItem(at: coordinatedSource, to: coordinatedDestination)
            } catch {
                copyError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
    }

    private func uniqueMarkdownURL(for requested: URL) -> URL {
        guard fileManager.fileExists(atPath: requested.path) else { return requested }
        let directory = requested.deletingLastPathComponent()
        let stem = requested.deletingPathExtension().lastPathComponent
        var suffix = 2
        while true {
            let candidate = directory.appendingPathComponent("\(stem) \(suffix).md")
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            suffix += 1
        }
    }

    private func uniqueFolderURL(for requested: URL) -> URL {
        guard fileManager.fileExists(atPath: requested.path) else { return requested }
        let parent = requested.deletingLastPathComponent()
        let name = requested.lastPathComponent
        var suffix = 2
        while true {
            let candidate = parent.appendingPathComponent("\(name) \(suffix)", isDirectory: true)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            suffix += 1
        }
    }

    private func userFolderURL(
        relativePath: String?,
        root: URL,
        allowRoot: Bool = false
    ) throws -> URL {
        guard let relativePath, !relativePath.isEmpty else {
            if allowRoot { return root }
            throw MarkdownLifecycleError.invalidFolder
        }
        guard Self.isUserFolderPath(relativePath),
              let url = AuthorizedLibraryPath.resolve(relativePath, within: root),
              (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw MarkdownLifecycleError.invalidFolder
        }
        return url
    }

    private static func validatedFolderName(_ name: String) throws -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value != ".",
              value != "..",
              !value.hasPrefix("."),
              !value.contains("/"),
              !value.contains(":") else {
            throw MarkdownLifecycleError.invalidFolderName
        }
        return value
    }

    private static func validatedNoteName(_ name: String) throws -> String {
        var value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasSuffix(".md") {
            value = String(value.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !value.isEmpty,
              value != ".",
              value != "..",
              !value.hasPrefix("."),
              !value.contains("/"),
              !value.contains(":"),
              !value.contains("\n"),
              !value.contains("\r") else {
            throw MarkdownLifecycleError.invalidNoteName
        }
        return value
    }

    private static func isUserFolderPath(_ relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/")
        guard let first = components.first,
              first != "Attachments",
              first != "Daily",
              !components.contains(where: { $0.hasPrefix(".") }) else { return false }
        return true
    }

    private func recentFile(at url: URL, root: URL) throws -> RecentMarkdownFile {
        let relativePath = Self.relativePath(for: url, root: root)
        let modifiedAt = try url.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate ?? .distantPast
        return RecentMarkdownFile(
            id: relativePath,
            relativePath: relativePath,
            title: url.deletingPathExtension().lastPathComponent,
            modifiedAt: modifiedAt
        )
    }

    private func modificationDate(for url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func folderDeletionInventory(
        at folder: URL,
        root: URL
    ) throws -> (notePaths: [String], directoriesDeepestFirst: [URL]) {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { throw MarkdownLifecycleError.invalidFolder }
        var notes: [String] = []
        var directories = [folder]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                throw MarkdownLifecycleError.folderContainsUnsupportedItems
            }
            if values.isDirectory == true {
                directories.append(url)
            } else if values.isRegularFile == true, url.pathExtension.lowercased() == "md" {
                notes.append(Self.relativePath(for: url, root: root))
            } else {
                throw MarkdownLifecycleError.folderContainsUnsupportedItems
            }
        }
        directories.sort { $0.pathComponents.count > $1.pathComponents.count }
        return (notes.sorted(), directories)
    }

    private func markdownNotePaths(at folder: URL, root: URL) throws -> [String] {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var paths: [String] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if values.isRegularFile == true, url.pathExtension.lowercased() == "md" {
                paths.append(Self.relativePath(for: url, root: root))
            }
        }
        return paths.sorted()
    }

    private func rewriteTrashedOriginalPathPrefix(
        from oldPrefix: String,
        to newPrefix: String,
        root: URL
    ) throws {
        let trashRoot = root.appendingPathComponent(".mudsnote/Trash", isDirectory: true)
        guard fileManager.fileExists(atPath: trashRoot.path) else { return }
        var updates: [(url: URL, original: Data, updated: Data)] = []
        for metadataURL in try fileManager.contentsOfDirectory(at: trashRoot, includingPropertiesForKeys: nil)
            where metadataURL.pathExtension.lowercased() == "json" {
            let data = try Data(contentsOf: metadataURL)
            var metadata = try JSONDecoder.mudsnote.decode(TrashedMarkdownMetadata.self, from: data)
            guard metadata.originalRelativePath.hasPrefix(oldPrefix + "/") else { continue }
            metadata.originalRelativePath = newPrefix + metadata.originalRelativePath.dropFirst(oldPrefix.count)
            updates.append((metadataURL, data, try JSONEncoder.mudsnote.encode(metadata)))
        }
        var written: [(url: URL, original: Data)] = []
        do {
            for update in updates {
                try update.updated.write(to: update.url, options: .atomic)
                written.append((update.url, update.original))
            }
        } catch {
            for update in written.reversed() {
                try? update.original.write(to: update.url, options: .atomic)
            }
            throw error
        }
    }

    private func rewriteNoteLinksAfterMove(
        from oldPath: String,
        to newPath: String,
        root: URL
    ) throws -> [MarkdownLinkRewriteBackup] {
        try rewriteNoteLinksAfterMoves([oldPath: newPath], root: root)
    }

    private func rewriteNoteLinksAfterMoves(
        _ movedPaths: [String: String],
        root: URL
    ) throws -> [MarkdownLinkRewriteBackup] {
        guard !movedPaths.isEmpty else { return [] }
        let originalPathByCurrentPath = Dictionary(
            uniqueKeysWithValues: movedPaths.map { ($0.value, $0.key) }
        )
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var updates: [(backup: MarkdownLinkRewriteBackup, updated: Data)] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isDirectory != true,
                  values.isRegularFile == true,
                  url.pathExtension.lowercased() == "md" else { continue }
            let currentPath = Self.relativePath(for: url, root: root)
            let sourceBefore = originalPathByCurrentPath[currentPath] ?? currentPath
            let originalData = try Data(contentsOf: url, options: .mappedIfSafe)
            guard let markdown = String(data: originalData, encoding: .utf8) else { continue }
            let rewritten = MarkdownNoteLink.rewritingLinks(
                in: markdown,
                sourceBefore: sourceBefore,
                sourceAfter: currentPath,
                movedPaths: movedPaths
            )
            guard rewritten != markdown,
                  let updatedData = rewritten.data(using: .utf8) else { continue }
            updates.append((
                MarkdownLinkRewriteBackup(
                    url: url,
                    relativePath: currentPath,
                    data: originalData
                ),
                updatedData
            ))
        }

        var written: [MarkdownLinkRewriteBackup] = []
        do {
            for update in updates {
                try update.updated.write(to: update.backup.url, options: .atomic)
                written.append(update.backup)
            }
            return written
        } catch {
            restoreMarkdownLinkRewrites(written)
            throw error
        }
    }

    private func restoreMarkdownLinkRewrites(_ backups: [MarkdownLinkRewriteBackup]) {
        for backup in backups.reversed() {
            try? backup.data.write(to: backup.url, options: .atomic)
        }
    }

    private func invalidatePathPrefix(_ prefix: String) {
        cachedLibrarySnapshot = nil
        searchCache = searchCache.filter { !$0.key.hasPrefix(prefix + "/") && $0.key != prefix }
        listMetadataCache = listMetadataCache.filter {
            !$0.key.hasPrefix(prefix + "/") && $0.key != prefix
        }
    }

    private func loadPinnedPaths(root: URL) throws -> Set<String> {
        let url = root.appendingPathComponent(".mudsnote/pins.json")
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 1_048_576,
              let paths = try? JSONDecoder().decode([String].self, from: Data(contentsOf: url))
        else { return [] }
        return Set(paths.filter(Self.isPinnableNotePath))
    }

    private func loadSmartFolders(root: URL) throws -> [SmartFolderDefinition] {
        let url = root.appendingPathComponent(".mudsnote/smart-folders.json")
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 1_048_576 else {
            throw SmartFolderStoreError.damagedConfiguration
        }
        do {
            let configuration = try JSONDecoder.mudsnote.decode(
                SmartFolderConfiguration.self,
                from: Data(contentsOf: url)
            )
            guard configuration.version == 1 else {
                throw SmartFolderStoreError.damagedConfiguration
            }
            let normalized = configuration.folders.compactMap(\.normalized)
            let ids = Set(normalized.map(\.id))
            let names = Set(normalized.map { SmartFolderDefinition.tagKey($0.name) })
            guard normalized.count == configuration.folders.count,
                  ids.count == normalized.count,
                  names.count == normalized.count else {
                throw SmartFolderStoreError.damagedConfiguration
            }
            return normalized.sorted(by: Self.smartFolderOrder)
        } catch let error as SmartFolderStoreError {
            throw error
        } catch {
            throw SmartFolderStoreError.damagedConfiguration
        }
    }

    private func saveSmartFolders(
        _ folders: [SmartFolderDefinition],
        root: URL
    ) throws {
        let url = root.appendingPathComponent(".mudsnote/smart-folders.json")
        let configuration = SmartFolderConfiguration(version: 1, folders: folders)
        try JSONEncoder.mudsnote.encode(configuration).write(to: url, options: .atomic)
    }

    private static func sameSmartFolderName(_ lhs: String, _ rhs: String) -> Bool {
        SmartFolderDefinition.tagKey(lhs) == SmartFolderDefinition.tagKey(rhs)
    }

    private static func smartFolderOrder(
        _ lhs: SmartFolderDefinition,
        _ rhs: SmartFolderDefinition
    ) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func savePinnedPaths(_ paths: Set<String>, root: URL) throws {
        let url = root.appendingPathComponent(".mudsnote/pins.json")
        let data = try JSONEncoder().encode(paths.sorted())
        try data.write(to: url, options: .atomic)
    }

    private func addPinnedPath(_ path: String, root: URL) throws {
        var pins = try loadPinnedPaths(root: root)
        pins.insert(path)
        try savePinnedPaths(pins, root: root)
    }

    private func removePinnedPath(_ path: String, root: URL) throws {
        var pins = try loadPinnedPaths(root: root)
        guard pins.remove(path) != nil else { return }
        try savePinnedPaths(pins, root: root)
    }

    private func replacePinnedPath(_ oldPath: String, with newPath: String, root: URL) throws {
        var pins = try loadPinnedPaths(root: root)
        guard pins.remove(oldPath) != nil else { return }
        pins.insert(newPath)
        try savePinnedPaths(pins, root: root)
    }

    private func rewritePinnedPathPrefix(from oldPrefix: String, to newPrefix: String, root: URL) throws {
        let pins = try loadPinnedPaths(root: root)
        let updated = Set(pins.map { path in
            path.hasPrefix(oldPrefix + "/")
                ? newPrefix + path.dropFirst(oldPrefix.count)
                : path
        })
        guard updated != pins else { return }
        try savePinnedPaths(updated, root: root)
    }

    private static func notesOrder(_ lhs: RecentMarkdownFile, _ rhs: RecentMarkdownFile) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
    }

    private static func inboxAttachmentOwners(
        in items: [MemoBlock]
    ) -> [String: [LibraryAttachment.Owner]] {
        var owners: [String: [LibraryAttachment.Owner]] = [:]
        for memo in items {
            let owner = LibraryAttachment.Owner(
                id: "memo:\(memo.id)",
                title: String(memo.preview.prefix(80)),
                destination: .memo(memo.id)
            )
            for path in MarkdownAttachmentSearch.relativePaths(in: memo.body) {
                owners[path, default: []].append(owner)
            }
        }
        return owners
    }

    private func invalidateAfterMutation(relativePaths: [String]) {
        cachedLibrarySnapshot = nil
        for path in relativePaths {
            searchCache.removeValue(forKey: path)
            listMetadataCache.removeValue(forKey: path)
        }
    }

    private static func isMutableNotePath(_ relativePath: String) -> Bool {
        guard relativePath != "Inbox.md",
              !relativePath.hasPrefix("Daily/"),
              !relativePath.hasPrefix("Attachments/"),
              !relativePath.hasPrefix(".mudsnote/") else { return false }
        return true
    }

    private static func isTrashableNotePath(_ relativePath: String) -> Bool {
        relativePath != "Inbox.md"
            && !relativePath.hasPrefix("Attachments/")
            && !relativePath.hasPrefix(".mudsnote/")
            && relativePath.hasSuffix(".md")
    }

    static func isConflictCopyPath(_ relativePath: String) -> Bool {
        guard relativePath.lowercased().hasSuffix(".md") else { return false }
        let stem = ((relativePath as NSString).lastPathComponent as NSString)
            .deletingPathExtension
            .lowercased()
        return stem.contains("conflicted copy")
            || stem.hasSuffix(" conflict")
            || stem.hasSuffix(" conflicted")
            || stem.hasSuffix("-conflict")
            || stem.hasSuffix("_conflict")
            || stem.hasSuffix(" (conflict)")
            || stem.hasSuffix(" (conflicted)")
    }

    static func recoveredConflictStem(_ filenameStem: String) -> String {
        var value = filenameStem
        if let marker = value.range(
            of: "conflicted copy",
            options: [.caseInsensitive, .diacriticInsensitive]
        ) {
            value = String(value[..<marker.lowerBound])
        } else {
            value = value.replacingOccurrences(
                of: #"(?i)(?:[ _-]+|\s*\()(?:conflict|conflicted)\)?\s*$"#,
                with: "",
                options: .regularExpression
            )
        }
        value = value.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines
                .union(CharacterSet(charactersIn: "-_(."))
        )
        return value.isEmpty ? "Recovered Note" : String(value.prefix(80))
    }

    private static func isGeneratedUntitledNotePath(_ relativePath: String) -> Bool {
        let stem = (relativePath as NSString).lastPathComponent
            .replacingOccurrences(of: ".md", with: "")
        return stem == "Untitled Note"
            || stem.range(of: #"^Untitled Note [0-9]+$"#, options: .regularExpression) != nil
    }

    private static func portableNoteFilenameStem(from markdown: String) -> String {
        let title = MarkdownListMetadata.extract(
            from: markdown,
            fallbackTitle: "Untitled Note"
        ).title
        var value = title.replacingOccurrences(
            of: #"[/\\:?*|\"<>]+"#,
            with: "-",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        value = value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        if value.hasPrefix(".") { value.removeFirst() }
        let bounded = String(value.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
        return bounded.isEmpty ? "Untitled Note" : bounded
    }

    private static func isPinnableNotePath(_ relativePath: String) -> Bool {
        relativePath != "Inbox.md"
            && !relativePath.hasPrefix("Attachments/")
            && !relativePath.hasPrefix(".mudsnote/")
            && relativePath.hasSuffix(".md")
    }

    private func boundedSearchText(from url: URL) throws -> String {
        let maximumBytes = 32 * 1_024 * 1_024
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private func metadataForList(
        relativePath: String,
        url: URL,
        modifiedAt: Date,
        byteCount: Int
    ) throws -> MarkdownListMetadata {
        if let cached = listMetadataCache[relativePath],
           cached.modifiedAt == modifiedAt,
           cached.byteCount == byteCount {
            return cached.metadata
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 64 * 1_024) ?? Data()
        let markdown = String(decoding: data, as: UTF8.self)
        let metadata = MarkdownListMetadata.extract(
            from: markdown,
            fallbackTitle: url.deletingPathExtension().lastPathComponent
        )
        listMetadataCache[relativePath] = ListMetadataCacheEntry(
            modifiedAt: modifiedAt,
            byteCount: byteCount,
            metadata: metadata
        )
        trimListMetadataCacheIfNeeded()
        return metadata
    }

    private func trimListMetadataCacheIfNeeded() {
        let maximumEntries = 2_048
        guard listMetadataCache.count > maximumEntries else { return }
        let overflow = listMetadataCache.count - maximumEntries
        let oldestKeys = listMetadataCache
            .sorted { $0.value.modifiedAt < $1.value.modifiedAt }
            .prefix(overflow)
            .map(\.key)
        for key in oldestKeys {
            listMetadataCache.removeValue(forKey: key)
        }
    }

    private func trimSearchCacheIfNeeded() {
        let maximumEntries = 64
        guard searchCache.count > maximumEntries else { return }
        let overflow = searchCache.count - maximumEntries
        let oldestKeys = searchCache
            .sorted { $0.value.modifiedAt < $1.value.modifiedAt }
            .prefix(overflow)
            .map(\.key)
        for key in oldestKeys {
            searchCache.removeValue(forKey: key)
        }
    }

    func performPendingWrite(_ pending: PendingWrite) async throws {
        guard let root else { throw FolderAccessError.missingFolder }
        guard let target = AuthorizedLibraryPath.resolve(pending.targetRelativePath, within: root),
              target.pathExtension.lowercased() == "md" else {
            throw PendingWriteValidationError.invalidTargetPath
        }
        guard !pending.markdownBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PendingWriteValidationError.invalidMarkdown
        }

        let validatedAttachments = try pending.attachments.map { attachment in
            guard let url = AuthorizedLibraryPath.resolve(
                attachment.relativePath,
                within: root,
                constrainedTo: "Attachments"
            ) else {
                throw PendingWriteValidationError.invalidAttachmentPath
            }
            guard let data = Data(base64Encoded: attachment.base64Data), !data.isEmpty else {
                throw PendingWriteValidationError.invalidAttachmentData
            }
            return (url: url, data: data)
        }
        let accessed = root.startAccessingSecurityScopedResource()
        defer {
            if accessed { root.stopAccessingSecurityScopedResource() }
        }

        for attachment in validatedAttachments {
            let attachmentURL = attachment.url
            try fileManager.createDirectory(
                at: attachmentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard !fileManager.fileExists(atPath: attachmentURL.path) else { continue }
            try attachment.data.write(to: attachmentURL, options: .atomic)
        }

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

    private func uniqueAttachmentDestination(for requestedURL: URL, root: URL) -> URL {
        guard fileManager.fileExists(atPath: requestedURL.path) else { return requestedURL }
        let folder = requestedURL.deletingLastPathComponent()
        let base = requestedURL.deletingPathExtension().lastPathComponent
        let fileExtension = requestedURL.pathExtension
        var index = 2
        while true {
            let name = fileExtension.isEmpty
                ? "\(base)-\(index)"
                : "\(base)-\(index).\(fileExtension)"
            let candidate = folder.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate.path),
               candidate.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") {
                return candidate
            }
            index += 1
        }
    }

    private static func validatedAttachmentBaseName(
        _ name: String,
        preservingExtension fileExtension: String
    ) throws -> String {
        var value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"
        if !suffix.isEmpty, value.lowercased().hasSuffix(suffix.lowercased()) {
            value.removeLast(suffix.count)
        }
        guard !value.isEmpty,
              value.count <= 120,
              value != ".",
              value != "..",
              !value.hasPrefix("."),
              !value.contains("/"),
              !value.contains(":"),
              value.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw MarkdownDocumentError.invalidAttachmentName
        }
        return value
    }

    private static func renamedAttachmentLine(
        _ line: String,
        oldPath: String,
        newPath: String
    ) -> String {
        if line.hasPrefix("![[") {
            return line.replacingOccurrences(of: oldPath, with: newPath)
        }
        guard line.range(of: "](") != nil else {
            return line.replacingOccurrences(of: oldPath, with: newPath)
        }
        let prefix = line.hasPrefix("![") ? "![" : "["
        let indentation = String(line.prefix { $0 == " " || $0 == "\t" })
        let displayName = (newPath as NSString).lastPathComponent
        return "\(indentation)\(prefix)\(displayName)](\(newPath))"
    }

    private func attachmentIsReferencedOutsideDocument(
        _ attachmentPath: String,
        documentRelativePath: String,
        root: URL
    ) throws -> Bool {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return false }
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "md" {
            guard Self.relativePath(for: url, root: root) != documentRelativePath else { continue }
            if try String(contentsOf: url, encoding: .utf8).contains(attachmentPath) {
                return true
            }
        }
        return false
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

struct TrashedMarkdownFile: Identifiable, Equatable {
    var id: String
    var originalRelativePath: String
    var title: String
    var trashedAt: Date
}

private struct TrashedMarkdownMetadata: Codable {
    var id: String
    var originalRelativePath: String
    var title: String
    var trashedAt: Date
    var wasPinned: Bool?
}

struct LibraryFolderNode: Identifiable, Equatable {
    var relativePath: String
    var name: String
    var directNoteCount: Int
    var totalNoteCount: Int
    var children: [LibraryFolderNode]

    var id: String { relativePath }

    var isMergedInboxFolder: Bool {
        let normalized = name
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let unprefixed = normalized.drop {
            $0.isNumber || $0 == "-" || $0 == "_" || $0 == " "
        }
        return unprefixed == "inbox" || unprefixed == "收件箱" || unprefixed == "收件"
    }

    static func makeTree(
        directoryPaths: some Sequence<String>,
        files: [RecentMarkdownFile]
    ) -> [LibraryFolderNode] {
        let excludedRoots: Set<String> = ["Attachments", "Daily"]
        var paths = Set<String>()

        func includeAncestors(of rawPath: String) {
            let components = rawPath
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            guard let root = components.first,
                  !excludedRoots.contains(root),
                  !root.hasPrefix(".") else { return }

            for depth in 1...components.count {
                let candidate = components.prefix(depth).joined(separator: "/")
                guard !candidate.split(separator: "/").contains(where: { $0.hasPrefix(".") }) else {
                    break
                }
                paths.insert(candidate)
            }
        }

        for path in directoryPaths {
            includeAncestors(of: path)
        }
        for file in files {
            let parent = (file.relativePath as NSString).deletingLastPathComponent
            guard parent != ".", !parent.isEmpty else { continue }
            includeAncestors(of: parent)
        }

        let directCounts = files.reduce(into: [String: Int]()) { counts, file in
            let parent = (file.relativePath as NSString).deletingLastPathComponent
            guard paths.contains(parent) else { return }
            counts[parent, default: 0] += 1
        }

        let childrenByParent = paths.reduce(into: [String: [String]]()) { children, path in
            let rawParent = (path as NSString).deletingLastPathComponent
            let parent = rawParent == "." ? "" : rawParent
            children[parent, default: []].append(path)
        }

        func nodes(parent: String?) -> [LibraryFolderNode] {
            childrenByParent[parent ?? "", default: []]
                .map { path in
                    let children = nodes(parent: path)
                    let directCount = directCounts[path, default: 0]
                    return LibraryFolderNode(
                        relativePath: path,
                        name: (path as NSString).lastPathComponent,
                        directNoteCount: directCount,
                        totalNoteCount: directCount + children.reduce(0) { $0 + $1.totalNoteCount },
                        children: children
                    )
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }

        return nodes(parent: nil)
    }
}

struct LibraryAttachment: Identifiable, Equatable {
    var id: String
    var relativePath: String
    var fileName: String
    var modifiedAt: Date
    var byteCount: Int64
    var kind: Kind
    var owners: [Owner] = []

    struct Owner: Identifiable, Equatable {
        var id: String
        var title: String
        var destination: Destination
    }

    enum Destination: Equatable {
        case file(String)
        case memo(String)
    }

    enum Kind: Equatable {
        case image
        case video
        case audio
        case other

        init(fileExtension: String) {
            switch fileExtension.lowercased() {
            case "png", "jpg", "jpeg", "heic", "gif", "webp", "tif", "tiff":
                self = .image
            case "mov", "mp4", "m4v":
                self = .video
            case "m4a", "wav", "mp3", "aac", "caf", "aif", "aiff":
                self = .audio
            default:
                self = .other
            }
        }

        var systemImage: String {
            switch self {
            case .image: "photo"
            case .video: "video"
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
    var modifiedAt: Date? = nil
    var isNew = false
}

enum MarkdownDocumentError: LocalizedError, Equatable {
    case invalidPath
    case changedExternally
    case attachmentReferenceNotFound
    case invalidAttachmentName
    case attachmentReferencedElsewhere

    var errorDescription: String? {
        switch self {
        case .invalidPath:
            String(localized: "This Markdown file is outside the authorized library.")
        case .changedExternally:
            String(localized: "This note changed elsewhere. Reopen it before editing again.")
        case .attachmentReferenceNotFound:
            String(localized: "This attachment is no longer referenced by the note.")
        case .invalidAttachmentName:
            String(localized: "Enter a valid attachment name.")
        case .attachmentReferencedElsewhere:
            String(localized: "This attachment is also used by another note and cannot be renamed safely.")
        }
    }
}

enum CaptureDraftError: LocalizedError, Equatable {
    case empty

    var errorDescription: String? {
        String(localized: "Add text or an attachment before saving.")
    }
}

enum PendingWriteValidationError: LocalizedError, Equatable {
    case invalidTargetPath
    case invalidAttachmentPath
    case invalidAttachmentData
    case invalidMarkdown

    var errorDescription: String? {
        String(localized: "A pending capture is damaged and was not written.")
    }
}

struct PreparedAttachmentPreview: Identifiable, Equatable, Sendable {
    var url: URL
    var relativePath: String
    var originalDigest: Data

    var id: String { "\(relativePath)|\(url.path)" }
    var isPDF: Bool { url.pathExtension.lowercased() == "pdf" }
}

enum AttachmentPreviewError: LocalizedError, Equatable {
    case invalidPath
    case unsupportedEditing
    case changedExternally

    var errorDescription: String? {
        switch self {
        case .invalidPath:
            String(localized: "This attachment is outside the authorized library.")
        case .unsupportedEditing:
            String(localized: "Only PDF attachments can be marked up here.")
        case .changedExternally:
            String(localized: "This attachment changed in another app. Reopen it before marking it up.")
        }
    }
}

struct LibrarySummary: Equatable {
    var allNotesCount = 0
    var inboxCount = 0
    var dailyCount = 0
    var attachmentCount = 0
    var recentlyDeletedCount = 0
}

struct MarkdownTagMutationResult: Equatable {
    var sourceTag: String
    var replacementTag: String?
    var changedPaths: [String]
    var occurrenceCount: Int
}

enum MarkdownTagMutationError: LocalizedError, Equatable {
    case invalidTag
    case notFound
    case changedExternally(String)
    case rollbackFailed

    var errorDescription: String? {
        switch self {
        case .invalidTag:
            String(localized: "Enter a valid tag name.")
        case .notFound:
            String(localized: "This tag is no longer used by any active note.")
        case .changedExternally:
            String(localized: "A note changed elsewhere before the tag update completed.")
        case .rollbackFailed:
            String(localized: "Some tag changes could not be restored after the update failed.")
        }
    }
}

enum MarkdownLifecycleError: LocalizedError, Equatable {
    case protectedNote
    case noteNotFound
    case invalidTrashMetadata
    case invalidFolder
    case invalidFolderName
    case invalidNoteName
    case folderContainsUnsupportedItems
    case invalidConflictCopy
    case batchRollbackFailed

    var errorDescription: String? {
        switch self {
        case .protectedNote:
            String(localized: "Inbox cannot be deleted.")
        case .noteNotFound:
            String(localized: "This note is no longer available.")
        case .invalidTrashMetadata:
            String(localized: "This deleted note has invalid recovery information.")
        case .invalidFolder:
            String(localized: "This folder is no longer available.")
        case .invalidFolderName:
            String(localized: "Enter a valid folder name.")
        case .invalidNoteName:
            String(localized: "Enter a valid note name.")
        case .folderContainsUnsupportedItems:
            String(localized: "This folder contains files Mudsnote will not delete.")
        case .invalidConflictCopy:
            String(localized: "This file is not a recoverable conflict copy.")
        case .batchRollbackFailed:
            String(localized: "Some selected notes could not be restored after the operation failed.")
        }
    }
}

private extension JSONEncoder {
    static var mudsnote: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var mudsnote: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum InboxMutation: Equatable {
    case delete(memoID: String)
    case pin(memoID: String)
    case addTag(memoID: String, tag: String)
    case replaceBody(memoID: String, expectedBody: String, newBody: String)

    var memoID: String {
        switch self {
        case .delete(let memoID), .pin(let memoID), .addTag(let memoID, _), .replaceBody(let memoID, _, _): memoID
        }
    }
}

enum InboxMutationError: LocalizedError, Equatable {
    case memoNotFound
    case memoChanged

    var errorDescription: String? {
        String(localized: "The memo changed before this action completed. Refresh and try again.")
    }
}

extension MarkdownAttachmentReference {
    var markdownLine: String {
        switch kind {
        case .image:
            return "![Image](\(relativePath))"
        case .video:
            return "[Video](\(relativePath))"
        case .audio:
            return "[Audio](\(relativePath))"
        case .file:
            return "[\((relativePath as NSString).lastPathComponent)](\(relativePath))"
        }
    }
}
