import Foundation
import Testing
@testable import MudsnoteCore

struct MudsnoteCoreTests {
    @Test
    func saveUpdateAndRecentFilesWork() throws {
        let harness = try TestHarness()
        let store = harness.store

        store.notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        let firstURL = try store.saveNewNote(title: "First Note", body: "hello", tags: ["inbox"])
        #expect(FileManager.default.fileExists(atPath: firstURL.path))

        let archiveDirectory = harness.root.appendingPathComponent("Archive", isDirectory: true)
        let movedURL = try store.updateNote(at: firstURL, title: "Moved Note", body: "updated", tags: ["archive", "inbox"], in: archiveDirectory)

        #expect(!FileManager.default.fileExists(atPath: firstURL.path))
        #expect(FileManager.default.fileExists(atPath: movedURL.path))
        #expect(movedURL.deletingLastPathComponent() == archiveDirectory)

        let loaded = try store.loadNote(at: movedURL)
        #expect(loaded.title == "Moved Note")
        #expect(loaded.body == "updated")
        #expect(loaded.tags == ["archive", "inbox"])

        let recents = store.listRecentFiles(limit: 5)
        #expect(recents.first?.url == movedURL)
    }

    @Test
    func inPlaceUpdatePreservesExternalMarkdownPathAndExtension() throws {
        let harness = try TestHarness()
        let store = harness.store
        let externalURL = harness.root.appendingPathComponent("External Document.markdown")
        try "# Original\n\nBody\n".write(to: externalURL, atomically: true, encoding: .utf8)

        let savedURL = try store.updateNoteInPlace(
            at: externalURL,
            title: "Renamed Heading",
            body: "Updated body"
        )

        #expect(savedURL == externalURL.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: externalURL.path))
        #expect(!FileManager.default.fileExists(atPath: harness.root.appendingPathComponent("Renamed Heading.md").path))
        let loaded = try store.loadNote(at: externalURL)
        #expect(loaded.title == "Renamed Heading")
        #expect(loaded.body == "Updated body")
    }

