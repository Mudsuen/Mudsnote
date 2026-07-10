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
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newDate = Date(timeIntervalSince1970: 1_700_000_200)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldURL.path)
        try FileManager.default.setAttributes([.modificationDate: newDate], ofItemAtPath: newURL.path)

        let notes = store.listNotes(limit: 10)

        #expect(Array(notes.map(\.title).prefix(2)) == ["Newer", "Older"])
        #expect(notes.first?.tags == ["work"])
        #expect(notes.first?.snippet == "second")
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
    func behaviorSettingsDefaultOnAndPersist() throws {
        let harness = try TestHarness()
        let store = harness.store

        #expect(store.revealSavedNoteInFinder)
        #expect(store.floatingNoteStaysOnTop)
        #expect(store.spellCheckingEnabled)
        #expect(store.libraryNoteSortOrderRawValue == 0)
        #expect(store.libraryGroupsNotesByDate)
        #expect(!store.aiEnabled)
        #expect(store.aiOllamaBaseURLString == "http://localhost:11434")
        #expect(store.aiOllamaModel == "llama3.2")

        store.revealSavedNoteInFinder = false
        store.floatingNoteStaysOnTop = false
        store.spellCheckingEnabled = false
        store.libraryNoteSortOrderRawValue = 1
        store.libraryGroupsNotesByDate = false
        store.aiEnabled = true
        store.aiOllamaBaseURLString = "http://127.0.0.1:11434"
        store.aiOllamaModel = "qwen2.5"

        #expect(!store.revealSavedNoteInFinder)
        #expect(!store.floatingNoteStaysOnTop)
        #expect(!store.spellCheckingEnabled)
        #expect(store.libraryNoteSortOrderRawValue == 1)
        #expect(!store.libraryGroupsNotesByDate)
        #expect(store.aiEnabled)
        #expect(store.aiOllamaBaseURLString == "http://127.0.0.1:11434")
        #expect(store.aiOllamaModel == "qwen2.5")
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
