import AppKit
import Carbon.HIToolbox
import CoreServices
import ImageIO
@_spi(Testing) import MudsnoteCore
import Testing
@testable import Mudsnote

extension NSView {
    var allSubviews: [NSView] {
        subviews + subviews.flatMap(\.allSubviews)
    }
}

@MainActor
final class DisplayInvalidationRecordingClipView: NSClipView {
    private(set) var invalidatedRects: [NSRect] = []

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        invalidatedRects.append(invalidRect)
        super.setNeedsDisplay(invalidRect)
    }
}

@MainActor
final class TextStorageEditCounter {
    var count = 0
}

@MainActor
final class ManualResizeDelegate: NSObject, NSWindowDelegate {
    var starts = 0
    var ends = 0
    func windowWillStartLiveResize(_ notification: Notification) { starts += 1 }
    func windowDidEndLiveResize(_ notification: Notification) { ends += 1 }
}

actor LibraryFileSystemChangeRecorder {
    private var changes: Set<LibraryFileSystemChange> = []

    func append(_ newChanges: Set<LibraryFileSystemChange>) {
        changes.formUnion(newChanges)
    }

    func snapshot() -> Set<LibraryFileSystemChange> {
        changes
    }
}

@MainActor
final class SlashCommandInputSourceSessionRecorder: SlashCommandInputSourceSessioning {
    private(set) var beginCalls: [(hasMarkedText: Bool, editorIsFirstResponder: Bool)] = []
    private(set) var endCallCount = 0
    private(set) var isActive = false

    @discardableResult
    func beginIfAllowed(hasMarkedText: Bool, editorIsFirstResponder: Bool) -> Bool {
        beginCalls.append((hasMarkedText, editorIsFirstResponder))
        guard !hasMarkedText, editorIsFirstResponder else { return false }
        isActive = true
        return true
    }

    func end() {
        endCallCount += 1
        isActive = false
    }

    func reset() {
        beginCalls = []
        endCallCount = 0
        isActive = false
    }
}

final class DelayedFileModificationDateProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var readCount = 0
    private var observedMainThread = false

    func read(_ url: URL) -> Date? {
        Thread.sleep(forTimeInterval: 0.35)
        let isMainThread = Thread.isMainThread
        lock.lock()
        readCount += 1
        observedMainThread = observedMainThread || isMainThread
        lock.unlock()
        return (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    func snapshot() -> (readCount: Int, observedMainThread: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (readCount, observedMainThread)
    }
}

final class DraftPersistenceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let beforeRecord: ((DraftSnapshot) -> Void)?
    private var savedTitles: [String] = []
    private var observedMainThread = false

    init(beforeRecord: ((DraftSnapshot) -> Void)? = nil) {
        self.beforeRecord = beforeRecord
    }

    func record(_ snapshot: DraftSnapshot) {
        beforeRecord?(snapshot)
        lock.lock()
        savedTitles.append(snapshot.title)
        observedMainThread = observedMainThread || Thread.isMainThread
        lock.unlock()
    }

    func snapshot() -> (savedTitles: [String], observedMainThread: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (savedTitles, observedMainThread)
    }
}

final class MutableBoolFlag: @unchecked Sendable {
    private var value: Bool
    private let lock = NSLock()

    init(_ initial: Bool) { self.value = initial }

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Bool) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }
}

final class ThreadObservationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var observedMainThread = false
    private var callCount = 0

    func recordCurrentThread() {
        lock.lock()
        callCount += 1
        observedMainThread = observedMainThread || Thread.isMainThread
        lock.unlock()
    }

    func didObserveMainThread() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return observedMainThread
    }

    func snapshot() -> (callCount: Int, observedMainThread: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (callCount, observedMainThread)
    }
}

final class BlockingAutosaveRecorder: @unchecked Sendable {
    let firstWriteStarted = DispatchSemaphore(value: 0)
    let releaseFirstWrite = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var callCount = 0
    private var observedMainThread = false

    func record() {
        lock.lock()
        callCount += 1
        let currentCall = callCount
        observedMainThread = observedMainThread || Thread.isMainThread
        lock.unlock()
        if currentCall == 1 {
            firstWriteStarted.signal()
            releaseFirstWrite.wait()
        }
    }

    func snapshot() -> (callCount: Int, observedMainThread: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (callCount, observedMainThread)
    }
}

