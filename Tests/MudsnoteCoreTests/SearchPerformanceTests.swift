import Foundation
import Testing
@testable import MudsnoteCore

private final class LockedSearchReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }

    func snapshot() -> Int {
        lock.withLock { value }
    }
}

private func emitSearchPerformanceEvidence(_ message: @autoclosure () -> String) {
    guard ProcessInfo.processInfo.environment["MUDSNOTE_SEARCH_PERF_EVIDENCE"] == "1" else {
        return
    }
    print("SEARCH_PERF_EVIDENCE \(message())")
}

struct SearchPerformanceTests {
    @Test
    func cancelledColdIndexBuildStopsPromptlyInsteadOfHoldingTheNextQuery() async throws {
        let suiteName = "mudsnote.search-cancellation-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-search-cancellation-tests-\(UUID().uuidString)", isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        for index in 0..<240 {
            let body = """
            # Fixture \(index)

            searchable body \(index)
            """
            try body.write(
                to: notesDirectory.appendingPathComponent("fixture-\(index).md"),
                atomically: true,
                encoding: .utf8
            )
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)

        let reads = LockedSearchReadCounter()
        store.searchIndexEntryWillReadForTesting = {
            _ = reads.increment()
            Thread.sleep(forTimeInterval: 0.004)
        }

        let build = Task.detached {
            store.makeSearchSession(
                roots: [notesDirectory],
                cancellationCheck: { Task.isCancelled }
            )
        }
        let readDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while reads.snapshot() == 0, ContinuousClock.now < readDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(reads.snapshot() > 0)

        let clock = ContinuousClock()
        let cancellationStarted = clock.now
        build.cancel()
        _ = await build.value
        let cancellationLatency = cancellationStarted.duration(to: clock.now)
        let completedReads = reads.snapshot()

        emitSearchPerformanceEvidence(
            "cold-cancel latency=\(cancellationLatency) reads=\(completedReads)"
        )
        #expect(cancellationLatency < .milliseconds(250))
        #expect(completedReads < 50)
    }

    @Test
    func cancelledWarmQueryStopsBeforeScanningTheWholeSnapshot() async throws {
        let suiteName = "mudsnote.warm-search-cancellation-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-warm-search-cancellation-tests-\(UUID().uuidString)", isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        for index in 0..<800 {
            try "# Fixture \(index)\n\nshared searchable body \(index)\n".write(
                to: notesDirectory.appendingPathComponent("fixture-\(index).md"),
                atomically: true,
                encoding: .utf8
            )
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)
        let session = store.makeSearchSession(roots: [notesDirectory])
        let reads = LockedSearchReadCounter()
        store.searchIndexEntryWillMatchForTesting = {
            _ = reads.increment()
            Thread.sleep(forTimeInterval: 0.002)
        }

        let search = Task.detached {
            session.searchNotes(
                query: "searchable",
                limit: 30,
                cancellationCheck: { Task.isCancelled }
            )
        }
        let readDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while reads.snapshot() == 0, ContinuousClock.now < readDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(reads.snapshot() > 0)

        let clock = ContinuousClock()
        let cancellationStarted = clock.now
        search.cancel()
        _ = await search.value
        let cancellationLatency = cancellationStarted.duration(to: clock.now)
        let completedReads = reads.snapshot()

        emitSearchPerformanceEvidence(
            "warm-cancel latency=\(cancellationLatency) reads=\(completedReads)"
        )
        #expect(cancellationLatency < .milliseconds(250))
        #expect(completedReads < 50)
    }

