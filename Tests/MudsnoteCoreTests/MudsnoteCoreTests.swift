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