@Suite(.serialized)
@MainActor
struct MarkdownRichEditorTests {
    @Test func boundedNoteProjectionStopsAfterReachingItsLimit() {
        var visited = 0
        let matches = LibraryNoteListProjection.prefix(0..<10_000, limit: 240) { value in
            visited += 1
            return value.isMultiple(of: 2)
        }

        #expect(matches.count == 240)
        #expect(matches.first == 0)
        #expect(matches.last == 478)
        #expect(visited == 479)
        #expect(LibraryNoteListProjection.prefix(0..<10_000, limit: 0) { _ in
            Issue.record("A zero-limit projection must not evaluate its predicate")
            return true
        }.isEmpty)
    }

    @Test func rankedNoteProjectionFindsGlobalResultsBeyondModifiedDatePrefix() {
        let now = Date()
        var notes = (0..<1_000).map { index in
            NoteSearchResult(
                url: URL(fileURLWithPath: "/tmp/ranked-\(index).md"),
                title: String(format: "Zulu %04d", index),
                snippet: "",
                modifiedAt: now.addingTimeInterval(TimeInterval(-index)),
                createdAt: now.addingTimeInterval(TimeInterval(-index - 10_000))
            )
        }
        notes[900] = NoteSearchResult(
            url: notes[900].url,
            title: "Alpha Global",
            snippet: "",
            modifiedAt: notes[900].modifiedAt,
            createdAt: now.addingTimeInterval(1_000)
        )

        let titleResults = LibraryNoteListProjection.rankedPrefix(
            notes,
            limit: 240,
            sortOrder: .title,
            groupsByDate: false,
            includesPinnedGroup: false,
            pinnedPaths: []
        ) { _ in true }
        let creationResults = LibraryNoteListProjection.rankedPrefix(
            notes,
            limit: 240,
            sortOrder: .dateCreated,
            groupsByDate: true,
            includesPinnedGroup: false,
            pinnedPaths: []
        ) { _ in true }

        #expect(titleResults.count == 240)
        #expect(titleResults.first?.title == "Alpha Global")
        #expect(creationResults.count == 240)
        #expect(creationResults.first?.title == "Alpha Global")
    }

    @Test func fullLibrarySnapshotKeepsNotesBeyondTenThousandReachable() {
        let root = URL(fileURLWithPath: "/tmp/mudsnote-full-snapshot", isDirectory: true)
        var notes = (0..<10_001).map { index in
            NoteSearchResult(
                url: root.appendingPathComponent("note-\(index).md"),
                title: String(format: "Zulu %05d", index),
                snippet: "",
                modifiedAt: Date(timeIntervalSince1970: Double(10_001 - index)),
                tags: ["archive"],
                hasAttachments: false,
                thumbnailURL: nil
            )
        }
        notes[10_000] = NoteSearchResult(
            url: notes[10_000].url,
            title: "Alpha Oldest",
            snippet: "",
            modifiedAt: notes[10_000].modifiedAt,
            tags: ["archive"],
            hasAttachments: false,
            thumbnailURL: nil
        )

        let snapshot = Array(notes.prefix(LibraryWindowController.sourceCountSnapshotLimit))
        let titleResults = LibraryNoteListProjection.rankedPrefix(
            snapshot,
            limit: 240,
            sortOrder: .title,
            groupsByDate: false,
            includesPinnedGroup: false,
            pinnedPaths: []
        ) { _ in true }
        let countIndex = LibrarySourceCountIndex(
            notes: snapshot,
            folderPaths: [root.path],
            inboxDirectory: root.appendingPathComponent("Inbox", isDirectory: true)
        )

        #expect(snapshot.count == 10_001)
        #expect(titleResults.first?.title == "Alpha Oldest")
        #expect(countIndex.count(forFolder: root) == 10_001)
        #expect(countIndex.count(forTag: "archive") == 10_001)
    }

    @Test func groupedTitleProjectionPrioritizesRecentDateGroupsAndPinnedNotes() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 13,
            hour: 12
        )))
        let recentURL = URL(fileURLWithPath: "/tmp/zulu-today.md")
        let oldURL = URL(fileURLWithPath: "/tmp/alpha-old.md")
        let pinnedURL = URL(fileURLWithPath: "/tmp/pinned-old.md")
        let notes = [
            NoteSearchResult(url: oldURL, title: "Alpha Old", snippet: "", modifiedAt: now.addingTimeInterval(-40 * 86_400)),
            NoteSearchResult(url: recentURL, title: "Zulu Today", snippet: "", modifiedAt: now),
            NoteSearchResult(url: pinnedURL, title: "Pinned Old", snippet: "", modifiedAt: now.addingTimeInterval(-80 * 86_400))
        ]

        let recentFirst = LibraryNoteListProjection.rankedPrefix(
            notes,
            limit: 1,
            sortOrder: .title,
            groupsByDate: true,
            includesPinnedGroup: false,
            pinnedPaths: [],
            now: now,
            calendar: calendar
        ) { _ in true }
        let pinnedFirst = LibraryNoteListProjection.rankedPrefix(
            notes,
            limit: 1,
            sortOrder: .title,
            groupsByDate: true,
            includesPinnedGroup: true,
            pinnedPaths: [pinnedURL.standardizedFileURL.path],
            now: now,
            calendar: calendar
        ) { _ in true }

        #expect(recentFirst.first?.url == recentURL)
        #expect(pinnedFirst.first?.url == pinnedURL)
    }

    @MainActor
    @Test func manualPanelResizeNotifiesItsWindowDelegate() throws {
        let panel = QuickEntryPanel(size: NSSize(width: 400, height: 300))
        let delegate = ManualResizeDelegate()
        panel.delegate = delegate
        defer { panel.close() }
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: NSPoint(x: 1, y: 100), modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        panel.sendEvent(try event(.leftMouseDown))
        #expect(delegate.starts == 1)
        #expect(delegate.ends == 0)
        panel.sendEvent(try event(.leftMouseUp))
        #expect(delegate.ends == 1)
        panel.sendEvent(try event(.leftMouseUp))
        #expect(delegate.ends == 1)
    }

    @Test func rankedTitleProjectionStaysInteractiveAtSnapshotLimit() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-ranked-projection-performance", isDirectory: true)
        let now = Date()
        let notes = (0..<10_000).map { index in
            NoteSearchResult(
                url: root.appendingPathComponent("note-\(index).md"),
                title: String(format: "Note %05d", 10_000 - index),
                snippet: "",
                modifiedAt: now.addingTimeInterval(TimeInterval(-index)),
                createdAt: now.addingTimeInterval(TimeInterval(index))
            )
        }

        let clock = ContinuousClock()
        var results: [NoteSearchResult] = []
        let elapsed = clock.measure {
            results = LibraryNoteListProjection.rankedPrefix(
                notes,
                limit: 240,
                sortOrder: .title,
                groupsByDate: true,
                includesPinnedGroup: true,
                pinnedPaths: [notes[9_000].url.standardizedFileURL.path],
                now: now
            ) { _ in true }
        }

        #expect(elapsed < .milliseconds(100))
        #expect(results.count == 240)
        #expect(results.first?.url == notes[9_000].url)
    }

    @Test func fullLibraryProductionProjectionStaysInteractiveAtSnapshotLimit() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-full-projection-performance", isDirectory: true)
        let now = Date()
        let notes = (0..<10_000).map { index in
            NoteSearchResult(
                url: root.appendingPathComponent("note-\(index).md"),
                title: String(format: "Note %05d", 10_000 - index),
                snippet: "",
                modifiedAt: now.addingTimeInterval(TimeInterval(-index)),
                createdAt: now.addingTimeInterval(TimeInterval(index))
            )
        }

        let clock = ContinuousClock()
        var results: [NoteSearchResult] = []
        let elapsed = clock.measure {
            results = LibraryNoteListProjection.rankedPrefix(
                notes,
                limit: LibraryWindowController.noteListResultLimit,
                sortOrder: .title,
                groupsByDate: true,
                includesPinnedGroup: true,
                pinnedPaths: [notes[9_000].url.standardizedFileURL.path],
                now: now
            ) { _ in true }
        }

        #expect(elapsed < .milliseconds(500))
        #expect(results.count == notes.count)
        #expect(results.first?.url == notes[9_000].url)
    }

    @Test
    func noteSnapshotUpsertKeepsModifiedOrderAndReplacesPaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-snapshot-upsert-\(UUID().uuidString)", isDirectory: true)
        let dates = [300.0, 200.0, 100.0]
        var snapshot = dates.enumerated().map { index, interval in
            NoteSearchResult(
                url: root.appendingPathComponent("note-\(index).md"),
                title: "Note \(index)",
                snippet: "",
                modifiedAt: Date(timeIntervalSince1970: interval),
                tags: [],
                hasAttachments: false,
                thumbnailURL: nil
            )
        }
        let previousURL = snapshot[2].url
        let savedURL = root.appendingPathComponent("renamed.md")
        let updated = NoteSearchResult(
            url: savedURL,
            title: "Updated",
            snippet: "Body",
            modifiedAt: Date(timeIntervalSince1970: 250),
            tags: ["updated"],
            hasAttachments: false,
            thumbnailURL: nil
        )

        LibraryNoteListProjection.upsertByModifiedDate(
            updated,
            into: &snapshot,
            replacingPaths: Set([previousURL.path, savedURL.path]),
            limit: 3
        )

        #expect(snapshot.map(\.title) == ["Note 0", "Updated", "Note 1"])
        #expect(snapshot.map(\.modifiedAt) == snapshot.map(\.modifiedAt).sorted(by: >))
        #expect(snapshot.filter { $0.url.standardizedFileURL == savedURL.standardizedFileURL }.count == 1)
        #expect(snapshot.allSatisfy { $0.url.standardizedFileURL != previousURL.standardizedFileURL })

        LibraryNoteListProjection.upsertByModifiedDate(
            updated,
            into: &snapshot,
            replacingPaths: [savedURL.path],
            limit: 0
        )
        #expect(snapshot.isEmpty)
    }

    @Test
    func noteSnapshotUpsertStaysInteractiveAtSnapshotLimit() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-snapshot-performance", isDirectory: true)
        var snapshot = (0..<10_000).map { index in
            NoteSearchResult(
                url: root.appendingPathComponent("note-\(index).md"),
                title: "Note \(index)",
                snippet: "",
                modifiedAt: Date(timeIntervalSince1970: Double(10_000 - index)),
                tags: [],
                hasAttachments: false,
                thumbnailURL: nil
            )
        }
        let replacement = NoteSearchResult(
            url: root.appendingPathComponent("replacement.md"),
            title: "Replacement",
            snippet: "",
            modifiedAt: Date(timeIntervalSince1970: 9_500.5),
            tags: [],
            hasAttachments: false,
            thumbnailURL: nil
        )

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            LibraryNoteListProjection.upsertByModifiedDate(
                replacement,
                into: &snapshot,
                replacingPaths: [root.appendingPathComponent("note-500.md").path],
                limit: 10_000
            )
        }

        #expect(elapsed < .milliseconds(50))
        #expect(snapshot.count == 10_000)
        #expect(snapshot.map(\.modifiedAt) == snapshot.map(\.modifiedAt).sorted(by: >))
    }

    let theme = MarkdownEditorTheme(
        textColor: NSColor.white,
        mutedTextColor: NSColor.white.withAlphaComponent(0.7),
        accentColor: NSColor.white,
        bodyFont: NSFont.systemFont(ofSize: 14, weight: .regular),
        boldFont: NSFont.systemFont(ofSize: 14, weight: .bold),
        italicFont: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 14, weight: .regular), toHaveTrait: .italicFontMask),
        codeFont: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
    )

    @Test
    func richMarkdownSerializationStaysInteractiveForDenseFormatting() {
        let document = NSMutableAttributedString()
        document.beginEditing()
        for index in 0..<5_000 {
            let font = index.isMultiple(of: 2) ? theme.bodyFont : theme.boldFont
            document.append(NSAttributedString(
                string: "segment\(index) ",
                attributes: [
                    .font: font,
                    .foregroundColor: theme.textColor,
                    .paragraphStyle: theme.paragraphStyle(for: .paragraph),
                    .qmParagraphKind: MarkdownParagraphKind.paragraph.encodedValue
                ]
            ))
        }
        document.endEditing()

        let clock = ContinuousClock()
        var markdown = ""
        let elapsed = clock.measure {
            markdown = MarkdownRichTextCodec.serialize(document, theme: theme)
        }
        let expected = (0..<5_000).map { index in
            index.isMultiple(of: 2) ? "segment\(index) " : "**segment\(index) **"
        }.joined()

        #expect(elapsed < .milliseconds(50))
        #expect(markdown == expected)
    }

    @Test
    func noteListMutationPlanAnimatesOnlyPureInsertionsAndDeletions() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Mutation Plan", isDirectory: true)
        let first = NoteSearchResult(
            url: root.appendingPathComponent("First.md"),
            title: "First",
            snippet: "",
            modifiedAt: Date()
        )
        let second = NoteSearchResult(
            url: root.appendingPathComponent("Second.md"),
            title: "Second",
            snippet: "",
            modifiedAt: Date()
        )
        let previous: [LibraryNoteListRow] = [.note(first)]
        let inserted: [LibraryNoteListRow] = [.note(second), .note(first)]

        let insertion = LibraryNoteListMutationPlan(
            previousRows: previous,
            currentRows: inserted,
            animation: .insertion
        )
        let deletion = LibraryNoteListMutationPlan(
            previousRows: inserted,
            currentRows: previous,
            animation: .deletion
        )

        #expect(insertion?.insertedRows == IndexSet(integer: 0))
        #expect(insertion?.removedRows.isEmpty == true)
        #expect(deletion?.removedRows == IndexSet(integer: 0))
        #expect(deletion?.insertedRows.isEmpty == true)
        #expect(LibraryNoteListMutationPlan(
            previousRows: previous,
            currentRows: inserted,
            animation: .deletion
        ) == nil)

        let movedAfterSave: [LibraryNoteListRow] = [
            .group(title: "今天"),
            .note(first),
            .group(title: "更早"),
            .note(second)
        ]
        let beforeSave: [LibraryNoteListRow] = [
            .group(title: "更早"),
            .note(first),
            .note(second)
        ]
        let refresh = LibraryNoteListMutationPlan(
            previousRows: beforeSave,
            currentRows: movedAfterSave,
            refreshingNotePaths: [first.url.standardizedFileURL.path]
        )
        #expect(refresh?.removedRows == IndexSet(integer: 1))
        #expect(refresh?.insertedRows == IndexSet([0, 1]))
    }

    @MainActor
    @Test
    func tabIndentsEverySelectedLineAndShiftTabOutdentsThem() throws {
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
        textView.markdownPasteTheme = theme
        textView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "First\nSecond\nThird",
            theme: theme
        ))
        textView.setSelectedRange(NSRange(location: 0, length: textView.string.utf16.count))

        textView.keyDown(with: try keyEvent(keyCode: UInt16(kVK_Tab), modifiers: [], characters: "\t"))
        #expect(MarkdownRichTextCodec.serialize(textView.attributedString(), theme: theme) == "\tFirst\n\tSecond\n\tThird")

        textView.keyDown(with: try keyEvent(keyCode: UInt16(kVK_Tab), modifiers: [.shift], characters: "\t"))
        #expect(MarkdownRichTextCodec.serialize(textView.attributedString(), theme: theme) == "First\nSecond\nThird")
    }

    @MainActor
    @Test
    func bareLinksAreDetectedWithoutRewritingMarkdown() throws {
        let markdown = "Visit https://example.com/path and mail hello@example.com"
        let rendered = MarkdownRichTextCodec.render(markdown: markdown, theme: theme)
        let urlLocation = (rendered.string as NSString).range(of: "https://example.com/path").location
        let emailLocation = (rendered.string as NSString).range(of: "hello@example.com").location

        #expect(rendered.attribute(.qmAutomaticLink, at: urlLocation, effectiveRange: nil) as? Bool == true)
        #expect(rendered.attribute(.qmAutomaticLink, at: emailLocation, effectiveRange: nil) as? Bool == true)
        #expect((rendered.attribute(.qmLinkURL, at: emailLocation, effectiveRange: nil) as? String)?.hasPrefix("mailto:") == true)
        #expect(MarkdownRichTextCodec.serialize(rendered, theme: theme) == markdown)

        let textView = MarkdownTextView(frame: .zero)
        textView.markdownPasteTheme = theme
        textView.textStorage?.setAttributedString(rendered)
        #expect(textView.linkReference(atCharacterIndex: urlLocation)?.url == "https://example.com/path")

        textView.textStorage?.setAttributedString(NSAttributedString(
            string: "",
            attributes: theme.baseAttributes(for: .paragraph)
        ))
        textView.insertText("Typed https://openai.com/docs", replacementRange: NSRange(location: 0, length: 0))
        let typedLocation = (textView.string as NSString).range(of: "https://openai.com/docs").location
        #expect(textView.linkReference(atCharacterIndex: typedLocation)?.url == "https://openai.com/docs")

        let veryLongLine = NSString(
            string: String(repeating: "prefix", count: 20_000) + " https://example.com/final"
        )
        let refreshRange = try #require(MarkdownRichTextCodec.automaticLinkRefreshRange(
            in: veryLongLine,
            around: veryLongLine.length
        ))
        #expect(refreshRange.length <= 8_192)
        #expect(veryLongLine.substring(with: refreshRange) == "https://example.com/final")
    }

    @MainActor
    @Test
    func replacingAllContentDropsLongerDocumentTailAndInvalidatesClipView() {
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
        textView.drawsBackground = false
        let scrollView = NSScrollView(frame: textView.frame)
        let clipView = DisplayInvalidationRecordingClipView(frame: textView.frame)
        scrollView.contentView = clipView
        scrollView.documentView = textView
        textView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "Short note\nStale tail from the previous document",
            theme: theme
        ))
        let invalidationCount = clipView.invalidatedRects.count

        textView.replaceAllContent(with: MarkdownRichTextCodec.render(
            markdown: "Short note",
            theme: theme
        ))

        #expect(textView.string == "Short note")
        #expect(clipView.invalidatedRects.count == invalidationCount + 1)
        #expect(clipView.invalidatedRects.last == clipView.bounds)
    }

    @MainActor
    @Test
    func markdownLinksRoundTripBalancedAndEscapedParentheses() {
        let markdown = #"Links [nested](https://host/a_(b)) and [escaped](https://host/a_\(b\))"#
        let rendered = MarkdownRichTextCodec.render(markdown: markdown, theme: theme)
        let nestedLocation = (rendered.string as NSString).range(of: "nested").location
        let escapedLocation = (rendered.string as NSString).range(of: "escaped").location

        #expect(rendered.attribute(.qmLinkURL, at: nestedLocation, effectiveRange: nil) as? String == "https://host/a_(b)")
        #expect(rendered.attribute(.qmLinkURL, at: escapedLocation, effectiveRange: nil) as? String == #"https://host/a_\(b\)"#)
        #expect(MarkdownRichTextCodec.serialize(rendered, theme: theme) == markdown)
    }

    @MainActor
    @Test
    func markdownAttachmentsRoundTripPathsContainingParentheses() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-parenthesized-attachment-tests-\(UUID().uuidString)", isDirectory: true)
        let attachments = root.appendingPathComponent("Attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let noteURL = root.appendingPathComponent("Note.md")
        let fileURL = attachments.appendingPathComponent("spec_(v2).pdf")
        let imageURL = attachments.appendingPathComponent("image_(v2).png")
        try Data("PDF".utf8).write(to: fileURL)
        let pngData = try #require(Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
        ))
        try pngData.write(to: imageURL)

        let markdown = """
        [Spec](Attachments/spec_(v2).pdf)
        ![Diagram](Attachments/image_(v2).png)
        """
        let rendered = MarkdownRichTextCodec.render(
            markdown: markdown,
            theme: theme,
            baseURL: noteURL
        )

        #expect(MarkdownRichTextCodec.serialize(rendered, theme: theme) == markdown)
    }

    @MainActor
    @Test
    func editorMenuCustomizationFiltersContextAndSelectionSurfaces() throws {
        let harness = try makeEditorControllerHarness(
            draftID: "floating-note",
            showsSaveButton: false,
            configureStore: { store in
                store.enabledEditorContextMenuOptions = [.copy, .insertLink]
                store.enabledSelectionToolbarOptions = [.bold, .orderedList]
            }
        )
        defer { harness.tearDown() }

        let floatingController = harness.controller
        floatingController.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "Selected text",
            theme: floatingController.theme
        ))
        floatingController.editorTextView.setSelectedRange(NSRange(location: 0, length: 8))
        #expect(floatingController.editorTextView.conciseEditingMenu(from: NSMenu()).items.map(\.title) == ["拷贝"])
        let floatingSelectionMenu = try #require(floatingController.makeSelectionFormattingMenu())
        #expect(floatingSelectionMenu.items.map(\.title) == ["转换为", "加粗"])
        #expect(floatingSelectionMenu.items.first?.submenu?.items.map(\.title) == ["编号列表"])
        #expect(harness.store.editorContextMenuItemIdentifiers == ["copy", "insertLink"])
        #expect(harness.store.selectionToolbarItemIdentifiers == ["bold", "orderedList"])

        _ = try harness.store.saveNewNote(title: "Custom Menus", body: "Selected text")
        let libraryController = LibraryWindowController(
            noteStore: harness.store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { libraryController.close() }
        libraryController.editorTextView.setSelectedRange(NSRange(location: 0, length: 8))
        let selectionMenu = try #require(libraryController.makeSelectionFormattingMenuForLibrary())
        #expect(selectionMenu.items.map(\.title) == ["转换为", "加粗"])
        #expect(selectionMenu.items.first?.submenu?.items.map(\.title) == ["编号列表"])

        let contextMenu = libraryController.editorTextView.conciseEditingMenu(from: NSMenu())
        let contextEvent = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: libraryController.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        libraryController.editorTextView.configureContextMenu?(contextMenu, contextEvent)
        #expect(contextMenu.items.first?.title == "插入")
        #expect(contextMenu.items.last { $0.title == "插入" }?.submenu?.items.map(\.title) == ["链接…"])

        harness.store.selectionToolbarItemIdentifiers = ["bold", "underline", "strikethrough"]
        #expect(harness.store.enabledSelectionToolbarOptions == [.bold, .link])
    }

    @MainActor
    @Test
    func wordCountScansVisibleEditorTextWithoutSerializingHiddenMarkdownTargets() async throws {
        let harness = try makeEditorControllerHarness(
            draftID: "visible-word-count",
            showsSaveButton: false
        )
        defer { harness.tearDown() }
        let markdown = "[Visible](https://example.com/hidden/path) 中文"
        let editorController = harness.controller
        editorController.editorTextView.textStorage?.setAttributedString(
            MarkdownRichTextCodec.render(markdown: markdown, theme: editorController.theme)
        )
        editorController.updateWordCount()
        #expect(editorController.wordCountLabel.stringValue == "3 字")

        _ = try harness.store.saveNewNote(title: "Title", body: markdown)
        let libraryController = LibraryWindowController(
            noteStore: harness.store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { libraryController.close() }

        #expect(libraryController.titleField.stringValue == "Title")
        #expect(libraryController.wordCountLabel.stringValue == "3 字")
        libraryController.editorTextView.setSelectedRange(
            NSRange(location: libraryController.editorTextView.string.utf16.count, length: 0)
        )
        libraryController.editorTextView.insertText(
            " Added",
            replacementRange: libraryController.editorTextView.selectedRange()
        )
        libraryController.textDidChange(Notification(
            name: NSText.didChangeNotification,
            object: libraryController.editorTextView
        ))
        #expect(libraryController.titleField.stringValue == "Title")
        try await Task.sleep(for: .milliseconds(250))
        #expect(libraryController.wordCountLabel.stringValue == "4 字")
    }

    @MainActor
    @Test
    func shiftReturnCreatesPersistentShortSpacedLineBreak() throws {
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        textView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(markdown: "First", theme: theme))
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        textView.keyDown(with: try keyEvent(
            keyCode: UInt16(kVK_Return),
            modifiers: [.shift],
            characters: "\r"
        ))
        textView.insertText("Second", replacementRange: textView.selectedRange())

        let markdown = MarkdownRichTextCodec.serialize(textView.attributedString(), theme: theme)
        #expect(textView.string == "First\u{2028}Second")
        #expect(markdown == "First  \nSecond")

        let reopened = MarkdownRichTextCodec.render(markdown: markdown, theme: theme)
        #expect(reopened.string == "First\u{2028}Second")
        let style = try #require(reopened.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(style.lineSpacing == theme.lineSpacing)
        #expect(style.paragraphSpacing == theme.paragraphSpacing)
    }

    @MainActor
    @Test
    func doubleClickSelectionTrimsTrailingWhitespaceAndSnapsToWord() {
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        textView.markdownPasteTheme = theme
        textView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "hello world\n\nnext line",
            theme: theme
        ))
        let string = textView.string as NSString

        // Double-click at the boundary between the word and the newline.
        // The default AppKit selection would be just the newline; the fix
        // should snap to the word "world" instead.
        let boundary = textView.selectionRange(forProposedRange: NSRange(location: 11, length: 0), granularity: .selectByWord)
        #expect(boundary == NSRange(location: 6, length: 5))
        #expect(string.substring(with: boundary) == "world")

        // Double-click in the middle of the word still selects the whole word.
        let middle = textView.selectionRange(forProposedRange: NSRange(location: 8, length: 0), granularity: .selectByWord)
        #expect(middle == NSRange(location: 6, length: 5))

        // Double-click on the blank line should snap to the preceding word and
        // never include the blank line itself.
        let onBlank = textView.selectionRange(forProposedRange: NSRange(location: 12, length: 0), granularity: .selectByWord)
        #expect(string.substring(with: onBlank) == "world")
        #expect(!string.substring(with: onBlank).contains("\n"))

        // Double-click on a long word that already extends across the line
        // should still drop the trailing newline.
        let trailingSpace = textView.selectionRange(forProposedRange: NSRange(location: 5, length: 0), granularity: .selectByWord)
        #expect(trailingSpace == NSRange(location: 0, length: 5))
        #expect(string.substring(with: trailingSpace) == "hello")
    }

    @MainActor
    @Test
    func shiftReturnOnFirstLineHeadingBreaksIntoBodyParagraph() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        // Realistic scenario: the user has typed only the title on the first
        // line and is about to add a second line. The caret sits at the end
        // of the heading.
        let markdown = "# Title"
        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: markdown,
            theme: controller.theme
        ))
        controller.hasAutomaticTitleFormatting = true
        let titleLine = controller.editorTextView.string.utf16.count
        controller.editorTextView.setSelectedRange(NSRange(location: titleLine, length: 0))

        controller.editorTextView.keyDown(with: try keyEvent(
            keyCode: UInt16(kVK_Return),
            modifiers: [.shift],
            characters: "\r"
        ))

        let storage = try #require(controller.editorTextView.textStorage)
        let rendered = MarkdownRichTextCodec.serialize(storage, theme: controller.theme)
        // The fix breaks out of the heading paragraph so the continuation is a
        // body paragraph; the title line must not carry a hard-break marker
        // (which is the symptom of a soft line break inside a heading).
        #expect(!rendered.contains("  \n"))
        #expect(!rendered.hasPrefix("# "))
        let titleKind = MarkdownRichTextCodec.paragraphKind(
            at: NSRange(location: 0, length: min(storage.length, 1)),
            in: storage
        )
        #expect(titleKind == .paragraph)
        // The second paragraph (after the title) must NOT carry the heading
        // kind — it should be a body paragraph so the title format only
        // applies to the first line.
        guard storage.length > titleLine else {
            Issue.record("Shift+Return did not leave the title line")
            return
        }
        let insertion = controller.editorTextView.selectedRange().location
        #expect(insertion > titleLine)
        let bodyKind = MarkdownRichTextCodec.paragraphKind(
            at: NSRange(location: min(insertion, storage.length), length: 0),
            in: storage
        )
        #expect(bodyKind == .paragraph)
    }

    @MainActor
    @Test
    func manuallyAppliedFirstLineHeadingRemainsHeadingAfterShiftReturn() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "# Manual title",
            theme: controller.theme
        ))
        controller.hasAutomaticTitleFormatting = false
        controller.editorTextView.setSelectedRange(NSRange(
            location: controller.editorTextView.string.utf16.count,
            length: 0
        ))

        controller.editorTextView.keyDown(with: try keyEvent(
            keyCode: UInt16(kVK_Return),
            modifiers: [.shift],
            characters: "\r"
        ))

        let storage = try #require(controller.editorTextView.textStorage)
        let titleKind = MarkdownRichTextCodec.paragraphKind(
            at: NSRange(location: 0, length: min(storage.length, 1)),
            in: storage
        )
        #expect(titleKind == .heading(level: 1))
    }

    @MainActor
    @Test
    func shiftReturnOnLaterHeadingPreservesSoftBreak() throws {
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        textView.markdownPasteTheme = theme
        // Mid-document heading: the rule is title format only on the first
        // line, so a heading elsewhere still accepts a soft line break.
        textView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "body line\n\n## Section",
            theme: theme
        ))
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))

        textView.keyDown(with: try keyEvent(
            keyCode: UInt16(kVK_Return),
            modifiers: [.shift],
            characters: "\r"
        ))

        let string = textView.string
        #expect(string.contains("\u{2028}"))
    }

    @MainActor
    @Test
    func shiftReturnDuringMarkedTextDoesNotInsertDirectly() throws {
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        textView.markdownPasteTheme = theme
        textView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(markdown: "你好", theme: theme))
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        // Simulate an in-progress IME composition (e.g. pinyin "ni").
        textView.setMarkedText(
            "ni",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: textView.selectedRange()
        )
        let stringBefore = textView.string as NSString

        textView.keyDown(with: try keyEvent(
            keyCode: UInt16(kVK_Return),
            modifiers: [.shift],
            characters: "\r"
        ))

        #expect(!textView.hasMarkedText())
        #expect(textView.string.contains("\u{2028}"))
        // Sanity: the original characters are preserved.
        let stringAfter = textView.string as NSString
        for char in "你好ni" {
                #expect(stringAfter.contains(String(char)))
        }
        _ = stringBefore
    }

    @MainActor
    @Test
    func commandVPasteKeyEquivalentDoesNotHijackOtherFocusedControl() {
        // The editor must not steal Cmd+V when another text input (e.g. a
        // search field) is the first responder. Direct test of the guard:
        // when firstResponder is not the editor, the editor's
        // performKeyEquivalent returns false for Cmd+V so the search field
        // handles the paste natively.
        let editor = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        editor.markdownPasteTheme = theme
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.contentView = nil }
        let container = NSView(frame: window.contentLayoutRect)
        window.contentView = container
        container.addSubview(editor)
        let searchField = NSSearchField(frame: NSRect(x: 320, y: 0, width: 140, height: 24))
        container.addSubview(searchField)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(searchField)

        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.setString("from-search-field", forType: .string)
        editor.pasteboardForPaste = { pasteboard }

        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "v",
            charactersIgnoringModifiers: "v",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_V)
        )!
        // The search field owns the focus, so the editor must NOT intercept
        // the key equivalent — Cmd+V must fall through to the search field.
        let responder = window.firstResponder
        #expect(responder !== editor)
        #expect(editor.performKeyEquivalent(with: event) == false)
    }

    @Test
    func richCodecRoundTripsHeadingAndLists() {
        let markdown = """
        # Smoke Title

        - [ ] alpha
        1. first
        2. next
        """

        let attributed = MarkdownRichTextCodec.render(markdown: markdown, theme: theme)
        let serialized = MarkdownRichTextCodec.serialize(attributed, theme: theme)

        #expect(serialized == markdown)
    }

    @Test
    func richCodecRoundTripsHeadingLevelsAndChineseItalic() {
        let markdown = """
        # Heading 1
        ## Heading 2
        ### Heading 3
        *中文斜体*
        """

        let attributed = MarkdownRichTextCodec.render(markdown: markdown, theme: theme)
        let chineseRange = (attributed.string as NSString).range(of: "中文斜体")
        let obliqueness = attributed.attribute(.obliqueness, at: chineseRange.location, effectiveRange: nil) as? NSNumber
        let serialized = MarkdownRichTextCodec.serialize(attributed, theme: theme)

        #expect(chineseRange.location != NSNotFound)
        #expect((obliqueness?.doubleValue ?? 0) > 0)
        #expect(serialized == markdown)
    }

    @Test
    func richCodecRemovesMarkdownMarkersFromVisibleText() {
        let markdown = """
        # Heading
        - [ ] task
        """

        let attributed = MarkdownRichTextCodec.render(markdown: markdown, theme: theme)
        let visible = attributed.string
        let checklistAttachment = attributed.attribute(.attachment, at: 8, effectiveRange: nil) as? NSTextAttachment

        #expect(!visible.contains("# "))
        #expect(!visible.contains("- [ ]"))
        #expect(visible.contains("Heading"))
        #expect(checklistAttachment != nil)
    }

    @Test
    func richCodecTreatsBracketShortcutsAsChecklist() {
        let squareRendered = MarkdownRichTextCodec.renderLine("[] ", theme: theme)
        let fullWidthRendered = MarkdownRichTextCodec.renderLine("【】 task", theme: theme)

        #expect(squareRendered.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment != nil)
        #expect(fullWidthRendered.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment != nil)
        #expect(MarkdownRichTextCodec.serialize(squareRendered, theme: theme) == "- [ ] ")
        #expect(MarkdownRichTextCodec.serialize(fullWidthRendered, theme: theme) == "- [ ] task")
    }

    @Test
    func richCodecRendersLocalMarkdownImagesAndSerializesPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-rich-image-tests-\(UUID().uuidString)", isDirectory: true)
        let noteURL = root.appendingPathComponent("Note.md")
        let imageURL = root
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent("preview.png")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pngData = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="))
        try pngData.write(to: imageURL)

        let markdown = "Before\n![Preview](Attachments/preview.png)\nAfter"
        let rendered = MarkdownRichTextCodec.render(markdown: markdown, theme: theme, baseURL: noteURL)
        var imageMarkdown: String?
        rendered.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rendered.length)) { value, range, stop in
            guard value as? NSTextAttachment != nil else { return }
            imageMarkdown = rendered.attribute(.qmImageMarkdown, at: range.location, effectiveRange: nil) as? String
            stop.pointee = true
        }

        #expect(imageMarkdown == "![Preview](Attachments/preview.png)")
        #expect(MarkdownRichTextCodec.serialize(rendered, theme: theme) == markdown)
    }

    @Test
    func imageDisplaySizingPreservesAspectRatioAndBounds() {
        let naturalSize = NSSize(width: 840, height: 480)
        let fitted = MarkdownImageDisplaySizing.fitSize(for: naturalSize)
        let preferred = MarkdownImageDisplaySizing.displaySize(
            for: naturalSize,
            preferredWidth: 315
        )

        #expect(fitted == NSSize(width: 420, height: 240))
        #expect(preferred == NSSize(width: 315, height: 180))
        #expect(MarkdownImageDisplaySizing.clampedWidth(20) == 80)
        #expect(MarkdownImageDisplaySizing.clampedWidth(1_400) == 1_200)
    }

    @MainActor
    @Test
    func richCodecDefersImagePixelDecodingUntilAttachmentDrawing() async throws {
        await MarkdownImageDecodeService.shared.resetForTesting()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-async-image-tests-\(UUID().uuidString)", isDirectory: true)
        let noteURL = root.appendingPathComponent("Note.md")
        let imageURL = root.appendingPathComponent("preview.png")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pngData = try #require(Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
        ))
        try pngData.write(to: imageURL)

        let rendered = MarkdownRichTextCodec.render(
            markdown: "![Preview](preview.png)",
            theme: theme,
            baseURL: noteURL
        )
        let attachment = try #require(
            rendered.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
        )
        let cell = try #require(attachment.attachmentCell as? AsyncImageAttachmentCell)

        #expect(!cell.hasDecodedImage)
        #expect(cell.naturalSize == NSSize(width: 1, height: 1))

        cell.beginDecodingIfNeeded(in: nil)
        for _ in 0..<100 where !cell.hasDecodedImage {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(cell.hasDecodedImage)
        let firstDecodeCount = await MarkdownImageDecodeService.shared.decodeCount
        #expect(firstDecodeCount == 1)

        let secondRendered = MarkdownRichTextCodec.render(
            markdown: "![Preview](preview.png)",
            theme: theme,
            baseURL: noteURL
        )
        let secondAttachment = try #require(
            secondRendered.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
        )
        let secondCell = try #require(secondAttachment.attachmentCell as? AsyncImageAttachmentCell)
        secondCell.beginDecodingIfNeeded(in: nil)
        for _ in 0..<100 where !secondCell.hasDecodedImage {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(secondCell.hasDecodedImage)
        let cachedDecodeCount = await MarkdownImageDecodeService.shared.decodeCount
        #expect(cachedDecodeCount == 1)

        var revisedPNGData = pngData
        revisedPNGData.append(0)
        try revisedPNGData.write(to: imageURL, options: .atomic)
        let revisedRendered = MarkdownRichTextCodec.render(
            markdown: "![Preview](preview.png)",
            theme: theme,
            baseURL: noteURL
        )
        let revisedAttachment = try #require(
            revisedRendered.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
        )
        let revisedCell = try #require(revisedAttachment.attachmentCell as? AsyncImageAttachmentCell)
        revisedCell.beginDecodingIfNeeded(in: nil)
        for _ in 0..<100 where !revisedCell.hasDecodedImage {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(revisedCell.hasDecodedImage)
        let revisedDecodeCount = await MarkdownImageDecodeService.shared.decodeCount
        #expect(revisedDecodeCount == 2)
        revisedCell.reloadImage(in: nil)
        for _ in 0..<100 where !revisedCell.hasDecodedImage {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(revisedCell.hasDecodedImage)
        let forcedDecodeCount = await MarkdownImageDecodeService.shared.decodeCount
        #expect(forcedDecodeCount == 3)
    }

    @Test
    func richCodecRendersLocalMarkdownFileAttachmentsAndSerializesPath() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-rich-file-attachment-tests-\(UUID().uuidString)", isDirectory: true)
        let noteURL = root.appendingPathComponent("Note.md")
        let attachmentURL = root
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent("source file.pdf")
        try FileManager.default.createDirectory(at: attachmentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "pdf".write(to: attachmentURL, atomically: true, encoding: .utf8)

        let markdown = "Before\n[source file](Attachments/source%20file.pdf)\nAfter"
        let rendered = MarkdownRichTextCodec.render(markdown: markdown, theme: theme, baseURL: noteURL)
        var attachmentMarkdown: String?
        var attachmentFilePath: String?
        var attachmentMetadata: String?
        rendered.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rendered.length)) { value, range, stop in
            guard value as? NSTextAttachment != nil else { return }
            attachmentMarkdown = rendered.attribute(.qmAttachmentMarkdown, at: range.location, effectiveRange: nil) as? String
            attachmentFilePath = rendered.attribute(.qmAttachmentFilePath, at: range.location, effectiveRange: nil) as? String
            attachmentMetadata = rendered.attribute(.qmAttachmentMetadata, at: range.location, effectiveRange: nil) as? String
            stop.pointee = true
        }

        #expect(attachmentMarkdown == "[source file](Attachments/source%20file.pdf)")
        #expect(attachmentFilePath == attachmentURL.path)
        #expect(attachmentMetadata?.hasPrefix("PDF · ") == true)
        #expect(MarkdownRichTextCodec.serialize(rendered, theme: theme) == markdown)
    }

    @Test
    func richCodecShowsEmptyListPrefixesImmediately() {
        let bulletRendered = MarkdownRichTextCodec.renderLine("- ", theme: theme)
        let orderedRendered = MarkdownRichTextCodec.renderLine("1. ", theme: theme)

        #expect(bulletRendered.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment != nil)
        #expect(orderedRendered.string == "1. ")
        #expect(MarkdownRichTextCodec.serialize(bulletRendered, theme: theme) == "- ")
        #expect(MarkdownRichTextCodec.serialize(orderedRendered, theme: theme) == "1. ")
    }

    @MainActor
    @Test
    func deletingChecklistPrefixResetsLineToParagraph() throws {
        let harness = try makeEditorControllerHarness(draftID: "standard-editor", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let rendered = MarkdownRichTextCodec.renderLine("- [ ] task", theme: controller.theme)
        controller.editorTextView.textStorage?.setAttributedString(rendered)
        controller.editorTextView.textStorage?.deleteCharacters(in: NSRange(location: 0, length: 1))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 0))

        controller.userDidEdit()

        let storage = try #require(controller.editorTextView.textStorage)
        let lineRange = NSRange(location: 0, length: storage.length)
        #expect(storage.string == "task")
        #expect(storage.attribute(.attachment, at: 0, effectiveRange: nil) == nil)
        #expect(MarkdownRichTextCodec.paragraphKind(at: lineRange, in: storage) == .paragraph)
        #expect(MarkdownRichTextCodec.serialize(storage, theme: controller.theme) == "task")
        #expect(controller.toolbarButtonsByAction[.checklist]?.isActive == false)
    }

    @Test
    func richCodecInterpretsBareBulletPrefixAsSoonAsSpaceIsTyped() {
        #expect(MarkdownRichTextCodec.shouldInterpretMarkdown(in: "- "))
        #expect(MarkdownRichTextCodec.shouldInterpretMarkdown(in: "* "))
        #expect(MarkdownRichTextCodec.shouldInterpretMarkdown(in: "+ "))
    }

    @Test
    func richCodecKeepsBodyHashtagsAsOrdinaryText() {
        let rendered = MarkdownRichTextCodec.renderLine("hello #alpha world", theme: theme)
        let visible = rendered.string as NSString
        let tagRange = visible.range(of: "#alpha")
        let color = rendered.attribute(.foregroundColor, at: tagRange.location, effectiveRange: nil) as? NSColor
        let isTag = rendered.attribute(.qmTag, at: tagRange.location, effectiveRange: nil) as? Bool

        #expect(tagRange.location != NSNotFound)
        #expect(isTag == nil)
        #expect(color == theme.textColor)
        #expect(MarkdownRichTextCodec.serialize(rendered, theme: theme) == "hello #alpha world")
    }

    @MainActor
    @Test
    func metadataTagBarReservesBodySpaceWithoutAnEmptyParagraph() throws {
        let textView = MarkdownTextView(
            frame: NSRect(x: 0, y: 0, width: 480, height: 240)
        )
        let markdown = MarkdownEditorDocument.composeEditorText(
            title: "信念",
            body: "正文首行",
            hasMetadataTags: true
        )
        textView.replaceAllContent(with: MarkdownRichTextCodec.render(
            markdown: markdown,
            theme: theme
        ))
        textView.setMetadataTags(["个人感悟", "知识管理"])

        let layoutManager = try #require(textView.layoutManager)
        let textContainer = try #require(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let bodyRange = (textView.string as NSString).range(of: "正文首行")
        let bodyGlyphRange = layoutManager.glyphRange(
            forCharacterRange: bodyRange,
            actualCharacterRange: nil
        )
        let bodyRect = layoutManager.boundingRect(
            forGlyphRange: bodyGlyphRange,
            in: textContainer
        )
        let tagBar = try #require(
            textView.subviews.compactMap { $0 as? NSScrollView }.first
        )

        #expect(textView.string == "信念\n正文首行")
        #expect(tagBar.frame.maxY <= textView.textContainerInset.height + bodyRect.minY)

        textView.textStorage?.addAttribute(
            .paragraphStyle,
            value: theme.paragraphStyle(for: .heading(level: 1)),
            range: NSRange(location: 0, length: 2)
        )
        textView.didChangeText()
        let reserve = textView.textStorage?.attribute(
            .qmMetadataTagReserve,
            at: 0,
            effectiveRange: nil
        ) as? CGFloat
        #expect(reserve == 36)
    }

    @Test
    func richCodecRoundTripsPortableHighlightedFormatting() throws {
        let markdown = "Keep <mark>**important**</mark> text"
        let rendered = MarkdownRichTextCodec.render(markdown: markdown, theme: theme)
        let importantRange = (rendered.string as NSString).range(of: "important")

        #expect((rendered.attribute(.qmHighlight, at: importantRange.location, effectiveRange: nil) as? Bool) == true)
        #expect(rendered.attribute(.backgroundColor, at: importantRange.location, effectiveRange: nil) as? NSColor != nil)
        let font = try #require(rendered.attribute(.font, at: importantRange.location, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        #expect(MarkdownRichTextCodec.serialize(rendered, theme: theme) == markdown)
    }

    @Test
    func editorContextMenuKeepsOnlyConciseNativeEditingCommands() {
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        let nativeMenu = NSMenu()
        nativeMenu.addItem(NSMenuItem(title: "查询", action: Selector(("lookUp:")), keyEquivalent: ""))
        nativeMenu.addItem(NSMenuItem(title: "翻译“文字”", action: Selector(("translate:")), keyEquivalent: ""))
        nativeMenu.addItem(.separator())
        nativeMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        nativeMenu.addItem(NSMenuItem(title: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        nativeMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        nativeMenu.addItem(NSMenuItem(title: "粘贴并匹配样式", action: nil, keyEquivalent: ""))

        let conciseMenu = textView.conciseEditingMenu(from: nativeMenu)
        #expect(!conciseMenu.allowsContextMenuPlugIns)
        #expect(conciseMenu.items.map(\.title) == ["撤销", "", "剪切", "拷贝", "粘贴"])
        #expect(conciseMenu.items.first?.keyEquivalent == "z")
        #expect(conciseMenu.items.first?.keyEquivalentModifierMask == [.command])
        #expect(conciseMenu.items.first?.image != nil)

        textView.sealContextMenu(conciseMenu)
        conciseMenu.addItem(NSMenuItem(title: "自动填充", action: nil, keyEquivalent: ""))
        conciseMenu.addItem(NSMenuItem(title: "服务", action: nil, keyEquivalent: ""))
        #expect(conciseMenu.items.map(\.title) == ["撤销", "", "剪切", "拷贝", "粘贴"])
    }

    @Test
    func editorTrailingWhitespaceContextClickPreservesSelection() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 160))
        textView.string = "First line\nSecond line"
        window.contentView = textView
        textView.layoutManager?.ensureLayout(for: try #require(textView.textContainer))
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        let event = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: NSPoint(x: 300, y: 150),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        #expect(textView.isEventInTrailingLineWhitespace(event))
        _ = textView.menu(for: event)
        #expect(textView.selectedRange() == NSRange(location: 0, length: 0))
    }

    @Test
    func richCodecKeepsEmptyBacktickPairVisibleWhileTyping() {
        let rendered = MarkdownRichTextCodec.renderLine("``", theme: theme)

        #expect(rendered.string == "``")
        #expect(rendered.attribute(.qmCode, at: 0, effectiveRange: nil) == nil)
        #expect(MarkdownRichTextCodec.serialize(rendered, theme: theme) == "``")
    }

    @MainActor
    @Test
    func bareTagAndMentionTriggersShowImmediateGuidanceInTheLiveEditor() async throws {
        let harness = try makeEditorControllerHarness(
            draftID: "quick-capture",
            showsSaveButton: true
        )
        defer { harness.tearDown() }
        let controller = harness.controller
        controller.window?.makeFirstResponder(controller.editorTextView)

        controller.editorTextView.string = "#"
        controller.editorTextView.setSelectedRange(NSRange(location: 1, length: 0))
        NotificationCenter.default.post(
            name: NSText.didChangeNotification,
            object: controller.editorTextView
        )
        await Task.yield()
        await Task.yield()

        guard case .tags(let tagQuery, _, let tagItems) = controller.inlineSuggestionContext else {
            Issue.record("Expected immediate tag guidance after typing #")
            return
        }
        #expect(tagQuery.isEmpty)
        #expect(tagItems.isEmpty)
        #expect(!controller.suggestionController.view.isHidden)

        let scrollView = try #require(
            controller.suggestionController.view.subviews.compactMap { $0 as? NSScrollView }.first
        )
        let listView = try #require(scrollView.documentView as? SuggestionListView)
        #expect(listView.items == [
            SuggestionItem(
                title: "输入标签名称",
                subtitle: "继续输入，空格或回车确认",
                symbolName: "number",
                isSelectable: false
            )
        ])

        controller.editorTextView.string = "@"
        controller.editorTextView.setSelectedRange(NSRange(location: 1, length: 0))
        NotificationCenter.default.post(
            name: NSText.didChangeNotification,
            object: controller.editorTextView
        )
        await Task.yield()
        await Task.yield()

        guard case .notes(let noteQuery, _, let noteItems) = controller.inlineSuggestionContext else {
            Issue.record("Expected immediate note guidance after typing @")
            return
        }
        #expect(noteQuery.isEmpty)
        #expect(noteItems.isEmpty)
        #expect(!controller.suggestionController.view.isHidden)
        #expect(listView.items == [
            SuggestionItem(
                title: "输入笔记标题",
                subtitle: "相关笔记会随输入更新",
                symbolName: "note.text",
                isSelectable: false
            )
        ])
    }

    @Test
    func optionRFloatingHotKeyParses() throws {
        let spec = try #require(HotKeySpec.parse("option+r"))

        #expect(spec.keyCode == UInt32(kVK_ANSI_R))
        #expect(spec.modifiers == UInt32(optionKey))
        #expect(spec.displayString == "option+r")
        #expect(spec.userVisibleString == "⌥R")
    }

    @Test
    func hotKeySpecRecognizesRecordedEvents() throws {
        let floatingEvent = try keyEvent(keyCode: UInt16(kVK_ANSI_R), modifiers: [.option], characters: "r")
        let floatingSpec = try #require(HotKeySpec.from(event: floatingEvent))
        #expect(floatingSpec.displayString == "option+r")
        #expect(floatingSpec.userVisibleString == "⌥R")

        let saveEvent = try keyEvent(keyCode: UInt16(kVK_Return), modifiers: [.command], characters: "\r")
        let saveSpec = try #require(HotKeySpec.from(event: saveEvent))
        #expect(saveSpec.displayString == "command+return")
        #expect(saveSpec.userVisibleString == "⌘↩")
    }

    @MainActor
    @Test
    func shortcutRecorderCapturesKeyEquivalentStyleShortcut() throws {
        let recorder = ShortcutRecorderButton(shortcutString: "option+r")
        let mouseEvent = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        recorder.mouseDown(with: mouseEvent)

        #expect(recorder.isRecording)

        let event = try keyEvent(keyCode: UInt16(kVK_Return), modifiers: [.command], characters: "\r")
        recorder.recordShortcutEvent(event)

        #expect(!recorder.isRecording)
        #expect(recorder.shortcutString == "command+return")
        #expect(recorder.title == "⌘↩")
    }

    @MainActor
    @Test
    func formattingKeyboardShortcutsApplyExpectedStylesAndParagraphKinds() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(
            string: "selected text",
            attributes: controller.theme.baseAttributes(for: .paragraph)
        ))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 8))

        #expect(controller.handleShortcutEvent(try keyEvent(keyCode: UInt16(kVK_ANSI_B), modifiers: [.command], characters: "b")))
        #expect(controller.handleShortcutEvent(try keyEvent(keyCode: UInt16(kVK_ANSI_I), modifiers: [.command], characters: "i")))
        #expect(controller.handleShortcutEvent(try keyEvent(keyCode: UInt16(kVK_ANSI_U), modifiers: [.command], characters: "u")))
        #expect(controller.handleShortcutEvent(try keyEvent(keyCode: UInt16(kVK_ANSI_X), modifiers: [.command, .shift], characters: "X")))

        let storage = try #require(controller.editorTextView.textStorage)
        let font = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let traits = NSFontManager.shared.traits(of: font)
        #expect(traits.contains(.boldFontMask))
        #expect(traits.contains(.italicFontMask))
        #expect((storage.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int) == NSUnderlineStyle.single.rawValue)
        #expect((storage.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int) == NSUnderlineStyle.single.rawValue)

        let heading1Kind = try paragraphKind(after: keyEvent(keyCode: UInt16(kVK_ANSI_1), modifiers: [.command, .option], characters: "1"), controller: controller)
        let heading2Kind = try paragraphKind(after: keyEvent(keyCode: UInt16(kVK_ANSI_2), modifiers: [.command, .option], characters: "2"), controller: controller)
        let heading3Kind = try paragraphKind(after: keyEvent(keyCode: UInt16(kVK_ANSI_3), modifiers: [.command, .option], characters: "3"), controller: controller)
        let orderedKind = try paragraphKind(after: keyEvent(keyCode: UInt16(kVK_ANSI_7), modifiers: [.command, .shift], characters: "&"), controller: controller)
        let bulletKind = try paragraphKind(after: keyEvent(keyCode: UInt16(kVK_ANSI_8), modifiers: [.command, .shift], characters: "*"), controller: controller)
        let checklistKind = try paragraphKind(after: keyEvent(keyCode: UInt16(kVK_ANSI_9), modifiers: [.command, .shift], characters: "("), controller: controller)

        #expect(heading1Kind.headingLevel == 1)
        #expect(heading2Kind.headingLevel == 2)
        #expect(heading3Kind.headingLevel == 3)
        #expect(orderedKind.isOrderedList)
        #expect(bulletKind.isBulletList)
        #expect(checklistKind.isChecklist)
    }

    @MainActor
    @Test
    func italicShortcutAppliesObliquenessForChineseText() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(
            string: "中文斜体",
            attributes: controller.theme.baseAttributes(for: .paragraph)
        ))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 4))

        #expect(controller.handleShortcutEvent(try keyEvent(keyCode: UInt16(kVK_ANSI_I), modifiers: [.command], characters: "i")))

        let storage = try #require(controller.editorTextView.textStorage)
        let obliqueness = storage.attribute(.obliqueness, at: 0, effectiveRange: nil) as? NSNumber
        #expect((obliqueness?.doubleValue ?? 0) > 0)
        #expect(MarkdownRichTextCodec.serialize(storage, theme: controller.theme) == "*中文斜体*")
    }

    @Test
    func clampedPanelFrameMovesOffscreenFrameIntoVisibleArea() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let offscreen = NSRect(x: 35, y: -288, width: 322, height: 416)

        let clamped = clampedPanelFrame(
            offscreen,
            fallbackSize: NSSize(width: 412, height: 314),
            visibleFrames: [visible]
        )

        #expect(clamped.origin.y >= visible.minY)
        #expect(visible.contains(NSPoint(x: clamped.midX, y: clamped.midY)))
        #expect(clamped.size == offscreen.size)

        let minimumSized = clampedPanelFrame(
            NSRect(x: -900, y: -700, width: 200, height: 100),
            fallbackSize: NSSize(width: 1080, height: 720),
            visibleFrames: [visible],
            minimumSize: NSSize(width: 1040, height: 620)
        )
        #expect(minimumSized.size == NSSize(width: 1040, height: 620))
        #expect(visible.contains(NSPoint(x: minimumSized.midX, y: minimumSized.midY)))
    }

    @MainActor
    @Test
    func toolbarMouseDownFormatsPreviouslySelectedTextAfterSelectionCollapse() throws {
        let harness = try makeEditorControllerHarness(draftID: "standard-editor", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let boldButton = try #require(controller.toolbarButtonsByAction[.bold])
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(string: "selected text", attributes: controller.theme.baseAttributes(for: .paragraph)))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 8))
        controller.rememberEditorSelectionForToolbarActions()
        controller.editorTextView.setSelectedRange(NSRange(location: 13, length: 0))

        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        boldButton.mouseDown(with: event)

        let storage = try #require(controller.editorTextView.textStorage)
        let formattedFont = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let untouchedFont = try #require(storage.attribute(.font, at: 9, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: formattedFont).contains(.boldFontMask))
        #expect(!NSFontManager.shared.traits(of: untouchedFont).contains(.boldFontMask))
    }

    @MainActor
    @Test
    func panelPreflightPreservesSelectionBeforeToolbarClickCollapsesIt() throws {
        let harness = try makeEditorControllerHarness(draftID: "standard-editor", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let panel = try #require(controller.window as? QuickEntryPanel)
        let boldButton = try #require(controller.toolbarButtonsByAction[.bold])
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(string: "selected text", attributes: controller.theme.baseAttributes(for: .paragraph)))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 8))

        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        panel.onLeftMouseDownPreflight?(event)
        controller.editorTextView.setSelectedRange(NSRange(location: 13, length: 0))
        boldButton.mouseDown(with: event)

        let storage = try #require(controller.editorTextView.textStorage)
        let formattedFont = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: formattedFont).contains(.boldFontMask))
    }

    @MainActor
    @Test
    func toolbarMouseDownTogglesSelectedTextAcrossRepeatedClicks() throws {
        let harness = try makeEditorControllerHarness(draftID: "standard-editor", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let boldButton = try #require(controller.toolbarButtonsByAction[.bold])
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(string: "selected text", attributes: controller.theme.baseAttributes(for: .paragraph)))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 8))
        controller.rememberEditorSelectionForToolbarActions()
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))

        boldButton.mouseDown(with: event)
        boldButton.mouseDown(with: event)

        let storage = try #require(controller.editorTextView.textStorage)
        let font = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(!NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        #expect(controller.editorTextView.selectedRange() == NSRange(location: 0, length: 8))
    }

    @MainActor
    @Test
    func toolbarMouseDownAppliesDifferentFormatsToCachedSelection() throws {
        let harness = try makeEditorControllerHarness(draftID: "standard-editor", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let boldButton = try #require(controller.toolbarButtonsByAction[.bold])
        let italicButton = try #require(controller.toolbarButtonsByAction[.italic])
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(string: "selected text", attributes: controller.theme.baseAttributes(for: .paragraph)))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 8))
        controller.rememberEditorSelectionForToolbarActions()
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))

        boldButton.mouseDown(with: event)
        controller.editorTextView.setSelectedRange(NSRange(location: 13, length: 0))
        italicButton.mouseDown(with: event)

        let storage = try #require(controller.editorTextView.textStorage)
        let font = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let traits = NSFontManager.shared.traits(of: font)
        #expect(traits.contains(.boldFontMask))
        #expect(traits.contains(.italicFontMask))
    }

    @MainActor
    @Test
    func toolbarKeepsSingleHeadingButtonForHeadingOne() throws {
        let harness = try makeEditorControllerHarness(draftID: "standard-editor", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let headingButton = try #require(controller.toolbarButtonsByAction[.heading])
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(string: "selected text", attributes: controller.theme.baseAttributes(for: .paragraph)))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 8))
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))

        headingButton.mouseDown(with: event)

        let storage = try #require(controller.editorTextView.textStorage)
        let kind = MarkdownRichTextCodec.paragraphKind(at: NSRange(location: 0, length: storage.length), in: storage)
        #expect(kind.headingLevel == 1)
        #expect(controller.toolbarButtonsByAction.count == 9)
        #expect(MarkdownRichTextCodec.serialize(storage, theme: controller.theme) == "# selected text")
    }

    @MainActor
    @Test
    func toolbarInlineFormattingCanBeUndone() throws {
        let harness = try makeEditorControllerHarness(draftID: "standard-editor", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let boldButton = try #require(controller.toolbarButtonsByAction[.bold])
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(string: "selected text", attributes: controller.theme.baseAttributes(for: .paragraph)))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 8))
        controller.editorTextView.undoManager?.removeAllActions()
        let event = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))

        boldButton.mouseDown(with: event)
        controller.editorTextView.undoManager?.undo()

        let storage = try #require(controller.editorTextView.textStorage)
        let font = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(!NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        #expect(controller.editorTextView.selectedRange() == NSRange(location: 0, length: 8))
    }

    @MainActor
    @Test
    func positionalTitleFormattingDoesNotFollowTextIntoBody() throws {
        let harness = try makeEditorControllerHarness(draftID: "title-provenance", showsSaveButton: false)
        defer { harness.tearDown() }
        _ = try harness.store.saveNewNote(title: "Alpha Beta", body: "## Explicit heading\n**Bold body**")
        let controller = LibraryWindowController(noteStore: harness.store,
            onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close() }
        let view = controller.editorTextView
        let storage = try #require(view.textStorage)
        view.setSelectedRange(NSRange(location: 6, length: 0))
        controller.markdownTextViewInsertNewline(view)
        let beta = (view.string as NSString).range(of: "Beta")
        #expect(storage.attribute(.qmParagraphKind, at: beta.location, effectiveRange: nil) as? String == "paragraph")
        #expect(storage.attribute(.font, at: beta.location, effectiveRange: nil) as? NSFont == controller.theme.bodyFont)
        let explicit = (view.string as NSString).range(of: "Explicit heading")
        #expect(storage.attribute(.qmParagraphKind, at: explicit.location, effectiveRange: nil) as? String == "heading:2")
        #expect(MarkdownRichTextCodec.serialize(storage, theme: controller.theme).contains("**Bold body**"))

        // Moving the entire first line down must also remove its automatic style.
        view.setSelectedRange(NSRange(location: 0, length: 0))
        controller.markdownTextViewInsertNewline(view)
        let alpha = (view.string as NSString).range(of: "Alpha")
        #expect(storage.attribute(.qmParagraphKind, at: alpha.location, effectiveRange: nil) as? String == "paragraph")
        #expect(storage.attribute(.font, at: alpha.location, effectiveRange: nil) as? NSFont == controller.theme.bodyFont)
    }

    @MainActor
    @Test
    func inlineMarkdownTagsMigrateIntoDocumentMetadata() {
        let migration = MarkdownEditorDocument.extractingInlineTags(
            from: "Body #project and #work.\nArea #area/topic.\n\n`#code`\n\n```\n#fence\n```"
        )

        #expect(migration.tags == ["project", "work", "area/topic"])
        #expect(migration.occurrenceCount == 3)
        #expect(migration.body.contains("Body and."))
        #expect(migration.body.contains("Area."))
        #expect(migration.body.contains("`#code`"))
        #expect(migration.body.contains("#fence"))
        #expect(!migration.body.contains("Body #project"))
    }

    @MainActor
    @Test
    func visualQACanonicalWindowIgnoresStoredLibraryFrame() throws {
        let suiteName = "mudsnote-library-canonical-frame-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-canonical-frame-tests-\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        store.libraryWindowFrame = StoredWindowFrame(x: 20, y: 20, width: 1400, height: 900)
        _ = try store.saveNewNote(title: "Canonical", body: "Body")

        let controller = LibraryWindowController(
            noteStore: store,
            usesCanonicalWindowSize: true,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }
        controller.showWindowAndFocus()

        #expect(controller.window?.frame.size == LibraryNotesLayout.presentedWindowSize)
        #expect(store.libraryWindowFrame == StoredWindowFrame(x: 20, y: 20, width: 1400, height: 900))
    }

    @Test
    func externalMarkdownEventInvalidatesActiveSearchSession() async throws {
        let suiteName = "mudsnote.library-external-search-event-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-external-search-event-tests-\(UUID().uuidString)", isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = notesDirectory
        _ = try store.saveNewNote(title: "Existing", body: "Initial body")
        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        controller.searchForLibrary(query: "External", allNotes: true)
        let initialSession = try #require(controller.activeSearchSessionForLibrary())
        #expect(controller.noteListSearchResultsForLibrary().isEmpty)

        let externalURL = notesDirectory.appendingPathComponent("External Search.md")
        try "# External Search\n\nAdded from Finder\n".write(
            to: externalURL,
            atomically: true,
            encoding: .utf8
        )
        controller.handleLibraryFileSystemChangesForTesting([
            LibraryFileSystemChange(
                path: externalURL.path,
                flags: FSEventStreamEventFlags(
                    kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemIsFile
                )
            )
        ])
        await controller.waitForExternalLibraryRefreshForTesting()

        let refreshedSession = try #require(controller.activeSearchSessionForLibrary())
        #expect(refreshedSession !== initialSession)
        #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["External Search"])
    }

    @Test
    func externalMarkdownEventReloadsCleanSelectedNote() async throws {
        let suiteName = "mudsnote.library-external-selected-event-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-external-selected-event-tests-\(UUID().uuidString)", isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = notesDirectory
        let selectedURL = try store.saveNewNote(title: "Selected", body: "Initial body")
        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }
        #expect(controller.editorTextView.string == "Selected\n\nInitial body")
        controller.editorTextView.setSelectedRange(NSRange(location: 7, length: 0))

        try "# Selected externally\n\nUpdated outside Mudsnote\n".write(
            to: selectedURL,
            atomically: true,
            encoding: .utf8
        )
        controller.handleLibraryFileSystemChangesForTesting([
            LibraryFileSystemChange(
                path: selectedURL.path,
                flags: FSEventStreamEventFlags(
                    kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemIsFile
                )
            )
        ])
        #expect(controller.editorTextView.string == "Selected\n\nInitial body")
        #expect(controller.editorTextView.selectedRange() == NSRange(location: 7, length: 0))
        await controller.waitForExternalLibraryRefreshForTesting()

        #expect(controller.titleField.stringValue == "Selected externally")
        #expect(controller.editorTextView.string == "Selected externally\n\nUpdated outside Mudsnote")
        #expect(controller.editorTextView.selectedRange() == NSRange(location: 7, length: 0))
    }

    @Test
    func localAutosavePreservesExternalRevisionWithoutWaitingForValidation() async throws {
        let suiteName = "mudsnote.library-stale-external-reload-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-stale-external-reload-tests-\(UUID().uuidString)", isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = notesDirectory
        let selectedURL = try store.saveNewNote(title: "Selected", body: "Initial body")
        let controller = LibraryWindowController(
            noteStore: store,
            noteLoader: { url in
                Thread.sleep(forTimeInterval: 0.25)
                return try store.loadNote(at: url)
            },
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        try "# Selected externally\n\nExternal body\n".write(
            to: selectedURL,
            atomically: true,
            encoding: .utf8
        )
        controller.handleLibraryFileSystemChangesForTesting([
            LibraryFileSystemChange(
                path: selectedURL.path,
                flags: FSEventStreamEventFlags(
                    kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemIsFile
                )
            )
        ])

        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "# Selected\n\nLocal autosaved body",
            theme: controller.theme,
            baseURL: selectedURL
        ))
        controller.editorTextView.setSelectedRange(NSRange(location: 8, length: 0))
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.editorTextView))
        _ = try controller.flushPendingAutosaveForTesting()
        await controller.waitForExternalLibraryRefreshForTesting()

        #expect(controller.editorTextView.string == "Selected\n\nLocal autosaved body")
        #expect(controller.editorTextView.selectedRange() == NSRange(location: 8, length: 0))
        #expect(!controller.currentNoteHasUnsavedChangesForLibrary)
        #expect(try store.loadNote(at: selectedURL).body == "External body")
        let conflictURL = try #require(
            FileManager.default.contentsOfDirectory(
                at: notesDirectory,
                includingPropertiesForKeys: nil
            ).first { $0.lastPathComponent.contains("(Mudsnote Conflict)") }
        )
        #expect(try store.loadNote(at: conflictURL).body == "Local autosaved body")
    }

    @Test
    func internalSaveEventDoesNotRebuildActiveSearchSession() throws {
        let suiteName = "mudsnote.library-internal-save-event-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-internal-save-event-tests-\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let selectedURL = try store.saveNewNote(title: "Existing", body: "Initial body")
        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        _ = try controller.saveCurrentNoteForLibrary()
        controller.searchForLibrary(query: "Existing", allNotes: true)
        let activeSession = try #require(controller.activeSearchSessionForLibrary())

        controller.handleLibraryFileSystemChangesForTesting([
            LibraryFileSystemChange(
                path: selectedURL.path,
                flags: FSEventStreamEventFlags(
                    kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemIsFile
                )
            )
        ])

        #expect(controller.activeSearchSessionForLibrary() === activeSession)
        #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["Existing"])
    }

    @MainActor
    @Test
    func externalTablesKeepRowsAndColumnsWhenPasted() throws {
        let html = "<p>Before</p><table><tr><td>Name</td><td>Value</td></tr><tr><td>A</td><td>42</td></tr></table><p>After</p>"
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setData(Data(html.utf8), forType: .html)
        let markdown = try #require(MarkdownRichPasteNormalizer.markdown(from: board, theme: theme))
        #expect(markdown.contains("| Name | Value |\n| --- | --- |\n| A | 42 |"))
        #expect(markdown.contains("Before"))
        #expect(markdown.contains("After"))
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        view.markdownPasteTheme = theme
        #expect(view.pasteContents(from: board))
        let stored = MarkdownRichTextCodec.serialize(view.attributedString(), theme: theme)
        #expect(stored.contains("| A | 42 |"))

        board.clearContents()
        board.setString("Name\tValue\r\nA\t42\r\n", forType: .string)
        #expect(MarkdownRichPasteNormalizer.markdown(from: board, theme: theme)
            == "| Name | Value |\n| --- | --- |\n| A | 42 |")
        board.clearContents()
        board.setString("ordinary text\nnext line", forType: .string)
        #expect(MarkdownRichPasteNormalizer.markdown(from: board, theme: theme) == nil)
    }

    @MainActor
    @Test
    func bodyTypingDoesNotRewriteTitleAttributes() throws {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        view.replaceAllContent(with: MarkdownRichTextCodec.render(markdown: "# Title\nBody", theme: theme))
        view.setMetadataTags(["tag"])
        let storage = try #require(view.textStorage)
        let edits = TextStorageEditCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil
        ) { _ in MainActor.assumeIsolated { edits.count += 1 } }
        defer { NotificationCenter.default.removeObserver(observer) }
        view.didChangeText()
        view.didChangeText()
        #expect(edits.count == 0)
        let style = try #require(storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(style.paragraphSpacing >= 36)
    }

    @MainActor
    @Test
    func commandPasteNormalizesHTMLFormattingIntoPortableMarkdown() throws {
        let html = """
        <h1>Release Plan</h1>
        <p>Keep <strong>bold</strong>, <em>italic</em>, and <a href="https://example.com">links</a>.</p>
        <ul><li>First task</li><li>Second task</li></ul>
        <ol><li>Review</li><li>Ship</li></ol>
        """
        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        #expect(pasteboard.setData(Data(html.utf8), forType: .html))
        let imageData = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="))
        #expect(pasteboard.setData(imageData, forType: .png))
        #expect(MarkdownAttachmentStorage.pastePayload(from: pasteboard) == nil)

        let normalized = try #require(MarkdownRichPasteNormalizer.markdown(from: pasteboard, theme: theme))
        #expect(normalized.contains("# Release Plan"))
        #expect(normalized.contains("Keep **bold**, *italic*, and [links](https://example.com/)."))
        #expect(normalized.contains("- First task\n- Second task"))
        #expect(normalized.contains("1. Review\n2. Ship"))

        let importedHTML = try NSAttributedString(
            data: Data(html.utf8),
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        )
        let rtfData = try importedHTML.data(
            from: NSRange(location: 0, length: importedHTML.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let rtfPasteboard = NSPasteboard.withUniqueName()
        rtfPasteboard.clearContents()
        #expect(rtfPasteboard.setData(rtfData, forType: .rtf))
        #expect(MarkdownRichPasteNormalizer.markdown(from: rtfPasteboard, theme: theme) == normalized)

        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        textView.isRichText = true
        textView.markdownPasteTheme = theme
        textView.pasteboardForPaste = { pasteboard }
        textView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "Paste below:",
            theme: theme
        ))
        textView.setSelectedRange(NSRange(location: textView.attributedString().length, length: 0))
        let pasteEvent = try keyEvent(
            keyCode: UInt16(kVK_ANSI_V),
            modifiers: [.command],
            characters: "v"
        )

        #expect(textView.performKeyEquivalent(with: pasteEvent))
        let serialized = MarkdownRichTextCodec.serialize(textView.attributedString(), theme: theme)
        #expect(serialized == "Paste below:\n\(normalized)")
    }

    @MainActor
    @Test
    func linkEditorSheetRequiresDestinationAndSupportsSubmitAndCancel() throws {
        var submittedValue: (destination: String, name: String)?
        var dismissCount = 0
        let controller = LinkEditorSheetController(
            title: "添加链接",
            destination: "",
            name: "Selected text",
            onSubmit: { submittedValue = ($0, $1) },
            onDismiss: { dismissCount += 1 }
        )

        let window = try #require(controller.window)
        let surface = try #require(window.contentView)
        let material = try #require(surface.allSubviews.first {
            $0.identifier?.rawValue == "LinkEditorMaterial"
        } as? NSVisualEffectView)
        #expect(window.frame.size == LinkEditorSheetController.compactContentSize)
        #expect(surface.frame.size == LinkEditorSheetController.compactContentSize)
        #expect(window.styleMask.contains(.borderless))
        #expect(!window.styleMask.contains(.titled))
        #expect(window.canBecomeKey)
        #expect(window.canBecomeMain)
        #expect(!window.isOpaque)
        #expect(window.backgroundColor.alphaComponent == 0)
        #expect(surface.identifier?.rawValue == "LinkEditorCompactSurface")
        #expect(material.material == .underWindowBackground)
        #expect(material.blendingMode == .behindWindow)
        #expect(material.alphaValue == 0.62)
        #expect(surface.layer?.cornerRadius == 12)
        surface.layoutSubtreeIfNeeded()
        let titleLabel = try #require(surface.allSubviews.first {
            $0.identifier?.rawValue == "LinkEditorTitle"
        } as? NSTextField)
        #expect(titleLabel.alignment == .left)
        #expect(abs(titleLabel.frame.minX - controller.destinationField.frame.minX) <= 2)
        #expect(controller.destinationField.frame.height == 28)
        #expect(controller.nameField.frame.height == 28)
        #expect(controller.window?.contentView?.allSubviews.compactMap { $0.identifier?.rawValue }.contains("LinkEditorDestinationField") == true)
        #expect(controller.window?.contentView?.allSubviews.compactMap { $0.identifier?.rawValue }.contains("LinkEditorNameField") == true)
        #expect(controller.nameField.stringValue == "Selected text")
        #expect(!controller.confirmButton.isEnabled)

        controller.destinationField.stringValue = "  https://example.com/path  "
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.destinationField))
        #expect(controller.confirmButton.isEnabled)
        controller.submitForTesting()
        #expect(submittedValue?.destination == "https://example.com/path")
        #expect(submittedValue?.name == "Selected text")
        #expect(dismissCount == 1)

        var cancelledSubmission = false
        let cancelledController = LinkEditorSheetController(
            title: "编辑链接",
            destination: "https://muds.top",
            name: "Muds",
            onSubmit: { _, _ in cancelledSubmission = true },
            onDismiss: { dismissCount += 1 }
        )
        cancelledController.cancelForTesting()
        #expect(!cancelledSubmission)
        #expect(dismissCount == 2)
    }

    @Test
    func localHTMLLinkUsesItsDefaultExternalApplicationInsteadOfMudsnote() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-html-link-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appendingPathComponent("Source.md")
        let htmlURL = root.appendingPathComponent("Dashboard.html")
        try "# Source".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "<html></html>".write(to: htmlURL, atomically: true, encoding: .utf8)

        #expect(
            markdownLinkDestination(htmlURL.absoluteString, relativeTo: sourceURL)
                == .external(htmlURL.standardizedFileURL)
        )
    }

    @MainActor
    @Test
    func localMarkdownCommandClickOpensInsideLibraryAndShowsLinkRelations() async throws {
        let suiteName = "mudsnote.local-link-navigation-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-local-link-navigation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        store.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)
        let relatedURL = try store.saveNewNote(title: "Related", body: "Related body", in: notesDirectory)
        let targetURL = try store.saveNewNote(
            title: "Target",
            body: "[Related](\(relatedURL.lastPathComponent))",
            in: notesDirectory
        )
        let sourceURL = try store.saveNewNote(
            title: "Source",
            body: "[Target](\(targetURL.path))",
            in: notesDirectory
        )

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        try controller.openMarkdownDocumentForLibrary(at: targetURL)
        await controller.waitForNoteLinksRefreshForLibrary()
        #expect(!controller.noteLinksView.isHidden)
        let relationButtonTitles = controller.noteLinksView.allSubviews
            .compactMap { ($0 as? NSButton)?.title }
        #expect(relationButtonTitles.contains("Source"))
        #expect(relationButtonTitles.contains("Related"))

        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(10)],
            ofItemAtPath: sourceURL.path
        )
        let navigationController = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { navigationController.close() }
        try navigationController.openMarkdownDocumentForLibrary(at: sourceURL)
        await navigationController.waitForActiveNoteLoadForLibrary()

        let linkLocation = (navigationController.editorTextView.string as NSString).range(of: "Target").location
        try #require(linkLocation != NSNotFound)
        #expect(navigationController.editorTextView.linkReference(atCharacterIndex: linkLocation)?.url == targetURL.path)
        try #require(FileManager.default.fileExists(atPath: targetURL.path))
        #expect(navigationController.markdownTextView(
            navigationController.editorTextView,
            didCommandClickLinkAt: linkLocation
        ))
        #expect(navigationController.selectedMarkdownFileURLForLibrary()?.standardizedFileURL == targetURL.standardizedFileURL)
        #expect(navigationController.titleField.stringValue == "Target")
    }

    @MainActor
    @Test
    func knowledgeRelationNavigationStaysInOneWindowAndSupportsBack() async throws {
        let suiteName = "mudsnote.knowledge-navigation-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-knowledge-navigation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        store.configurePreferredDirectories([notesDirectory], defaultDirectory: notesDirectory)
        let sourceURL = try store.saveNewNote(
            title: "Source",
            body: "Source body",
            tags: ["层级/点"],
            in: notesDirectory
        )
        let targetURL = try store.saveNewNote(
            title: "Target",
            body: "[Source](\(sourceURL.lastPathComponent))",
            tags: ["层级/线"],
            in: notesDirectory
        )
        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        try controller.openMarkdownDocumentForLibrary(at: targetURL)
        await controller.waitForNoteLinksRefreshForLibrary()
        let sourceButton = try #require(controller.noteLinksView.allSubviews
            .compactMap { $0 as? NSButton }
            .first { $0.title == "Source" })
        sourceButton.performClick(nil)
        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL == sourceURL.standardizedFileURL)
        // No action from the old note may remain clickable while the new
        // note's background relations are being resolved.
        #expect(controller.noteLinksView.knowledgeRelations == .empty)

        let backButton = try #require(controller.noteLinksView.allSubviews
            .compactMap { $0 as? NSButton }
            .first { $0.title == "‹" })
        #expect(backButton.isEnabled)
        backButton.performClick(nil)
        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL == targetURL.standardizedFileURL)
    }

    @MainActor
    @Test
    func knowledgeRelationsViewStaysAvailableWithoutExistingRelations() {
        let view = NoteLinksView(frame: .zero)
        #expect(!view.isHidden)
        var requestedLayer: KnowledgeLayer?
        var requestedGraph = false
        view.onGenerateHigherLayer = { requestedLayer = $0 }
        view.onShowGraph = { requestedGraph = true }

        view.update(KnowledgeRelations(
            currentLayer: .point,
            parents: [],
            children: [],
            related: [KnowledgeRelationItem(
                url: URL(fileURLWithPath: "/tmp/source.md"),
                title: "Source"
            )],
            suggested: [KnowledgeRelationItem(
                url: URL(fileURLWithPath: "/tmp/suggested.md"),
                title: "Suggested",
                reason: "共同标签：数据治理"
            )]
        ))
        #expect(!view.isHidden)
        let buttonTitles = view.allSubviews.compactMap { ($0 as? NSButton)?.title }
        #expect(buttonTitles.contains("生成线层草案"))
        let relationLabels = view.allSubviews
            .compactMap { ($0 as? NSTextField)?.stringValue }
        #expect(relationLabels.contains("共同标签：数据治理"))
        view.allSubviews
            .compactMap { $0 as? NSButton }
            .first { $0.title == "生成线层草案" }?
            .performClick(nil)
        #expect(requestedLayer == .line)
        let graphButton = view.allSubviews
            .compactMap { $0 as? NSButton }
            .first { $0.accessibilityLabel() == "打开当前笔记知识图谱" }
        graphButton?.performClick(nil)
        #expect(requestedGraph)

        view.update(.empty)
        #expect(!view.isHidden)
    }

    @MainActor
    @Test
    func knowledgeGraphCanvasFiltersNavigationFromGraphPresentation() {
        let pointURL = URL(fileURLWithPath: "/tmp/Point.md")
        let lineURL = URL(fileURLWithPath: "/tmp/Line.md")
        let canvas = KnowledgeGraphCanvasView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        let window = NSWindow(
            contentRect: canvas.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = canvas
        canvas.update(KnowledgeGraphSnapshot(
            nodes: [
                KnowledgeGraphNode(url: pointURL, title: "Point", layer: .point, linkCount: 1),
                KnowledgeGraphNode(url: lineURL, title: "Line", layer: .line, linkCount: 1)
            ],
            edges: [
                KnowledgeGraphEdge(
                    sourceURL: pointURL,
                    targetURL: lineURL,
                    kind: .hierarchy
                )
            ],
            focusedURL: lineURL
        ))

        #expect(canvas.accessibilityLabel()?.contains("2 个节点") == true)
        let accessibleNodes = canvas.accessibilityChildren()?
            .compactMap { $0 as? NSAccessibilityElement } ?? []
        #expect(accessibleNodes.count == 2)
        #expect(accessibleNodes.allSatisfy { $0.accessibilityRole() == .button })
        #expect(accessibleNodes.contains {
            $0.accessibilityLabel()?.contains("Point，点层") == true
        })
        canvas.zoom(by: 100)
        canvas.zoom(by: 0.0001)
        canvas.fitGraph()
        #expect(canvas.acceptsFirstResponder)
    }

    @MainActor
    @Test
    func knowledgeGraphWindowKeepsControlsAboveTheCanvasAtMinimumSize() throws {
        let suiteName = "mudsnote.knowledge-graph-window-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-knowledge-graph-window-\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        let controller = KnowledgeGraphWindowController(noteStore: store, rootsProvider: { [] })
        defer { controller.close() }
        controller.window?.setContentSize(NSSize(width: 820, height: 460))
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        let content = try #require(controller.window?.contentView)
        let scope = try #require(content.allSubviews.first {
            $0.identifier?.rawValue == "KnowledgeGraphScopeControl"
        })
        let canvas = try #require(content.allSubviews.first {
            $0.identifier?.rawValue == "KnowledgeGraphCanvas"
        })
        let toolbar = try #require(content.allSubviews.first {
            $0.identifier?.rawValue == "KnowledgeGraphToolbar"
        })
        let scopeFrame = content.convert(scope.bounds, from: scope)
        let canvasFrame = content.convert(canvas.bounds, from: canvas)
        let toolbarFrame = content.convert(toolbar.bounds, from: toolbar)
        #expect(toolbarFrame.height == 44)
        #expect(!toolbarFrame.intersects(canvasFrame))
        #expect(!scopeFrame.intersects(canvasFrame))
        #expect(scopeFrame.minX >= content.bounds.minX)
        #expect(scopeFrame.maxX <= content.bounds.maxX)
    }

    @MainActor
    @Test
    func markdownTablesRenderAsNativeGridsAndRoundTrip() throws {
        let markdown = """
        Before
        | Name | Status |
        | --- | --- |
        | Alpha | Todo |
        After
        """

        let rendered = MarkdownRichTextCodec.render(markdown: markdown, theme: theme)
        #expect(!rendered.string.contains("|"))
        #expect(!rendered.string.contains("---"))
        #expect(rendered.string.contains("Name\nStatus\nAlpha\nTodo"))
        #expect(MarkdownRichTextCodec.serialize(rendered, theme: theme) == markdown)

        let nameLocation = (rendered.string as NSString).range(of: "Name").location
        let paragraphStyle = try #require(rendered.attribute(.paragraphStyle, at: nameLocation, effectiveRange: nil) as? NSParagraphStyle)
        let tableBlock = try #require(paragraphStyle.textBlocks.first as? NSTextTableBlock)
        #expect(tableBlock.table.contentWidth == 99.25)
        #expect(tableBlock.table.contentWidthValueType == .percentageValueType)
        #expect((rendered.attribute(.qmTableRow, at: nameLocation, effectiveRange: nil) as? Int) == 0)
        #expect((rendered.attribute(.qmTableColumn, at: nameLocation, effectiveRange: nil) as? Int) == 0)

        let editable = NSMutableAttributedString(attributedString: rendered)
        let todoRange = (editable.string as NSString).range(of: "Todo")
        editable.deleteCharacters(in: todoRange)
        #expect(MarkdownRichTextCodec.serialize(editable, theme: theme) == """
        Before
        | Name | Status |
        | --- | --- |
        | Alpha |  |
        After
        """)
    }

    @MainActor
    @Test
    func markdownTablesPreserveEscapedPipesBackslashesEmptyCellsAndAlignment() {
        let markdown = #"""
        | Value | Path | Empty | Alignment |
        | :--- | ---: | :---: | --- |
        | A\|B | slash\\|pipe |  | Plain |
        """#

        let rendered = MarkdownRichTextCodec.render(markdown: markdown, theme: theme)
        #expect(rendered.string.contains("A|B"))
        #expect(rendered.string.contains(#"slash\|pipe"#))
        #expect(MarkdownRichTextCodec.serialize(rendered, theme: theme) == markdown)
    }

    @MainActor
    @Test
    func internalFileEventWaitsForActiveAutosaveAndDoesNotRestartSearch() async throws {
        let suiteName = "mudsnote.library-autosave-file-event-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-autosave-file-event-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let noteURL = try store.saveNewNote(title: "Existing", body: "Initial body")
        let recorder = BlockingAutosaveRecorder()
        let controller = LibraryWindowController(
            noteStore: store,
            backgroundAutosaveWillPersist: recorder.record,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer {
            recorder.releaseFirstWrite.signal()
            controller.close()
        }

        controller.searchForLibrary(query: "Existing", allNotes: true)
        let activeSession = try #require(controller.activeSearchSessionForLibrary())
        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "# " + "Existing\n\nExisting updated body", theme: controller.theme
        ))
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.editorTextView))
        controller.triggerBackgroundAutosaveForTesting()
        let firstStarted = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(
                    returning: recorder.firstWriteStarted.wait(timeout: .now() + 2)
                )
            }
        }
        #expect(firstStarted == .success)

        controller.handleLibraryFileSystemChangesForTesting([
            LibraryFileSystemChange(
                path: noteURL.path,
                flags: FSEventStreamEventFlags(
                    kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemIsFile
                )
            )
        ])
        #expect(controller.activeSearchSessionForLibrary() === activeSession)

        recorder.releaseFirstWrite.signal()
        await controller.waitForBackgroundAutosaveForTesting()
        await controller.waitForExternalLibraryRefreshForTesting()
        #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["Existing"])
        #expect(try store.loadNote(at: noteURL).body == "Existing updated body")
    }

    @MainActor
    @Test
    func draftPersistenceCoalescesQueuedSnapshotsAndFlushesAfterActiveWrite() throws {
        let activeWriteStarted = DispatchSemaphore(value: 0)
        let releaseActiveWrite = DispatchSemaphore(value: 0)
        let recorder = DraftPersistenceRecorder { snapshot in
            guard snapshot.title == "First" else { return }
            activeWriteStarted.signal()
            releaseActiveWrite.wait()
        }
        let coordinator = DraftPersistenceCoordinator(
            save: recorder.record,
            delete: { _ in }
        )
        func snapshot(_ title: String) -> DraftSnapshot {
            DraftSnapshot(
                id: "coalesced-draft",
                sourcePath: nil,
                selectedDirectoryPath: "/tmp",
                title: title,
                body: "",
                updatedAt: Date()
            )
        }

        coordinator.enqueue(.save(snapshot("First"))) { _ in }
        #expect(activeWriteStarted.wait(timeout: .now() + 1) == .success)
        coordinator.enqueue(.save(snapshot("Stale"))) { _ in }
        coordinator.enqueue(.save(snapshot("Latest"))) { _ in }
        releaseActiveWrite.signal()
        coordinator.waitUntilIdle()

        #expect(recorder.snapshot().savedTitles == ["First", "Latest"])
        try coordinator.flush(.save(snapshot("Closing")))
        #expect(recorder.snapshot().savedTitles == ["First", "Latest", "Closing"])
    }

    @MainActor
    @Test
    func draftFailureBlocksWindowCloseAndApplicationTermination() throws {
        let failLock = MutableBoolFlag(true)
        var reportedErrors = 0
        let harness = try makeEditorControllerHarness(
            draftID: "guarded-draft-close",
            showsSaveButton: false,
            saveDraftSnapshot: { _ in
                if failLock.get() {
                    throw CocoaError(.fileWriteNoPermission)
                }
            },
            draftPersistenceErrorHandler: { _ in
                reportedErrors += 1
            }
        )
        defer {
            failLock.set(false)
            harness.tearDown()
        }
        let controller = harness.controller
        let window = try #require(controller.window)

        controller.editorTextView.string = "Unsaved guarded draft"
        controller.markDocumentDirty()

        #expect(!controller.windowShouldClose(window))
        #expect(controller.isDirty)
        #expect(controller.statusLabel.stringValue == "草稿保存失败，当前编辑仍保留")
        #expect(reportedErrors == 1)

        #expect(AppController.terminationReply(
            editorControllers: [controller],
            libraryController: nil
        ) == .terminateCancel)
        #expect(controller.isDirty)
        #expect(reportedErrors == 2)

        failLock.set(false)
        #expect(AppController.terminationReply(
            editorControllers: [controller],
            libraryController: nil
        ) == .terminateNow)
        #expect(!controller.isDirty)
    }

    @MainActor
    @Test
    func visibleLibraryDecodesThumbnailOffMainAndDeduplicatesRequests() async throws {
        let suiteName = "mudsnote.library-async-thumbnail-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-async-thumbnail-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let noteURL = try store.saveNewNote(
            title: "Async Thumbnail",
            body: "![Preview](Attachments/async-thumb.png)"
        )
        let imageURL = noteURL.deletingLastPathComponent()
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent("async-thumb.png")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let pngData = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="))
        try pngData.write(to: imageURL)

        let decodeGate = DispatchSemaphore(value: 0)
        defer { decodeGate.signal() }
        let controller = LibraryWindowController(
            noteStore: store,
            thumbnailDecoder: { url in
                decodeGate.wait()
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                return CGImageSourceCreateImageAtIndex(source, 0, nil)
            },
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }
        controller.showWindowAndFocus()

        let firstCell = try #require(controller.tableView(
            controller.tableView,
            viewFor: nil,
            row: 1
        ) as? LibraryNoteCellView)
        _ = controller.tableView(controller.tableView, viewFor: nil, row: 1)

        #expect(firstCell.thumbnailImageView.image == nil)
        #expect(firstCell.thumbnailImageView.isHidden)
        #expect(!firstCell.attachmentImageView.isHidden)
        #expect(controller.thumbnailImageDecodeCountForLibrary == 1)

        decodeGate.signal()
        await controller.waitForThumbnailLoadsForLibrary()
        let loadedCell = try #require(controller.tableView(
            controller.tableView,
            viewFor: nil,
            row: 1
        ) as? LibraryNoteCellView)

        #expect(loadedCell.thumbnailImageView.image != nil)
        #expect(!loadedCell.thumbnailImageView.isHidden)
        #expect(loadedCell.attachmentImageView.isHidden)
        #expect(controller.thumbnailImageDecodeCountForLibrary == 1)
        #expect(controller.thumbnailReloadBatchCountForLibrary == 1)
    }

    @MainActor
    @Test
    func visibleGalleryThumbnailRefreshPreservesSelectionAndKeyboardTarget() async throws {
        let harness = try makeEditorControllerHarness(draftID: "gallery-thumbnail-selection", showsSaveButton: false)
        defer { harness.tearDown() }
        let root = harness.store.notesDirectory
        let firstURL = try harness.store.saveNewNote(title: "First Image", body: "![Preview](Attachments/shared.png)", in: root)
        let secondURL = try harness.store.saveNewNote(title: "Second Image", body: "![Preview](Attachments/shared.png)", in: root)
        let imageURL = root.appendingPathComponent("Attachments/shared.png")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="))
        try png.write(to: imageURL)
        let controller = LibraryWindowController(noteStore: harness.store,
            onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close() }
        controller.showWindowAndFocus()
        let launchDeadline = Date().addingTimeInterval(6)
        while Date() < launchDeadline, controller.isFullLibrarySnapshotLoading {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(!controller.isFullLibrarySnapshotLoading)
        controller.setNoteListViewModeForLibrary(.gallery)
        let window = try #require(controller.window)
        window.contentView?.layoutSubtreeIfNeeded()
        await controller.waitForThumbnailLoadsForLibrary()
        let gallery = try #require(window.contentView?.allSubviews.compactMap { $0 as? LibraryGalleryCollectionView }.first)
        let firstIndex = try #require(controller.galleryIndexPath(for: firstURL.standardizedFileURL.path))
        let secondIndex = try #require(controller.galleryIndexPath(for: secondURL.standardizedFileURL.path))
        let selection: Set<IndexPath> = [firstIndex, secondIndex]
        gallery.selectionIndexPaths = selection
        controller.collectionView(gallery, didSelectItemsAt: selection)
        try #require(gallery.selectionIndexPaths == selection)
        try #require(controller.selectedMarkdownFileURLsForLibrary().count == 2)
        let firstItem = try #require(gallery.item(at: firstIndex) as? LibraryGalleryItem)
        let secondItem = try #require(gallery.item(at: secondIndex) as? LibraryGalleryItem)
        let reloadCount = controller.thumbnailReloadBatchCountForLibrary

        try png.write(to: imageURL)
        controller.handleLibraryFileSystemChangesForTesting([
            LibraryFileSystemChange(path: imageURL.path, flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified))
        ])
        // The invalidation batch first starts a new decode; the next wait drains it.
        await controller.waitForThumbnailLoadsForLibrary()
        await controller.waitForThumbnailLoadsForLibrary()
        window.contentView?.layoutSubtreeIfNeeded()

        #expect(controller.thumbnailReloadBatchCountForLibrary > reloadCount)
        #expect(gallery.selectionIndexPaths == selection)
        #expect(gallery.item(at: firstIndex) === firstItem)
        #expect(gallery.item(at: secondIndex) === secondItem)
        for item in [firstItem, secondItem] {
            #expect(item.isSelected)
            #expect(item.previewSurface.layer?.borderWidth == 2)
            #expect(item.previewImageView.image != nil)
        }
        #expect(Set(controller.selectedMarkdownFileURLsForLibrary().map(\.standardizedFileURL)) == Set([firstURL, secondURL].map(\.standardizedFileURL)))

        gallery.selectionIndexPaths = [firstIndex]
        controller.collectionView(gallery, didSelectItemsAt: [firstIndex])
        gallery.keyDown(with: try keyEvent(keyCode: 36, modifiers: [], characters: "\r", windowNumber: window.windowNumber))
        #expect(controller.noteListViewMode == .list)
        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL == firstURL.standardizedFileURL)
    }

    @MainActor
    @Test
    func slowLibrarySearchKeepsTypingOnMainResponsiveAndPublishesOnlyLatestQuery() async throws {
        let suiteName = "mudsnote.library-search-responsiveness-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-search-responsiveness-tests-\(UUID().uuidString)", isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        for index in 0..<300 {
            let marker = index == 299 ? "latest-query-marker" : "stale-query-marker"
            try "# Fixture \(index)\n\n\(marker)\n".write(
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
        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }
        await controller.waitForExternalLibraryRefreshForTesting()

        let searchThread = ThreadObservationRecorder()
        store.setSearchIndexEntryWillMatchForTesting {
            searchThread.recordCurrentThread()
            Thread.sleep(forTimeInterval: 0.002)
        }

        controller.searchField.stringValue = "stale-query-marker"
        controller.controlTextDidChange(Notification(
            name: NSControl.textDidChangeNotification,
            object: controller.searchField
        ))
        let firstSearchDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while searchThread.snapshot().callCount == 0,
              ContinuousClock.now < firstSearchDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(searchThread.snapshot().callCount > 0)

        let typingStarted = ContinuousClock.now
        controller.searchField.stringValue = "latest-query-marker"
        controller.controlTextDidChange(Notification(
            name: NSControl.textDidChangeNotification,
            object: controller.searchField
        ))
        let typingLatency = typingStarted.duration(to: ContinuousClock.now)
        #expect(typingLatency < .milliseconds(50))

        let resultDeadline = ContinuousClock.now.advanced(by: .seconds(4))
        while controller.noteListSearchResultsForLibrary().map(\.title) != ["Fixture 299"],
              ContinuousClock.now < resultDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["Fixture 299"])
        #expect(!searchThread.snapshot().observedMainThread)
    }

    @MainActor
    @Test
    func firstKeyboardSearchFlushUsesSnapshotBeforeBuildingSearchSession() async throws {
        let suiteName = "mudsnote.first-search-flush-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-first-search-flush-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        _ = try store.saveNewNote(title: "Immediate Snapshot", body: "First search body")
        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        controller.searchField.stringValue = "immediate"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.searchField))
        #expect(controller.activeSearchSessionForLibrary() == nil)
        let fieldEditor = NSTextView()
        #expect(controller.control(
            controller.searchField,
            textView: fieldEditor,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))
        #expect(controller.titleField.stringValue == "Immediate Snapshot")
        #expect(controller.activeSearchSessionForLibrary() == nil)

        await controller.waitForExternalLibraryRefreshForTesting()
        #expect(controller.activeSearchSessionForLibrary() != nil)
    }

    @MainActor
    @Test
    func recentlyDeletedKeyboardSearchFlushesFromSnapshotBeforeFullTextRefresh() throws {
        let suiteName = "mudsnote.trash-search-snapshot-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-trash-search-snapshot-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let noteURL = try store.saveNewNote(title: "Cached Trash Result", body: "Snapshot preview")
        let trashedURL = try store.trashNote(at: noteURL)
        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        #expect(controller.selectSourceForLibrary(titled: "最近删除"))
        controller.tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        try FileManager.default.removeItem(at: trashedURL)

        controller.searchField.stringValue = "cached"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.searchField))
        let fieldEditor = NSTextView()
        #expect(controller.control(
            controller.searchField,
            textView: fieldEditor,
            doCommandBy: #selector(NSResponder.moveDown(_:))
        ))
        #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["Cached Trash Result"])
    }

    @Test
    func recentlyDeletedSearchFiltersBeforeApplyingItsResultLimit() throws {
        let suiteName = "mudsnote.trash-search-limit-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-trash-search-limit-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)

        let decoyOne = try store.trashNote(at: store.saveNewNote(title: "Recent One", body: "No match"))
        let decoyTwo = try store.trashNote(at: store.saveNewNote(title: "Recent Two", body: "No match"))
        let bodyMatch = try store.trashNote(at: store.saveNewNote(
            title: "Older Body",
            body: "The recovery needle is here"
        ))
        let tagMatch = try store.trashNote(at: store.saveNewNote(
            title: "Oldest Tag",
            body: "No body match",
            tags: ["needle-tag"]
        ))
        let dates: [(URL, Date)] = [
            (decoyOne, Date(timeIntervalSince1970: 400)),
            (decoyTwo, Date(timeIntervalSince1970: 300)),
            (bodyMatch, Date(timeIntervalSince1970: 200)),
            (tagMatch, Date(timeIntervalSince1970: 100))
        ]
        for (url, date) in dates {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }

        let results = libraryFilteredTrashedNotes(noteStore: store, query: "needle", limit: 2)
        #expect(Set(results.map(\.title)) == Set(["Older Body", "Oldest Tag"]))
        let bodyResult = results.first { $0.title == "Older Body" }
        #expect(bodyResult?.snippet.localizedCaseInsensitiveContains("needle") == true)
        #expect(libraryFilteredTrashedNotes(noteStore: store, query: "needle", limit: 0).isEmpty)
    }

    @MainActor
    @Test
    func nativeSourceOutlineInstantiatesOnlyVisibleRows() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-native-outline-reuse-\(UUID().uuidString)", isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for index in 0..<600 {
            try FileManager.default.createDirectory(
                at: notesDirectory.appendingPathComponent(String(format: "Folder %04d", index), isDirectory: true),
                withIntermediateDirectories: false
            )
        }

        let suiteName = "mudsnote.native-outline-reuse.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = notesDirectory

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }
        let window = try #require(controller.window)
        controller.loadSourceFoldersForLibrary()
        window.contentView?.layoutSubtreeIfNeeded()
        controller.sourceOutlineView.layoutSubtreeIfNeeded()

        #expect(controller.sourceOutlineView.numberOfRows > 600)
        #expect(controller.sourceOutlineInstantiatedCellCountForLibrary < 40)
        #expect(
            controller.sourceOutlineInstantiatedCellCountForLibrary
                < controller.sourceOutlineView.numberOfRows
        )
    }

    @MainActor
    @Test
    func deferredLibraryLaunchIgnoresRecentExternalDocuments() async throws {
        let suiteName = "mudsnote.library-recent-shell-boundary-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-recent-shell-boundary-tests-\(UUID().uuidString)", isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let externalDirectory = root.appendingPathComponent(".hermes", isDirectory: true)
        let externalNote = externalDirectory.appendingPathComponent("SOUL.md")
        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = notesDirectory
        let managedNote = try store.saveNewNote(title: "Managed", body: "Library body")
        try "# SOUL\n\nExternal body".write(to: externalNote, atomically: true, encoding: .utf8)
        _ = try store.updateNoteInPlace(at: externalNote, title: "SOUL", body: "External body")
        #expect(store.listRecentFiles(limit: 2).first?.url.standardizedFileURL == externalNote.standardizedFileURL)

        let controller = LibraryWindowController(
            noteStore: store,
            defersInitialNoteHydration: true,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        #expect(controller.noteListSearchResultsForLibrary().map(\.url.standardizedFileURL.path) == [
            managedNote.standardizedFileURL.path
        ])
        controller.showWindowAndFocus()
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline, controller.editorTextView.string != "Managed\n\nLibrary body" {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL.path == managedNote.standardizedFileURL.path)
        #expect(controller.titleField.stringValue == "Managed")
        #expect(controller.editorTextView.string == "Managed\n\nLibrary body")
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(controller.noteListSearchResultsForLibrary().map(\.url.standardizedFileURL.path) == [
            managedNote.standardizedFileURL.path
        ])
        #expect(controller.selectSourceForLibrary(titled: "Notes"))
        await controller.waitForSourceSnapshotValidationForLibrary()
        #expect(controller.noteListSearchResultsForLibrary().map(\.url.standardizedFileURL.path) == [
            managedNote.standardizedFileURL.path
        ])
        controller.selectRecentScopeForLibrary()
        #expect(controller.noteListSearchResultsForLibrary().map(\.url.standardizedFileURL.path) == [
            managedNote.standardizedFileURL.path
        ])
    }

    @MainActor
    @Test
    func cachedNoteVersionValidationDoesNotBlockKeyboardNavigation() async throws {
        let suiteName = "mudsnote.library-cache-validation-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-cache-validation-tests-\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        _ = try store.saveNewNote(title: "Cached First", body: "First body")
        _ = try store.saveNewNote(title: "Cached Second", body: "Second body")
        let probe = DelayedFileModificationDateProbe()
        let controller = LibraryWindowController(
            noteStore: store,
            fileModificationDateLoader: { probe.read($0) },
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let initiallySelectedURL = try #require(controller.selectedMarkdownFileURLForLibrary())
        let otherRow = try #require((0..<controller.tableView.numberOfRows).first { row in
            guard let writer = controller.tableView(
                controller.tableView,
                pasteboardWriterForRow: row
            ) as? NSURL else {
                return false
            }
            return (writer as URL).standardizedFileURL != initiallySelectedURL.standardizedFileURL
        })
        controller.tableView.selectRowIndexes(IndexSet(integer: otherRow), byExtendingSelection: false)

        let initialRow = try #require((0..<controller.tableView.numberOfRows).first { row in
            guard let writer = controller.tableView(
                controller.tableView,
                pasteboardWriterForRow: row
            ) as? NSURL else {
                return false
            }
            return (writer as URL).standardizedFileURL == initiallySelectedURL.standardizedFileURL
        })
        let selectionStartedAt = Date()
        controller.tableView.selectRowIndexes(IndexSet(integer: initialRow), byExtendingSelection: false)
        let selectionDuration = Date().timeIntervalSince(selectionStartedAt)

        #expect(selectionDuration < 0.15)
        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL == initiallySelectedURL.standardizedFileURL)
        await controller.waitForActiveNoteLoadForLibrary()
        let probeSnapshot = probe.snapshot()
        #expect(probeSnapshot.readCount >= 1)
        #expect(!probeSnapshot.observedMainThread)
    }

    @MainActor
    @Test
    func visibleLibraryLoadsUncachedNotesOffMainAndIgnoresStaleResults() async throws {
        let suiteName = "mudsnote.library-async-load-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-async-load-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let now = Date()
        var noteURLs: [URL] = []
        for index in 0..<8 {
            let url = try store.saveNewNote(title: "Async Note \(index)", body: "Async body \(index)")
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(Double(index) * -60)],
                ofItemAtPath: url.path
            )
            noteURLs.append(url)
        }
        let delayedURL = noteURLs[7].standardizedFileURL
        let targetURL = noteURLs[4].standardizedFileURL

        let controller = LibraryWindowController(
            noteStore: store,
            noteLoader: { url in
                if url.standardizedFileURL == delayedURL {
                    Thread.sleep(forTimeInterval: 0.45)
                }
                return try store.loadNote(at: url)
            },
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }
        controller.showWindowAndFocus()

        func row(for url: URL) -> Int? {
            (0..<controller.tableView.numberOfRows).first { row in
                guard let writer = controller.tableView(
                    controller.tableView,
                    pasteboardWriterForRow: row
                ) as? NSURL else {
                    return false
                }
                return (writer as URL).standardizedFileURL == url.standardizedFileURL
            }
        }

        let delayedRow = try #require(row(for: delayedURL))
        let targetRow = try #require(row(for: targetURL))
        let initialTitle = controller.titleField.stringValue
        let initialBody = controller.editorTextView.string
        let selectionStart = Date()
        controller.tableView.selectRowIndexes(IndexSet(integer: delayedRow), byExtendingSelection: false)
        #expect(Date().timeIntervalSince(selectionStart) < 0.2)
        #expect(controller.titleField.stringValue == initialTitle)
        #expect(controller.editorTextView.string == initialBody)
        #expect(!controller.editorTextView.isEditable)

        controller.tableView.selectRowIndexes(IndexSet(integer: targetRow), byExtendingSelection: false)
        await controller.waitForActiveNoteLoadForLibrary()
        try await Task.sleep(nanoseconds: 600_000_000)

        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL == targetURL)
        #expect(controller.titleField.stringValue == "Async Note 4")
        #expect(controller.editorTextView.string == "Async Note 4\n\nAsync body 4")
        #expect(controller.hasCachedLoadedNoteForLibrary(at: targetURL))
    }

    @MainActor
    @Test
    func fileTreeLoadsUncachedNoteDespiteHiddenListSelection() async throws {
        let suiteName = "mudsnote.library-async-load-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-async-load-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let now = Date()
        var noteURLs: [URL] = []
        for index in 0..<8 {
            let url = try store.saveNewNote(title: "Async Note \(index)", body: "Async body \(index)")
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(Double(index) * -60)],
                ofItemAtPath: url.path
            )
            noteURLs.append(url)
        }
        let delayedURL = noteURLs[7].standardizedFileURL
        let targetURL = noteURLs[4].standardizedFileURL

        let controller = LibraryWindowController(
            noteStore: store,
            noteLoader: { url in
                if url.standardizedFileURL == delayedURL {
                    Thread.sleep(forTimeInterval: 0.45)
                }
                return try store.loadNote(at: url)
            },
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }
        controller.loadSourceFoldersForLibrary()
        controller.showWindowAndFocus()
        #expect(controller.setSourceFolderExpandedForLibrary(store.notesDirectory, expanded: true))
        let outline = controller.sourceOutlineView
        let previousListRow = controller.tableView.selectedRow
        func treeRow(titled title: String) throws -> Int {
            try #require((0..<outline.numberOfRows).first { row in
                (outline.view(atColumn: 0, row: row, makeIfNecessary: true)
                    as? NSTableCellView)?.textField?.stringValue == title
            })
        }
        outline.selectRowIndexes(IndexSet(integer: try treeRow(titled: "Async Note 7")), byExtendingSelection: false)
        #expect(!controller.editorTextView.isEditable)
        outline.selectRowIndexes(IndexSet(integer: try treeRow(titled: "Async Note 4")), byExtendingSelection: false)
        #expect(controller.tableView.selectedRow == previousListRow)
        await controller.waitForActiveNoteLoadForLibrary()
        try await Task.sleep(nanoseconds: 600_000_000)
        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL == targetURL)
        #expect(controller.editorTextView.string == "Async Note 4\n\nAsync body 4")
        #expect(controller.editorTextView.isEditable)
        let menu = try #require(controller.sourceContextMenuForLibrary(row: outline.selectedRow))
        let titles = menu.items.map(\.title)
        #expect(titles.contains("删除"))
        #expect(titles.contains("置顶笔记"))
        #expect(titles.contains("移到文件夹"))
        #expect(!titles.contains("复制 Markdown 路径"))
        #expect(!titles.contains("复制 Markdown 内容"))
        #expect(!titles.contains("导出 Markdown..."))
        #expect(controller.selectedMarkdownFileURLsForLibrary() == [targetURL])
        try controller.deleteSelectedNotesForLibrary()
        #expect(!FileManager.default.fileExists(atPath: targetURL.path))
        #expect(FileManager.default.fileExists(atPath: noteURLs[0].path))
        #expect(store.listTrashedNotes(limit: 10).contains { $0.title == "Async Note 4" })
    }

    @MainActor
    @Test
    func defaultLaunchOpensLibraryUnlessAnotherSurfaceIsRequested() {
        #expect(AppController.shouldOpenLibraryOnLaunch(arguments: []))
        #expect(AppController.shouldOpenLibraryOnLaunch(arguments: ["--library"]))
        #expect(AppController.shouldOpenLibraryOnLaunch(arguments: ["-psn_0_12345"]))
        #expect(!AppController.shouldOpenLibraryOnLaunch(arguments: ["--quick-capture"]))
        #expect(!AppController.shouldOpenLibraryOnLaunch(arguments: ["--floating-note"]))
        #expect(!AppController.shouldOpenLibraryOnLaunch(arguments: ["--search"]))
        #expect(!AppController.shouldOpenLibraryOnLaunch(arguments: ["--preferences"]))
        #expect(AppController.usesCanonicalVisualQAWindowSize(arguments: [
            "--library",
            "--visual-qa-canonical-window-size"
        ]))
        #expect(!AppController.usesCanonicalVisualQAWindowSize(arguments: ["--library"]))
    }

    @MainActor
    @Test
    func appControllerAcceptsExistingMarkdownFilesAndRejectsOtherItems() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-open-file-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let markdownURL = root.appendingPathComponent("Direct Open.MD")
        let longMarkdownURL = root.appendingPathComponent("Second.markdown")
        let textURL = root.appendingPathComponent("Ignored.txt")
        let directoryURL = root.appendingPathComponent("Folder.md", isDirectory: true)
        try "# Direct Open".write(to: markdownURL, atomically: true, encoding: .utf8)
        try "Second".write(to: longMarkdownURL, atomically: true, encoding: .utf8)
        try "Ignored".write(to: textURL, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let urls = AppController.markdownFileURLs(from: [
            markdownURL.path,
            markdownURL.path,
            longMarkdownURL.path,
            textURL.path,
            directoryURL.path,
            root.appendingPathComponent("Missing.md").path
        ])

        #expect(urls.map(\.path) == [markdownURL.standardizedFileURL.path, longMarkdownURL.standardizedFileURL.path])
    }

    @MainActor
    @Test
    func externalMarkdownOpensAndSavesInPlaceInLibraryWindow() async throws {
        let suiteName = "mudsnote.external-library-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-external-library-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        try store.ensureNotesDirectory()
        let managedURL = try store.saveNewNote(title: "Managed Draft", body: "Managed body")
        let externalURL = root.appendingPathComponent("Original Name.markdown")
        try "# Original Heading\n\nOriginal body\n".write(to: externalURL, atomically: true, encoding: .utf8)
        var savedURL: URL?
        let controller = LibraryWindowController(
            noteStore: store,
            defersInitialNoteHydration: false,
            onOpenInSeparateWindow: { _ in },
            onSave: { savedURL = $0 },
            onClose: {}
        )
        defer { controller.close() }

        controller.titleField.stringValue = "Managed Updated"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.titleField))
        try controller.openMarkdownDocumentForLibrary(at: externalURL)

        await controller.waitForBackgroundAutosaveForTesting()
        let managedSavedURL = try #require(savedURL)
        #expect(!FileManager.default.fileExists(atPath: managedURL.path))
        #expect(FileManager.default.fileExists(atPath: managedSavedURL.path))
        #expect(managedSavedURL.lastPathComponent.localizedCaseInsensitiveContains("managed-updated"))
        #expect(!(controller.window is NSPanel))
        #expect(controller.selectedMarkdownFileURLForLibrary() == externalURL.standardizedFileURL)
        #expect(controller.titleField.stringValue == "Original Heading")
        #expect(controller.editorTextView.string == "Original Heading\n\nOriginal body")
        #expect(controller.noteListSearchResultsForLibrary().contains {
            $0.url.standardizedFileURL == externalURL.standardizedFileURL
        })
        #expect(!controller.sourceTitlesForLibrary().contains("所有 iCloud 笔记"))
        #expect(controller.sourceTitlesForLibrary().contains(root.lastPathComponent))
        #expect(controller.selectedSourceTitleForLibrary == root.lastPathComponent)
        #expect(controller.noteListTitleLabel.stringValue == root.lastPathComponent)
        #expect(controller.sourceFolderURLsForLibrary().contains(root.standardizedFileURL))
        let previewFolderMenu = try #require(controller.sourceContextMenuForLibrary(
            row: controller.sourceOutlineView.selectedRow
        ))
        #expect(previewFolderMenu.items.filter { !$0.isSeparatorItem }.map(\.title) == ["以列表显示", "在 Finder 中显示"])

        let updated = MarkdownRichTextCodec.render(markdown: "# Changed Heading\n\nUpdated body", theme: controller.theme)
        controller.titleField.stringValue = "Changed Heading"
        controller.editorTextView.textStorage?.setAttributedString(updated)
        _ = try controller.saveCurrentNoteForLibrary()

        #expect(savedURL == externalURL.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: externalURL.path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Changed Heading.md").path))
        let loaded = try store.loadNote(at: externalURL)
        #expect(loaded.title == "Changed Heading")
        #expect(loaded.body == "Updated body")
    }

    @MainActor
    @Test
    func externalMarkdownReplacesDeferredInitialLoadingShell() async throws {
        let suiteName = "mudsnote.external-deferred-open-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-external-deferred-open-tests-\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        try store.ensureNotesDirectory()
        _ = try store.saveNewNote(title: "Initial Note", body: "Initial body")
        let externalURL = root.appendingPathComponent("Outside.md")
        try "# Outside\n\nVisible external body".write(
            to: externalURL,
            atomically: true,
            encoding: .utf8
        )
        let controller = LibraryWindowController(
            noteStore: store,
            defersInitialNoteHydration: true,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        controller.showWindowAndFocus()
        try controller.openMarkdownDocumentForLibrary(at: externalURL)
        try await Task.sleep(for: .milliseconds(250))

        #expect(controller.selectedMarkdownFileURLForLibrary() == externalURL.standardizedFileURL)
        #expect(controller.titleField.stringValue == "Outside")
        #expect(controller.editorTextView.string == "Outside\n\nVisible external body")
        #expect(controller.editorTextView.isEditable)
    }

    @MainActor
    @Test
    func attachmentInventoryClassifiesReferencedOrphanedAndMissingFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-attachment-inventory-tests-\(UUID().uuidString)", isDirectory: true)
        let attachments = root.appendingPathComponent("Attachments/2026/07", isDirectory: true)
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let referencedURL = attachments.appendingPathComponent("photo (1).png")
        let orphanedURL = attachments.appendingPathComponent("unused.pdf")
        try Data([0x01, 0x02, 0x03]).write(to: referencedURL)
        try Data([0x04]).write(to: orphanedURL)
        let noteURL = root.appendingPathComponent("Note.md")
        try """
        # Note

        ![photo](Attachments/2026/07/photo%20(1).png)
        [missing](<Attachments/2026/07/缺失 文件.pdf>)
        [website](https://example.com/Attachments/remote.pdf)
        """.write(to: noteURL, atomically: true, encoding: .utf8)

        let items = LibraryAttachmentInventory.build(roots: [root])
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.filename, $0) })
        let referenced = try #require(byName["photo (1).png"])
        let orphaned = try #require(byName["unused.pdf"])
        let missing = try #require(byName["缺失 文件.pdf"])

        #expect(referenced.state == .referenced)
        #expect(referenced.byteCount == 3)
        #expect(referenced.referencingNotes == [noteURL.standardizedFileURL])
        #expect(orphaned.state == .unreferenced)
        #expect(orphaned.byteCount == 1)
        #expect(missing.state == .missing)
        #expect(missing.byteCount == nil)
        #expect(missing.referencingNotes == [noteURL.standardizedFileURL])
        #expect(items.count == 3)
    }

    @MainActor
    @Test
    func attachmentManagerOnlyEnablesDeletionForExistingUnreferencedFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-attachment-manager-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let referencedURL = root.appendingPathComponent("referenced.png")
        let orphanedURL = root.appendingPathComponent("orphaned.png")
        let missingURL = root.appendingPathComponent("missing.png")
        try Data([0x01]).write(to: referencedURL)
        try Data([0x02]).write(to: orphanedURL)
        let noteURL = root.appendingPathComponent("Note.md")
        let items = [
            LibraryAttachmentItem(
                url: referencedURL,
                state: .referenced,
                byteCount: 1,
                referencingNotes: [noteURL]
            ),
            LibraryAttachmentItem(
                url: orphanedURL,
                state: .unreferenced,
                byteCount: 1,
                referencingNotes: []
            ),
            LibraryAttachmentItem(
                url: missingURL,
                state: .missing,
                byteCount: nil,
                referencingNotes: [noteURL]
            )
        ]
        let controller = LibraryAttachmentManagerWindowController(
            rootsProvider: { [root] in [root] },
            onOpenNote: { _ in }
        )
        defer { controller.close() }
        controller.loadAttachmentItemsForTesting(items)

        controller.selectAttachmentForTesting(at: 0)
        #expect(!controller.canDeleteSelectedAttachmentForTesting)
        controller.selectAttachmentForTesting(at: 1)
        #expect(controller.canDeleteSelectedAttachmentForTesting)
        controller.selectAttachmentForTesting(at: 2)
        #expect(!controller.canDeleteSelectedAttachmentForTesting)

        controller.setAttachmentFilterForTesting(.unreferenced)
        #expect(controller.attachmentItemsForTesting.map(\.url) == [orphanedURL])
    }

    @MainActor
    @Test
    func movingPreviewedExternalMarkdownIntoLibraryRemovesOldProjection() throws {
        let suiteName = "mudsnote.external-preview-move-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-external-preview-move-tests-\(UUID().uuidString)", isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let previewDirectory = root.appendingPathComponent("Preview", isDirectory: true)
        let externalURL = previewDirectory.appendingPathComponent("Move Me.md")
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        try "# Move Me\n\nBody".write(to: externalURL, atomically: true, encoding: .utf8)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = notesDirectory
        let controller = LibraryWindowController(
            noteStore: store,
            defersInitialNoteHydration: false,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        try controller.openMarkdownDocumentForLibrary(at: externalURL)
        let movedURL = try #require(controller.moveSelectedNotesForLibrary(to: notesDirectory).first)

        #expect(!FileManager.default.fileExists(atPath: externalURL.path))
        #expect(FileManager.default.fileExists(atPath: movedURL.path))
        let matchingNotes = controller.noteListSearchResultsForLibrary().filter { $0.title == "Move Me" }
        #expect(matchingNotes.map { $0.url.standardizedFileURL } == [movedURL.standardizedFileURL])
        #expect(!controller.sourceFolderURLsForLibrary().contains(previewDirectory.standardizedFileURL))
    }

    @MainActor
    @Test
    func applicationMainMenuProvidesNotesLikeCoreCommands() throws {
        let controller = AppController()
        let mainMenu = controller.makeMainMenuForApplication()

        #expect(mainMenu.items.map(\.title) == [MudsnoteBrand.appName, "文件", "编辑", "显示", "窗口"])

        let fileMenu = try #require(mainMenu.items.first { $0.title == "文件" }?.submenu)
        let newNoteItem = try #require(fileMenu.items.first { $0.title == "新建笔记" })
        #expect(newNoteItem.target === controller)
        #expect(newNoteItem.action == #selector(AppController.newNoteFromMainMenu))
        #expect(newNoteItem.keyEquivalent == "n")
        #expect(newNoteItem.keyEquivalentModifierMask == [.command])
        let newFolderItem = try #require(fileMenu.items.first { $0.title == "新建文件夹" })
        #expect(newFolderItem.target === controller)
        #expect(newFolderItem.action == #selector(AppController.newFolderFromMainMenu))
        #expect(newFolderItem.keyEquivalent == "n")
        #expect(newFolderItem.keyEquivalentModifierMask == [.command, .shift])
        let manageAttachmentsItem = try #require(fileMenu.items.first { $0.title == "管理附件…" })
        #expect(manageAttachmentsItem.target === controller)
        #expect(manageAttachmentsItem.action == #selector(AppController.manageAttachmentsFromMainMenu))
        let openItem = try #require(fileMenu.items.first { $0.title == "打开..." })
        #expect(openItem.target === controller)
        #expect(openItem.action == #selector(AppController.openDocumentFromMainMenu))
        #expect(openItem.keyEquivalent == "o")
        #expect(openItem.keyEquivalentModifierMask == [.command])
        let saveItem = try #require(fileMenu.items.first { $0.title == "保存" })
        #expect(saveItem.target === controller)
        #expect(saveItem.action == #selector(AppController.saveDocumentFromMainMenu))
        #expect(saveItem.keyEquivalent == "s")
        #expect(saveItem.keyEquivalentModifierMask == [.command])
        #expect(!controller.validateMenuItem(saveItem))
        let deleteNoteItem = try #require(fileMenu.items.first { $0.title == "移到最近删除" })
        #expect(deleteNoteItem.target === controller)
        #expect(deleteNoteItem.action == #selector(AppController.deleteSelectedNotesFromMainMenu))
        #expect(!controller.validateMenuItem(deleteNoteItem))
        let restoreNoteItem = try #require(fileMenu.items.first { $0.title == "恢复笔记" })
        #expect(restoreNoteItem.target === controller)
        #expect(restoreNoteItem.action == #selector(AppController.restoreSelectedNotesFromMainMenu))
        #expect(!controller.validateMenuItem(restoreNoteItem))
        let moveNoteItem = try #require(fileMenu.items.first { $0.title == "移到文件夹" })
        #expect(moveNoteItem.target === controller)
        #expect(moveNoteItem.action == #selector(AppController.moveSelectedNotesFromMainMenu))
        #expect(!controller.validateMenuItem(moveNoteItem))
        let moveNoteMenu = try #require(moveNoteItem.submenu)
        controller.menuNeedsUpdate(moveNoteMenu)
        #expect(moveNoteMenu.items.map(\.title) == ["无可用文件夹"])
        #expect(moveNoteMenu.items.allSatisfy { !$0.isEnabled })
        #expect(fileMenu.items.first { $0.title == "关闭窗口" }?.keyEquivalent == "w")

        let editMenu = try #require(mainMenu.items.first { $0.title == "编辑" }?.submenu)
        #expect(editMenu.items.contains { $0.title == "撤销" && $0.keyEquivalent == "z" })
        #expect(editMenu.items.contains { $0.title == "粘贴" && $0.keyEquivalent == "v" })
        #expect(editMenu.items.contains { $0.title == "全选" && $0.keyEquivalent == "a" })

        let viewMenu = try #require(mainMenu.items.first { $0.title == "显示" }?.submenu)
        let listViewItem = try #require(viewMenu.items.first { $0.title == "显示为列表" })
        #expect(listViewItem.target === controller)
        #expect(listViewItem.action == #selector(AppController.setLibraryNoteViewModeFromMainMenu(_:)))
        #expect(listViewItem.keyEquivalent == "1")
        #expect(listViewItem.keyEquivalentModifierMask == [.command])
        #expect(controller.validateMenuItem(listViewItem))
        #expect(listViewItem.state == .on)
        let galleryViewItem = try #require(viewMenu.items.first { $0.title == "显示为画廊" })
        #expect(galleryViewItem.target === controller)
        #expect(galleryViewItem.action == #selector(AppController.setLibraryNoteViewModeFromMainMenu(_:)))
        #expect(galleryViewItem.keyEquivalent == "2")
        #expect(galleryViewItem.keyEquivalentModifierMask == [.command])
        #expect(controller.validateMenuItem(galleryViewItem))
        #expect(galleryViewItem.state == .off)
        let searchItem = try #require(viewMenu.items.first { $0.title == "搜索笔记" })
        #expect(searchItem.target === controller)
        #expect(searchItem.action == #selector(AppController.focusLibrarySearchFromMainMenu))
        #expect(searchItem.keyEquivalent == "f")
        #expect(searchItem.keyEquivalentModifierMask == [.command])
        #expect(viewMenu.items.first { $0.title == "显示或隐藏资料库" }?.keyEquivalentModifierMask == [.command, .control])
        let sortMenu = try #require(viewMenu.items.first { $0.title == "排序方式" }?.submenu)
        #expect(sortMenu.items.map(\.title) == ["编辑日期", "创建日期", "标题"])
        #expect(sortMenu.items.allSatisfy {
            $0.target === controller && $0.action == #selector(AppController.sortLibraryNotesFromMainMenu(_:))
        })
        let editedDateItem = try #require(sortMenu.items.first { $0.title == "编辑日期" })
        #expect(controller.validateMenuItem(editedDateItem))
        #expect(editedDateItem.state == .on)
        let groupingItem = try #require(viewMenu.items.first { $0.title == "按日期分组" })
        #expect(groupingItem.target === controller)
        #expect(groupingItem.action == #selector(AppController.toggleLibraryNoteGroupingFromMainMenu(_:)))
        #expect(controller.validateMenuItem(groupingItem))
        #expect(groupingItem.state == .on)
    }

    @MainActor
    @Test
    func appControllerVisualQAModeUsesIsolatedNoteStore() throws {
        let suiteName = "mudsnote.visual-qa-launch-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-visual-qa-launch-tests-\(UUID().uuidString)", isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let resourcesDirectory = root.appendingPathComponent("Resources", isDirectory: true)
        let archivesDirectory = root.appendingPathComponent("Archives", isDirectory: true)
        let appSupportDirectory = root.appendingPathComponent("AppSupport", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = AppController.makeNoteStore(arguments: [
            "--library",
            "--visual-qa-defaults-suite",
            suiteName,
            "--visual-qa-notes-dir",
            notesDirectory.path,
            "--visual-qa-extra-dir",
            resourcesDirectory.path,
            "--visual-qa-extra-dir",
            archivesDirectory.path,
            "--visual-qa-app-support-dir",
            appSupportDirectory.path
        ])

        #expect(store.notesDirectory.standardizedFileURL == notesDirectory.standardizedFileURL)
        #expect(store.preferredDirectories.map(\.standardizedFileURL.path) == [
            notesDirectory.standardizedFileURL.path,
            resourcesDirectory.standardizedFileURL.path,
            archivesDirectory.standardizedFileURL.path
        ])
        #expect(defaults.string(forKey: "mudsnote.notesDirectory") == notesDirectory.standardizedFileURL.path)
        #expect(UserDefaults.standard.string(forKey: "mudsnote.notesDirectory") != notesDirectory.standardizedFileURL.path)
        let selectedNoteURL = notesDirectory.appendingPathComponent("Selected Visual.md")
        #expect(AppController.visualQASelectedNoteURL(arguments: [
            "--visual-qa-select-note",
            selectedNoteURL.path
        ]) == selectedNoteURL.standardizedFileURL)
        #expect(AppController.visualQASelectedNoteURL(arguments: [
            "--visual-qa-select-note",
            "--library"
        ]) == nil)
    }

    @Test
    func visualQALaunchCanPreferAnExternalDisplay() {
        #expect(AppController.prefersExternalVisualQAScreen(arguments: ["--visual-qa-external-screen"]))
        #expect(!AppController.prefersExternalVisualQAScreen(arguments: ["--library"]))
    }

    @MainActor
    @Test
    func deferredLibraryLaunchShowsLastCachedBodyBeforeSlowSourceRefresh() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-launch-body-cache-tests-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "mudsnote.library-launch-body-cache-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let cachedURL = try store.saveNewNote(title: "Cached Selection", body: "Fresh source body")
        _ = try store.saveNewNote(title: "Newer List Note", body: "Other body")
        let modifiedAt = try #require(
            (try FileManager.default.attributesOfItem(atPath: cachedURL.path)[.modificationDate]) as? Date
        )
        store.cacheLibraryLaunchNote(
            LoadedNoteDocument(
                title: "Cached Selection",
                body: "Cached body is immediate",
                tags: [],
                sourceContents: "# Cached Selection\n\nCached body is immediate"
            ),
            at: cachedURL,
            modifiedAt: modifiedAt
        )

        let controller = LibraryWindowController(
            noteStore: store,
            defersInitialNoteHydration: true,
            noteLoader: { url in
                Thread.sleep(forTimeInterval: 0.45)
                return try store.loadNote(at: url)
            },
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        controller.showWindowAndFocus()

        #expect(controller.selectedMarkdownFileURLForLibrary() == cachedURL.standardizedFileURL)
        #expect(controller.titleField.stringValue == "Cached Selection")
        #expect(controller.editorTextView.string == "Cached Selection\n\nCached body is immediate")
        #expect(!controller.editorTextView.isEditable)
        #expect(!controller.hasReleasedDeferredLaunchWorkForLibrary)

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, controller.editorTextView.string != "Cached Selection\n\nFresh source body" {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(controller.editorTextView.string == "Cached Selection\n\nFresh source body")
        #expect(controller.editorTextView.isEditable)
        #expect(controller.hasReleasedDeferredLaunchWorkForLibrary)
    }

    @MainActor
    @Test
    func coldLibraryLaunchPrioritizesFirstNoteBeforeIndexAndFolderWork() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-launch-priority-tests-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "mudsnote.library-launch-priority-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        _ = try store.saveNewNote(title: "Cold Priority", body: "First body wins")
        let controller = LibraryWindowController(
            noteStore: store,
            defersInitialNoteHydration: true,
            noteLoader: { url in
                Thread.sleep(forTimeInterval: 0.35)
                return try store.loadNote(at: url)
            },
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        controller.showWindowAndFocus()

        #expect(!controller.hasReleasedDeferredLaunchWorkForLibrary)
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, controller.editorTextView.string != "Cold Priority\n\nFirst body wins" {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(controller.editorTextView.string == "Cold Priority\n\nFirst body wins")
        #expect(controller.hasReleasedDeferredLaunchWorkForLibrary)
    }

    @Test
    func recentlyDeletedNavigationUsesSnapshotBeforeBackgroundTrashRefresh() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-trash-navigation-snapshot-tests-\(UUID().uuidString)", isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let suiteName = "mudsnote.trash-navigation-snapshot-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = notesDirectory

        store.librarySidebarPresentationRawValue = 1
        let controller = LibraryWindowController(
            noteStore: store,
            defersInitialNoteHydration: true,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }
        controller.showWindowAndFocus()

        let noteURL = try store.saveNewNote(title: "Background Trash", body: "Loaded off navigation.")
        _ = try store.trashNote(at: noteURL)
        #expect(controller.selectSourceForLibrary(titled: "最近删除"))
        #expect(controller.noteListSearchResultsForLibrary().isEmpty)

        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline, controller.noteListSearchResultsForLibrary().isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["Background Trash"])
    }

    @MainActor
    @Test
    func preferencesWindowUsesStandardMacSettingsChrome() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-preferences-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var savedSettings: PreferencesSettings?
        let controller = PreferencesWindowController(
            currentDirectory: root,
            availableDirectories: [root],
            currentOpacity: NoteStore.defaultPanelOpacity,
            currentQuickCaptureHotKey: "option+shift+n",
            currentFloatingHotKey: "option+r",
            currentSaveShortcut: "command+return",
            floatingNoteStaysOnTop: true,
            spellCheckingEnabled: true,
            aiEnabled: false,
            aiCodexExecutablePath: "",
            onPreviewOpacity: { _ in },
            onResetWindowFrames: {},
            onSave: { savedSettings = $0 }
        )
        defer { controller.close() }

        let window = try #require(controller.window)
        #expect(window.title == "Mudsnote 设置")
        #expect(window.styleMask.contains(NSWindow.StyleMask.titled))
        #expect(!window.styleMask.contains(NSWindow.StyleMask.fullSizeContentView))
        #expect(window.isOpaque)
        #expect(window.backgroundColor == NSColor.windowBackgroundColor)
        #expect(window.alphaValue == 1)
        #expect(window.toolbarStyle == NSWindow.ToolbarStyle.preference)
        #expect(window.toolbar?.selectedItemIdentifier?.rawValue == "mudsnote.settings.general")
        #expect(window.toolbar?.items.contains {
            $0.itemIdentifier.rawValue == "mudsnote.settings.theme" && $0.label == "主题"
        } == true)
        #expect(window.contentView?.allSubviews.compactMap { $0 as? NSButton }.contains {
            $0.title == "保存后在 Finder 中显示笔记"
        } == false)
        #expect(controller.contextMenuOptionButtons.count == EditorContextMenuOption.allCases.count)
        #expect(controller.selectionToolbarOptionButtons.count == SelectionToolbarOption.allCases.count)
        #expect(controller.themeColorPopUp.itemTitles.contains("经典黄"))
        controller.contextMenuOptionButtons[.paste]?.state = .off
        controller.selectionToolbarOptionButtons[.highlight]?.state = .off
        controller.themeColorPopUp.selectItem(withTitle: "松石")
        let saveButton = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSButton }.first { $0.title == "保存" })
        saveButton.performClick(nil)
        #expect(savedSettings?.editorContextMenuOptions.contains(.paste) == false)
        #expect(savedSettings?.selectionToolbarOptions.contains(.highlight) == false)
        #expect(savedSettings?.themeColorIdentifier == "teal")

        controller.updatePanelOpacity(NoteStore.minimumPanelOpacity)
        #expect(window.alphaValue == 1)
    }

    @MainActor
    @Test
    func preferencesResetWindowPositionsCommitsOnlyOnSave() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-preferences-reset-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var resetCount = 0
        func makeController() -> PreferencesWindowController {
            PreferencesWindowController(
                currentDirectory: root,
                availableDirectories: [root],
                currentOpacity: NoteStore.defaultPanelOpacity,
                currentQuickCaptureHotKey: "option+shift+n",
                currentFloatingHotKey: "option+r",
                currentSaveShortcut: "command+return",
                floatingNoteStaysOnTop: true,
                spellCheckingEnabled: true,
                aiEnabled: false,
                aiCodexExecutablePath: "",
                onPreviewOpacity: { _ in },
                onResetWindowFrames: { resetCount += 1 },
                onSave: { _ in }
            )
        }

        let cancelledController = makeController()
        let cancelledWindow = try #require(cancelledController.window)
        let cancelledResetButton = cancelledController.resetWindowPositionsButton
        cancelledResetButton.performClick(nil)
        #expect(resetCount == 0)
        #expect(cancelledResetButton.title == "保存后重置")
        #expect(cancelledResetButton.isEnabled == false)
        let cancelButton = try #require(
            cancelledWindow.contentView?.allSubviews.compactMap { $0 as? NSButton }
                .first { $0.title == "取消" }
        )
        cancelButton.performClick(nil)
        #expect(resetCount == 0)

        let savedController = makeController()
        defer { savedController.close() }
        let savedWindow = try #require(savedController.window)
        let savedResetButton = savedController.resetWindowPositionsButton
        savedResetButton.performClick(nil)
        #expect(resetCount == 0)
        let saveButton = try #require(
            savedWindow.contentView?.allSubviews.compactMap { $0 as? NSButton }
                .first { $0.title == "保存" }
        )
        saveButton.performClick(nil)
        #expect(resetCount == 1)
    }

    @MainActor
    @Test
    func editorDisablesSpellCheckingFromPreference() throws {
        let harness = try makeEditorControllerHarness(
            draftID: "quick-capture",
            showsSaveButton: true,
            configureStore: { store in
                store.spellCheckingEnabled = false
            }
        )
        defer { harness.tearDown() }

        #expect(!harness.controller.editorTextView.isContinuousSpellCheckingEnabled)
    }

    @MainActor
    @Test
    func slashSuggestionPopoverUsesCompactMenuSizing() throws {
        let controller = SuggestionPopoverController()
        controller.loadViewIfNeeded()

        controller.updateItems([
            SuggestionItem(title: "Heading 1", subtitle: nil, symbolName: nil),
            SuggestionItem(title: "Heading 2", subtitle: nil, symbolName: nil),
            SuggestionItem(title: "Heading 3", subtitle: nil, symbolName: nil),
            SuggestionItem(title: "To-do List", subtitle: nil, symbolName: nil),
            SuggestionItem(title: "Bulleted List", subtitle: nil, symbolName: nil),
            SuggestionItem(title: "Numbered List", subtitle: nil, symbolName: nil),
            SuggestionItem(title: "Divider", subtitle: nil, symbolName: nil)
        ])

        #expect(controller.preferredContentSize.width < 102)
        #expect(controller.preferredContentSize.width >= 96)
        #expect(controller.preferredContentSize.height == 120)
        #expect(controller.view.layer?.borderWidth == 0)
        #expect(controller.view.layer?.backgroundColor != NSColor.clear.cgColor)

        let scrollView = try #require(controller.view.subviews.compactMap { $0 as? NSScrollView }.first)
        let listView = try #require(scrollView.documentView as? SuggestionListView)
        #expect(listView.frame.width == controller.contentWidth)
        #expect(controller.preferredContentSize.width == controller.contentWidth)
        #expect(!scrollView.hasVerticalScroller)
    }

    @MainActor
    @Test
    func slashCommandsShareStableIdentifiersAndMatching() {
        let identifiers = SlashCommand.allCases.map(\.identifier)
        #expect(Set(identifiers).count == identifiers.count)

        #expect(SlashCommand.matching("h", includesAI: false).map(\.identifier) == [
            "heading1", "heading2", "heading3"
        ])
        #expect(SlashCommand.matching("H", includesAI: false).map(\.identifier) == [
            "heading1", "heading2", "heading3"
        ])
        #expect(SlashCommand.matching("t", includesAI: false).map(\.identifier) == ["checklist"])
        #expect(SlashCommand.matching("编号", includesAI: false).map(\.identifier) == ["orderedList"])
        #expect(SlashCommand.matching("sum", includesAI: true).map(\.identifier) == ["aiSummarize"])
        #expect(SlashCommand.matching("sum", includesAI: false).isEmpty)
        #expect(SlashCommand.matching("not-a-command", includesAI: true).isEmpty)
    }

    @MainActor
    @Test
    func slashSuggestionCompositionAndCancelPreserveEditorState() async throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let recorder = SlashCommandInputSourceSessionRecorder()
        controller.slashCommandInputSourceSession = recorder
        controller.window?.makeFirstResponder(controller.editorTextView)

        controller.editorTextView.string = "/"
        controller.editorTextView.setSelectedRange(NSRange(location: 1, length: 0))
        controller.updateInlineSuggestions()
        try await Task.sleep(for: .milliseconds(10))
        let beforeCancel = controller.editorTextView.attributedString()
        let escape = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: controller.window?.windowNumber ?? 0,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: UInt16(kVK_Escape)
        ))
        #expect(controller.handleShortcutEvent(escape))
        #expect(controller.editorTextView.attributedString().isEqual(to: beforeCancel))
        #expect(controller.window?.firstResponder === controller.editorTextView)
        #expect(recorder.endCallCount > 0)

        recorder.reset()
        controller.editorTextView.setSelectedRange(NSRange(location: 1, length: 0))
        controller.editorTextView.setMarkedText(
            "拼",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 1, length: 0)
        )
        let markedTextSnapshot = controller.editorTextView.attributedString()
        #expect(controller.editorTextView.hasMarkedText())
        controller.updateInlineSuggestions()
        try await Task.sleep(for: .milliseconds(10))
        #expect(recorder.beginCalls.isEmpty)
        #expect(controller.editorTextView.attributedString().isEqual(to: markedTextSnapshot))
        #expect(controller.window?.firstResponder === controller.editorTextView)
        controller.editorTextView.unmarkText()
    }

    @MainActor
    @Test
    func systemSlashInputSourceSessionRefusesUnsafeSwitchBoundaries() {
        let session = SlashCommandInputSourceSession()

        #expect(!session.beginIfAllowed(hasMarkedText: true, editorIsFirstResponder: true))
        #expect(!session.isActive)
        #expect(!session.beginIfAllowed(hasMarkedText: false, editorIsFirstResponder: false))
        #expect(!session.isActive)
    }

    @MainActor
    @Test
    func inlineSuggestionPopoverIsHostedAtWindowContentLevel() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let contentView = try #require(controller.window?.contentView)

        #expect(controller.suggestionController.view.superview === contentView)

        controller.editorTextView.string = "/heading"
        controller.editorTextView.setSelectedRange(NSRange(location: 8, length: 0))
        controller.updateInlineSuggestions()

        #expect(controller.suggestionController.view.superview === contentView)
        #expect(!controller.suggestionController.view.isHidden)
        #expect(controller.suggestionController.view.frame.minX >= 4)
        #expect(controller.suggestionController.view.frame.maxX <= contentView.bounds.maxX - 4)

        let tokenStartRect = controller.editorTextView.convert(
            caretRectInWindow(for: controller.editorTextView, at: 0),
            to: contentView
        )
        let caretRect = controller.editorTextView.convert(
            caretRectInWindow(for: controller.editorTextView),
            to: contentView
        )
        let expectedX = min(
            max(tokenStartRect.minX, 4),
            max(contentView.bounds.width - controller.suggestionController.view.frame.width - 4, 4)
        )
        #expect(abs(controller.suggestionController.view.frame.minX - expectedX) < 1)
        #expect(controller.suggestionController.view.frame.minX < caretRect.minX)
    }

    @MainActor
    @Test
    func activeToolbarButtonUsesWhiteFillHighlight() {
        let button = HoverToolbarButton(frame: NSRect(x: 0, y: 0, width: 30, height: 26))
        button.isActive = true

        #expect(button.layer?.borderWidth == 0)
        #expect(button.layer?.backgroundColor != NSColor.clear.cgColor)
        #expect(button.contentTintColor == panelPrimaryTextColor())
    }

    @MainActor
    @Test
    func ghostButtonRefreshesTintWhenHighlightChanges() {
        let button = FocusAwareGhostButton(frame: NSRect(x: 0, y: 0, width: 30, height: 26))

        button.highlight(true)
        #expect(button.contentTintColor == panelPrimaryTextColor())

        button.highlight(false)
        #expect(button.contentTintColor == panelPrimaryTextColor())
    }

    @MainActor
    @Test
    func debouncedNoteSearchPublishesOnlyTheLatestGeneration() async throws {
        let suiteName = "mudsnote.debounced-search-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-debounced-search-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        _ = try store.saveNewNote(title: "Alpha", body: "First")
        _ = try store.saveNewNote(title: "Beta", body: "Second")

        let controller = DebouncedNoteSearchController(noteStore: store, limit: 10)
        var deliveries: [DebouncedNoteSearchResults] = []
        controller.submit(query: "Alpha") { deliveries.append($0) }
        controller.submit(query: "Beta") { deliveries.append($0) }
        #expect(deliveries.isEmpty)

        await controller.waitForCurrentSearchForTesting()
        #expect(deliveries.map(\.query) == ["Beta"])
        #expect(deliveries.first?.results.map(\.title) == ["Beta"])

        controller.submit(query: "Alpha") { deliveries.append($0) }
        controller.cancel()
        await controller.waitForCurrentSearchForTesting()
        #expect(deliveries.map(\.query) == ["Beta"])
    }

    @MainActor
    @Test
    func searchWindowDebouncesTypingAndAppliesBackgroundResults() async throws {
        let suiteName = "mudsnote.search-window-background-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-search-window-background-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        _ = try store.saveNewNote(title: "Alpha", body: "First")
        _ = try store.saveNewNote(title: "Beta", body: "Second")

        let controller = SearchWindowController(noteStore: store, onOpen: { _ in }, onClose: {})
        defer { controller.close() }
        await controller.waitForSearchForTesting()

        controller.searchField.stringValue = "Beta"
        controller.controlTextDidChange(Notification(
            name: NSControl.textDidChangeNotification,
            object: controller.searchField
        ))
        #expect(controller.searchInfoForTesting == "正在搜索…")
        await controller.waitForSearchForTesting()

        #expect(controller.resultTitlesForTesting == ["Beta"])
        #expect(controller.searchInfoForTesting.contains("1 条匹配"))
    }

    @MainActor
    @Test
    func separateNoteWindowReusesFloatingNoteChromeAndManager() throws {
        let notesRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-floating-style-test-\(UUID().uuidString)", isDirectory: true)
        let noteURL = notesRoot.appendingPathComponent("Managed.md")
        try FileManager.default.createDirectory(at: notesRoot, withIntermediateDirectories: true)
        try Data("# Managed\n\nBody".utf8).write(to: noteURL)
        defer { try? FileManager.default.removeItem(at: notesRoot) }

        let harness = try makeEditorControllerHarness(
            draftID: "floating-note",
            showsSaveButton: false,
            fileURL: noteURL,
            configureStore: { store in
                store.notesDirectory = notesRoot
            }
        )
        defer { harness.tearDown() }
        let controller = harness.controller

        #expect(controller.activeFloatingNoteURL == noteURL)
        #expect(controller.floatingNotePlaceholderLabel?.isHidden == true)
        #expect(controller.floatingNoteBrowseButton?.toolTip == "管理悬浮笔记")
        #expect(controller.saveButton == nil)

        controller.showWindowAndFocus()
        controller.floatingBrowseNotesPressed(controller.floatingNoteBrowseButton)
        let browser = try #require(controller.floatingNoteBrowserController)
        #expect(browser.window?.isVisible == true)
        controller.floatingBrowseNotesPressed(controller.floatingNoteBrowseButton)
        #expect(browser.window?.isVisible == false)
        controller.floatingBrowseNotesPressed(controller.floatingNoteBrowseButton)
        #expect(browser.window?.isVisible == true)
        browser.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: browser.window))
        #expect(browser.window?.isVisible == false)
    }

    @MainActor
    @Test
    func movableBackgroundViewReturnsSelfForEmptyHitAreas() {
        let view = WindowMoveBackgroundView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        let point = NSPoint(x: 24, y: 20)

        #expect(view.hitTest(point) === view)
        #expect(view.mouseDownCanMoveWindow == false)
    }

    @MainActor
    @Test
    func subviewPassthroughViewDoesNotSwallowBlankClicks() {
        let view = SubviewPassthroughView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        let point = NSPoint(x: 24, y: 20)

        #expect(view.hitTest(point) == nil)
    }

    @MainActor
    @Test
    func focusProxyContainerLetsTextFieldKeepDirectHits() {
        let proxy = FocusProxyContainerView(frame: NSRect(x: 0, y: 0, width: 220, height: 40))
        let field = FocusableTextField(string: "")
        field.frame = NSRect(x: 12, y: 6, width: 160, height: 28)
        proxy.addSubview(field)

        #expect(proxy.hitTest(NSPoint(x: 24, y: 20)) === field)
        #expect(proxy.hitTest(NSPoint(x: 208, y: 20)) === proxy)
    }

    @MainActor
    @Test
    func titleEditorProxyLetsTitleViewReceiveDirectHits() {
        let proxy = TitleEditorProxyView(frame: NSRect(x: 0, y: 0, width: 220, height: 34))
        let textView = FocusableTitleTextView(frame: proxy.bounds)
        proxy.addSubview(textView)

        #expect(proxy.hitTest(NSPoint(x: 24, y: 16)) === textView)
        #expect(proxy.hitTest(NSPoint(x: 200, y: 16)) === textView)
    }

    @MainActor
    @Test
    func titleTextViewReportsMarkedTextStateChanges() {
        let textView = FocusableTitleTextView(frame: NSRect(x: 0, y: 0, width: 220, height: 34))
        var callbackCount = 0
        textView.onTextInputStateChanged = { callbackCount += 1 }

        textView.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        textView.unmarkText()

        #expect(callbackCount >= 2)
    }

    struct EditorControllerHarness {
        let root: URL
        let suiteName: String
        let defaults: UserDefaults
        let store: NoteStore
        let controller: EditorWindowController

        @MainActor
        func tearDown() {
            controller.close()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
    }

    func makeEditorControllerHarness(
        draftID: String,
        showsSaveButton: Bool,
        fileURL: URL? = nil,
        saveShortcut: HotKeySpec? = nil,
        configureStore: (NoteStore) -> Void = { _ in },
        onSave: @escaping (URL) -> Void = { _ in },
        floatingNoteWindows: @escaping () -> [FloatingNoteWindowDescriptor] = { [] },
        onRequestOpenFloatingNote: @escaping (URL) -> Void = { _ in },
        onRequestActivateFloatingNote: @escaping (UUID) -> Void = { _ in },
        onRequestCloseFloatingNote: @escaping (UUID) -> Void = { _ in },
        onRequestCreateFloatingNote: @escaping () -> Void = {},
        saveDraftSnapshot: (@Sendable (DraftSnapshot) throws -> Void)? = nil,
        draftPersistenceErrorHandler: ((Error) -> Void)? = nil
    ) throws -> EditorControllerHarness {
        let suiteName = "mudsnote.app-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-app-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        configureStore(store)

        let controller = EditorWindowController(
            noteStore: store,
            panelOpacity: NoteStore.defaultPanelOpacity,
            fileURL: fileURL,
            draftIDOverride: draftID,
            saveShortcut: saveShortcut,
            showsSaveButton: showsSaveButton,
            onSave: onSave,
            onClose: {},
            onRequestSearch: {},
            floatingNoteWindows: floatingNoteWindows,
            onRequestOpenFloatingNote: onRequestOpenFloatingNote,
            onRequestActivateFloatingNote: onRequestActivateFloatingNote,
            onRequestCloseFloatingNote: onRequestCloseFloatingNote,
            onRequestCreateFloatingNote: onRequestCreateFloatingNote,
            saveDraftSnapshot: saveDraftSnapshot,
            draftPersistenceErrorHandler: draftPersistenceErrorHandler,
            onRequestPreferences: {}
        )

        return EditorControllerHarness(root: root, suiteName: suiteName, defaults: defaults, store: store, controller: controller)
    }

    func keyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        characters: String,
        windowNumber: Int = 0
    ) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters.lowercased(),
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    func paragraphKind(after event: NSEvent, controller: EditorWindowController) throws -> MarkdownParagraphKind {
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(
            string: "item",
            attributes: controller.theme.baseAttributes(for: .paragraph)
        ))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 4))
        #expect(controller.handleShortcutEvent(event))

        let storage = try #require(controller.editorTextView.textStorage)
        return MarkdownRichTextCodec.paragraphKind(at: NSRange(location: 0, length: storage.length), in: storage)
    }

    func tableCellRange(row: Int, column: Int, in attributedString: NSAttributedString) -> NSRange? {
        guard attributedString.length > 0 else { return nil }
        var matchingRange: NSRange?
        attributedString.enumerateAttribute(
            .qmTableColumn,
            in: NSRange(location: 0, length: attributedString.length),
            options: []
        ) { value, range, stop in
            let storedColumn = (value as? Int) ?? (value as? NSNumber)?.intValue
            let rowValue = attributedString.attribute(.qmTableRow, at: range.location, effectiveRange: nil)
            let storedRow = (rowValue as? Int) ?? (rowValue as? NSNumber)?.intValue
            if storedRow == row, storedColumn == column {
                matchingRange = range
                stop.pointee = true
            }
        }
        return matchingRange
    }
}

extension MarkdownParagraphKind {
    var headingLevel: Int? {
        if case .heading(let level) = self { return level }
        return nil
    }

    var isOrderedList: Bool {
        if case .ordered = self { return true }
        return false
    }

    var isBulletList: Bool {
        if case .bullet = self { return true }
        return false
    }

    var isChecklist: Bool {
        if case .checklist = self { return true }
        return false
    }
}