    @Test
    func incrementalMultilingualIndexSurvivesAddRenameDeleteAndRelaunch() throws {
        let suiteName = "mudsnote.search-lifecycle-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-search-lifecycle-tests-\(UUID().uuidString)", isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let appSupport = root.appendingPathComponent("AppSupport", isDirectory: true)
        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: appSupport
        )
        store.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)
        let chineseURL = try store.saveNewNote(title: "中文计划", body: "搜索关键字 海风")
        _ = try store.saveNewNote(title: "English Plan", body: "search marker lighthouse")
        #expect(store.prewarmSearchIndex() == 2)
        #expect(store.searchNotes(query: "海风").first?.url == chineseURL)
        #expect(store.searchNotes(query: "LIGHTHOUSE").first?.title == "English Plan")

        let addedURL = notesDirectory.appendingPathComponent("Added.md")
        try "# Added\n\nincremental comet marker\n".write(
            to: addedURL,
            atomically: true,
            encoding: .utf8
        )
        store.searchIndexEntryReadCountForTesting = 0
        store.markSearchIndexDirty(at: [addedURL])
        #expect(store.searchNotes(query: "comet").first?.url == addedURL)
        #expect(store.searchIndexEntryReadCountForTesting == 1)

        let renamedURL = notesDirectory.appendingPathComponent("Renamed.md")
        try FileManager.default.moveItem(at: addedURL, to: renamedURL)
        store.markSearchIndexDirty(at: [addedURL, renamedURL])
        #expect(store.searchNotes(query: "comet").first?.url == renamedURL)

        try FileManager.default.removeItem(at: renamedURL)
        store.markSearchIndexDirty(at: [renamedURL])
        #expect(store.searchNotes(query: "comet").isEmpty)

        let relaunchedStore = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: appSupport
        )
        relaunchedStore.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)
        #expect(relaunchedStore.searchNotes(query: "海风").first?.url == chineseURL)
        #expect(relaunchedStore.searchNotes(query: "comet").isEmpty)
    }

    @Test
    func boundedTopKPreservesTitleScoreThenModificationDateOrdering() throws {
        let suiteName = "mudsnote.search-top-k-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-search-top-k-tests-\(UUID().uuidString)", isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        for index in 0..<60 {
            let title = index < 20 ? "Needle Title \(index)" : "Body Match \(index)"
            let url = notesDirectory.appendingPathComponent("fixture-\(index).md")
            try "# \(title)\n\nneedle body\n".write(
                to: url,
                atomically: true,
                encoding: .utf8
            )
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: TimeInterval(index))],
                ofItemAtPath: url.path
            )
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)
        #expect(store.searchNotes(query: "needle", limit: 10).map(\.title) == [
            "Needle Title 19",
            "Needle Title 18",
            "Needle Title 17",
            "Needle Title 16",
            "Needle Title 15",
            "Needle Title 14",
            "Needle Title 13",
            "Needle Title 12",
            "Needle Title 11",
            "Needle Title 10",
        ])
    }

    @Test
    func malformedOversizedAndOversizedCacheInputsFailSoft() throws {
        let suiteName = "mudsnote.search-fail-soft-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-search-fail-soft-tests-\(UUID().uuidString)", isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        try "# Healthy\n\nrecoverable marker\n".write(
            to: notesDirectory.appendingPathComponent("Healthy.md"),
            atomically: true,
            encoding: .utf8
        )
        try Data([0xFF, 0xFE, 0xFD]).write(
            to: notesDirectory.appendingPathComponent("Malformed.md")
        )
        try Data(count: Int(NoteStore.maximumSearchIndexedFileSize + 1)).write(
            to: notesDirectory.appendingPathComponent("Oversized.md")
        )

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)
        #expect(store.prewarmSearchIndex() == 1)
        #expect(store.searchNotes(query: "recoverable").first?.title == "Healthy")
        #expect(store.searchNotes(query: "oversized").isEmpty)

        let largeBody = String(repeating: "a", count: 7 * 1_024 * 1_024)
        let now = Date()
        let entries = (0..<5).map { index in
            NoteSearchIndexEntry(
                url: notesDirectory.appendingPathComponent("cache-\(index).md"),
                title: "Cache \(index)",
                body: largeBody,
                bodyLower: largeBody,
                snippet: "",
                modifiedAt: now,
                createdAt: now,
                tags: [],
                tagsLower: [],
                knowledgeLayer: nil,
                hasAttachments: false,
                thumbnailURL: nil
            )
        }
        let snapshot = NoteSearchIndexSnapshot(
            rootsKey: [notesDirectory.path],
            fileSignatures: [:],
            entries: entries
        )
        store.writeSearchIndexSnapshotToDisk(snapshot)
        #expect(!FileManager.default.fileExists(atPath: store.searchIndexCacheURL.path))
    }

    @Test
    func largeLibraryColdWarmAndRelaunchLatencyStayWithinBaseline() throws {
        let suiteName = "mudsnote.large-search-baseline-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-large-search-baseline-tests-\(UUID().uuidString)", isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        for index in 0..<1_500 {
            let marker = index.isMultiple(of: 2) ? "lighthouse" : "海风"
            try "# Fixture \(index)\n\n\(marker) searchable body \(index)\n".write(
                to: notesDirectory.appendingPathComponent("fixture-\(index).md"),
                atomically: true,
                encoding: .utf8
            )
        }

        let appSupport = root.appendingPathComponent("AppSupport", isDirectory: true)
        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: appSupport
        )
        store.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)
        let clock = ContinuousClock()
        let coldStarted = clock.now
        let session = store.makeSearchSession(roots: [notesDirectory])
        let coldLatency = coldStarted.duration(to: clock.now)
        #expect(coldLatency < .seconds(6))

        let warmStarted = clock.now
        for index in 0..<40 {
            let query = index.isMultiple(of: 2) ? "lighthouse" : "海风"
            #expect(session.searchNotes(query: query, limit: 30).count == 30)
        }
        let warmLatency = warmStarted.duration(to: clock.now)
        #expect(warmLatency < .seconds(2))

        let relaunchedStore = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: appSupport
        )
        relaunchedStore.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)
        let relaunchStarted = clock.now
        #expect(relaunchedStore.searchNotes(query: "海风", limit: 30).count == 30)
        let relaunchLatency = relaunchStarted.duration(to: clock.now)
        emitSearchPerformanceEvidence(
            "large-library files=1500 cold=\(coldLatency) warm40=\(warmLatency) relaunch=\(relaunchLatency)"
        )
        #expect(relaunchLatency < .seconds(3))
    }
}