    @Test
    func inPlaceUpdateDoesNotReplaceUnreadableDocument() throws {
        let harness = try TestHarness()
        let store = harness.store
        let noteURL = harness.root.appendingPathComponent("Unreadable.md")
        let invalidUTF8 = Data([0xFF, 0xFE, 0xFD])
        try invalidUTF8.write(to: noteURL)

        #expect(throws: Error.self) {
            _ = try store.updateNoteInPlace(
                at: noteURL,
                title: "Replacement",
                body: "Must not replace the original"
            )
        }
        #expect(try Data(contentsOf: noteURL) == invalidUTF8)
    }

    @Test
    func inPlaceUpdateDoesNotRecreateMissingDocument() throws {
        let harness = try TestHarness()
        let store = harness.store
        let noteURL = harness.root.appendingPathComponent("Deleted.md")
        try "# Deleted\n\nOriginal\n".write(to: noteURL, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: noteURL)

        #expect(throws: Error.self) {
            _ = try store.updateNoteInPlace(
                at: noteURL,
                title: "Replacement",
                body: "Must not recreate the deleted note"
            )
        }
        #expect(!FileManager.default.fileExists(atPath: noteURL.path))
    }

    @Test
    func noteUpdatePreservesUnknownFrontMatterAndOnlyRewritesTags() throws {
        let harness = try TestHarness()
        let store = harness.store
        let noteURL = harness.root.appendingPathComponent("Front Matter.md")
        let original = """
        ---
        layout: note
        aliases:
          - Alpha
        # keep this comment
        tags: [old, legacy]
        published: false
        nested:
          owner: me
        ---
        # Original

        Original body
        """
        try original.write(to: noteURL, atomically: true, encoding: .utf8)
        #expect(try store.loadNote(at: noteURL).tags == ["old", "legacy"])

        _ = try store.updateNoteInPlace(
            at: noteURL,
            title: "Updated",
            body: "Updated body",
            tags: ["new", "second"]
        )

        let expected = """
        ---
        layout: note
        aliases:
          - Alpha
        # keep this comment
        tags:
          - new
          - second
        published: false
        nested:
          owner: me
        ---

        # Updated

        Updated body

        """
        #expect(try String(contentsOf: noteURL, encoding: .utf8) == expected)
    }

    @Test
    func clearingTagsPreservesFrontMatterCommentsAndUnknownFields() throws {
        let harness = try TestHarness()
        let store = harness.store
        let noteURL = harness.root.appendingPathComponent("Clear Tags.md")
        try """
        ---
        category: reference
        tags:
          # keep managed-field context
          - old
        custom: yes
        ---
        # Original
        """.write(to: noteURL, atomically: true, encoding: .utf8)

        _ = try store.updateNoteInPlace(
            at: noteURL,
            title: "Original",
            body: "",
            tags: []
        )

        let updated = try String(contentsOf: noteURL, encoding: .utf8)
        #expect(updated.contains("category: reference"))
        #expect(updated.contains("# keep managed-field context"))
        #expect(updated.contains("custom: yes"))
        #expect(!updated.contains("tags:"))
        #expect(!updated.contains("- old"))
    }

    @Test
    func managedUpdatesPreserveMarkdownAndTextExtensions() throws {
        for pathExtension in ["markdown", "txt"] {
            let harness = try TestHarness()
            let store = harness.store
            let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
            try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
            let originalURL = notesDirectory
                .appendingPathComponent("Original")
                .appendingPathExtension(pathExtension)
            try "# Original\n\nBody\n".write(to: originalURL, atomically: true, encoding: .utf8)

            let updatedURL = try store.updateNote(
                at: originalURL,
                title: "Renamed",
                body: "Updated body"
            )

            #expect(updatedURL.pathExtension == pathExtension)
            #expect(updatedURL.deletingPathExtension().lastPathComponent.hasSuffix("-renamed"))
            #expect(!FileManager.default.fileExists(atPath: originalURL.path))
            #expect(try store.loadNote(at: updatedURL).body == "Updated body")
        }
    }

    @Test
    func failedManagedUpdateRollsBackDestinationAndPreservesSource() throws {
        for checkpoint in [
            NoteUpdateCommitCheckpoint.afterStaging,
            NoteUpdateCommitCheckpoint.afterDestinationCommit
        ] {
            let harness = try TestHarness()
            let store = harness.store
            let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
            let archiveDirectory = harness.root.appendingPathComponent("Archive", isDirectory: true)
            try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
            let originalURL = notesDirectory.appendingPathComponent("Original.markdown")
            let originalContent = "# Original\n\nOriginal body\n"
            try originalContent.write(to: originalURL, atomically: true, encoding: .utf8)
            store.updateNoteCommitHook = { observedCheckpoint in
                guard observedCheckpoint == checkpoint else { return }
                throw CocoaError(.fileWriteUnknown)
            }

            #expect(throws: CocoaError.self) {
                _ = try store.updateNote(
                    at: originalURL,
                    title: "Renamed",
                    body: "Replacement body",
                    in: archiveDirectory
                )
            }

            #expect(FileManager.default.fileExists(atPath: originalURL.path))
            #expect(try String(contentsOf: originalURL, encoding: .utf8) == originalContent)
            #expect(!FileManager.default.fileExists(
                atPath: archiveDirectory.appendingPathComponent("Renamed.markdown").path
            ))
            let stagedFiles = (try? FileManager.default.contentsOfDirectory(
                at: archiveDirectory,
                includingPropertiesForKeys: nil
            )) ?? []
            #expect(stagedFiles.isEmpty)
        }
    }

    @Test
    func movingNoteCopiesAndRewritesRelativeAttachmentsWithoutDeletingSources() throws {
        let harness = try TestHarness()
        let store = harness.store
        let sourceDirectory = harness.root.appendingPathComponent("Source", isDirectory: true)
        let destinationDirectory = harness.root.appendingPathComponent("Destination", isDirectory: true)
        let relativeDirectory = "Attachments/2026/07"
        let sourceAttachments = sourceDirectory.appendingPathComponent(relativeDirectory, isDirectory: true)
        let destinationAttachments = destinationDirectory.appendingPathComponent(relativeDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceAttachments, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationAttachments, withIntermediateDirectories: true)

        let imageURL = sourceAttachments.appendingPathComponent("示例 图片.png")
        let pdfURL = sourceAttachments.appendingPathComponent("spec sheet.pdf")
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        let pdfData = Data("%PDF-test".utf8)
        try imageData.write(to: imageURL)
        try pdfData.write(to: pdfURL)
        try Data("existing".utf8).write(
            to: destinationAttachments.appendingPathComponent("示例 图片.png")
        )

        let noteURL = sourceDirectory.appendingPathComponent("Move Me.markdown")
        let original = """
        # Move Me

        ![Preview](<Attachments/2026/07/示例 图片.png>)
        [Specification](Attachments/2026/07/spec%20sheet.pdf)
        [Shared preview](<Attachments/2026/07/示例 图片.png>)
        [Remote](https://example.com/file.pdf)
        [Absolute](/tmp/file.pdf)
        """
        try original.write(to: noteURL, atomically: true, encoding: .utf8)

        let movedURL = try store.moveNote(at: noteURL, to: destinationDirectory)
        let movedText = try String(contentsOf: movedURL, encoding: .utf8)

        #expect(!FileManager.default.fileExists(atPath: noteURL.path))
        #expect(try Data(contentsOf: imageURL) == imageData)
        #expect(try Data(contentsOf: pdfURL) == pdfData)
        #expect(try Data(contentsOf: destinationAttachments.appendingPathComponent("示例 图片-2.png")) == imageData)
        #expect(try Data(contentsOf: destinationAttachments.appendingPathComponent("spec sheet.pdf")) == pdfData)
        #expect(movedText.contains("Attachments/2026/07/%E7%A4%BA%E4%BE%8B%20%E5%9B%BE%E7%89%87-2.png"))
        #expect(movedText.components(separatedBy: "%E7%A4%BA%E4%BE%8B%20%E5%9B%BE%E7%89%87-2.png").count == 3)
        #expect(movedText.contains("Attachments/2026/07/spec%20sheet.pdf"))
        #expect(movedText.contains("https://example.com/file.pdf"))
        #expect(movedText.contains("](/tmp/file.pdf)"))
    }

    @Test
    func failedCrossDirectoryUpdateRemovesCopiedAttachmentsAndPreservesSource() throws {
        let harness = try TestHarness()
        let store = harness.store
        let sourceDirectory = harness.root.appendingPathComponent("Source", isDirectory: true)
        let destinationDirectory = harness.root.appendingPathComponent("Destination", isDirectory: true)
        let attachmentURL = sourceDirectory
            .appendingPathComponent("Attachments/2026/07", isDirectory: true)
            .appendingPathComponent("asset.png")
        try FileManager.default.createDirectory(
            at: attachmentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([1, 2, 3]).write(to: attachmentURL)
        let noteURL = sourceDirectory.appendingPathComponent("Original.md")
        let original = "# Original\n\n![Asset](Attachments/2026/07/asset.png)\n"
        try original.write(to: noteURL, atomically: true, encoding: .utf8)
        store.updateNoteCommitHook = { checkpoint in
            guard checkpoint == .afterStaging else { return }
            throw CocoaError(.fileWriteUnknown)
        }

        #expect(throws: CocoaError.self) {
            _ = try store.updateNote(
                at: noteURL,
                title: "Moved",
                body: "![Asset](Attachments/2026/07/asset.png)",
                in: destinationDirectory
            )
        }

        #expect(try String(contentsOf: noteURL, encoding: .utf8) == original)
        #expect(try Data(contentsOf: attachmentURL) == Data([1, 2, 3]))
        #expect(!FileManager.default.fileExists(
            atPath: destinationDirectory.appendingPathComponent("Attachments").path
        ))
        #expect((try FileManager.default.contentsOfDirectory(
            at: destinationDirectory,
            includingPropertiesForKeys: nil
        )).isEmpty)
    }

    @Test
    func registeredRootSearchSessionAndTagsExcludeRecentExternalDirectories() throws {
        let harness = try TestHarness()
        let store = harness.store
        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        let externalDirectory = harness.root.appendingPathComponent(".hermes", isDirectory: true)
        let externalURL = externalDirectory.appendingPathComponent("SOUL.md")
        store.notesDirectory = notesDirectory
        _ = try store.saveNewNote(title: "Managed", body: "Library body", tags: ["library"])
        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
        try Data().write(to: externalURL)
        _ = try store.updateNoteInPlace(
            at: externalURL,
            title: "SOUL",
            body: "Hermes body",
            tags: ["hermes"]
        )

        #expect(store.listNotes(limit: 10).contains { $0.url.standardizedFileURL == externalURL.standardizedFileURL })
        let roots = store.preferredDirectories
        let session = store.makeSearchSession(roots: roots)
        #expect(session.searchNotes(query: "Hermes", limit: 10).isEmpty)
        #expect(session.searchNotes(query: "Library", limit: 10).map(\.title) == ["Managed"])
        #expect(store.knownTags(limit: 10, roots: roots) == ["library"])
    }

    @Test
    func recentFilesAreListedWithoutSynchronousFileMetadataReads() throws {
        let harness = try TestHarness()
        let missingPath = harness.root
            .appendingPathComponent("Missing External")
            .appendingPathComponent("2025-11-03-Draft.md")
            .path
        harness.defaults.set([missingPath], forKey: NoteStoreDefaultsKey.recentFiles)

        let recents = harness.store.listRecentFiles(limit: 5)
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: try #require(recents.first?.modifiedAt))

        #expect(recents.count == 1)
        #expect(recents.first?.url.path == missingPath)
        #expect(recents.first?.title == "Draft")
        #expect(components.year == 2025)
        #expect(components.month == 11)
        #expect(components.day == 3)

        harness.store.removeRecentFileReference(at: URL(fileURLWithPath: missingPath))
        #expect(harness.store.listRecentFiles(limit: 5).isEmpty)
    }

    @Test
    func libraryLayoutScaleMigrationResetsOnlyLegacyPaneWidthsOnce() throws {
        let harness = try TestHarness()
        harness.store.librarySourceColumnWidth = 320
        harness.store.libraryNoteColumnWidth = 304

        #expect(harness.store.migrateLibraryLayoutScaleIfNeeded(to: 2))
        #expect(harness.store.librarySourceColumnWidth == nil)
        #expect(harness.store.libraryNoteColumnWidth == nil)

        harness.store.librarySourceColumnWidth = 270
        harness.store.libraryNoteColumnWidth = 320
        #expect(!harness.store.migrateLibraryLayoutScaleIfNeeded(to: 2))
        #expect(harness.store.librarySourceColumnWidth == 270)
        #expect(harness.store.libraryNoteColumnWidth == 320)
    }

    @Test
    func libraryLayoutScaleMigrationReplacesOldDefaultsButPreservesCustomWidths() throws {
        let harness = try TestHarness()
        #expect(harness.store.migrateLibraryLayoutScaleIfNeeded(to: 2))
        harness.store.librarySourceColumnWidth = 250
        harness.store.libraryNoteColumnWidth = 286

        #expect(harness.store.migrateLibraryLayoutScaleIfNeeded(
            to: 3,
            replacingDefaultPaneWidths: (source: 250, note: 250)
        ))
        #expect(harness.store.librarySourceColumnWidth == nil)
        #expect(harness.store.libraryNoteColumnWidth == 286)

        harness.store.librarySourceColumnWidth = 300
        #expect(!harness.store.migrateLibraryLayoutScaleIfNeeded(
            to: 3,
            replacingDefaultPaneWidths: (source: 250, note: 250)
        ))
        #expect(harness.store.librarySourceColumnWidth == 300)
        #expect(harness.store.libraryNoteColumnWidth == 286)
    }

    @Test
    func libraryLayoutScaleMigrationTightensOnlyUntouchedNoteColumn() throws {
        let harness = try TestHarness()
        #expect(harness.store.migrateLibraryLayoutScaleIfNeeded(to: 3))
        harness.store.librarySourceColumnWidth = 220
        harness.store.libraryNoteColumnWidth = 220

        #expect(harness.store.migrateLibraryLayoutScaleIfNeeded(
            to: 4,
            replacingDefaultPaneWidths: (source: 220, note: 220)
        ))
        #expect(harness.store.librarySourceColumnWidth == nil)
        #expect(harness.store.libraryNoteColumnWidth == nil)

        let customized = try TestHarness()
        #expect(customized.store.migrateLibraryLayoutScaleIfNeeded(to: 3))
        customized.store.librarySourceColumnWidth = 280
        customized.store.libraryNoteColumnWidth = 238
        #expect(customized.store.migrateLibraryLayoutScaleIfNeeded(
            to: 4,
            replacingDefaultPaneWidths: (source: 220, note: 220)
        ))
        #expect(customized.store.librarySourceColumnWidth == 280)
        #expect(customized.store.libraryNoteColumnWidth == 238)
    }

    @Test
    func libraryLayoutScaleMigrationTightensOnlyUntouchedSourceColumn() throws {
        let defaultLayout = try TestHarness()
        #expect(defaultLayout.store.migrateLibraryLayoutScaleIfNeeded(to: 5))
        defaultLayout.store.librarySourceColumnWidth = 220
        defaultLayout.store.libraryNoteColumnWidth = 200

        #expect(defaultLayout.store.migrateLibraryLayoutScaleIfNeeded(
            to: 6,
            replacingDefaultPaneWidths: (source: 220, note: 200)
        ))
        #expect(defaultLayout.store.librarySourceColumnWidth == nil)
        #expect(defaultLayout.store.libraryNoteColumnWidth == nil)

        let customized = try TestHarness()
        #expect(customized.store.migrateLibraryLayoutScaleIfNeeded(to: 5))
        customized.store.librarySourceColumnWidth = 246
        customized.store.libraryNoteColumnWidth = 224

        #expect(customized.store.migrateLibraryLayoutScaleIfNeeded(
            to: 6,
            replacingDefaultPaneWidths: (source: 220, note: 200)
        ))
        #expect(customized.store.librarySourceColumnWidth == 246)
        #expect(customized.store.libraryNoteColumnWidth == 224)
    }

    @Test
    func libraryLayoutScaleMigrationMatchesRenderedSourceColumn() throws {
        let defaultLayout = try TestHarness()
        #expect(defaultLayout.store.migrateLibraryLayoutScaleIfNeeded(to: 6))
        defaultLayout.store.librarySourceColumnWidth = 212
        defaultLayout.store.libraryNoteColumnWidth = 200

        #expect(defaultLayout.store.migrateLibraryLayoutScaleIfNeeded(
            to: 7,
            replacingDefaultPaneWidths: (source: 212, note: 200)
        ))
        #expect(defaultLayout.store.librarySourceColumnWidth == nil)
        #expect(defaultLayout.store.libraryNoteColumnWidth == nil)

        let customized = try TestHarness()
        #expect(customized.store.migrateLibraryLayoutScaleIfNeeded(to: 6))
        customized.store.librarySourceColumnWidth = 236
        customized.store.libraryNoteColumnWidth = 218

        #expect(customized.store.migrateLibraryLayoutScaleIfNeeded(
            to: 7,
            replacingDefaultPaneWidths: (source: 212, note: 200)
        ))
        #expect(customized.store.librarySourceColumnWidth == 236)
        #expect(customized.store.libraryNoteColumnWidth == 218)
    }

    @Test
    func libraryLayoutScaleMigrationMatchesNormalizedReferenceOrigin() throws {
        let defaultLayout = try TestHarness()
        #expect(defaultLayout.store.migrateLibraryLayoutScaleIfNeeded(to: 7))
        defaultLayout.store.librarySourceColumnWidth = 205
        defaultLayout.store.libraryNoteColumnWidth = 200

        #expect(defaultLayout.store.migrateLibraryLayoutScaleIfNeeded(
            to: 8,
            replacingDefaultPaneWidths: (source: 205, note: 200)
        ))
        #expect(defaultLayout.store.librarySourceColumnWidth == nil)
        #expect(defaultLayout.store.libraryNoteColumnWidth == nil)

        let customized = try TestHarness()
        #expect(customized.store.migrateLibraryLayoutScaleIfNeeded(to: 7))
        customized.store.librarySourceColumnWidth = 236
        customized.store.libraryNoteColumnWidth = 218

        #expect(customized.store.migrateLibraryLayoutScaleIfNeeded(
            to: 8,
            replacingDefaultPaneWidths: (source: 205, note: 200)
        ))
        #expect(customized.store.librarySourceColumnWidth == 236)
        #expect(customized.store.libraryNoteColumnWidth == 218)
    }

    @Test
    func emptyMarkdownFileKeepsEditorTitleEmptyButListsByFilename() throws {
        let harness = try TestHarness()
        let store = harness.store

        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        store.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        let emptyNoteURL = notesDirectory.appendingPathComponent("New Note.md")
        try Data().write(to: emptyNoteURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_800_000_000)],
            ofItemAtPath: emptyNoteURL.path
        )

        let loaded = try store.loadNote(at: emptyNoteURL)
        #expect(loaded.title == "")
        #expect(loaded.body == "")
        #expect(loaded.tags.isEmpty)

        let listedNote = try #require(store.listNotes(limit: 10).first)
        #expect(listedNote.title == "New Note")
        #expect(listedNote.snippet == "")

        let searchResult = try #require(store.searchNotes(query: "New", limit: 10).first)
        #expect(searchResult.url.standardizedFileURL.path == emptyNoteURL.standardizedFileURL.path)
        #expect(searchResult.title == "New Note")
    }

    @Test
    func tableNotesUseReadableListPreviewText() throws {
        let harness = try TestHarness()
        let store = harness.store
        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        store.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)

        _ = try store.saveNewNote(
            title: "Table Preview",
            body: """
            | Name | Status |
            | --- | --- |
            | Mudsnote | Active |
            """
        )

        let result = try #require(store.listNotes(limit: 10).first)
        #expect(result.snippet == "Name  Status")
        #expect(!result.snippet.contains("|"))
        #expect(store.searchNotes(query: "Mudsnote", limit: 10).first?.snippet == "Mudsnote  Active")
        #expect(MarkdownEditorDocument.previewText(
            fromMarkdownLine: "- [ ] Review **Mudsnote** at [site](https://muds.top)"
        ) == "Review Mudsnote at site")
        #expect(MarkdownEditorDocument.previewText(
            fromMarkdownLine: "1. Use `Command-K` and ~~old text~~"
        ) == "Use Command-K and old text")
    }

    @Test
    func searchFindsNotesAcrossKnownRoots() throws {
        let harness = try TestHarness()
        let store = harness.store

        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        let customDirectory = harness.root.appendingPathComponent("Projects", isDirectory: true)
        store.notesDirectory = notesDirectory

        _ = try store.saveNewNote(title: "Alpha Plan", body: "shipment delta", in: notesDirectory)
        let external = try store.saveNewNote(title: "Roadmap", body: "beta launch checklist", tags: ["launch"], in: customDirectory)

        let results = store.searchNotes(query: "beta", limit: 10)
        #expect(results.contains(where: { $0.url.standardizedFileURL == external.standardizedFileURL }))
        #expect(results.first?.title == "Roadmap")
    }

    @Test
    func recentSearchExcludesLibraryFilesThatWereNeverOpened() throws {
        let harness = try TestHarness()
        let store = harness.store

        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        store.notesDirectory = notesDirectory
        let recentURL = try store.saveNewNote(title: "Recent Alpha", body: "shared search phrase")
        let externalURL = notesDirectory.appendingPathComponent("External Alpha.md")
        try "# External Alpha\n\nshared search phrase\n".write(to: externalURL, atomically: true, encoding: .utf8)

        let allResults = store.searchNotes(query: "shared search phrase", limit: 10)
        let recentResults = store.searchRecentNotes(query: "shared search phrase", limit: 10)

        #expect(Set(allResults.map { $0.url.standardizedFileURL.path }) == Set([
            recentURL.standardizedFileURL.path,
            externalURL.standardizedFileURL.path,
        ]))
        #expect(recentResults.map { $0.url.standardizedFileURL.path } == [recentURL.standardizedFileURL.path])
    }

    @Test
    func scopedSearchFiltersBeforeLimitingAndPreservesFullLibraryIndexRoots() throws {
        let harness = try TestHarness()
        let store = harness.store
        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        let projectDirectory = harness.root.appendingPathComponent("Projects", isDirectory: true)
        let inboxDirectory = notesDirectory.appendingPathComponent("Inbox", isDirectory: true)
        store.configurePreferredDirectories([notesDirectory, projectDirectory], defaultDirectory: notesDirectory)

        for index in 0..<4 {
            _ = try store.saveNewNote(
                title: "Needle \(index)",
                body: "needle needle needle",
                tags: ["other"],
                in: notesDirectory
            )
        }
        let folderMatch = try store.saveNewNote(
            title: "Project Result",
            body: "one needle",
            tags: ["focus"],
            in: projectDirectory
        )
        let inboxMatch = try store.saveNewNote(
            title: "Follow Up",
            body: "one needle",
            tags: ["inbox"],
            in: inboxDirectory
        )

        #expect(store.prewarmSearchIndex() == 6)
        let fullRoots = try #require(store.searchIndexSnapshot?.rootsKey)

        #expect(store.searchNotes(query: "needle", limit: 1, in: projectDirectory).first?.url == folderMatch)
        #expect(store.searchNotes(query: "needle", limit: 1, tagged: "focus").first?.url == folderMatch)
        #expect(store.searchInboxNotes(query: "needle", limit: 1).first?.url == inboxMatch)
        #expect(store.searchIndexSnapshot?.rootsKey == fullRoots)
        #expect(Set(store.listNotes(limit: 20).map { $0.url.standardizedFileURL.path }).count == 6)
    }

    @Test
    func searchSessionReusesValidatedSnapshotAcrossQueriesAndScopes() throws {
        let harness = try TestHarness()
        let store = harness.store
        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        let projectDirectory = harness.root.appendingPathComponent("Projects", isDirectory: true)
        let inboxDirectory = notesDirectory.appendingPathComponent("Inbox", isDirectory: true)
        store.configurePreferredDirectories([notesDirectory, projectDirectory], defaultDirectory: notesDirectory)

        let alphaURL = try store.saveNewNote(
            title: "Alpha",
            body: "shared phrase alpha",
            tags: ["focus"],
            in: inboxDirectory
        )
        let betaURL = try store.saveNewNote(
            title: "Beta",
            body: "shared phrase beta",
            tags: ["other"],
            in: projectDirectory
        )

        #expect(store.prewarmSearchIndex() == 2)
        store.searchIndexSignatureReadCountForTesting = 0
        let session = store.makeSearchSession()
        #expect(store.searchIndexSignatureReadCountForTesting == 0)

        #expect(session.searchNotes(query: "shared phrase", limit: 10).count == 2)
        #expect(session.searchNotes(query: "beta", limit: 10, in: projectDirectory).first?.url == betaURL)
        #expect(session.searchNotes(query: "alpha", limit: 10, tagged: "focus").first?.url == alphaURL)
        #expect(session.searchInboxNotes(query: "alpha", limit: 10).first?.url == alphaURL)
        #expect(session.searchRecentNotes(query: "shared phrase", limit: 10).count == 2)
        #expect(store.searchIndexSignatureReadCountForTesting == 0)
    }

    @Test
    func searchIndexRefreshesWhenMarkdownFileChanges() throws {
        let harness = try TestHarness()
        let store = harness.store

        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        store.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)
        let noteURL = try store.saveNewNote(title: "Indexed Note", body: "alpha body", tags: ["alpha"])

        #expect(store.searchNotes(query: "alpha", limit: 10).first?.url.standardizedFileURL.path == noteURL.standardizedFileURL.path)
        #expect(store.knownTags(limit: 10).contains("alpha"))

        let updatedURL = try store.updateNote(
            at: noteURL,
            title: "Indexed Note",
            body: "beta body with more content",
            tags: ["beta"]
        )

        #expect(updatedURL.standardizedFileURL.path == noteURL.standardizedFileURL.path)
        #expect(store.searchNotes(query: "alpha", limit: 10).isEmpty)
        #expect(store.searchNotes(query: "beta", limit: 10).first?.url.standardizedFileURL.path == noteURL.standardizedFileURL.path)
        #expect(!store.knownTags(limit: 10).contains("alpha"))
        #expect(store.knownTags(limit: 10).contains("beta"))
    }

    @Test
    func dirtySearchPathRefreshesEqualSizeContentWithRestoredModificationDate() throws {
        let harness = try TestHarness()
        let store = harness.store
        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        store.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)
        let noteURL = try store.saveNewNote(title: "Stable", body: "alpha")

        #expect(store.searchNotes(query: "alpha", limit: 10).count == 1)
        store.searchIndexEntryReadCountForTesting = 0
        let originalModificationDate = try #require(
            FileManager.default.attributesOfItem(atPath: noteURL.path)[.modificationDate] as? Date
        )
        let originalText = try String(contentsOf: noteURL, encoding: .utf8)
        let rewrittenText = originalText.replacingOccurrences(of: "alpha", with: "bravo")
        #expect(rewrittenText.utf8.count == originalText.utf8.count)
        let handle = try FileHandle(forWritingTo: noteURL)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(rewrittenText.utf8))
        try handle.synchronize()
        try handle.close()
        try FileManager.default.setAttributes(
            [.modificationDate: originalModificationDate],
            ofItemAtPath: noteURL.path
        )

        store.markSearchIndexDirty(at: [noteURL])
        #expect(store.searchNotes(query: "alpha", limit: 10).isEmpty)
        #expect(store.searchNotes(query: "bravo", limit: 10).first?.url == noteURL)
        #expect(store.searchIndexEntryReadCountForTesting == 1)
    }

    @Test
    func markingSearchIndexDirtyDoesNotWaitForOngoingIndexIO() throws {
        let harness = try TestHarness()
        let store = harness.store
        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        store.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)
        let noteURL = try store.saveNewNote(title: "Concurrent", body: "body")

        let buildStarted = DispatchSemaphore(value: 0)
        let allowBuildToContinue = DispatchSemaphore(value: 0)
        let buildFinished = DispatchSemaphore(value: 0)
        let dirtyMarkFinished = DispatchSemaphore(value: 0)
        store.searchIndexBuildWillReadForTesting = {
            buildStarted.signal()
            allowBuildToContinue.wait()
        }

        DispatchQueue.global(qos: .utility).async {
            _ = store.prewarmSearchIndex()
            buildFinished.signal()
        }
        try #require(buildStarted.wait(timeout: .now() + 2) == .success)

        DispatchQueue.global(qos: .userInitiated).async {
            store.markSearchIndexDirty(at: [noteURL])
            dirtyMarkFinished.signal()
        }
        let dirtyMarkCompletedWithoutWaiting = dirtyMarkFinished.wait(timeout: .now() + 1)
        allowBuildToContinue.signal()
        #expect(buildFinished.wait(timeout: .now() + 2) == .success)
        if dirtyMarkCompletedWithoutWaiting != .success {
            _ = dirtyMarkFinished.wait(timeout: .now() + 2)
        }
        store.searchIndexBuildWillReadForTesting = nil

        #expect(dirtyMarkCompletedWithoutWaiting == .success)
    }

    @Test
    func cleanSearchSnapshotDoesNotWaitForFullValidation() throws {
        let harness = try TestHarness()
        let store = harness.store
        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        store.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)
        _ = try store.saveNewNote(title: "Fast Read", body: "body")
        #expect(store.prewarmSearchIndex() == 1)

        let validationStarted = DispatchSemaphore(value: 0)
        let allowValidationToContinue = DispatchSemaphore(value: 0)
        let validationFinished = DispatchSemaphore(value: 0)
        let cleanReadFinished = DispatchSemaphore(value: 0)
        store.searchIndexBuildWillReadForTesting = {
            validationStarted.signal()
            allowValidationToContinue.wait()
        }

        DispatchQueue.global(qos: .utility).async {
            _ = store.listNotesRefreshingIndex()
            validationFinished.signal()
        }
        try #require(validationStarted.wait(timeout: .now() + 2) == .success)

        DispatchQueue.global(qos: .userInitiated).async {
            _ = store.listNotes()
            cleanReadFinished.signal()
        }
        let cleanReadCompletedWithoutWaiting = cleanReadFinished.wait(timeout: .now() + 1)
        allowValidationToContinue.signal()
        #expect(validationFinished.wait(timeout: .now() + 2) == .success)
        store.searchIndexBuildWillReadForTesting = nil

        #expect(cleanReadCompletedWithoutWaiting == .success)
    }

    @Test
    func prewarmSearchIndexBuildsReusableSnapshot() throws {
        let harness = try TestHarness()
        let store = harness.store

        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        let projectDirectory = harness.root.appendingPathComponent("Projects", isDirectory: true)
        store.configurePreferredDirectories([notesDirectory, projectDirectory], defaultDirectory: notesDirectory)

        _ = try store.saveNewNote(title: "Alpha", body: "body one", tags: ["alpha"], in: notesDirectory)
        _ = try store.saveNewNote(title: "Beta", body: "body two", tags: ["beta"], in: projectDirectory)

        #expect(store.searchIndexSnapshot == nil)
        #expect(store.prewarmSearchIndex() == 2)
        let snapshot = try #require(store.searchIndexSnapshot)
        #expect(snapshot.entries.map(\.title).sorted() == ["Alpha", "Beta"])
        #expect(store.searchNotes(query: "body two", limit: 10).first?.title == "Beta")
        #expect(store.knownTags(limit: 10) == ["alpha", "beta"])
    }

    @Test
    func libraryLaunchNoteCacheRestoresOneBoundedDocumentAcrossStoreInstances() throws {
        let harness = try TestHarness()
        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        harness.store.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)
        let noteURL = try harness.store.saveNewNote(
            title: "Instant Launch",
            body: "Visible without waiting for iCloud.",
            tags: ["launch"],
            in: notesDirectory
        )
        let document = try harness.store.loadNoteDocument(at: noteURL)
        let modifiedAt = Date(timeIntervalSince1970: 1_786_612_800)
        let createdAt = Date(timeIntervalSince1970: 1_786_526_400)
        harness.store.cacheLibraryLaunchNote(
            document,
            at: noteURL,
            modifiedAt: modifiedAt,
            createdAt: createdAt
        )

        let reloadedStore = NoteStore(
            defaults: harness.defaults,
            legacyDefaults: nil,
            fileManager: FileManager.default,
            appSupportDirectory: harness.store.appSupportDirectory
        )
        let snapshot = try #require(reloadedStore.cachedLibraryLaunchNote())

        #expect(snapshot.url == noteURL.standardizedFileURL)
        #expect(snapshot.document == document)
        #expect(snapshot.modifiedAt == modifiedAt)
        #expect(snapshot.createdAt == createdAt)
    }

    @Test
    func libraryPresentationCacheRestoresCountsAndTagsWithoutScanningNotes() throws {
        let harness = try TestHarness()
        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        let noteURL = notesDirectory.appendingPathComponent("Cached.md")
        let snapshot = [
            NoteSearchResult(
                url: noteURL,
                title: "Cached",
                snippet: "Launch projection",
                modifiedAt: Date(timeIntervalSince1970: 1_786_612_800),
                createdAt: Date(timeIntervalSince1970: 1_786_526_400),
                tags: ["launch", "macOS"],
                hasAttachments: true,
                thumbnailURL: notesDirectory.appendingPathComponent("preview.png")
            )
        ]
        harness.store.cacheLibraryPresentationSnapshot(snapshot)

        let reloadedStore = NoteStore(
            defaults: harness.defaults,
            legacyDefaults: nil,
            fileManager: FileManager.default,
            appSupportDirectory: harness.store.appSupportDirectory
        )

        #expect(reloadedStore.cachedLibraryPresentationSnapshot() == snapshot)
    }

    @Test
    func searchIndexPersistsAndReloadsAcrossStoreInstances() throws {
        let harness = try TestHarness()
        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        let projectDirectory = harness.root.appendingPathComponent("Projects", isDirectory: true)
        harness.store.configurePreferredDirectories([notesDirectory, projectDirectory], defaultDirectory: notesDirectory)

        _ = try harness.store.saveNewNote(title: "Cache Alpha", body: "durable body one", tags: ["cache"], in: notesDirectory)
        _ = try harness.store.saveNewNote(title: "Cache Beta", body: "durable body two", tags: ["reload"], in: projectDirectory)

        #expect(harness.store.prewarmSearchIndex() == 2)
        #expect(FileManager.default.fileExists(atPath: harness.store.searchIndexCacheURL.path))

        let reloadedStore = NoteStore(
            defaults: harness.defaults,
            legacyDefaults: nil,
            fileManager: FileManager.default,
            appSupportDirectory: harness.store.appSupportDirectory
        )
        reloadedStore.configurePreferredDirectories([notesDirectory, projectDirectory], defaultDirectory: notesDirectory)

        #expect(reloadedStore.searchIndexSnapshot == nil)
        #expect(reloadedStore.prewarmSearchIndex() == 2)
        #expect(reloadedStore.searchIndexSnapshot?.entries.map(\.title).sorted() == ["Cache Alpha", "Cache Beta"])
        #expect(reloadedStore.searchNotes(query: "durable body two", limit: 10).first?.title == "Cache Beta")
        #expect(reloadedStore.knownTags(limit: 10) == ["cache", "reload"])
    }

    @Test
    func searchIndexDiskCacheRefreshesWhenMarkdownFileChanges() throws {
        let harness = try TestHarness()
        let store = harness.store

        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        store.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)
        let noteURL = try store.saveNewNote(title: "Disk Cache", body: "old body", tags: ["old"])

        #expect(store.prewarmSearchIndex() == 1)
        #expect(FileManager.default.fileExists(atPath: store.searchIndexCacheURL.path))

        let updatedURL = try store.updateNote(at: noteURL, title: "Disk Cache", body: "new body", tags: ["new"])
        #expect(updatedURL.standardizedFileURL.path == noteURL.standardizedFileURL.path)

        let reloadedStore = NoteStore(
            defaults: harness.defaults,
            legacyDefaults: nil,
            fileManager: FileManager.default,
            appSupportDirectory: store.appSupportDirectory
        )
        reloadedStore.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)

        #expect(reloadedStore.searchNotes(query: "old", limit: 10).isEmpty)
        #expect(reloadedStore.searchNotes(query: "new", limit: 10).first?.title == "Disk Cache")
        #expect(reloadedStore.knownTags(limit: 10) == ["new"])
    }

    @Test
    func searchIndexRefreshReadsOnlyChangedMarkdownFiles() throws {
        let harness = try TestHarness()
        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        harness.store.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)

        let alphaURL = try harness.store.saveNewNote(title: "Alpha", body: "alpha body")
        let betaURL = try harness.store.saveNewNote(title: "Beta", body: "beta body")
        let gammaURL = try harness.store.saveNewNote(title: "Gamma", body: "gamma body")

        #expect(harness.store.prewarmSearchIndex() == 3)
        #expect(harness.store.searchIndexEntryReadCountForTesting == 3)

        harness.store.searchIndexEntryReadCountForTesting = 0
        harness.store.searchIndexSignatureReadCountForTesting = 0
        _ = try harness.store.updateNote(
            at: betaURL,
            title: "Beta",
            body: "beta body changed with a different size"
        )

        #expect(harness.store.prewarmSearchIndex() == 3)
        #expect(harness.store.searchIndexEntryReadCountForTesting == 1)
        #expect(harness.store.searchIndexSignatureReadCountForTesting == 1)
        #expect(harness.store.searchNotes(query: "different size", limit: 10).first?.url.standardizedFileURL.path == betaURL.path)
        #expect(harness.store.searchNotes(query: "alpha body", limit: 10).first?.url.standardizedFileURL.path == alphaURL.path)

        _ = try harness.store.updateNote(
            at: gammaURL,
            title: "Gamma",
            body: "gamma body changed after the disk snapshot"
        )
        let reloadedStore = NoteStore(
            defaults: harness.defaults,
            legacyDefaults: nil,
            fileManager: FileManager.default,
            appSupportDirectory: harness.store.appSupportDirectory
        )
        reloadedStore.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)

        #expect(reloadedStore.prewarmSearchIndex() == 3)
        #expect(reloadedStore.searchIndexEntryReadCountForTesting == 1)
        #expect(reloadedStore.searchNotes(query: "after the disk snapshot", limit: 10).first?.url.standardizedFileURL.path == gammaURL.path)
        #expect(reloadedStore.searchNotes(query: "alpha body", limit: 10).first?.url.standardizedFileURL.path == alphaURL.path)
    }

    @Test
    func corruptSearchIndexDiskCacheIsIgnoredAndRebuilt() throws {
        let harness = try TestHarness()
        let store = harness.store

        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        store.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)
        _ = try store.saveNewNote(title: "Recovered", body: "cache recovery", tags: ["healthy"])

        try FileManager.default.createDirectory(
            at: store.searchIndexCacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: store.searchIndexCacheURL)

        #expect(store.prewarmSearchIndex() == 1)
        #expect(store.searchNotes(query: "recovery", limit: 10).first?.title == "Recovered")
        #expect(store.knownTags(limit: 10) == ["healthy"])
        #expect(FileManager.default.fileExists(atPath: store.searchIndexCacheURL.path))
    }

    @Test
    func listNotesReturnsAllKnownMarkdownFilesByModifiedDate() throws {
        let harness = try TestHarness()
        let store = harness.store

        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        let projectDirectory = harness.root.appendingPathComponent("Projects", isDirectory: true)
        store.configurePreferredDirectories([notesDirectory, projectDirectory], defaultDirectory: notesDirectory)

        let oldURL = try store.saveNewNote(title: "Older", body: "first", in: notesDirectory)
        let newURL = try store.saveNewNote(title: "Newer", body: "second", tags: ["work"], in: projectDirectory)
        let attachmentDirectory = notesDirectory.appendingPathComponent(NoteStore.attachmentDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
        try "# Not a note\n".write(
            to: attachmentDirectory.appendingPathComponent("pasted-markdown.md"),
            atomically: true,
            encoding: .utf8
        )
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newDate = Date(timeIntervalSince1970: 1_700_000_200)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldURL.path)
        try FileManager.default.setAttributes([.modificationDate: newDate], ofItemAtPath: newURL.path)

        let notes = store.listNotes(limit: 10)

        #expect(Array(notes.map(\.title).prefix(2)) == ["Newer", "Older"])
        #expect(notes.count == 2)
        #expect(notes.first?.tags == ["work"])
        #expect(notes.first?.snippet == "second")
    }

    @Test
    func localMarkdownLinksResolveRelativeAbsoluteAndFileURLs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-local-link-tests-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = root.appendingPathComponent("Source.md")
        let targetURL = root.appendingPathComponent("关联 笔记.md")

        #expect(
            MarkdownLocalLinkResolver.fileURL(
                for: "%E5%85%B3%E8%81%94%20%E7%AC%94%E8%AE%B0.md#section",
                relativeTo: sourceURL
            ) == targetURL.standardizedFileURL
        )
        #expect(
            MarkdownLocalLinkResolver.fileURL(
                for: targetURL.path,
                relativeTo: sourceURL
            ) == targetURL.standardizedFileURL
        )
        #expect(
            MarkdownLocalLinkResolver.fileURL(
                for: targetURL.absoluteString,
                relativeTo: sourceURL
            ) == targetURL.standardizedFileURL
        )
        #expect(MarkdownLocalLinkResolver.fileURL(
            for: "https://example.com/note.md",
            relativeTo: sourceURL
        ) == nil)
    }

    @Test
    func linkRelationsReportIncomingAndOutgoingMarkdownNotes() throws {
        let harness = try TestHarness()
        let store = harness.store
        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        store.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)

        let relatedURL = try store.saveNewNote(title: "Related", body: "Related body", in: notesDirectory)
        let targetURL = try store.saveNewNote(
            title: "Target",
            body: "[Related](\(relatedURL.lastPathComponent))",
            in: notesDirectory
        )
        let sourceURL = try store.saveNewNote(
            title: "Source",
            body: "[Target](\(targetURL.path))\n\n![Not a backlink](\(targetURL.path))",
            in: notesDirectory
        )

        let relations = store.linkRelations(for: targetURL, roots: [notesDirectory])

        #expect(relations.incoming == [NoteLinkItem(url: sourceURL.standardizedFileURL, title: "Source")])
        #expect(relations.outgoing == [NoteLinkItem(url: relatedURL.standardizedFileURL, title: "Related")])
    }

    @Test
    func outgoingLinkRefreshDoesNotRebuildDirtySearchIndex() throws {
        let harness = try TestHarness()
        let store = harness.store
        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        store.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)
        let relatedURL = try store.saveNewNote(title: "Related", body: "Related body")
        let targetURL = try store.saveNewNote(title: "Target", body: "Initial body")
        #expect(store.prewarmSearchIndex() == 2)

        store.searchIndexEntryReadCountForTesting = 0
        let body = "[Related](\(relatedURL.lastPathComponent))"
        _ = try store.updateNote(at: targetURL, title: "Target", body: body)
        let outgoing = store.outgoingLinks(for: targetURL, currentBody: body)

        #expect(outgoing == [NoteLinkItem(url: relatedURL.standardizedFileURL, title: "Related")])
        #expect(store.searchIndexEntryReadCountForTesting == 0)
        #expect(store.dirtySearchIndexPaths.contains(targetURL.standardizedFileURL.path))
    }

    @Test
    func listNotesResolvesLocalImageThumbnailReferences() throws {
        let harness = try TestHarness()
        let store = harness.store

        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        store.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)
        let noteURL = try store.saveNewNote(
            title: "Image Note",
            body: "![preview](Attachments/photo%20one.png)",
            in: notesDirectory
        )
        let imageURL = noteURL.deletingLastPathComponent()
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent("photo one.png")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imageURL)

        let note = try #require(store.listNotes(limit: 10).first)

        #expect(note.hasAttachments)
        #expect(note.thumbnailURL?.standardizedFileURL.path == imageURL.standardizedFileURL.path)
    }

    @Test
    func trashRestoreAndPermanentDeletePreserveMarkdownLifecycle() throws {
        let harness = try TestHarness()
        let store = harness.store

        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        store.notesDirectory = notesDirectory
        let noteURL = try store.saveNewNote(title: "Trash Candidate", body: "restore me", tags: ["trash-test"])
        #expect(store.trashedNoteCount() == 0)

        let trashedURL = try store.trashNote(at: noteURL)
        #expect(store.trashedNoteCount() == 1)

        #expect(!FileManager.default.fileExists(atPath: noteURL.path))
        #expect(FileManager.default.fileExists(atPath: trashedURL.path))
        #expect(store.listRecentFiles(limit: 5).contains { $0.url == noteURL } == false)
        let trashedNotes = store.listTrashedNotes(limit: 10)
        #expect(trashedNotes.first?.url.standardizedFileURL.path == trashedURL.standardizedFileURL.path)
        #expect(trashedNotes.first?.title == "Trash Candidate")
        #expect(trashedNotes.first?.snippet == "restore me")
        #expect(trashedNotes.first?.tags == ["trash-test"])

        let restoredURL = try store.restoreTrashedNote(at: trashedURL)
        #expect(store.trashedNoteCount() == 0)

        #expect(restoredURL == noteURL)
        #expect(FileManager.default.fileExists(atPath: restoredURL.path))
        #expect(store.listTrashedNotes(limit: 10).isEmpty)
        #expect(store.listRecentFiles(limit: 5).first?.url == restoredURL)

        let trashedAgainURL = try store.trashNote(at: restoredURL)
        #expect(store.trashedNoteCount() == 1)
        try store.permanentlyDeleteTrashedNote(at: trashedAgainURL)
        #expect(store.trashedNoteCount() == 0)

        #expect(!FileManager.default.fileExists(atPath: trashedAgainURL.path))
        #expect(store.listTrashedNotes(limit: 10).isEmpty)
    }

    @Test
    func tagsRoundTripAndKnownTagsAreCollected() throws {
        let harness = try TestHarness()
        let store = harness.store

        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        store.notesDirectory = notesDirectory

        let firstURL = try store.saveNewNote(title: "Tagged Note", body: "hello", tags: ["alpha", "beta"])
        _ = try store.saveNewNote(title: "Second Note", body: "world", tags: ["beta", "gamma"])

        let loaded = try store.loadNote(at: firstURL)
        #expect(loaded.tags == ["alpha", "beta"])
        #expect(store.knownTags().prefix(3).contains("beta"))
        #expect(store.searchNotes(query: "gamma").first?.tags.contains("gamma") == true)
    }

    @Test
    func draftsRoundTrip() throws {
        let harness = try TestHarness()
        let store = harness.store

        let draft = DraftSnapshot(
            id: "quick-capture",
            sourcePath: nil,
            selectedDirectoryPath: harness.root.path,
            title: "Draft title",
            body: "Draft body",
            tags: ["draft"],
            updatedAt: Date()
        )

        try store.saveDraft(draft)
        let loaded = try #require(store.loadDraft(id: draft.id))
        #expect(loaded.title == draft.title)
        #expect(loaded.body == draft.body)
        #expect(loaded.tags == draft.tags)

        store.deleteDraft(id: draft.id)
        #expect(store.loadDraft(id: draft.id) == nil)
    }

    @Test
    func preferredDirectoriesIncludeSettingsFolders() throws {
        let harness = try TestHarness()
        let store = harness.store

        let defaultDirectory = harness.root.appendingPathComponent("Inbox", isDirectory: true)
        let archiveDirectory = harness.root.appendingPathComponent("Archive", isDirectory: true)
        let projectsDirectory = harness.root.appendingPathComponent("Projects", isDirectory: true)

        store.configurePreferredDirectories([defaultDirectory, archiveDirectory, projectsDirectory], defaultDirectory: defaultDirectory)

        let directories = store.preferredDirectories.map(\.standardizedFileURL.path)
        #expect(directories.contains(defaultDirectory.standardizedFileURL.path))
        #expect(directories.contains(archiveDirectory.standardizedFileURL.path))
        #expect(directories.contains(projectsDirectory.standardizedFileURL.path))
        #expect(store.knownSearchRoots().contains { $0.standardizedFileURL.path == archiveDirectory.standardizedFileURL.path })
    }

    @Test
    func preferredInboxDoesNotInferFromAnUnrelatedContainingFolderName() throws {
        let harness = try TestHarness()
        let store = harness.store
        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        let unrelatedDirectory = harness.root.appendingPathComponent("Inbox Zero Research", isDirectory: true)
        store.configurePreferredDirectories(
            [notesDirectory, unrelatedDirectory],
            defaultDirectory: notesDirectory
        )

        #expect(
            store.preferredInboxDirectory.standardizedFileURL.path
                == notesDirectory.appendingPathComponent("Inbox").standardizedFileURL.path
        )
    }

    @Test
    func folderLifecycleCreatesMovesRenamesAndTrashesMarkdownNotes() throws {
        let harness = try TestHarness()
        let store = harness.store

        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        store.notesDirectory = notesDirectory

        let projectFolder = try store.createFolder(named: "Project")
        #expect(FileManager.default.fileExists(atPath: projectFolder.path))
        #expect(store.preferredDirectories.contains {
            $0.standardizedFileURL.path == projectFolder.standardizedFileURL.path
        })

        let noteURL = try store.saveNewNote(title: "Move Me", body: "folder body")
        let movedURL = try store.moveNote(at: noteURL, to: projectFolder)
        #expect(!FileManager.default.fileExists(atPath: noteURL.path))
        #expect(FileManager.default.fileExists(atPath: movedURL.path))
        #expect(movedURL.deletingLastPathComponent().standardizedFileURL.path == projectFolder.standardizedFileURL.path)
        #expect(store.listRecentFiles(limit: 1).first?.url.standardizedFileURL.path == movedURL.standardizedFileURL.path)

        let renamedFolder = try store.renamePreferredDirectory(projectFolder, to: "Renamed")
        let renamedNoteURL = renamedFolder.appendingPathComponent(movedURL.lastPathComponent)
        #expect(!FileManager.default.fileExists(atPath: movedURL.path))
        #expect(FileManager.default.fileExists(atPath: renamedNoteURL.path))
        #expect(store.preferredDirectories.contains {
            $0.standardizedFileURL.path == renamedFolder.standardizedFileURL.path
        })
        #expect(!store.preferredDirectories.contains {
            $0.standardizedFileURL.path == projectFolder.standardizedFileURL.path
        })
        #expect(store.listRecentFiles(limit: 1).first?.url.standardizedFileURL.path == renamedNoteURL.standardizedFileURL.path)

        let trashedFolder = try store.trashFolder(at: renamedFolder)
        #expect(!FileManager.default.fileExists(atPath: renamedFolder.path))
        #expect(FileManager.default.fileExists(atPath: trashedFolder.path))
        #expect(!store.preferredDirectories.contains {
            $0.standardizedFileURL.path == renamedFolder.standardizedFileURL.path
        })
        let trashedNotes = store.listTrashedNotes(limit: 10)
        #expect(trashedNotes.first?.title == "Move Me")
        #expect(trashedNotes.first?.snippet == "folder body")
    }

    @Test
    func folderTrashUsesKnownNotesWithoutLosingRestorePathsForUncachedNotes() throws {
        let harness = try TestHarness()
        let store = harness.store
        store.notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)

        let folder = try store.createFolder(named: "Project")
        let knownNote = try store.saveNewNote(title: "Known", body: "cached", in: folder)
        let nestedFolder = folder.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedFolder, withIntermediateDirectories: true)
        let uncachedNote = nestedFolder.appendingPathComponent("Uncached.md")
        try "# Uncached\n\nexternal".write(to: uncachedNote, atomically: true, encoding: .utf8)

        let trashResult = try store.trashFolderWithNoteURLs(
            at: folder,
            knownNoteURLs: [knownNote]
        )
        #expect(trashResult.noteURLs.count == 1)
        #expect(trashResult.noteURLs.first?.lastPathComponent == knownNote.lastPathComponent)

        let trashedNotes = store.listTrashedNotes(limit: 10)
        #expect(Set(trashedNotes.map(\.title)) == ["Known", "Uncached"])
        let trashedUncached = try #require(trashedNotes.first { $0.title == "Uncached" })
        let restoredURL = try store.restoreTrashedNote(at: trashedUncached.url)
        #expect(restoredURL.standardizedFileURL.path == uncachedNote.standardizedFileURL.path)
        #expect(FileManager.default.fileExists(atPath: uncachedNote.path))
    }

    @Test
    func panelOpacityPersistsWithinBounds() throws {
        let harness = try TestHarness()
        let store = harness.store

        #expect(store.panelOpacity == 0.78)

        store.panelOpacity = 0.70
        #expect(store.panelOpacity == 0.70)

        store.panelOpacity = 1.5
        #expect(store.panelOpacity == 0.96)

        store.panelOpacity = 0.1
        #expect(store.panelOpacity == 0.62)
    }

    @Test
    func quickCaptureWindowFramePersists() throws {
        let harness = try TestHarness()
        let store = harness.store

        #expect(store.quickCaptureWindowFrame == nil)

        store.quickCaptureWindowFrame = StoredWindowFrame(x: 320, y: 540, width: 480, height: 296)
        #expect(store.quickCaptureWindowFrame == StoredWindowFrame(x: 320, y: 540, width: 480, height: 296))
        #expect(store.quickCaptureWindowOrigin == StoredWindowOrigin(x: 320, y: 540))

        store.quickCaptureWindowFrame = nil
        #expect(store.quickCaptureWindowFrame == nil)
    }

    @Test
    func libraryWindowFramePersists() throws {
        let harness = try TestHarness()
        let store = harness.store

        #expect(store.libraryWindowFrame == nil)
        let frame = StoredWindowFrame(x: 180, y: 140, width: 1120, height: 760)
        store.libraryWindowFrame = frame
        #expect(store.libraryWindowFrame == frame)

        store.libraryWindowFrame = nil
        #expect(store.libraryWindowFrame == nil)
    }

    @Test
    func floatingShortcutAndFrameSettingsPersist() throws {
        let harness = try TestHarness()
        let store = harness.store

        #expect(store.floatingNoteHotKeyString == "option+r")
        #expect(store.saveShortcutString == "command+return")
        #expect(store.floatingNoteWindowFrame == nil)

        store.floatingNoteHotKeyString = "option+shift+r"
        store.saveShortcutString = "command+enter"
        store.floatingNoteWindowFrame = StoredWindowFrame(x: 120, y: 160, width: 400, height: 280)

        #expect(store.floatingNoteHotKeyString == "option+shift+r")
        #expect(store.saveShortcutString == "command+enter")
        #expect(store.floatingNoteWindowFrame == StoredWindowFrame(x: 120, y: 160, width: 400, height: 280))
    }

    @Test
    func behaviorSettingsDefaultsAndPersistence() throws {
        let harness = try TestHarness()
        let store = harness.store

        #expect(!store.revealSavedNoteInFinder)
        #expect(store.floatingNoteStaysOnTop)
        #expect(store.spellCheckingEnabled)
        #expect(store.themeColorIdentifier == "ocean")
        #expect(store.libraryNoteSortOrderRawValue == 0)
        #expect(store.libraryNoteViewModeRawValue == 0)
        #expect(store.libraryGroupsNotesByDate)
        #expect(store.libraryCollapsedFolderPaths.isEmpty)
        #expect(store.libraryExpandedFolderPaths.isEmpty)
        #expect(!store.libraryFoldersSectionCollapsed)
        #expect(!store.libraryTagsSectionCollapsed)
        #expect(store.librarySourceColumnWidth == nil)
        #expect(store.libraryNoteColumnWidth == nil)
        #expect(store.librarySourceListVisible)
        #expect(!store.aiEnabled)
        #expect(store.aiCodexExecutablePath.isEmpty)

        store.revealSavedNoteInFinder = false
        store.floatingNoteStaysOnTop = false
        store.spellCheckingEnabled = false
        store.themeColorIdentifier = "violet"
        store.libraryNoteSortOrderRawValue = 1
        store.libraryNoteViewModeRawValue = 1
        store.libraryGroupsNotesByDate = false
        store.libraryCollapsedFolderPaths = ["/tmp/Notes"]
        store.libraryExpandedFolderPaths = ["/tmp/Notes/Projects"]
        store.libraryFoldersSectionCollapsed = true
        store.libraryTagsSectionCollapsed = true
        store.librarySourceColumnWidth = 372
        store.libraryNoteColumnWidth = 388
        store.librarySourceListVisible = false
        store.aiEnabled = true
        store.aiCodexExecutablePath = "/usr/local/bin/codex"

        #expect(!store.revealSavedNoteInFinder)
        #expect(!store.floatingNoteStaysOnTop)
        #expect(!store.spellCheckingEnabled)
        #expect(store.themeColorIdentifier == "violet")
        #expect(store.libraryNoteSortOrderRawValue == 1)
        #expect(store.libraryNoteViewModeRawValue == 1)
        #expect(!store.libraryGroupsNotesByDate)
        #expect(store.libraryCollapsedFolderPaths == ["/tmp/Notes"])
        #expect(store.libraryExpandedFolderPaths == ["/tmp/Notes/Projects"])
        #expect(store.libraryFoldersSectionCollapsed)
        #expect(store.libraryTagsSectionCollapsed)
        #expect(store.librarySourceColumnWidth == 372)
        #expect(store.libraryNoteColumnWidth == 388)
        #expect(!store.librarySourceListVisible)
        #expect(store.aiEnabled)
        #expect(store.aiCodexExecutablePath == "/usr/local/bin/codex")
    }

    @Test
    func codexRuntimeAndReadOnlyArgumentsFollowLocalRuntimeContract() throws {
        let executable = try #require(CodexRuntimeLocator.resolve(
            configuredPath: "/bin/sh",
            environmentPath: nil,
            homeDirectory: "/tmp"
        ))
        #expect(executable.path == "/bin/sh")

        let workingDirectory = URL(fileURLWithPath: "/tmp/Notes", isDirectory: true)
        let outputURL = URL(fileURLWithPath: "/tmp/output.txt")
        let arguments = CodexAIProvider.makeArguments(workingDirectory: workingDirectory, outputURL: outputURL)
        #expect(arguments.contains("--ephemeral"))
        #expect(arguments.contains("read-only"))
        #expect(arguments.contains("--skip-git-repo-check"))
        #expect(arguments.contains(workingDirectory.path))
        #expect(arguments.last == "-")
    }

    @Test
    func folderDisclosurePathsPersistAndFollowFolderLifecycle() throws {
        let harness = try TestHarness()
        let store = harness.store
        store.notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        let project = try store.createFolder(named: "Project")
        let client = project.appendingPathComponent("Client", isDirectory: true)
        try FileManager.default.createDirectory(at: client, withIntermediateDirectories: true)

        store.libraryCollapsedFolderPaths = [project.path]
        store.libraryExpandedFolderPaths = [client.path]

        let renamed = try store.renamePreferredDirectory(project, to: "Renamed Project")
        let renamedClient = renamed.appendingPathComponent("Client", isDirectory: true)
        #expect(store.libraryCollapsedFolderPaths == [renamed.path])
        #expect(store.libraryExpandedFolderPaths == [renamedClient.path])

        _ = try store.trashFolder(at: renamed)
        #expect(store.libraryCollapsedFolderPaths.isEmpty)
        #expect(store.libraryExpandedFolderPaths.isEmpty)
    }

    @Test
    func folderIconNamesPersistFollowRenamesAndClearWhenTrashed() throws {
        let harness = try TestHarness()
        let store = harness.store
        store.notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        let project = try store.createFolder(named: "Project")

        #expect(store.libraryFolderIconName(for: project) == nil)
        store.setLibraryFolderIconName("briefcase.fill", for: project)
        #expect(store.libraryFolderIconName(for: project) == "briefcase.fill")

        let renamed = try store.renamePreferredDirectory(project, to: "Renamed Project")
        #expect(store.libraryFolderIconName(for: project) == nil)
        #expect(store.libraryFolderIconName(for: renamed) == "briefcase.fill")

        _ = try store.trashFolder(at: renamed)
        #expect(store.libraryFolderIconName(for: renamed) == nil)
    }

    @Test
    func pinnedNotePathsPersistAndFollowFileLifecycle() throws {
        let harness = try TestHarness()
        let store = harness.store
        let notesDirectory = harness.root.appendingPathComponent("Notes", isDirectory: true)
        store.notesDirectory = notesDirectory

        let noteURL = try store.saveNewNote(title: "Pinned Draft", body: "Body")
        store.setLibraryNotePinned(true, at: noteURL)
        #expect(store.isLibraryNotePinned(at: noteURL))

        let renamedURL = try store.updateNote(at: noteURL, title: "Pinned Final", body: "Body")
        #expect(!store.isLibraryNotePinned(at: noteURL))
        #expect(store.isLibraryNotePinned(at: renamedURL))

        let projectFolder = try store.createFolder(named: "Project")
        let movedURL = try store.moveNote(at: renamedURL, to: projectFolder)
        #expect(!store.isLibraryNotePinned(at: renamedURL))
        #expect(store.isLibraryNotePinned(at: movedURL))

        let renamedFolder = try store.renamePreferredDirectory(projectFolder, to: "Renamed Project")
        let folderRenamedURL = renamedFolder.appendingPathComponent(movedURL.lastPathComponent)
        #expect(!store.isLibraryNotePinned(at: movedURL))
        #expect(store.isLibraryNotePinned(at: folderRenamedURL))

        _ = try store.trashNote(at: folderRenamedURL)
        #expect(!store.isLibraryNotePinned(at: folderRenamedURL))
        #expect(store.libraryPinnedNotePaths.isEmpty)
    }

    @Test
    func aiPromptBuilderKeepsSelectionScopeExplicit() throws {
        let request = AIRequest(
            actionID: .fix,
            noteTitle: "Private Plan",
            inputMarkdown: "Fix **this** #tag",
            scope: .selection
        )

        let prompt = try AIPromptBuilder.prompt(for: request)

        #expect(prompt.contains("Input scope: selected Markdown only."))
        #expect(prompt.contains("Do not change meaning, structure, links, code spans, hashtags, or task markers."))
        #expect(prompt.contains("Fix **this** #tag"))
    }

    @Test
    func aiPromptBuilderUsesMarkdownTasksForTodos() throws {
        let request = AIRequest(
            actionID: .todos,
            noteTitle: nil,
            inputMarkdown: "Donald should package the app and update the README.",
            scope: .wholeNote
        )

        let prompt = try AIPromptBuilder.prompt(for: request)

        #expect(prompt.contains("Input scope: current note only."))
        #expect(prompt.contains("Return only Markdown task items using \"- [ ]\"."))
        #expect(prompt.contains("Do not invent tasks."))
    }

    @Test
    func markdownEditorDocumentParsesHeadingContent() {
        let document = MarkdownEditorDocument.parse(editorText: "# Inbox\n\n- [ ] follow up\nsecond line")
        #expect(document.title == "Inbox")
        #expect(document.body == "- [ ] follow up\nsecond line")
        #expect(document.editorText == "# Inbox\n\n- [ ] follow up\nsecond line")
    }

    @Test
    func markdownEditorDocumentUsesFirstLineAsTitleWithoutHeading() {
        let document = MarkdownEditorDocument.parse(editorText: "Quick thought\n\nbody line")
        #expect(document.title == "Quick thought")
        #expect(document.body == "body line")
        #expect(MarkdownEditorDocument.composeEditorText(title: document.title, body: document.body) == "# Quick thought\n\nbody line")
    }

    @Test
    func markdownEditorDocumentNormalizesTags() {
        let document = MarkdownEditorDocument.parse(editorText: "# Inbox", tags: ["#Alpha", "alpha", " beta "])
        #expect(document.tags == ["Alpha", "beta"])
    }

    @Test
    func migratesLegacyDefaultsIntoMudsnoteDomain() throws {
        let suiteSuffix = UUID().uuidString
        let currentSuite = "mudsnote.tests.current.\(suiteSuffix)"
        let legacySuite = "mudsnote.tests.legacy.\(suiteSuffix)"
        let currentDefaults = try #require(UserDefaults(suiteName: currentSuite))
        let legacyDefaults = try #require(UserDefaults(suiteName: legacySuite))
        removeDefaultsSuite(currentSuite, defaults: currentDefaults)
        removeDefaultsSuite(legacySuite, defaults: legacyDefaults)
        defer {
            removeDefaultsSuite(currentSuite, defaults: currentDefaults)
            removeDefaultsSuite(legacySuite, defaults: legacyDefaults)
        }

        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("mudsnote-legacy-\(suiteSuffix)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let legacyNotes = root.appendingPathComponent("QuickMarkdown", isDirectory: true)
        let expectedNotes = root.appendingPathComponent("Mudsnote", isDirectory: true)
        legacyDefaults.set(legacyNotes.path, forKey: "quickmarkdown.notesDirectory")
        legacyDefaults.set("option+shift+m", forKey: "quickmarkdown.hotkey")
        legacyDefaults.set(0.9, forKey: "quickmarkdown.panelOpacity")

        let store = NoteStore(
            defaults: currentDefaults,
            legacyDefaults: legacyDefaults,
            fileManager: fm,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )

        #expect(store.notesDirectory == expectedNotes)
        #expect(store.hotKeyString == "option+shift+m")
        #expect(store.panelOpacity == 0.9)
        #expect(currentDefaults.string(forKey: "mudsnote.notesDirectory") == expectedNotes.path)
        #expect(currentDefaults.string(forKey: "mudsnote.hotkey") == "option+shift+m")
    }
}

private final class TestHarness {
    let root: URL
    let suiteName: String
    let defaults: UserDefaults
    let store: NoteStore

    init() throws {
        let fm = FileManager.default
        root = fm.temporaryDirectory.appendingPathComponent("mudsnote-tests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        suiteName = "mudsnote.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        removeDefaultsSuite(suiteName, defaults: defaults)

        let appSupport = root.appendingPathComponent("AppSupport", isDirectory: true)
        store = NoteStore(defaults: defaults, legacyDefaults: nil, fileManager: fm, appSupportDirectory: appSupport)
    }

    deinit {
        removeDefaultsSuite(suiteName, defaults: defaults)
        try? FileManager.default.removeItem(at: root)
    }
}

private func removeDefaultsSuite(_ suiteName: String, defaults: UserDefaults) {
    defaults.removePersistentDomain(forName: suiteName)

    let plistURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences", isDirectory: true)
        .appendingPathComponent("\(suiteName).plist", isDirectory: false)

    try? FileManager.default.removeItem(at: plistURL)
}
