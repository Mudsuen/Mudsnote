import Foundation
import Testing
@testable import MudsnoteCore

struct MacOSFeatureRegressionTests {
    private func makeStore() throws -> (NoteStore, URL, UserDefaults, String) {
        let suiteName = "mudsnote.macos-feature-regressions.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-macos-feature-regressions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        let notes = root.appendingPathComponent("Notes", isDirectory: true)
        store.configurePreferredDirectories([notes], defaultDirectory: notes)
        return (store, root, defaults, suiteName)
    }

    @Test
    func blankNewNoteKeepsItsDocumentTitleEmpty() throws {
        let (store, root, defaults, suiteName) = try makeStore()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let url = try store.saveNewNote(title: "", body: "")
        let loaded = try store.loadNote(at: url)

        #expect(loaded.title.isEmpty)
        #expect(loaded.body.isEmpty)
        #expect(!url.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveContains("无标题"))
    }

    @Test
    func archivedNotesAreExcludedFromSearchTagsAndKnowledgeByDefault() throws {
        let (store, root, defaults, suiteName) = try makeStore()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        let notes = store.notesDirectory
        let archive = notes.appendingPathComponent("Archive", isDirectory: true)
        let active = try store.saveNewNote(
            title: "Active",
            body: "shared distinctive topic",
            tags: ["active"],
            in: notes
        )
        let archived = try store.saveNewNote(
            title: "Archived",
            body: "shared distinctive topic",
            tags: ["archived"],
            in: archive
        )

        #expect(store.searchNotes(query: "Archived").isEmpty)
        #expect(!store.knownTags().contains("archived"))
        #expect(!store.knowledgeRelations(for: active, roots: [notes]).suggested.map(\.url).contains(archived))

        store.includesArchivedNotesInSearchAndKnowledge = true
        #expect(store.searchNotes(query: "Archived").map(\.url).contains(archived))
        #expect(store.knownTags().contains("archived"))
    }

    @Test
    func filteredSearchCanLimitMatchesToTitleBodyTagsOrAttachments() throws {
        let (store, root, defaults, suiteName) = try makeStore()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        let titleURL = try store.saveNewNote(title: "Needle", body: "plain")
        let bodyURL = try store.saveNewNote(title: "Body", body: "needle appears here")
        let tagURL = try store.saveNewNote(title: "Tag", body: "plain", tags: ["needle"])
        let attachmentURL = try store.saveNewNote(title: "Attachment", body: "![preview](Attachments/needle.png)")
        let session = store.makeSearchSession()

        #expect(session.searchNotes(query: "needle", filter: .title).map(\.url) == [titleURL])
        #expect(Set(session.searchNotes(query: "needle", filter: .body).map(\.url)) == Set([bodyURL, attachmentURL]))
        #expect(session.searchNotes(query: "needle", filter: .tags).map(\.url) == [tagURL])
        #expect(session.searchNotes(query: "", filter: .attachments).map(\.url) == [attachmentURL])
        for filter in [NoteSearchFilter.title, .body, .tags] {
            #expect(session.searchNotes(query: "  needle\n", filter: filter).map(\.url)
                == session.searchNotes(query: "needle", filter: filter).map(\.url))
        }
    }

    @Test
    func pathScopedSearchOnlyRanksRequestedNotesAndHonorsCancellation() throws {
        let (store, root, defaults, suiteName) = try makeStore()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        var paths: Set<String> = []
        for index in 0..<20 {
            let url = try store.saveNewNote(title: "Note \(index)", body: "shared body")
            if index < 2 { paths.insert(url.standardizedFileURL.path) }
        }
        let session = store.makeSearchSession()
        var matchCount = 0
        store.searchIndexEntryWillMatchForTesting = { matchCount += 1 }
        let results = session.searchNotes(query: " shared \n", limit: 1, restrictedTo: paths, cancellationCheck: { false })
        #expect(results.count == 1)
        #expect(results.allSatisfy { paths.contains($0.url.standardizedFileURL.path) })
        #expect(matchCount == 2)
        #expect(session.searchNotes(query: "", limit: 10, restrictedTo: paths, cancellationCheck: { false }).count == 2)
        #expect(session.searchNotes(query: "shared", limit: 0, restrictedTo: paths, cancellationCheck: { false }).isEmpty)
        #expect(session.searchNotes(query: "shared", limit: 10, restrictedTo: paths, cancellationCheck: { true }).isEmpty)
        #expect(matchCount == 2)
    }

    @Test
    func aiMemorySyncImportsOnlyMudsnoteSectionsAndSkipsUnchangedDailyRuns() throws {
        let (store, root, defaults, suiteName) = try makeStore()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        let memoryDirectory = root.appendingPathComponent("Memory", isDirectory: true)
        try FileManager.default.createDirectory(at: memoryDirectory, withIntermediateDirectories: true)
        try """
        # Memory

        ## /Users/Donald/Code/Mudsnote

        - Preserve local Markdown files.

        ### Nested decision

        - Keep shared data contracts compatible.

        ## /Users/Donald/Code/Other

        - Private unrelated project context.
        """.write(
            to: memoryDirectory.appendingPathComponent("MEMORY.md"),
            atomically: true,
            encoding: .utf8
        )
        let service = AIMemorySyncService(
            memoryDirectory: memoryDirectory,
            destinationRoot: store.notesDirectory
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let first = try service.sync(lastSyncDate: nil, now: now, force: false)
        let second = try service.sync(lastSyncDate: now, now: now.addingTimeInterval(60), force: false)
        let markdown = try String(contentsOf: first.destinationURL, encoding: .utf8)

        #expect(first.didWrite)
        #expect(!second.didWrite)
        #expect(markdown.contains("Preserve local Markdown files."))
        #expect(markdown.contains("Keep shared data contracts compatible."))
        #expect(!markdown.contains("Private unrelated project context."))
    }

    @Test
    func wordCountHandlesCJKAndLatinWordsWithoutCountingMarkdownPunctuation() {
        #expect(MarkdownEditorDocument.wordCount(in: "# 标题\n\nHello, world! 中文") == 6)
        #expect(MarkdownEditorDocument.wordCount(in: "   \n\n") == 0)
    }

    @Test
    func knowledgeSuggestionsIgnoreLibraryWideBoilerplateTokens() throws {
        let (store, root, defaults, suiteName) = try makeStore()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        let notes = store.notesDirectory
        let source = try store.saveNewNote(
            title: "Source",
            body: "project notes meeting update",
            in: notes
        )
        let unrelated = try store.saveNewNote(
            title: "Unrelated",
            body: "project notes meeting update unrelated",
            in: notes
        )
        for index in 0..<4 {
            _ = try store.saveNewNote(
                title: "Boilerplate \(index)",
                body: "project notes meeting update topic\(index)",
                in: notes
            )
        }

        let suggestions = store.knowledgeRelations(
            for: source,
            roots: [notes],
            suggestionLimit: 10
        ).suggested

        #expect(!suggestions.map(\.url).contains(unrelated))
    }
}
