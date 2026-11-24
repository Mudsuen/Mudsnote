import Foundation
import Testing
@testable import MudsnoteCore

struct MacOSFeatureRegressionTests {
    @Test func multiTermSearchMatchesMixedScriptsAcrossFieldsAndKeepsFilters() throws {
        let (store, root, defaults, suiteName) = try makeStore()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        let crossField = try store.saveNewNote(title: "Knock", body: "操作说明\n短密码的使用方式", tags: ["工具"])
        let titleOnly = try store.saveNewNote(title: "ＫＮＯＣＫ短密码", body: "标题命中")
        _ = try store.saveNewNote(title: "Knock", body: "没有第二个词")
        _ = try store.saveNewNote(title: "Other", body: "只有短密码")
        let cafe = try store.saveNewNote(title: "Café", body: "Résumé")
        let session = store.makeSearchSession()
        let reads = store.searchIndexEntryReadCountForTesting
        for query in ["knock短密码", "KNOCK 短密码", "短密码\nknock", "  knock　短密码  "] {
            #expect(Set(session.searchNotes(query: query).map(\.url)) == [crossField, titleOnly])
        }
        #expect(session.searchNotes(query: "knock 短密码", filter: .title).map(\.url) == [titleOnly])
        #expect(session.searchNotes(query: "knock 短密码", filter: .body).isEmpty)
        #expect(session.searchNotes(query: "工具 knock").map(\.url) == [crossField])
        #expect(session.searchNotes(query: "cafe resume").map(\.url) == [cafe])
        #expect(session.searchNotes(query: "knock", limit: 0, filter: .all).isEmpty)
        #expect(session.searchNotes(query: "knock", filter: .title, cancellationCheck: { true }).isEmpty)
        #expect(store.searchIndexEntryReadCountForTesting == reads)
        let relaunchedStore = NoteStore(defaults: defaults, legacyDefaults: nil,
                                       appSupportDirectory: root.appendingPathComponent("AppSupport"))
        #expect(Set(relaunchedStore.searchNotes(query: "knock 短密码").map(\.url)) == [crossField, titleOnly])
        #expect(relaunchedStore.searchIndexEntryReadCountForTesting == 0)
        let trashed = try store.trashNote(at: crossField)
        #expect(store.searchTrashedNotes(query: "knock短密码", limit: 10, cancellationCheck: { false }).map { $0.url.resolvingSymlinksInPath() } == [trashed.resolvingSymlinksInPath()])
    }

    @Test func searchSnippetKeepsLateMatchVisibleInLongLines() throws {
        let (store, root, defaults, suiteName) = try makeStore()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        _ = try store.saveNewNote(title: "Knock", body:
            String(repeating: "前置内容 ", count: 2_000) + "短密码示例" + String(repeating: " 后续内容", count: 2_000))
        let result = try #require(store.searchNotes(query: "knock 短密码").first)
        #expect(result.snippet.contains("短密码"))
        #expect(result.snippet.count < 200)
    }

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
    func archivedSearchPreferenceControlsSearchAndKnownTags() throws {
        let (store, root, defaults, suiteName) = try makeStore()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        let notes = store.notesDirectory
        let archive = notes.appendingPathComponent("Archive", isDirectory: true)
        _ = try store.saveNewNote(
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

        store.includesArchivedNotesInSearch = true
        #expect(store.searchNotes(query: "Archived").map(\.url) == [archived])
        #expect(store.makeSearchSession().searchNotes(query: "Archived").map(\.url) == [archived])
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
}
