import AppKit
import Carbon.HIToolbox
import CoreServices
import ImageIO
@_spi(Testing) import MudsnoteCore
import Testing
@testable import Mudsnote

private extension NSView {
    var allSubviews: [NSView] {
        subviews + subviews.flatMap(\.allSubviews)
    }
}

@MainActor
private final class DisplayInvalidationRecordingClipView: NSClipView {
    private(set) var invalidatedRects: [NSRect] = []

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        invalidatedRects.append(invalidRect)
        super.setNeedsDisplay(invalidRect)
    }
}

private actor LibraryFileSystemChangeRecorder {
    private var changes: Set<LibraryFileSystemChange> = []

    func append(_ newChanges: Set<LibraryFileSystemChange>) {
        changes.formUnion(newChanges)
    }

    func snapshot() -> Set<LibraryFileSystemChange> {
        changes
    }
}

@MainActor
private final class SlashCommandInputSourceSessionRecorder: SlashCommandInputSourceSessioning {
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

private final class DelayedFileModificationDateProbe: @unchecked Sendable {
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

private final class DraftPersistenceRecorder: @unchecked Sendable {
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

private final class MutableBoolFlag: @unchecked Sendable {
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

private final class ThreadObservationRecorder: @unchecked Sendable {
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

private final class BlockingAutosaveRecorder: @unchecked Sendable {
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

    private let theme = MarkdownEditorTheme(
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
    func librarySourceCountIndexAggregatesFoldersTagsAndInboxInOnePass() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Source Count Index", isDirectory: true)
        let notesFolder = root.appendingPathComponent("Notes", isDirectory: true)
        let projectsFolder = root.appendingPathComponent("Projects", isDirectory: true)
        let clientFolder = projectsFolder.appendingPathComponent("Client", isDirectory: true)
        let now = Date()
        let notes = [
            NoteSearchResult(
                url: notesFolder.appendingPathComponent("Inbox.md"),
                title: "Inbox",
                snippet: "",
                modifiedAt: now,
                tags: ["Alpha", "alpha"]
            ),
            NoteSearchResult(
                url: projectsFolder.appendingPathComponent("Plan.md"),
                title: "Plan",
                snippet: "",
                modifiedAt: now,
                tags: ["ALPHA"]
            ),
            NoteSearchResult(
                url: clientFolder.appendingPathComponent("Brief.md"),
                title: "Brief",
                snippet: "",
                modifiedAt: now,
                tags: ["Beta"]
            ),
            NoteSearchResult(
                url: projectsFolder.appendingPathComponent("Inbox Rules.md"),
                title: "Project Inbox Rules",
                snippet: "",
                modifiedAt: now,
                tags: []
            )
        ]
        let index = LibrarySourceCountIndex(
            notes: notes,
            folderPaths: Set([notesFolder.path, projectsFolder.path, clientFolder.path]),
            inboxDirectory: notesFolder.appendingPathComponent("Inbox", isDirectory: true)
        )

        #expect(index.inboxCount == 1)
        #expect(index.count(forFolder: notesFolder) == 1)
        #expect(index.count(forFolder: projectsFolder) == 3)
        #expect(index.count(forFolder: projectsFolder, includingDescendants: false) == 2)
        #expect(index.count(forFolder: clientFolder) == 1)
        #expect(index.count(forTag: "alpha") == 2)
        #expect(index.count(forTag: "BETA") == 1)
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
    func floatingEditorExposesSelectionFormattingToolbar() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "Selected text",
            theme: controller.theme
        ))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 8))

        let titles = controller.editorTextView.selectionMenuProvider?()?.items.map(\.title) ?? []
        #expect(titles.contains("加粗"))
        #expect(titles.contains("待办列表"))
        #expect(titles.contains("编号列表"))
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
        #expect(floatingController.makeSelectionFormattingMenu()?.items.map(\.title) == ["加粗", "编号列表"])
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
        #expect(selectionMenu.items.map(\.title) == ["加粗", "转换为"])
        #expect(selectionMenu.items.last?.submenu?.items.map(\.title) == ["编号列表"])

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
        #expect(contextMenu.items.first?.title == "拷贝")
        #expect(contextMenu.items.last { $0.title == "插入" }?.submenu?.items.map(\.title) == ["链接…"])
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

    @MainActor
    @Test
    func libraryFolderVisibilityCanExcludeSubfolderNotes() throws {
        let suiteName = "mudsnote.folder-visibility-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-folder-visibility-tests-\(UUID().uuidString)", isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Library", isDirectory: true)
        let childDirectory = notesDirectory.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: childDirectory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        #expect(store.libraryIncludesSubfolderNotes)
        store.notesDirectory = notesDirectory
        _ = try store.saveNewNote(title: "Direct", body: "Root note", in: notesDirectory)
        _ = try store.saveNewNote(title: "Nested", body: "Child note", in: childDirectory)

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }
        #expect(controller.selectSourceForLibrary(titled: "Library"))
        #expect(Set(controller.noteListSearchResultsForLibrary().map(\.title)) == ["Direct", "Nested"])

        store.libraryIncludesSubfolderNotes = false
        #expect(!NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        ).libraryIncludesSubfolderNotes)
        controller.refreshFolderNoteVisibilityForLibrary()
        #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["Direct"])
        controller.searchForLibrary(query: "Nested", allNotes: false)
        #expect(controller.noteListSearchResultsForLibrary().isEmpty)

        store.libraryIncludesSubfolderNotes = true
        controller.refreshFolderNoteVisibilityForLibrary()
        #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["Nested"])
        controller.searchForLibrary(query: "", allNotes: false)
        #expect(Set(controller.noteListSearchResultsForLibrary().map(\.title)) == ["Direct", "Nested"])
    }

    @MainActor
    @Test
    func libraryCreatesNotesImmediatelyAndSupportsSlashCommands() throws {
        let suiteName = "mudsnote.library-immediate-slash-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-immediate-slash-tests-\(UUID().uuidString)", isDirectory: true)
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
        _ = try store.saveNewNote(title: "Seed", body: "Body")
        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }
        let contentView = try #require(controller.window?.contentView)
        let suggestionView = try #require(contentView.allSubviews.first {
            $0.identifier?.rawValue == "LibraryEditorSlashSuggestionPopover"
        })
        #expect(suggestionView.superview === contentView)
        #expect(suggestionView.isHidden)

        let previousCount = store.listNotes(limit: 20).count
        controller.createNewNoteForLibrary()
        let createdURL = try #require(controller.selectedMarkdownFileURLForLibrary())
        #expect(FileManager.default.fileExists(atPath: createdURL.path))
        #expect(store.listNotes(limit: 20).count == previousCount + 1)
        #expect(controller.noteListSearchResultsForLibrary().contains { $0.url.standardizedFileURL == createdURL.standardizedFileURL })

        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(markdown: "", theme: controller.theme))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 0))
        controller.editorTextView.insertText("/", replacementRange: controller.editorTextView.selectedRange())
        let titles = controller.editorSlashSuggestionTitlesForLibrary
        #expect(!suggestionView.isHidden)
        let suggestionList = try #require(
            suggestionView.allSubviews.compactMap { $0 as? SuggestionListView }.first
        )
        let libraryCommands = SlashCommand.matching("", includesAI: false)
        #expect(suggestionList.items.map(\.title) == libraryCommands.map(\.title))
        #expect(suggestionList.items.allSatisfy { $0.symbolName == nil })
        let checklistIndex = try #require(titles.firstIndex(of: "待办列表"))
        controller.acceptEditorSlashSuggestionForLibrary(at: checklistIndex)
        #expect(MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme) == "- [ ] ")

        let longPrefix = String(repeating: "a", count: 20_000) + " "
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(
            string: longPrefix,
            attributes: controller.theme.baseAttributes(for: .paragraph)
        ))
        controller.editorTextView.setSelectedRange(NSRange(location: longPrefix.utf16.count, length: 0))
        controller.editorTextView.insertText("/", replacementRange: controller.editorTextView.selectedRange())
        #expect(controller.editorSlashSuggestionInspectionLengthForLibrary <= 128)
        #expect(!controller.editorSlashSuggestionTitlesForLibrary.isEmpty)
    }

    @MainActor
    @Test
    func libraryImportsExternalItemsAndUsesPersistedFolderOrder() throws {
        let suiteName = "mudsnote.library-folder-drag-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-folder-drag-tests-\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        let library = root.appendingPathComponent("Library", isDirectory: true)
        store.notesDirectory = library
        let alpha = try store.createFolder(named: "Alpha", in: library)
        let beta = try store.createFolder(named: "Beta", in: library)
        store.libraryFolderOrderPaths = [beta.path, alpha.path]
        let external = root.appendingPathComponent("External.md")
        try "# External\n\nBody".write(to: external, atomically: true, encoding: .utf8)

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }
        controller.loadSourceFoldersForLibrary()
        let directChildren = controller.sourceFolderURLsForLibrary().filter {
            $0.deletingLastPathComponent().standardizedFileURL == library.standardizedFileURL
        }
        #expect(directChildren.map(\.lastPathComponent) == ["Beta", "Alpha"])

        let imported = try controller.importExternalLibraryItemForTesting(external, to: beta)
        #expect(FileManager.default.fileExists(atPath: external.path))
        #expect(FileManager.default.fileExists(atPath: imported.path))
        #expect(imported.deletingLastPathComponent().standardizedFileURL == beta.standardizedFileURL)

        let moved = try store.moveFolder(at: beta, to: alpha)
        controller.loadSourceFoldersForLibrary()
        #expect(moved.deletingLastPathComponent().standardizedFileURL == alpha.standardizedFileURL)
        #expect(controller.sourceFolderURLsForLibrary().contains { $0.standardizedFileURL == moved.standardizedFileURL })
    }

    @Test
    func libraryNoteListProjectionPreservesPinnedAndDateGroupOrdering() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_014_400)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("List Projection", isDirectory: true)
        let today = NoteSearchResult(
            url: root.appendingPathComponent("Zulu.md"),
            title: "Zulu",
            snippet: "",
            modifiedAt: now
        )
        let pinned = NoteSearchResult(
            url: root.appendingPathComponent("Alpha.md"),
            title: "Alpha",
            snippet: "",
            modifiedAt: calendar.date(byAdding: .day, value: -1, to: now)!
        )
        let earlier = NoteSearchResult(
            url: root.appendingPathComponent("Beta.md"),
            title: "Beta",
            snippet: "",
            modifiedAt: calendar.date(byAdding: .day, value: -3, to: now)!
        )

        let rows = LibraryNoteListProjection.rows(
            for: [earlier, today, pinned],
            sortOrder: .title,
            groupsByDate: true,
            includesPinnedGroup: true,
            pinnedPaths: [pinned.url.standardizedFileURL.path],
            now: now,
            calendar: calendar
        )
        let descriptions = rows.map { row in
            switch row {
            case .group(let title):
                return "group:\(title)"
            case .note(let note):
                return "note:\(note.title)"
            }
        }

        #expect(descriptions == [
            "group:置顶",
            "note:Alpha",
            "group:今天",
            "note:Zulu",
            "group:过去 7 天",
            "note:Beta"
        ])
    }

    @Test
    func libraryGalleryProjectionPreservesListSectionsAndUngroupedNotes() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Gallery Projection", isDirectory: true)
        let alpha = NoteSearchResult(
            url: root.appendingPathComponent("Alpha.md"),
            title: "Alpha",
            snippet: "A",
            modifiedAt: Date(timeIntervalSince1970: 300)
        )
        let beta = NoteSearchResult(
            url: root.appendingPathComponent("Beta.md"),
            title: "Beta",
            snippet: "B",
            modifiedAt: Date(timeIntervalSince1970: 200)
        )
        let gamma = NoteSearchResult(
            url: root.appendingPathComponent("Gamma.md"),
            title: "Gamma",
            snippet: "C",
            modifiedAt: Date(timeIntervalSince1970: 100)
        )

        let grouped = LibraryGalleryProjection.sections(from: [
            .group(title: "Today"),
            .note(alpha),
            .note(beta),
            .group(title: "Previous 7 Days"),
            .note(gamma)
        ])
        #expect(grouped.map(\.title) == ["Today", "Previous 7 Days"])
        #expect(grouped.map { $0.notes.map(\.title) } == [["Alpha", "Beta"], ["Gamma"]])

        let ungrouped = LibraryGalleryProjection.sections(from: [.note(alpha), .note(beta)])
        #expect(ungrouped.count == 1)
        #expect(ungrouped[0].title == nil)
        #expect(ungrouped[0].notes.map(\.title) == ["Alpha", "Beta"])
    }

    @Test
    func libraryGalleryProjectionStaysInteractiveAtSnapshotLimit() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Gallery Projection Performance", isDirectory: true)
        let now = Date()
        var rows: [LibraryNoteListRow] = []
        rows.reserveCapacity(10_200)
        for index in 0..<10_000 {
            if index.isMultiple(of: 50) {
                rows.append(.group(title: "Section \(index / 50)"))
            }
            rows.append(.note(NoteSearchResult(
                url: root.appendingPathComponent("Note-\(index).md"),
                title: "Note \(index)",
                snippet: "Body \(index)",
                modifiedAt: now.addingTimeInterval(TimeInterval(-index))
            )))
        }

        let clock = ContinuousClock()
        var sections: [LibraryGallerySection] = []
        let elapsed = clock.measure {
            sections = LibraryGalleryProjection.sections(from: rows)
        }

        #expect(elapsed < .milliseconds(100))
        #expect(sections.count == 200)
        #expect(sections.reduce(0) { $0 + $1.notes.count } == 10_000)
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
    }

    @MainActor
    @Test
    func libraryImageResizePersistsOutsideMarkdownWithoutRewritingImage() throws {
        let suiteName = "mudsnote.image-resize-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-image-resize-tests-\(UUID().uuidString)", isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let imageURL = notesDirectory
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent("preview.png")
        try FileManager.default.createDirectory(
            at: imageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let pngData = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="))
        try pngData.write(to: imageURL)
        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = notesDirectory
        let markdown = "![Preview](Attachments/preview.png)"
        _ = try store.saveNewNote(title: "Resizable Image", body: markdown)

        var controller: LibraryWindowController? = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        let firstController = try #require(controller)
        let firstImageIndex = try #require((0..<firstController.editorTextView.attributedString().length).first {
            firstController.editorTextView.attributedString().attribute(
                .qmImageFilePath,
                at: $0,
                effectiveRange: nil
            ) != nil
        })
        let initialReference = try #require(
            firstController.editorTextView.imageAttachmentReference(atCharacterIndex: firstImageIndex)
        )
        let resizeMenu = try #require(
            firstController.editorTextView.imageResizeMenu(atCharacterIndex: firstImageIndex)
        )
        #expect(resizeMenu.items.map(\.title) == [
            "适合编辑器",
            "25%",
            "50%",
            "75%",
            "100%",
            "原始大小",
            "",
            "重置自定义大小"
        ])
        firstController.editorTextView.setSelectedRange(NSRange(location: firstImageIndex, length: 0))
        #expect(
            firstController.editorTextView.accessibilityCustomActions()?.map(\.name)
                .contains("图片适合编辑器") == true
        )
        #expect(
            firstController.editorTextView.accessibilityCustomActions()?.map(\.name)
                .contains("重置图片大小") == true
        )
        firstController.showWindow(nil)
        firstController.editorTextView.layoutManager?.ensureLayout(
            for: try #require(firstController.editorTextView.textContainer)
        )
        let imageFrame = try #require(
            firstController.editorTextView.imageAttachmentFrame(atCharacterIndex: firstImageIndex)
        )
        let dragStart = NSPoint(x: imageFrame.maxX, y: imageFrame.midY)
        let dragMiddle = NSPoint(x: dragStart.x + 48, y: dragStart.y)
        let dragEnd = NSPoint(x: dragStart.x + 96, y: dragStart.y)
        let window = try #require(firstController.editorTextView.window)
        let startInWindow = firstController.editorTextView.convert(dragStart, to: nil)
        let middleInWindow = firstController.editorTextView.convert(dragMiddle, to: nil)
        let endInWindow = firstController.editorTextView.convert(dragEnd, to: nil)
        let mouseDown = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: startInWindow,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        let mouseDraggedMiddle = try #require(NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: middleInWindow,
            modifierFlags: [],
            timestamp: 0.05,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 1
        ))
        let mouseDraggedEnd = try #require(NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: endInWindow,
            modifierFlags: [],
            timestamp: 0.1,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 3,
            clickCount: 1,
            pressure: 1
        ))
        let mouseUp = try #require(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: endInWindow,
            modifierFlags: [],
            timestamp: 0.2,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 4,
            clickCount: 1,
            pressure: 0
        ))
        firstController.editorTextView.mouseDown(with: mouseDown)
        #expect(firstController.editorTextView.selectedRange().length == 0)
        firstController.editorTextView.mouseDragged(with: mouseDraggedMiddle)
        let middleReference = try #require(
            firstController.editorTextView.imageAttachmentReference(atCharacterIndex: firstImageIndex)
        )
        #expect(middleReference.displaySize.width > initialReference.displaySize.width)
        #expect(store.libraryImageDisplayWidth(for: imageURL) == nil)
        firstController.editorTextView.mouseDragged(with: mouseDraggedEnd)
        let endReferenceBeforeMouseUp = try #require(
            firstController.editorTextView.imageAttachmentReference(atCharacterIndex: firstImageIndex)
        )
        #expect(endReferenceBeforeMouseUp.displaySize.width > middleReference.displaySize.width)
        #expect(store.libraryImageDisplayWidth(for: imageURL) == nil)
        firstController.editorTextView.mouseUp(with: mouseUp)
        let resizedReference = try #require(
            firstController.editorTextView.imageAttachmentReference(atCharacterIndex: firstImageIndex)
        )
        #expect(resizedReference.displaySize.width > initialReference.displaySize.width)
        #expect(store.libraryImageDisplayWidth(for: imageURL) == Double(resizedReference.displaySize.width))
        #expect(firstController.editorTextView.undoManager?.canUndo == true)
        firstController.editorTextView.undoManager?.undo()
        let undoReference = try #require(
            firstController.editorTextView.imageAttachmentReference(atCharacterIndex: firstImageIndex)
        )
        #expect(undoReference.displaySize == initialReference.displaySize)
        #expect(store.libraryImageDisplayWidth(for: imageURL) == nil)
        #expect(firstController.editorTextView.undoManager?.canRedo == true)
        firstController.editorTextView.undoManager?.redo()
        let redoReference = try #require(
            firstController.editorTextView.imageAttachmentReference(atCharacterIndex: firstImageIndex)
        )
        #expect(redoReference.displaySize == resizedReference.displaySize)
        #expect(store.libraryImageDisplayWidth(for: imageURL) == Double(resizedReference.displaySize.width))
        #expect(MarkdownRichTextCodec.serialize(
            firstController.editorTextView.attributedString(),
            theme: firstController.theme
        ) == "# Resizable Image\n\n\(markdown)")
        #expect(try Data(contentsOf: imageURL) == pngData)
        firstController.close()
        controller = nil

        let reopenedController = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { reopenedController.close() }
        let reopenedImageIndex = try #require((0..<reopenedController.editorTextView.attributedString().length).first {
            reopenedController.editorTextView.attributedString().attribute(
                .qmImageFilePath,
                at: $0,
                effectiveRange: nil
            ) != nil
        })
        let reopenedReference = try #require(
            reopenedController.editorTextView.imageAttachmentReference(atCharacterIndex: reopenedImageIndex)
        )
        #expect(reopenedReference.displaySize == resizedReference.displaySize)
        store.setLibraryImageDisplayWidth(nil, for: imageURL)
        #expect(store.libraryImageDisplayWidth(for: imageURL) == nil)
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
    func richCodecRendersInlineTagsInBlueWithoutChangingMarkdown() {
        let rendered = MarkdownRichTextCodec.renderLine("hello #alpha world", theme: theme)
        let visible = rendered.string as NSString
        let tagRange = visible.range(of: "#alpha")
        let color = rendered.attribute(.foregroundColor, at: tagRange.location, effectiveRange: nil) as? NSColor
        let isTag = rendered.attribute(.qmTag, at: tagRange.location, effectiveRange: nil) as? Bool

        #expect(tagRange.location != NSNotFound)
        #expect(isTag == true)
        #expect(color == NSColor.systemBlue.withAlphaComponent(0.96))
        #expect(MarkdownRichTextCodec.serialize(rendered, theme: theme) == "hello #alpha world")
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
        #expect(conciseMenu.items.map(\.title) == ["撤销", "", "翻译", "", "剪切", "拷贝", "粘贴"])
        #expect(conciseMenu.items.first?.keyEquivalent == "z")
        #expect(conciseMenu.items.first?.keyEquivalentModifierMask == [.command])
        #expect(conciseMenu.items.first?.image != nil)

        textView.sealContextMenu(conciseMenu)
        conciseMenu.addItem(NSMenuItem(title: "自动填充", action: nil, keyEquivalent: ""))
        conciseMenu.addItem(NSMenuItem(title: "服务", action: nil, keyEquivalent: ""))
        #expect(conciseMenu.items.map(\.title) == ["撤销", "", "翻译", "", "剪切", "拷贝", "粘贴"])
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

    @Test
    func quickCaptureDocumentStateDerivesTitleWithoutRemovingBody() {
        let state = QuickCaptureDocumentState(
            title: "",
            bodyMarkdown: "\n\n  这是第一句。第二句仍在正文\n- [ ] Finish report\n#ops\n"
        )

        #expect(state.normalizedTitle == "这是第一句。")
        #expect(state.normalizedBody == "这是第一句。第二句仍在正文\n- [ ] Finish report\n#ops")
        #expect(state.document.title == "这是第一句。")
        #expect(state.document.body == "这是第一句。第二句仍在正文\n- [ ] Finish report\n#ops")
        #expect(state.document.tags == ["ops"])
        #expect(state.hasMeaningfulContent == true)
    }

    @Test
    func quickCaptureRecognizesHierarchicalInlineTags() {
        #expect(
            QuickCaptureDocumentState.extractedInlineTags(
                from: "Body #area/topic #中文/层级 #trailing/"
            ) == ["area/topic", "中文/层级", "trailing"]
        )

        let rendered = MarkdownRichTextCodec.renderLine("Body #area/topic", theme: theme)
        #expect(MarkdownRichTextCodec.serialize(rendered, theme: theme) == "Body #area/topic")
    }

    @Test
    func quickCaptureTitleDerivationHandlesMarkdownPunctuationAndLength() {
        #expect(QuickCaptureDocumentState.derivedTitle(from: "  \n# Plan v2? Keep this") == "Plan v2?")
        #expect(QuickCaptureDocumentState.derivedTitle(from: "\n「中文标题！」后续") == "「中文标题！」")
        #expect(QuickCaptureDocumentState.derivedTitle(from: "\n\n") == "")

        let longSentence = String(repeating: "长", count: 200)
        #expect(QuickCaptureDocumentState.derivedTitle(from: longSentence).count == 80)
    }

    @Test
    func quickCaptureLegacyTitleAndBodyMergeWithoutLossOrDuplication() {
        #expect(
            QuickCaptureDocumentState.unifiedMarkdown(
                legacyTitle: "Legacy title",
                bodyMarkdown: "Body line\nSecond line"
            ) == "Legacy title\n\nBody line\nSecond line"
        )
        #expect(
            QuickCaptureDocumentState.unifiedMarkdown(
                legacyTitle: "Already present.",
                bodyMarkdown: "Already present. More text\nSecond line"
            ) == "Already present. More text\nSecond line"
        )
        #expect(
            QuickCaptureDocumentState.unifiedMarkdown(
                legacyTitle: "",
                bodyMarkdown: "Body only"
            ) == "Body only"
        )
    }

    @MainActor
    @Test
    func quickCaptureTagSuggestionsLoadWithoutBlockingEditorInput() async throws {
        let harness = try makeEditorControllerHarness(
            draftID: "quick-capture",
            showsSaveButton: true,
            configureStore: { store in
                store.configurePreferredDirectories([store.notesDirectory], defaultDirectory: store.notesDirectory)
            }
        )
        defer { harness.tearDown() }
        _ = try harness.store.saveNewNote(title: "Tagged", body: "Saved note", tags: ["alpha"])

        let controller = harness.controller
        controller.editorTextView.string = "#al"
        controller.editorTextView.setSelectedRange(NSRange(location: 3, length: 0))
        controller.updateInlineSuggestions()

        #expect(controller.knownTagsForSuggestions == nil || controller.knownTagsForSuggestions?.contains("alpha") == true)
        try await Task.sleep(for: .milliseconds(100))

        #expect(controller.knownTagsForSuggestions?.contains("alpha") == true)
        guard case .tags(let query, _, let items) = controller.inlineSuggestionContext else {
            Issue.record("Expected tag suggestions after the background tag index load")
            return
        }
        #expect(query == "al")
        #expect(items == ["alpha"])
    }

    @MainActor
    @Test
    func quickEntryPanelRoutesCommandCommaToPreferences() throws {
        let panel = QuickEntryPanel(size: NSSize(width: 320, height: 260))
        var didRequestPreferences = false
        panel.onCommandComma = {
            didRequestPreferences = true
        }
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: ",",
            charactersIgnoringModifiers: ",",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_Comma)
        ))

        panel.sendEvent(event)

        #expect(didRequestPreferences)
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
    func floatingNoteDoesNotSaveOnCommandSAndUsesConfiguredSaveShortcut() throws {
        var savedURLs: [URL] = []
        let harness = try makeEditorControllerHarness(
            draftID: "floating-note",
            showsSaveButton: false,
            saveShortcut: HotKeySpec.parse("command+return"),
            onSave: { savedURLs.append($0) }
        )
        defer { harness.tearDown() }
        let controller = harness.controller
        let panel = try #require(controller.window as? QuickEntryPanel)
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(
            string: "Floating title\nbody",
            attributes: controller.theme.baseAttributes(for: .paragraph)
        ))

        panel.sendEvent(try keyEvent(keyCode: UInt16(kVK_ANSI_S), modifiers: [.command], characters: "s", windowNumber: panel.windowNumber))
        #expect(savedURLs.isEmpty)

        panel.sendEvent(try keyEvent(keyCode: UInt16(kVK_Return), modifiers: [.command], characters: "\r", windowNumber: panel.windowNumber))
        #expect(savedURLs.count == 1)
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

    @Test
    func libraryDefaultFrameMigrationShrinksOnlyPreviousDefaults() {
        let previous = StoredWindowFrame(x: 100, y: 80, width: 1080, height: 720)
        let migrated = LibraryNotesLayout.migratedDefaultWindowFrame(previous)
        #expect(migrated == StoredWindowFrame(x: 179.5, y: 133.5, width: 921, height: 613))

        let currentDefault = StoredWindowFrame(x: 100, y: 80, width: 940, height: 630)
        #expect(
            LibraryNotesLayout.migratedDefaultWindowFrame(currentDefault)
                == StoredWindowFrame(x: 109.5, y: 88.5, width: 921, height: 613)
        )

        let customized = StoredWindowFrame(x: 40, y: 30, width: 1180, height: 760)
        #expect(LibraryNotesLayout.migratedDefaultWindowFrame(customized) == customized)
        #expect(LibraryNotesLayout.migratedDefaultWindowFrame(nil) == nil)
    }

    @MainActor
    @Test
    func floatingToolbarButtonAppliesInlineTypingFormat() throws {
        let harness = try makeEditorControllerHarness(draftID: "standard-editor", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 0))
        let boldButton = try #require(controller.toolbarButtonsByAction[.bold])

        controller.toolbarButtonPressed(boldButton)

        let font = try #require(controller.editorTextView.typingAttributes[.font] as? NSFont)
        #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        #expect(controller.toolbarButtonsByAction[.bold]?.isActive == true)
    }

    @MainActor
    @Test
    func floatingToolbarMouseDownImmediatelyAppliesFormatting() throws {
        let harness = try makeEditorControllerHarness(draftID: "standard-editor", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let boldButton = try #require(controller.toolbarButtonsByAction[.bold])
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

        let font = try #require(controller.editorTextView.typingAttributes[.font] as? NSFont)
        #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
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
    func libraryWindowUsesNotesLikeSplitAndLoadsFirstNote() throws {
        let suiteName = "mudsnote.library-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-tests-\(UUID().uuidString)", isDirectory: true)
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
        let noteURL = try store.saveNewNote(title: "Library Seed", body: "Body line", tags: ["library"])
        let noteModifiedAt = try #require((try? FileManager.default.attributesOfItem(atPath: noteURL.path)[.modificationDate]) as? Date)
        let noteDateFormatter = DateFormatter()
        noteDateFormatter.locale = Locale(identifier: "zh_Hans_CN")
        noteDateFormatter.dateFormat = "yyyy年M月d日 HH:mm"

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let window = try #require(controller.window)
        #expect(window.title == "Mudsnote 笔记")
        #expect(window.titleVisibility == .hidden)
        #expect(window.titlebarAppearsTransparent)
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.contentViewController is NSSplitViewController)
        #expect(window.toolbarStyle == .unified)
        #expect(window.styleMask.contains(.resizable))
        let titlebarSeparators = window.contentView?.allSubviews.compactMap { $0 as? NSBox }.filter {
            $0.identifier?.rawValue.hasSuffix("TitlebarSeparator") == true
        } ?? []
        #expect(titlebarSeparators.count == 2)
        #expect(titlebarSeparators.allSatisfy { $0.boxType == .separator })
        #expect(window.minSize.width == LibraryNotesLayout.minimumWindowSize.width)
        #expect(LibraryNotesLayout.minimumWindowSize.width == 896)
        #expect(window.minSize.height >= LibraryNotesLayout.minimumWindowSize.height)
        #expect(!controller.tableView.floatsGroupRows)
        #expect(LibraryNotesLayout.storedLayoutScaleVersion == 8)
        #expect(LibraryNotesLayout.initialWindowSize == NSSize(width: 921, height: 613))
        #expect(LibraryNotesLayout.presentedWindowSize == NSSize(width: 921, height: 613))
        #expect(LibraryNotesLayout.sourceColumnWidth == 200)
        #expect(LibraryNotesLayout.noteColumnWidth == 200)
        #expect(LibraryNotesLayout.sourceColumnWidth == LibraryNotesLayout.noteColumnWidth)
        #expect(LibraryNotesLayout.noteTableInitialWidth == 174)
        #expect(LibraryNotesLayout.noteTableMinimumWidth == 174)
        #expect(LibraryNotesLayout.noteTableInitialWidth + LibraryNotesLayout.noteListLeadingInset + LibraryNotesLayout.noteListTrailingInset == LibraryNotesLayout.noteColumnWidth)
        #expect(LibraryNotesLayout.toolbarSearchWidth == 160)
        #expect(LibraryNotesLayout.toolbarSearchWrapperWidth == LibraryNotesLayout.toolbarSearchWidth)
        #expect(LibraryNotesLayout.presentedWindowSize(in: NSRect(x: 0, y: 0, width: 2200, height: 1200)) == LibraryNotesLayout.presentedWindowSize)
        let clampedSize = LibraryNotesLayout.presentedWindowSize(in: NSRect(x: 0, y: 0, width: 1180, height: 720))
        #expect(clampedSize == LibraryNotesLayout.presentedWindowSize)
        #expect(clampedSize.width >= LibraryNotesLayout.minimumWindowSize.width)
        #expect(clampedSize.height >= LibraryNotesLayout.minimumWindowSize.height)
        #expect(LibraryNotesLayout.presentedWindowSize(
            in: NSRect(x: 0, y: 0, width: 1180, height: 720),
            usesCanonicalSize: true
        ) == LibraryNotesLayout.presentedWindowSize)
        #expect(LibraryNotesLayout.presentedWindowSize(
            in: NSRect(x: 0, y: 0, width: 1180, height: 720),
            usesCanonicalSize: false
        ) == clampedSize)
        #expect(window.toolbar?.displayMode == .iconOnly)
        let toolbarItemIDs = Set((window.toolbar?.items ?? []).map(\.itemIdentifier.rawValue))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.add-folder"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.toggle-sidebar"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.source-separator"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.note-list-title"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.note-list-actions"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.new-note"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.note-separator"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.editor-tools"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.format"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.checklist"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.table"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.link"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.attachment"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.file-actions"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.export"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.more"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.search"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.save"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.move"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.delete"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.restore"))
        let toolbarItemOrder = try #require(window.toolbar).items.map(\.itemIdentifier.rawValue)
        let noteSeparatorIndex = try #require(toolbarItemOrder.firstIndex(
            of: "mudsnote.library.toolbar.note-separator"
        ))
        let newNoteIndex = try #require(toolbarItemOrder.firstIndex(
            of: "mudsnote.library.toolbar.new-note"
        ))
        #expect(noteSeparatorIndex < newNoteIndex)
        let defaultToolbarItems = controller.toolbarDefaultItemIdentifiers(try #require(window.toolbar))
        let defaultToolbarItemValues = defaultToolbarItems.map(\.rawValue)
        #expect(defaultToolbarItemValues.first == "mudsnote.library.toolbar.add-folder")
        let defaultNewNoteIndex = try #require(defaultToolbarItemValues.firstIndex(
            of: "mudsnote.library.toolbar.new-note"
        ))
        #expect(defaultToolbarItems[defaultNewNoteIndex + 1] == .space)
        #expect(defaultToolbarItemValues[defaultNewNoteIndex + 2] == "mudsnote.library.toolbar.editor-tools")
        #expect(defaultToolbarItems[defaultNewNoteIndex + 3] == .flexibleSpace)
        #expect(defaultToolbarItemValues[defaultNewNoteIndex + 4] == "mudsnote.library.toolbar.search")
        for toolbarButtonID in [
            "mudsnote.library.toolbar.add-folder",
            "mudsnote.library.toolbar.toggle-sidebar"
        ] {
            let item = try #require((window.toolbar?.items ?? []).first {
                $0.itemIdentifier.rawValue == toolbarButtonID
            })
            if toolbarButtonID == "mudsnote.library.toolbar.toggle-sidebar" {
                #expect(item.isBordered)
                #expect(item.view is NSButton)
            } else {
                #expect(!item.isBordered)
                let wrapper = try #require(item.view)
                #expect(wrapper.identifier?.rawValue == "LibraryToolbarAddFolderWrapper")
                #expect(wrapper.frame.width == LibraryNotesLayout.toolbarAddFolderWrapperWidth)
                #expect(LibraryNotesLayout.toolbarAddFolderWrapperWidth == 63)
            }
            #expect(item.image != nil)
            #expect(item.toolTip == item.label)
        }
        #expect(controller.makeExportMenuForLibrary().items.map(\.title) == ["复制 Markdown 内容", "导出 Markdown..."])
        let newNoteToolbarItem = try #require((window.toolbar?.items ?? []).first {
            $0.itemIdentifier.rawValue == "mudsnote.library.toolbar.new-note"
        })
        let newNoteToolbarWrapper = try #require(newNoteToolbarItem.view)
        #expect(newNoteToolbarWrapper.identifier?.rawValue == "LibraryToolbarNewNoteWrapper")
        #expect(newNoteToolbarWrapper.frame.width == LibraryNotesLayout.toolbarNewNoteWrapperWidth)
        #expect(LibraryNotesLayout.toolbarNewNoteWrapperWidth == 44)
        let newNoteToolbarButton = try #require(newNoteToolbarWrapper.allSubviews.compactMap { $0 as? NSButton }.first)
        #expect(!newNoteToolbarItem.isBordered)
        #expect(newNoteToolbarButton.target === controller)
        #expect(newNoteToolbarButton.action != nil)
        #expect(newNoteToolbarButton.identifier?.rawValue == "mudsnote.library.toolbar.new-note")
        #expect(newNoteToolbarButton.isBordered)
        #expect(newNoteToolbarButton.bezelStyle == .glass)
        #expect(newNoteToolbarButton.imageScaling == .scaleNone)
        #expect(newNoteToolbarButton.image?.accessibilityDescription == "新建笔记")
        #expect(newNoteToolbarButton.toolTip == "新建笔记")
        #expect(newNoteToolbarButton.constraints.contains {
            $0.firstAttribute == .width && $0.constant == LibraryNotesLayout.toolbarCircularButtonSize
        })
        #expect(newNoteToolbarButton.constraints.contains {
            $0.firstAttribute == .height && $0.constant == LibraryNotesLayout.toolbarCircularButtonSize
        })
        #expect(LibraryNotesLayout.toolbarCircularButtonSize == 30)
        #expect(LibraryNotesLayout.toolbarCircularButtonSymbolPointSize == 12)
        #expect(LibraryNotesLayout.toolbarSourceActionSymbolPointSize == 13)
        #expect(LibraryNotesLayout.toolbarNewNoteSymbolPointSize == 13)

        let initialListMenu = controller.makeNoteListActionsMenuForLibrary()
        let initialGroupingItem = try #require(initialListMenu.items.first { $0.title == "按日期分组" })
        let initialSortMenu = try #require(initialListMenu.items.first { $0.title == "排序方式" }?.submenu)
        #expect(initialListMenu.items.map(\.title) == ["排序方式", "按日期分组"])
        #expect(initialSortMenu.items.map(\.title) == ["编辑日期", "创建日期", "标题"])
        #expect(initialGroupingItem.state == .on)
        #expect(initialSortMenu.items.first { $0.title == "编辑日期" }?.state == .on)
        #expect(initialSortMenu.items.first { $0.title == "创建日期" }?.state == .off)
        #expect(initialSortMenu.items.first { $0.title == "标题" }?.state == .off)
        #expect(LibraryNoteSortOrder.dateEdited.rawValue == 0)
        #expect(LibraryNoteSortOrder.title.rawValue == 1)
        #expect(LibraryNoteSortOrder.dateCreated.rawValue == 2)
        #expect(controller.noteListSortOrder == .dateEdited)
        #expect(controller.groupsNoteListByDate)
        #expect(controller.numberOfRows(in: controller.tableView) == 2)

        func listedNoteTitles() -> [String] {
            (0..<controller.numberOfRows(in: controller.tableView)).compactMap { row in
                (controller.tableView(controller.tableView, viewFor: nil, row: row) as? LibraryNoteCellView)?
                    .titleLabel.stringValue
            }
        }

        #expect(listedNoteTitles() == ["Library Seed"])
        let titleSortItem = try #require(initialSortMenu.items.first { $0.title == "标题" })
        #expect(NSApp.sendAction(try #require(titleSortItem.action), to: titleSortItem.target, from: titleSortItem))
        #expect(controller.noteListSortOrder == .title)
        #expect(listedNoteTitles() == ["Library Seed"])
        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL.path == noteURL.standardizedFileURL.path)

        #expect(NSApp.sendAction(try #require(initialGroupingItem.action), to: initialGroupingItem.target, from: initialGroupingItem))
        #expect(!controller.groupsNoteListByDate)
        #expect(controller.numberOfRows(in: controller.tableView) == 1)
        #expect(listedNoteTitles() == ["Library Seed"])
        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL.path == noteURL.standardizedFileURL.path)

        let updatedListMenu = controller.makeNoteListActionsMenuForLibrary()
        #expect(updatedListMenu.items.first { $0.title == "按日期分组" }?.state == .off)
        #expect(updatedListMenu.items.first { $0.title == "排序方式" }?.submenu?.items.first {
            $0.title == "标题"
        }?.state == .on)
        let updatedGroupingItem = try #require(updatedListMenu.items.first { $0.title == "按日期分组" })
        let dateSortItem = try #require(updatedListMenu.items.first { $0.title == "排序方式" }?.submenu?.items.first {
            $0.title == "编辑日期"
        })
        #expect(NSApp.sendAction(try #require(updatedGroupingItem.action), to: updatedGroupingItem.target, from: updatedGroupingItem))
        #expect(NSApp.sendAction(try #require(dateSortItem.action), to: dateSortItem.target, from: dateSortItem))
        #expect(controller.groupsNoteListByDate)
        #expect(controller.noteListSortOrder == .dateEdited)
        let toolbarSearchFields = (window.toolbar?.items ?? []).flatMap { item in
            item.view?.allSubviews.compactMap { $0 as? NSSearchField } ?? []
        }
        let toolbarSearchField = try #require(toolbarSearchFields.first)
        #expect(toolbarSearchField.identifier?.rawValue == "LibraryToolbarSearchField")
        #expect(toolbarSearchField === controller.searchField)
        #expect(toolbarSearchField.frame.width == LibraryNotesLayout.toolbarSearchWidth)
        #expect(toolbarSearchField.frame.height == LibraryNotesLayout.toolbarSearchHeight)
        #expect(toolbarSearchField.font?.pointSize == 14)
        #expect(toolbarSearchField.placeholderString == "搜索")
        #expect(toolbarSearchField.toolTip == "搜索笔记")
        #expect(toolbarSearchField.accessibilityLabel() == "搜索笔记")
        #expect(LibraryNotesLayout.toolbarSymbolPointSize == 19)
        let toolbarSearchWrapper = try #require(toolbarSearchField.superview)
        #expect(toolbarSearchWrapper.frame.width == LibraryNotesLayout.toolbarSearchWrapperWidth)
        #expect(toolbarSearchWrapper.frame.height >= LibraryNotesLayout.toolbarSearchWrapperHeight)
        #expect(abs(toolbarSearchField.frame.midX - toolbarSearchWrapper.bounds.midX) < 0.5)
        let visibleToolbarItemIDs = Set((window.toolbar?.visibleItems ?? []).map(\.itemIdentifier.rawValue))
        #expect(visibleToolbarItemIDs.contains("mudsnote.library.toolbar.new-note"))
        #expect(visibleToolbarItemIDs.contains("mudsnote.library.toolbar.editor-tools"))
        #expect(visibleToolbarItemIDs.contains("mudsnote.library.toolbar.search"))
        let noteListTitleToolbarItem = try #require((window.toolbar?.items ?? []).first {
            $0.itemIdentifier.rawValue == "mudsnote.library.toolbar.note-list-title"
        })
        #expect(!noteListTitleToolbarItem.isBordered)
        let noteListTitleToolbarView = try #require(noteListTitleToolbarItem.view)
        #expect(noteListTitleToolbarView.identifier?.rawValue == "LibraryToolbarNoteListTitle")
        #expect(noteListTitleToolbarView.frame.width == LibraryNotesLayout.toolbarNoteListTitleWidth)
        #expect(noteListTitleToolbarView.frame.height == LibraryNotesLayout.toolbarNoteListTitleHeight)
        #expect(LibraryNotesLayout.toolbarNoteListTitleWidth == 160)
        let noteListHeaderStack = try #require(noteListTitleToolbarView.allSubviews.compactMap { $0 as? NSStackView }.first {
            $0.identifier?.rawValue == "LibraryToolbarNoteListHeaderStack"
        })
        let noteListTitleLeadingConstraint = try #require(noteListHeaderStack.superview?.constraints.first {
            $0.firstItem === noteListHeaderStack && $0.firstAttribute == .leading
        })
        #expect(noteListTitleLeadingConstraint.constant == LibraryNotesLayout.toolbarExpandedTitleLeadingOffset)
        #expect(LibraryNotesLayout.toolbarExpandedTitleLeadingOffset == 12)
        #expect(noteListHeaderStack.arrangedSubviews.contains(controller.searchScopeControl))
        #expect(controller.searchScopeControl.isHidden)
        #expect(controller.searchScopeControl.accessibilityLabel() == "搜索范围")
        noteListTitleToolbarView.layoutSubtreeIfNeeded()
        #expect(controller.noteListTitleLabel.frame.width + 1 >= controller.noteListTitleLabel.intrinsicContentSize.width)
        let editorToolsItem = try #require((window.toolbar?.items ?? []).first {
            $0.itemIdentifier.rawValue == "mudsnote.library.toolbar.editor-tools"
        })
        #expect(!editorToolsItem.isBordered)
        let editorToolsSlot = try #require(editorToolsItem.view)
        #expect(editorToolsSlot.identifier?.rawValue == "LibraryToolbarEditorToolsSlot")
        #expect(editorToolsSlot.frame.width == LibraryNotesLayout.toolbarEditorToolsSlotWidth)
        #expect(LibraryNotesLayout.toolbarEditorToolsSlotWidth == 162)
        let editorToolsGlass = try #require(editorToolsSlot.allSubviews.compactMap { $0 as? NSGlassEffectView }.first)
        #expect(editorToolsGlass.frame.width == LibraryNotesLayout.toolbarEditorToolsWidth)
        #expect(editorToolsGlass.frame.height == LibraryNotesLayout.toolbarEditorToolsHeight)
        #expect(editorToolsGlass.cornerRadius == LibraryNotesLayout.toolbarEditorToolsHeight / 2)
        #expect(editorToolsGlass.style == .regular)
        let editorToolButtons = editorToolsGlass.allSubviews.compactMap { $0 as? NSButton }
        #expect(Set(editorToolButtons.compactMap { $0.identifier?.rawValue }) == [
            "mudsnote.library.toolbar.format",
            "mudsnote.library.toolbar.checklist",
            "mudsnote.library.toolbar.table",
            "mudsnote.library.toolbar.link",
            "mudsnote.library.toolbar.source-mode"
        ])
        #expect(Set(editorToolButtons.compactMap(\.toolTip)) == Set(["格式", "待办列表", "插入表格", "插入链接", "显示 Markdown 源码"]))
        #expect(editorToolButtons.allSatisfy { $0.bezelStyle == .toolbar })
        #expect(editorToolButtons.allSatisfy { $0.isBordered })
        #expect(editorToolButtons.allSatisfy { $0.showsBorderOnlyWhileMouseInside })
        let formatButton = try #require(editorToolButtons.first {
            $0.identifier?.rawValue == "mudsnote.library.toolbar.format"
        })
        #expect(formatButton.title == "Aa")
        #expect(formatButton.image == nil)
        #expect(formatButton.font?.pointSize == LibraryNotesLayout.toolbarEditorFormatFontSize)
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
        let focusedFormatColor = try #require(formatButton.attributedTitle.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor)
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: window))
        let unfocusedFormatColor = try #require(formatButton.attributedTitle.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor)
        #expect(unfocusedFormatColor.alphaComponent < focusedFormatColor.alphaComponent)
        #expect(LibraryNotesLayout.toolbarEditorFormatFontSize == 17)
        #expect(LibraryNotesLayout.toolbarEditorToolSymbolPointSize == 13)
        let splitView = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSSplitView }.first)
        #expect(splitView.arrangedSubviews.count == 3)
        let sourceTrackingSeparator = try #require((window.toolbar?.items ?? []).first {
            $0.itemIdentifier.rawValue == "mudsnote.library.toolbar.source-separator"
        } as? NSTrackingSeparatorToolbarItem)
        let noteTrackingSeparator = try #require((window.toolbar?.items ?? []).first {
            $0.itemIdentifier.rawValue == "mudsnote.library.toolbar.note-separator"
        } as? NSTrackingSeparatorToolbarItem)
        #expect(sourceTrackingSeparator.splitView === splitView)
        #expect(sourceTrackingSeparator.dividerIndex == 0)
        #expect(noteTrackingSeparator.splitView === splitView)
        #expect(noteTrackingSeparator.dividerIndex == 1)
        let sourceList = splitView.arrangedSubviews[0]
        let noteList = splitView.arrangedSubviews[1]
        let sourceSurface = try #require(sourceList.allSubviews.compactMap { $0 as? NSVisualEffectView }.first {
            $0.identifier?.rawValue == "LibrarySourceSurface"
        })
        #expect(sourceSurface.identifier?.rawValue == "LibrarySourceSurface")
        #expect(sourceSurface.accessibilityLabel() == "资料库")
        #expect(controller.tableView.accessibilityLabel() == "笔记列表")
        #expect(sourceSurface.material == .sidebar)
        #expect(sourceSurface.blendingMode == .withinWindow)
        #expect(sourceSurface.layer?.cornerRadius == LibraryNotesLayout.sourceSurfaceCornerRadius)
        #expect(sourceSurface.layer?.borderWidth == 0)
        let sourceDarkeningTint = try #require(sourceSurface.allSubviews.first {
            $0.identifier?.rawValue == "LibrarySourceDarkeningTint"
        })
        #expect(sourceDarkeningTint.layer?.backgroundColor?.alpha == LibraryNotesLayout.sourceSurfaceDarkeningAlpha)
        #expect(LibraryNotesLayout.sourceSurfaceDarkeningAlpha == 0.30)
        #expect(LibraryNotesLayout.sourceCollapseAnimationDuration == 0.22)
        #expect(sourceList.frame.width >= LibraryNotesLayout.sourceColumnMinimumWidth)
        #expect(noteList.frame.width >= LibraryNotesLayout.noteColumnMinimumWidth)
        #expect(LibraryNotesLayout.sourceColumnMinimumWidth == 200)
        #expect(LibraryNotesLayout.sourceColumnMaximumWidth == 320)
        #expect(LibraryNotesLayout.noteColumnMinimumWidth == 200)
        #expect(LibraryNotesLayout.noteColumnMaximumWidth == 320)
        #expect(LibraryNotesLayout.editorColumnMinimumWidth == 480)
        let toggleSourceItem = try #require((window.toolbar?.items ?? []).first {
            $0.itemIdentifier.rawValue == "mudsnote.library.toolbar.toggle-sidebar"
        })
        let addFolderItem = try #require((window.toolbar?.items ?? []).first {
            $0.itemIdentifier.rawValue == "mudsnote.library.toolbar.add-folder"
        })
        let sourceTrackingSeparatorItem = try #require((window.toolbar?.items ?? []).first {
            $0.itemIdentifier.rawValue == "mudsnote.library.toolbar.source-separator"
        })
        #expect(controller.isSourceListVisibleForLibrary)
        #expect(!addFolderItem.isHidden)
        #expect(!sourceTrackingSeparatorItem.isHidden)
        #expect(toggleSourceItem.isBordered)
        let expandedToggleButton = try #require(toggleSourceItem.view as? NSButton)
        let addFolderButton = try #require(addFolderItem.view?.allSubviews.compactMap {
            $0 as? NSButton
        }.first)
        #expect(expandedToggleButton.image != nil)
        #expect(addFolderButton.image != nil)
        #expect(addFolderButton.image?.size == NSSize(width: 20, height: 15))
        #expect(expandedToggleButton.image?.size.height == 14)
        #expect((18...19).contains(expandedToggleButton.image?.size.width ?? 0))
        #expect(toggleSourceItem.label == "隐藏资料库")
        #expect(toggleSourceItem.toolTip == "隐藏资料库")
        expandedToggleButton.performClick(nil)
        #expect(!controller.isSourceListVisibleForLibrary)
        #expect(sourceList.isHidden)
        #expect(addFolderItem.isHidden)
        #expect(sourceTrackingSeparatorItem.isHidden)
        #expect(!toggleSourceItem.isBordered)
        let collapsedToggleWrapper = try #require(toggleSourceItem.view)
        #expect(collapsedToggleWrapper.identifier?.rawValue == "LibraryToolbarCollapsedSidebarWrapper")
        #expect(collapsedToggleWrapper.frame.width == LibraryNotesLayout.toolbarCollapsedSidebarWrapperWidth)
        #expect(LibraryNotesLayout.toolbarCollapsedSidebarWrapperWidth == 34)
        let collapsedToggleButton = try #require(collapsedToggleWrapper.allSubviews.compactMap {
            $0 as? NSButton
        }.first)
        #expect(collapsedToggleButton.constraints.contains {
            $0.firstAttribute == .width && $0.constant == LibraryNotesLayout.toolbarCircularButtonSize
        })
        #expect(collapsedToggleButton.constraints.contains {
            $0.firstAttribute == .height && $0.constant == LibraryNotesLayout.toolbarCircularButtonSize
        })
        #expect(collapsedToggleButton.bezelStyle == .glass)
        #expect(collapsedToggleButton.isBordered)
        #expect(collapsedToggleButton.imageScaling == .scaleNone)
        #expect(toggleSourceItem.label == "显示资料库")
        #expect(toggleSourceItem.toolTip == "显示资料库")
        let noteListTitleItem = try #require((window.toolbar?.items ?? []).first {
            $0.itemIdentifier.rawValue == "mudsnote.library.toolbar.note-list-title"
        })
        let collapsedTitleStack = try #require(noteListTitleItem.view?.allSubviews.compactMap { $0 as? NSStackView }.first {
            $0.identifier?.rawValue == "LibraryToolbarNoteListHeaderStack"
        })
        let collapsedTitleLeadingConstraint = try #require(collapsedTitleStack.superview?.constraints.first {
            $0.firstItem === collapsedTitleStack && $0.firstAttribute == .leading
        })
        #expect(collapsedTitleLeadingConstraint.constant == LibraryNotesLayout.toolbarCollapsedTitleLeadingOffset)
        #expect(LibraryNotesLayout.toolbarCollapsedTitleLeadingOffset == -11.5)
        window.contentView?.layoutSubtreeIfNeeded()
        let collapsedToggleFrame = collapsedToggleWrapper.convert(collapsedToggleWrapper.bounds, to: nil)
        let collapsedTitleFrame = collapsedTitleStack.convert(collapsedTitleStack.bounds, to: nil)
        #expect(collapsedTitleFrame.minX >= collapsedToggleFrame.maxX)
        collapsedToggleButton.performClick(nil)
        #expect(controller.isSourceListVisibleForLibrary)
        #expect(!sourceList.isHidden)
        #expect(!addFolderItem.isHidden)
        #expect(!sourceTrackingSeparatorItem.isHidden)
        #expect(toggleSourceItem.isBordered)
        #expect(toggleSourceItem.view is NSButton)
        #expect(toggleSourceItem.label == "隐藏资料库")
        #expect(toggleSourceItem.toolTip == "隐藏资料库")
        #expect(collapsedTitleLeadingConstraint.constant == LibraryNotesLayout.toolbarExpandedTitleLeadingOffset)
        let noteListStack = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSStackView }.first {
            $0.identifier?.rawValue == "LibraryNoteListStack"
        })
        #expect(noteListStack.edgeInsets.top == LibraryNotesLayout.noteListTopInset)
        #expect(LibraryNotesLayout.noteListTopInset == 0)
        #expect(noteListStack.edgeInsets.left == LibraryNotesLayout.noteListLeadingInset)
        #expect(noteListStack.edgeInsets.bottom == LibraryNotesLayout.noteListBottomInset)
        #expect(noteListStack.edgeInsets.right == LibraryNotesLayout.noteListTrailingInset)
        let noteListPane = try #require(noteListStack.superview)
        #expect(noteListPane.constraints.contains {
            $0.firstItem === noteListStack
                && $0.firstAttribute == .top
                && $0.secondItem === noteListPane.safeAreaLayoutGuide
                && $0.secondAttribute == .top
                && $0.constant == LibraryNotesLayout.noteListStackTopOffset
        })
        #expect(LibraryNotesLayout.noteListStackTopOffset == -1)
        let libraryGroup = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.first {
            $0.identifier?.rawValue == "LibrarySourceGroup-iCloud"
        })
        #expect(libraryGroup.stringValue == "iCloud")
        #expect(libraryGroup.font?.pointSize == LibraryNotesLayout.sourceGroupFontSize)
        #expect(LibraryNotesLayout.sourceGroupFontSize == 12)
        #expect(LibraryNotesLayout.sourceRowHeight == 32)
        #expect(LibraryNotesLayout.sourceListTopInset == 12)
        #expect(LibraryNotesLayout.sourceListLeadingInset == 14)
        #expect(LibraryNotesLayout.sourceListBottomInset == 14)
        #expect(LibraryNotesLayout.sourceListTrailingInset == 6)
        #expect(LibraryNotesLayout.sourceSymbolPointSize == 15)
        #expect(LibraryNotesLayout.sourceRowCornerRadius == 8)
        #expect(LibraryNotesLayout.sourceRowHighlightLeadingInset == 10)
        #expect(LibraryNotesLayout.sourceRowHighlightTrailingInset == 10)
        #expect(LibraryNotesLayout.sourceRowHighlightVerticalInset == 0)
        #expect(LibraryNotesLayout.sourceFolderIndentStep == 14)
        #expect(LibraryNotesLayout.sourceCellContentLeadingInset == 7.5)
        #expect(LibraryNotesLayout.sourceIconWidth == 22)
        #expect(LibraryNotesLayout.sourceIconHeight == 20)
        #expect(LibraryNotesLayout.sourceIconTitleSpacing == 3)
        #expect(LibraryNotesLayout.sourceGroupContentLeadingInset == 5)
        #expect(LibraryNotesLayout.sourceCountTrailingInset == 6)
        #expect(LibraryNotesLayout.sourceCountWidth == 32)
        #expect(LibraryNotesLayout.sourceButtonFontSize == 13.5)
        #expect(LibraryNotesLayout.sourceButtonFontWeight == LibraryNotesLayout.sourceSelectedButtonFontWeight)
        #expect(LibraryNotesLayout.sourceSelectedButtonFontWeight == .regular)
        #expect(LibraryNotesLayout.sourceUnselectedButtonFontWeight == .regular)
        #expect(LibraryNotesLayout.sourceCountFontSize == 13)
        #expect(LibraryNotesLayout.sourceSymbolWeight == .medium)
        let sourceOutline = controller.sourceOutlineView
        #expect(sourceOutline.identifier?.rawValue == "LibrarySourceOutline")
        #expect(sourceOutline.style == .sourceList)
        #expect(sourceOutline.allowsEmptySelection)
        #expect(sourceOutline.delegate === controller)
        #expect(sourceOutline.dataSource === controller)
        #expect(sourceOutline.indentationPerLevel == LibraryNotesLayout.sourceFolderIndentStep)
        #expect(sourceOutline.rowSizeStyle == .custom)
        #expect(sourceOutline.intercellSpacing == .zero)
        #expect(sourceOutline.enclosingScrollView?.hasVerticalScroller == true)
        #expect(sourceOutline.enclosingScrollView?.autohidesScrollers == true)
        let sourceScrollerInsets = try #require(sourceOutline.enclosingScrollView?.scrollerInsets)
        #expect(sourceScrollerInsets.top == 0)
        #expect(sourceScrollerInsets.left == 0)
        #expect(sourceScrollerInsets.bottom == 0)
        #expect(sourceScrollerInsets.right == 0)
        #expect(sourceOutline.enclosingScrollView is LibrarySourceScrollView)
        let sourceTitles = controller.sourceTitlesForLibrary()
        #expect(!sourceTitles.contains("所有 iCloud 笔记"))
        #expect(sourceTitles.contains("Notes"))
        #expect(sourceTitles.contains("最近删除"))
        #expect(!sourceTitles.contains("最近"))
        #expect(!sourceTitles.contains("收件箱"))
        #expect(!sourceTitles.contains("Call Recordings"))
        #expect(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.contains {
            $0.identifier?.rawValue == "LibrarySourceFolderStatus"
        } == false)
        #expect(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.contains {
            $0.identifier?.rawValue == "LibrarySourceTagStatus"
        } == false)
        let toolbarTextFields = (window.toolbar?.items ?? []).flatMap { item in
            item.view?.allSubviews.compactMap { $0 as? NSTextField } ?? []
        }
        let noteListTitle = try #require(toolbarTextFields.first {
            $0.identifier?.rawValue == "LibraryNoteListTitle"
        })
        let noteListCount = try #require(toolbarTextFields.first {
            $0.identifier?.rawValue == "LibraryNoteListCount"
        })
        let noteListEmpty = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.first {
            $0.identifier?.rawValue == "LibraryNoteListEmptyLabel"
        })
        #expect(noteListTitle.stringValue == "Notes")
        #expect(noteListTitle.font?.pointSize == LibraryNotesLayout.noteListHeaderTitleFontSize)
        #expect(LibraryNotesLayout.noteListHeaderTitleFontSize == 13)
        #expect(noteListCount.stringValue == "1 条笔记")
        #expect(noteListCount.font?.pointSize == LibraryNotesLayout.noteListHeaderCountFontSize)
        #expect(noteListEmpty.isHidden)
        #expect(controller.tableView.numberOfRows == 2)
        #expect(controller.tableView(controller.tableView, isGroupRow: 0))
        #expect(!controller.tableView(controller.tableView, shouldSelectRow: 0))
        #expect(controller.tableView(controller.tableView, pasteboardWriterForRow: 0) == nil)
        let groupCell = try #require(controller.tableView(controller.tableView, viewFor: nil, row: 0) as? LibraryGroupHeaderCellView)
        #expect(groupCell.titleLabel.stringValue == "今天")
        #expect(LibraryGroupHeaderCellView.titleLeadingInset == 16)
        #expect(LibraryGroupHeaderCellView.titleTrailingInset == 10)
        #expect(groupCell.isFirstGroup)
        #expect(groupCell.titleBottomInset == LibraryGroupHeaderCellView.firstTitleBottomInset)
        #expect(LibraryGroupHeaderCellView.firstTitleBottomInset == 15)
        groupCell.isFirstGroup = false
        #expect(groupCell.titleBottomInset == LibraryGroupHeaderCellView.followingTitleBottomInset)
        #expect(LibraryGroupHeaderCellView.followingTitleBottomInset == 2)
        groupCell.isFirstGroup = true
        #expect(
            LibraryNotesLayout.noteGroupRowHeight - LibraryGroupHeaderCellView.firstTitleBottomInset == 30
        )
        let groupRowView = try #require(controller.tableView(controller.tableView, rowViewForRow: 0) as? LibraryNoteRowView)
        groupRowView.setPointerHovered(true)
        #expect(!groupRowView.isPointerHovered)
        #expect(controller.tableView(controller.tableView, heightOfRow: 0) == LibraryNotesLayout.noteGroupRowHeight)
        #expect(LibraryNotesLayout.noteGroupRowHeight == 45)
        #expect(controller.tableView(controller.tableView, heightOfRow: 1) == LibraryNotesLayout.noteRowHeight)
        #expect(LibraryNotesLayout.noteRowHeight == 76)
        let notePasteboardWriter = try #require(controller.tableView(controller.tableView, pasteboardWriterForRow: 1) as? NSURL)
        #expect(notePasteboardWriter as URL == noteURL)
        let noteRowView = try #require(controller.tableView(controller.tableView, rowViewForRow: 1) as? LibraryNoteRowView)
        #expect(!noteRowView.isGroupRow)
        #expect(LibraryNoteRowView.selectionLeadingInset == 10)
        #expect(LibraryNoteRowView.selectionTrailingInset == 27)
        #expect(LibraryNoteRowView.selectionTopInset == 6)
        #expect(LibraryNoteRowView.selectionBottomInset == 4)
        #expect(LibraryNoteRowView.selectionCornerRadius == 8)
        #expect(
            LibraryNoteRowView.selectionFillColor
                == MudsnoteThemeColor(identifier: store.themeColorIdentifier).noteSelectionColor
        )
        #expect(LibraryNoteRowView.hoverLeadingInset == LibraryNoteRowView.selectionLeadingInset)
        #expect(LibraryNoteRowView.hoverTrailingInset == LibraryNoteRowView.selectionTrailingInset)
        #expect(LibraryNoteRowView.hoverVerticalInset < LibraryNoteRowView.selectionBottomInset)
        #expect(LibraryNoteRowView.hoverCornerRadius == LibraryNoteRowView.selectionCornerRadius)
        #expect(LibraryNoteRowView.hoverFillColor.alphaComponent < 0.3)
        #expect(LibraryNoteRowView.separatorLeadingInset == LibraryNoteCellView.contentLeadingInset + 2)
        #expect(LibraryNoteRowView.separatorTrailingInset == 28)
        #expect(LibraryNoteRowView.separatorAlpha < 0.4)
        #expect(!noteRowView.isPointerHovered)
        controller.tableView.setPointerHoveredRow(noteRowView)
        #expect(noteRowView.isPointerHovered)
        let replacementHoverRow = LibraryNoteRowView()
        controller.tableView.setPointerHoveredRow(replacementHoverRow)
        #expect(!noteRowView.isPointerHovered)
        #expect(replacementHoverRow.isPointerHovered)
        #expect(controller.tableView.pointerHoveredRow === replacementHoverRow)
        controller.tableView.reconcilePointerHover(at: nil)
        #expect(!replacementHoverRow.isPointerHovered)
        #expect(controller.tableView.pointerHoveredRow == nil)
        let firstNoteCell = try #require(controller.tableView(controller.tableView, viewFor: nil, row: 1) as? LibraryNoteCellView)
        #expect(firstNoteCell.snippetLabel.attributedStringValue.string.contains("Body line"))
        let snippetParagraphStyle = try #require(
            firstNoteCell.snippetLabel.attributedStringValue.attribute(
                .paragraphStyle,
                at: 0,
                effectiveRange: nil
            ) as? NSParagraphStyle
        )
        #expect(snippetParagraphStyle.lineBreakMode == .byTruncatingTail)
        let windowAspectRatio = LibraryNotesLayout.presentedWindowSize.width / LibraryNotesLayout.presentedWindowSize.height
        #expect(windowAspectRatio > 1.45 && windowAspectRatio < 1.60)
        #expect(LibraryNotesLayout.sourceColumnWidth == LibraryNotesLayout.noteColumnWidth)
        #expect(LibraryNoteCellView.contentTopInset == 4.5)
        #expect(LibraryNoteCellView.contentLeadingInset == 35)
        #expect(LibraryNoteCellView.contentBottomInset == 7.5)
        #expect(LibraryNoteCellView.contentTrailingInset == 39)
        #expect(
            LibraryNoteCellView.contentTrailingInset
                == LibraryNoteRowView.selectionTrailingInset
                    + LibraryNoteCellView.selectionTextTrailingPadding
                    + LibraryNoteCellView.stackTextTrailingAdjustment
        )
        #expect(LibraryNoteCellView.selectionTextTrailingPadding == 10)
        #expect(LibraryNoteCellView.stackTextTrailingAdjustment == 2)
        #expect(LibraryNoteCellView.minimumTextWidth == 40)
        #expect(LibraryNoteCellView.textRowSpacing == 2.5)
        #expect(LibraryNotesLayout.noteGroupFontSize == 15)
        #expect(LibraryNotesLayout.noteGroupFontWeight == .bold)
        #expect(LibraryNotesLayout.noteTitleFontSize == 14)
        #expect(LibraryNotesLayout.noteTitleFontWeight == .bold)
        #expect(LibraryNotesLayout.noteSnippetFontSize == 12)
        #expect(LibraryNotesLayout.noteSnippetFontWeight == .regular)
        #expect(LibraryNotesLayout.noteMetaFontSize == 11)
        #expect(LibraryNotesLayout.noteMetaFontWeight == .medium)
        #expect(firstNoteCell.titleLabel.font?.pointSize == LibraryNotesLayout.noteTitleFontSize)
        #expect(firstNoteCell.snippetLabel.font?.pointSize == LibraryNotesLayout.noteSnippetFontSize)
        #expect(firstNoteCell.metaLabel.font?.pointSize == LibraryNotesLayout.noteMetaFontSize)
        let noteTimeFormatter = DateFormatter()
        noteTimeFormatter.locale = Locale(identifier: "en_US_POSIX")
        noteTimeFormatter.dateFormat = "HH:mm"
        #expect(firstNoteCell.snippetLabel.attributedStringValue.string.hasPrefix(noteTimeFormatter.string(from: noteModifiedAt)))
        #expect(firstNoteCell.metaLabel.stringValue == "Notes · #library")
        #expect(firstNoteCell.titleLabel.maximumNumberOfLines == 1)
        #expect(firstNoteCell.snippetLabel.maximumNumberOfLines == 1)
        #expect(firstNoteCell.metaLabel.maximumNumberOfLines == 1)
        firstNoteCell.frame = NSRect(
            x: 0,
            y: 0,
            width: controller.tableView.tableColumns[0].width,
            height: LibraryNotesLayout.noteRowHeight
        )
        firstNoteCell.layoutSubtreeIfNeeded()
        let titleFrameInCell = firstNoteCell.titleLabel.convert(firstNoteCell.titleLabel.bounds, to: firstNoteCell)
        let availableTextWidth = firstNoteCell.bounds.width
            - LibraryNoteCellView.contentLeadingInset
            - LibraryNoteCellView.contentTrailingInset
        #expect(titleFrameInCell.width >= availableTextWidth - 4.5)
        let titleDrawingRect = try #require(firstNoteCell.titleLabel.cell?.drawingRect(
            forBounds: firstNoteCell.titleLabel.bounds
        ))
        let titleDrawingRectInCell = firstNoteCell.titleLabel.convert(titleDrawingRect, to: firstNoteCell)
        #expect(
            titleDrawingRectInCell.maxX
                <= firstNoteCell.bounds.maxX
                    - LibraryNoteRowView.selectionTrailingInset
                    - LibraryNoteCellView.selectionTextTrailingPadding
                    + 0.5
        )
        #expect(firstNoteCell.folderImageView.identifier?.rawValue == "LibraryNoteFolderIndicator")
        #expect(firstNoteCell.folderImageView.image?.accessibilityDescription == "文件夹")
        #expect(firstNoteCell.attachmentImageView.identifier?.rawValue == "LibraryNoteAttachmentIndicator")
        #expect(firstNoteCell.attachmentImageView.isHidden)
        #expect(controller.titleField.stringValue == "Library Seed")
        #expect(controller.statusLabel.identifier?.rawValue == "LibraryEditorStatusLabel")
        #expect(controller.statusLabel.accessibilityLabel() == "编辑时间或保存状态")
        #expect(controller.statusLabel.alignment == .center)
        #expect(controller.statusLabel.stringValue == "编辑于 \(noteDateFormatter.string(from: noteModifiedAt))")
        #expect(!controller.statusLabel.stringValue.contains("·"))
        #expect(controller.statusLabel.font?.pointSize == LibraryNotesLayout.editorStatusFontSize)
        #expect(controller.titleField.font?.pointSize == LibraryNotesLayout.editorTitleFontSize)
        #expect(LibraryNotesLayout.editorTitleFontSize == 24)
        #expect(controller.titleField.placeholderString == "")
        #expect(controller.titleField.accessibilityLabel() == "笔记标题")
        #expect(controller.editorTextView.accessibilityLabel() == "笔记内容")
        #expect(controller.statusLabel.accessibilityLabel() == "编辑时间或保存状态")
        #expect(controller.statusLabel.superview === controller.editorTextView)
        #expect(controller.createdDateLabel.accessibilityLabel() == "创建时间")
        #expect(controller.createdDateLabel.superview === controller.editorTextView)
        #expect(controller.createdDateLabel.stringValue.hasPrefix("创建于 "))
        #expect(controller.titleField.alignment == .left)
        #expect(controller.titleField.lineBreakMode == .byTruncatingTail)
        #expect(controller.theme.bodyFont.pointSize == LibraryNotesLayout.editorBodyFontSize)
        #expect(controller.theme.boldFont.pointSize == LibraryNotesLayout.editorBodyFontSize)
        #expect(controller.theme.italicFont.pointSize == LibraryNotesLayout.editorBodyFontSize)
        #expect(controller.theme.codeFont.pointSize == LibraryNotesLayout.editorCodeFontSize)
        #expect(LibraryNotesLayout.editorBodyFontSize == 15)
        #expect(LibraryNotesLayout.editorCodeFontSize == 14)
        let editorParagraphStyle = controller.theme.paragraphStyle(for: .paragraph)
        #expect(editorParagraphStyle.lineSpacing == LibraryNotesLayout.editorLineSpacing)
        #expect(editorParagraphStyle.paragraphSpacing == LibraryNotesLayout.editorParagraphSpacing)
        #expect(LibraryNotesLayout.editorLineSpacing == 2.5)
        #expect(LibraryNotesLayout.editorParagraphSpacing == 6)
        #expect(controller.editorTextView.textContainerInset.width == LibraryNotesLayout.editorTextContainerHorizontalInset)
        #expect(
            controller.editorTextView.textContainerInset.height
                == LibraryNotesLayout.editorDateRowHeight
                    + LibraryNotesLayout.editorDateToTitleSpacing
                    + 4
        )
        let editorScrollView = try #require(controller.editorTextView.enclosingScrollView)
        #expect(editorScrollView.hasHorizontalScroller == false)
        #expect(editorScrollView.horizontalScrollElasticity == .none)
        #expect(editorScrollView.contentInsets.right == LibraryNotesLayout.editorHorizontalInset)
        #expect(editorScrollView.scrollerInsets.right == 0)
        #expect(editorScrollView is LibraryEditorScrollView)
        let editorStack = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSStackView }.first {
            $0.identifier?.rawValue == "LibraryEditorStack"
        })
        let editorBodyContainer = try #require(window.contentView?.allSubviews.first {
            $0.identifier?.rawValue == "LibraryEditorBodyContainer"
        })
        let editorContentPane = try #require(editorStack.superview)
        editorContentPane.layoutSubtreeIfNeeded()
        let editorBodyFrame = editorBodyContainer.convert(editorBodyContainer.bounds, to: editorContentPane)
        #expect(abs(editorBodyFrame.maxX - editorContentPane.bounds.maxX) < 0.5)
        editorScrollView.tile()
        let editorVerticalScroller = try #require(editorScrollView.verticalScroller)
        #expect(abs(editorVerticalScroller.frame.maxX - editorScrollView.bounds.maxX) < 0.5)
        #expect(editorStack.spacing == 0)
        #expect(editorStack.alignment == .leading)
        #expect(editorStack.distribution == .fill)
        #expect(LibraryNotesLayout.editorStatusHorizontalOffset == -8.5)
        let editorLayoutManager = try #require(controller.editorTextView.layoutManager)
        let editorTextContainer = try #require(controller.editorTextView.textContainer)
        let editorUsedRect = editorLayoutManager.usedRect(for: editorTextContainer)
        #expect(
            controller.statusLabel.frame.minY
                >= controller.editorTextView.textContainerInset.height
                    + editorUsedRect.maxY
                    + LibraryNotesLayout.editorBottomInset
        )
        editorScrollView.contentView.scroll(to: .zero)
        editorScrollView.reflectScrolledClipView(editorScrollView.contentView)
        // Short notes pin the edit time label to the viewport bottom so it stays
        // visible without scrolling; tall notes still flow after the content.
        let statusLabelVisibleAtTop = editorScrollView.contentView.bounds.intersects(controller.statusLabel.frame)
        let bottomOriginY = max(
            0,
            controller.editorTextView.frame.height - editorScrollView.contentView.bounds.height
        )
        editorScrollView.contentView.scroll(to: NSPoint(x: 0, y: bottomOriginY))
        editorScrollView.reflectScrolledClipView(editorScrollView.contentView)
        #expect(statusLabelVisibleAtTop == editorScrollView.contentView.bounds.intersects(controller.statusLabel.frame))
        #expect(!editorStack.arrangedSubviews.contains(controller.statusLabel))
        #expect(LibraryNotesLayout.editorDateToTitleSpacing == 10.75)
        #expect(!editorStack.arrangedSubviews.contains(controller.titleField))
        // The date label now lives inside the text view, so the surrounding
        // stack must start at the safe-area edge without adding a second top
        // inset.
        #expect(editorStack.edgeInsets.top == 0)
        #expect(LibraryNotesLayout.editorTopInset == 6.25)
        #expect(LibraryNotesLayout.editorTopInset + LibraryNotesLayout.editorDateToTitleSpacing == 17)
        #expect(LibraryNotesLayout.editorDateToTitleSpacing < LibraryNotesLayout.editorDateRowHeight)
        #expect(editorStack.edgeInsets.left == LibraryNotesLayout.editorHorizontalInset)
        #expect(editorStack.edgeInsets.right == LibraryNotesLayout.editorHorizontalInset)
        #expect(LibraryNotesLayout.editorHorizontalInset == 23)
        #expect(LibraryNotesLayout.editorTextContainerHorizontalInset == 2)
        let editorPane = try #require(editorStack.superview)
        #expect(editorPane.constraints.contains {
            $0.firstItem === editorStack
                && $0.firstAttribute == .top
                && $0.secondItem === editorPane.safeAreaLayoutGuide
                && $0.secondAttribute == .top
        })
        #expect(controller.titleField.superview == nil)
        #expect(
            MarkdownRichTextCodec.serialize(
                controller.editorTextView.attributedString(),
                theme: controller.theme
            ) == "# Library Seed\n\nBody line"
        )
        let allCount = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.first {
            $0.identifier?.rawValue == "LibrarySourceCount-10"
        })
        #expect(allCount.stringValue == "1")
        #expect(allCount.font?.pointSize == LibraryNotesLayout.sourceCountFontSize)
        #expect(!allCount.isAccessibilityElement())
        #expect(allCount.textColor == LibrarySourceSelectionPalette.selectedCountColor)
        #expect(allCount.textColor != LibrarySourceSelectionPalette.foregroundColor)
        #expect(allCount.constraints.contains {
            $0.firstAttribute == .width && $0.constant == LibraryNotesLayout.sourceCountWidth
        })
        let allSourceCell = try #require(window.contentView?.allSubviews.compactMap {
            $0 as? LibrarySourceOutlineCellView
        }.first {
            $0.identifier?.rawValue == "LibrarySourceRow-10"
        })
        #expect(allSourceCell.textField?.font?.pointSize == LibraryNotesLayout.sourceButtonFontSize)
        #expect(allSourceCell.accessibilityLabel() == "Notes")
        #expect(allSourceCell.accessibilityValue() as? String == "1 条笔记")
        #expect(allSourceCell.imageView?.contentTintColor == nil)
        #expect(allSourceCell.imageView?.image?.isTemplate == false)
        let selectedSourceWeight = NSFontManager.shared.weight(of: try #require(allSourceCell.textField?.font))
        let expectedSelectedSourceWeight = NSFontManager.shared.weight(of: .systemFont(
            ofSize: LibraryNotesLayout.sourceButtonFontSize,
            weight: LibraryNotesLayout.sourceSelectedButtonFontWeight
        ))
        #expect(selectedSourceWeight == expectedSelectedSourceWeight)
        let allSourceRow = try #require(controller.sourceOutlineView.rowView(
            atRow: controller.sourceOutlineView.selectedRow,
            makeIfNecessary: false
        ) as? LibrarySourceOutlineRowView)
        #expect(LibrarySourceOutlineRowView.leadingInset == LibraryNotesLayout.sourceRowHighlightLeadingInset)
        #expect(LibrarySourceOutlineRowView.trailingInset == LibraryNotesLayout.sourceRowHighlightTrailingInset)
        #expect(LibrarySourceOutlineRowView.verticalInset == LibraryNotesLayout.sourceRowHighlightVerticalInset)
        #expect(LibrarySourceOutlineRowView.hoverColor.alphaComponent < 0.5)
        #expect(LibrarySourceOutlineRowView.dropTargetColor.alphaComponent > 0.2)
        #expect(
            LibrarySourceOutlineRowView.dropTargetBorderColor.alphaComponent
                > LibrarySourceOutlineRowView.dropTargetColor.alphaComponent
        )
        let dropFeedbackRow = LibrarySourceOutlineRowView(
            frame: NSRect(x: 0, y: 0, width: 220, height: LibraryNotesLayout.sourceRowHeight)
        )
        let dropFeedbackImage = NSImage(size: dropFeedbackRow.bounds.size)
        dropFeedbackImage.lockFocus()
        dropFeedbackRow.drawDraggingDestinationFeedback(in: dropFeedbackRow.bounds)
        dropFeedbackImage.unlockFocus()
        #expect(dropFeedbackRow.dropTargetFeedbackDrawCountForLibrary == 1)
        #expect(!allSourceRow.isPointerHovered)
        let selectedSourceRect = sourceOutline.rect(ofRow: sourceOutline.selectedRow)
        sourceOutline.reconcilePointerHover(at: NSPoint(
            x: selectedSourceRect.midX,
            y: selectedSourceRect.midY
        ))
        #expect(allSourceRow.isPointerHovered)
        #expect(sourceOutline.pointerHoveredRow === allSourceRow)
        let replacementSourceHoverRow = LibrarySourceOutlineRowView()
        sourceOutline.setPointerHoveredRow(replacementSourceHoverRow)
        #expect(!allSourceRow.isPointerHovered)
        #expect(replacementSourceHoverRow.isPointerHovered)
        #expect(sourceOutline.pointerHoveredRow === replacementSourceHoverRow)
        sourceOutline.reconcilePointerHover(at: nil)
        #expect(!replacementSourceHoverRow.isPointerHovered)
        #expect(sourceOutline.pointerHoveredRow == nil)
        #expect(controller.sourceOutlineView.registeredDraggedTypes.contains(.fileURL))
        let folderCount = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.first {
            $0.identifier?.rawValue == "LibrarySourceCount-10"
        })
        #expect(folderCount.stringValue == "1")
        #expect(!controller.sourceTitlesForLibrary().contains("#library"))
        let trashSourceCell = try #require(window.contentView?.allSubviews.compactMap {
            $0 as? LibrarySourceOutlineCellView
        }.first {
            $0.identifier?.rawValue == "LibrarySourceRow-3"
        })
        #expect(trashSourceCell.accessibilityPerformPress())
        #expect(controller.selectedSourceTitleForLibrary == "最近删除")

        controller.updatePanelOpacity(NoteStore.minimumPanelOpacity)
        #expect(window.alphaValue == 1)
    }

    @MainActor
    @Test
    func libraryTitleIsTheFirstEditorLineAndReturnCreatesBodyParagraph() throws {
        let suiteName = "mudsnote-library-title-return-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-title-return-tests-\(UUID().uuidString)", isDirectory: true)
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
        _ = try store.saveNewNote(title: "Return Target", body: "")

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let window = try #require(controller.window)
        #expect(window.makeFirstResponder(controller.editorTextView))
        #expect(controller.titleField.superview == nil)
        #expect(controller.titleField.stringValue == "Return Target")
        #expect(controller.editorTextView.string == "Return Target")
        #expect(
            MarkdownRichTextCodec.serialize(
                controller.editorTextView.attributedString(),
                theme: controller.theme
            ) == "# Return Target"
        )

        let titleRange = NSRange(location: 0, length: "Return Target".utf16.count)
        let titleKind = MarkdownRichTextCodec.paragraphKind(
            at: titleRange,
            in: try #require(controller.editorTextView.textStorage)
        )
        #expect(titleKind == .heading(level: 1))

        controller.editorTextView.setSelectedRange(NSRange(location: titleRange.length, length: 0))
        controller.markdownTextViewInsertNewline(controller.editorTextView)
        #expect(controller.editorTextView.string == "Return Target\n")
        #expect(controller.editorTextView.selectedRange().location == titleRange.length + 1)
    }

    @MainActor
    @Test
    func libraryLongTitleWrapsInsideUnifiedEditorWithoutStretchingWindow() throws {
        let suiteName = "mudsnote-library-long-title-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-long-title-tests-\(UUID().uuidString)", isDirectory: true)
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
        _ = try store.saveNewNote(title: "短标题", body: "正文")

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let window = try #require(controller.window)
        let originalWidth = window.frame.width
        let longTitle = String(repeating: "这是一个不会拉伸主页宽度的长标题", count: 12)
        let markdown = MarkdownEditorDocument.composeEditorText(title: longTitle, body: "正文")
        controller.editorTextView.textStorage?.setAttributedString(
            MarkdownRichTextCodec.render(markdown: markdown, theme: controller.theme)
        )
        controller.textDidChange(Notification(
            name: NSText.didChangeNotification,
            object: controller.editorTextView
        ))
        window.contentView?.layoutSubtreeIfNeeded()

        #expect(controller.titleField.superview == nil)
        #expect(controller.titleField.stringValue == longTitle)
        #expect(abs(window.frame.width - originalWidth) < 0.5)
        #expect(!controller.editorTextView.isHorizontallyResizable)
        #expect(controller.editorTextView.enclosingScrollView?.hasHorizontalScroller == false)

        let serialized = MarkdownRichTextCodec.serialize(
            controller.editorTextView.attributedString(),
            theme: controller.theme
        )
        let document = MarkdownEditorDocument.parse(editorText: serialized)
        #expect(document.title == longTitle)
        #expect(document.body == "正文")

        let layoutManager = try #require(controller.editorTextView.layoutManager)
        let titleCharacterRange = NSRange(location: 0, length: longTitle.utf16.count)
        let titleGlyphRange = layoutManager.glyphRange(
            forCharacterRange: titleCharacterRange,
            actualCharacterRange: nil
        )
        var titleLineCount = 0
        layoutManager.enumerateLineFragments(forGlyphRange: titleGlyphRange) { _, _, _, _, _ in
            titleLineCount += 1
        }
        #expect(titleLineCount > 1)
    }

    @MainActor
    @Test
    func libraryGalleryModeCollapsesListAndPreservesSelection() throws {
        let suiteName = "mudsnote-library-gallery-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-gallery-tests-\(UUID().uuidString)", isDirectory: true)
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
        _ = try store.saveNewNote(title: "Gallery Seed", body: "Gallery body", tags: [])
        _ = try store.saveNewNote(title: "Second Seed", body: "Second body", tags: [])

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }
        let window = try #require(controller.window)
        let splitController = try #require(window.contentViewController as? NSSplitViewController)
        let editorStack = try #require(window.contentView?.allSubviews.first {
            $0.identifier?.rawValue == "LibraryEditorStack"
        })
        let galleryScroll = try #require(window.contentView?.allSubviews.first {
            $0.identifier?.rawValue == "LibraryGalleryScroll"
        })

        #expect(controller.noteListViewMode == .list)
        #expect(!splitController.splitViewItems[1].isCollapsed)
        #expect(!editorStack.isHidden)
        #expect(galleryScroll.isHidden)
        let initialSelectedURL = try #require(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL)

        controller.setNoteListViewModeForLibrary(.gallery)
        splitController.view.layoutSubtreeIfNeeded()

        #expect(controller.noteListViewMode == .gallery)
        #expect(store.libraryNoteViewModeRawValue == LibraryNoteViewMode.gallery.rawValue)
        #expect(splitController.splitViewItems[1].isCollapsed)
        #expect(editorStack.isHidden)
        #expect(!galleryScroll.isHidden)
        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL == initialSelectedURL)
        let galleryHiddenIDs = Set((window.toolbar?.items ?? []).filter(\.isHidden).map { $0.itemIdentifier.rawValue })
        #expect(galleryHiddenIDs.contains("mudsnote.library.toolbar.note-list-title"))
        #expect(galleryHiddenIDs.contains("mudsnote.library.toolbar.note-separator"))
        #expect(galleryHiddenIDs.contains("mudsnote.library.toolbar.editor-tools"))

        controller.setNoteListViewModeForLibrary(.list)
        splitController.view.layoutSubtreeIfNeeded()

        #expect(controller.noteListViewMode == .list)
        #expect(store.libraryNoteViewModeRawValue == LibraryNoteViewMode.list.rawValue)
        #expect(!splitController.splitViewItems[1].isCollapsed)
        #expect(!editorStack.isHidden)
        #expect(galleryScroll.isHidden)
        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL == initialSelectedURL)

        controller.setNoteListViewModeForLibrary(.gallery)
        let reopenedController = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { reopenedController.close() }
        let reopenedWindow = try #require(reopenedController.window)
        let initiallyHiddenIDs = Set((reopenedWindow.toolbar?.items ?? []).filter(\.isHidden).map {
            $0.itemIdentifier.rawValue
        })
        #expect(reopenedController.noteListViewMode == .gallery)
        #expect(initiallyHiddenIDs.contains("mudsnote.library.toolbar.note-list-title"))
        #expect(initiallyHiddenIDs.contains("mudsnote.library.toolbar.note-separator"))
        #expect(initiallyHiddenIDs.contains("mudsnote.library.toolbar.editor-tools"))
        reopenedController.createNewNoteForLibrary()
        #expect(reopenedController.noteListViewMode == .list)
        #expect(store.libraryNoteViewModeRawValue == LibraryNoteViewMode.list.rawValue)
    }

    @MainActor
    @Test
    func librarySplitLayoutPersistsAcrossWindows() async throws {
        let suiteName = "mudsnote-library-split-layout-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-split-layout-tests-\(UUID().uuidString)", isDirectory: true)
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
        _ = try store.saveNewNote(title: "Split Layout", body: "Body")

        let firstController = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { firstController.close() }
        firstController.showWindowAndFocus()
        let firstWindow = try #require(firstController.window)
        firstWindow.contentView?.layoutSubtreeIfNeeded()
        let firstSplitView = try #require(firstWindow.contentView?.allSubviews.compactMap { $0 as? NSSplitView }.first)
        let visibleFrame = try #require((firstWindow.screen ?? NSScreen.main)?.visibleFrame)
        let desiredWindowFrame = NSRect(
            x: visibleFrame.minX + 24,
            y: visibleFrame.minY + 24,
            width: min(1120, visibleFrame.width - 48),
            height: min(760, visibleFrame.height - 48)
        )
        firstWindow.setFrame(desiredWindowFrame, display: false)
        firstWindow.contentView?.layoutSubtreeIfNeeded()
        let desiredSourceWidth: CGFloat = 240
        let desiredNoteWidth: CGFloat = 210

        firstSplitView.setPosition(desiredSourceWidth, ofDividerAt: 0)
        firstSplitView.layoutSubtreeIfNeeded()
        let firstNoteList = firstSplitView.arrangedSubviews[1]
        firstSplitView.setPosition(firstNoteList.frame.minX + desiredNoteWidth, ofDividerAt: 1)
        firstSplitView.layoutSubtreeIfNeeded()
        firstController.persistLibrarySplitLayoutForLibrary()

        try await Task.sleep(for: .milliseconds(260))

        #expect(abs((store.librarySourceColumnWidth ?? 0) - Double(desiredSourceWidth)) < 1)
        #expect(abs((store.libraryNoteColumnWidth ?? 0) - Double(desiredNoteWidth)) < 1)
        #expect(store.libraryWindowFrame == StoredWindowFrame(
            x: desiredWindowFrame.origin.x,
            y: desiredWindowFrame.origin.y,
            width: desiredWindowFrame.width,
            height: desiredWindowFrame.height
        ))
        #expect(firstController.setSourceListVisibleForLibrary(false) == false)
        #expect(!store.librarySourceListVisible)

        let restoredController = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { restoredController.close() }
        restoredController.showWindowAndFocus()
        let restoredWindow = try #require(restoredController.window)
        restoredWindow.contentView?.layoutSubtreeIfNeeded()
        let restoredSplitView = try #require(restoredWindow.contentView?.allSubviews.compactMap { $0 as? NSSplitView }.first)

        #expect(restoredSplitView.arrangedSubviews[0].isHidden)
        #expect(!restoredController.isSourceListVisibleForLibrary)
        #expect(restoredController.setSourceListVisibleForLibrary(true))
        restoredWindow.contentView?.layoutSubtreeIfNeeded()

        #expect(abs(restoredSplitView.arrangedSubviews[0].frame.width - desiredSourceWidth) < 1)
        #expect(abs(restoredSplitView.arrangedSubviews[1].frame.width - desiredNoteWidth) < 1)
        #expect(abs(restoredWindow.frame.origin.x - desiredWindowFrame.origin.x) < 1)
        #expect(abs(restoredWindow.frame.origin.y - desiredWindowFrame.origin.y) < 1)
        #expect(abs(restoredWindow.frame.width - desiredWindowFrame.width) < 1)
        #expect(abs(restoredWindow.frame.height - desiredWindowFrame.height) < 1)
        #expect(store.librarySourceListVisible)
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

    @MainActor
    @Test
    func libraryNoteListActionsSortWithinDateGroupsAndPreserveSelection() throws {
        let suiteName = "mudsnote-note-list-actions-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-note-list-actions-tests-\(UUID().uuidString)", isDirectory: true)
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

        let todayURL = try store.saveNewNote(title: "Zulu Today", body: "Today")
        let bravoURL = try store.saveNewNote(title: "Bravo Yesterday", body: "Yesterday")
        let alphaURL = try store.saveNewNote(title: "Alpha Yesterday", body: "Yesterday")
        let now = Date()
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: now))
        let twoDaysAgo = try #require(Calendar.current.date(byAdding: .day, value: -2, to: now))
        try FileManager.default.setAttributes(
            [.modificationDate: now, .creationDate: twoDaysAgo],
            ofItemAtPath: todayURL.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: yesterday, .creationDate: yesterday],
            ofItemAtPath: bravoURL.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: yesterday, .creationDate: now],
            ofItemAtPath: alphaURL.path
        )

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        func listedNoteTitles() -> [String] {
            (0..<controller.numberOfRows(in: controller.tableView)).compactMap { row in
                (controller.tableView(controller.tableView, viewFor: nil, row: row) as? LibraryNoteCellView)?
                    .titleLabel.stringValue
            }
        }

        #expect(controller.groupsNoteListByDate)
        #expect(controller.noteListSortOrder == .dateEdited)
        #expect(controller.numberOfRows(in: controller.tableView) == 5)
        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL.path == todayURL.standardizedFileURL.path)

        let initialMenu = controller.makeNoteListActionsMenuForLibrary()
        let createdSortItem = try #require(initialMenu.items.first { $0.title == "排序方式" }?.submenu?.items.first {
            $0.title == "创建日期"
        })
        #expect(NSApp.sendAction(try #require(createdSortItem.action), to: createdSortItem.target, from: createdSortItem))
        #expect(controller.noteListSortOrder == .dateCreated)
        #expect(listedNoteTitles() == ["Alpha Yesterday", "Bravo Yesterday", "Zulu Today"])
        let displayDateProbe = NoteSearchResult(
            url: alphaURL,
            title: "Probe",
            snippet: "",
            modifiedAt: yesterday,
            createdAt: now
        )
        #expect(controller.noteListDisplayDateForLibrary(displayDateProbe) == now)
        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL.path == todayURL.standardizedFileURL.path)

        let titleSortItem = try #require(initialMenu.items.first { $0.title == "排序方式" }?.submenu?.items.first {
            $0.title == "标题"
        })
        #expect(NSApp.sendAction(try #require(titleSortItem.action), to: titleSortItem.target, from: titleSortItem))
        #expect(listedNoteTitles() == ["Zulu Today", "Alpha Yesterday", "Bravo Yesterday"])
        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL.path == todayURL.standardizedFileURL.path)

        let groupingItem = try #require(controller.makeNoteListActionsMenuForLibrary().items.first {
            $0.title == "按日期分组"
        })
        #expect(NSApp.sendAction(try #require(groupingItem.action), to: groupingItem.target, from: groupingItem))
        #expect(!controller.groupsNoteListByDate)
        #expect(controller.numberOfRows(in: controller.tableView) == 3)
        #expect(listedNoteTitles() == ["Alpha Yesterday", "Bravo Yesterday", "Zulu Today"])
        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL.path == todayURL.standardizedFileURL.path)
        #expect(store.libraryNoteSortOrderRawValue == LibraryNoteSortOrder.title.rawValue)
        #expect(!store.libraryGroupsNotesByDate)
    }

    @MainActor
    @Test
    func libraryCustomSortReprojectsBeyondTheModifiedDateWindow() throws {
        let suiteName = "mudsnote-global-sort-window-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-global-sort-window-tests-\(UUID().uuidString)", isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let now = Date()
        for index in 0...240 {
            let title = index == 240 ? "Alpha Global" : String(format: "Zulu %03d", index)
            let url = notesDirectory.appendingPathComponent("note-\(index).md")
            try "# \(title)\n\nBody".write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(TimeInterval(-index))],
                ofItemAtPath: url.path
            )
        }

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

        func listedNoteTitles() -> [String] {
            (0..<controller.numberOfRows(in: controller.tableView)).compactMap { row in
                (controller.tableView(controller.tableView, viewFor: nil, row: row) as? LibraryNoteCellView)?
                    .titleLabel.stringValue
            }
        }

        controller.setNoteListGroupingForLibrary(false)
        #expect(!listedNoteTitles().contains("Alpha Global"))

        controller.setNoteListSortOrderForLibrary(.title)
        #expect(listedNoteTitles().count == 240)
        #expect(listedNoteTitles().first == "Alpha Global")
    }

    @MainActor
    @Test
    func libraryPinnedNotesGroupAndMenusMatchSelectionState() throws {
        let suiteName = "mudsnote-pinned-note-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-pinned-note-tests-\(UUID().uuidString)", isDirectory: true)
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
        let firstURL = try store.saveNewNote(title: "First", body: "Body")
        let secondURL = try store.saveNewNote(title: "Second", body: "Body")

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let initialMoreMenu = controller.makeMoreActionsMenuForLibrary()
        let pinItem = try #require(initialMoreMenu.items.first { $0.title == "置顶笔记" })
        #expect(NSApp.sendAction(try #require(pinItem.action), to: pinItem.target, from: pinItem))
        let pinnedURL = try #require(controller.selectedMarkdownFileURLForLibrary())
        #expect(store.isLibraryNotePinned(at: pinnedURL))
        let pinnedHeader = try #require(controller.tableView(controller.tableView, viewFor: nil, row: 0) as? LibraryGroupHeaderCellView)
        #expect(pinnedHeader.titleLabel.stringValue == "置顶")
        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL.path == pinnedURL.standardizedFileURL.path)
        #expect(controller.makeMoreActionsMenuForLibrary().items.contains { $0.title == "取消置顶" })

        let groupingItem = try #require(controller.makeNoteListActionsMenuForLibrary().items.first { $0.title == "按日期分组" })
        #expect(NSApp.sendAction(try #require(groupingItem.action), to: groupingItem.target, from: groupingItem))
        #expect(!controller.groupsNoteListByDate)
        #expect(controller.tableView.numberOfRows == 3)
        let ungroupedPinnedHeader = try #require(controller.tableView(controller.tableView, viewFor: nil, row: 0) as? LibraryGroupHeaderCellView)
        #expect(ungroupedPinnedHeader.titleLabel.stringValue == "置顶")

        let noteRows = (0..<controller.tableView.numberOfRows).filter { row in
            controller.tableView(controller.tableView, pasteboardWriterForRow: row) is NSURL
        }
        #expect(noteRows.count == 2)
        controller.tableView.selectRowIndexes(IndexSet(noteRows), byExtendingSelection: false)
        let multiPinItem = try #require(controller.makeMoreActionsMenuForLibrary().items.first { $0.title == "置顶 2 条笔记" })
        #expect(NSApp.sendAction(try #require(multiPinItem.action), to: multiPinItem.target, from: multiPinItem))
        #expect(store.isLibraryNotePinned(at: firstURL))
        #expect(store.isLibraryNotePinned(at: secondURL))

        let repinnedRows = (0..<controller.tableView.numberOfRows).filter { row in
            controller.tableView(controller.tableView, pasteboardWriterForRow: row) is NSURL
        }
        controller.tableView.selectRowIndexes(IndexSet(repinnedRows), byExtendingSelection: false)
        let unpinItem = try #require(controller.makeMoreActionsMenuForLibrary().items.first { $0.title == "取消置顶 2 条笔记" })
        #expect(NSApp.sendAction(try #require(unpinItem.action), to: unpinItem.target, from: unpinItem))
        #expect(store.libraryPinnedNotePaths.isEmpty)
        #expect(controller.tableView.numberOfRows == 2)
        #expect(controller.tableView(controller.tableView, viewFor: nil, row: 0) is LibraryNoteCellView)
    }

    @MainActor
    @Test
    func libraryNoteListAvoidsDuplicatingWeekdayPrefixInSnippet() throws {
        let suiteName = "mudsnote-note-list-weekday-snippet-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-note-list-weekday-snippet-tests-\(UUID().uuidString)", isDirectory: true)
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

        let modifiedAt = try #require(Calendar.current.date(byAdding: .day, value: -3, to: Date()))
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "zh_Hans_CN")
        weekdayFormatter.dateFormat = "EEEE"
        let weekday = weekdayFormatter.string(from: modifiedAt)
        let noteURL = try store.saveNewNote(title: "Weekday Prefix", body: "\(weekday)  动机")
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: noteURL.path)

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let noteCell = try #require((0..<controller.tableView.numberOfRows).compactMap { row -> LibraryNoteCellView? in
            controller.tableView(controller.tableView, viewFor: nil, row: row) as? LibraryNoteCellView
        }.first {
            $0.titleLabel.attributedStringValue.string == "Weekday Prefix"
        })
        let snippet = noteCell.snippetLabel.attributedStringValue.string
        #expect(snippet == "\(weekday)  动机")
        #expect(!snippet.contains("\(weekday) \(weekday)"))
    }

    @MainActor
    @Test
    func libraryNoteScrollViewFitsSingleColumnToVisibleWidth() {
        let tableView = LibraryNoteTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("library-note"))
        column.width = LibraryNotesLayout.noteTableInitialWidth
        column.minWidth = LibraryNotesLayout.noteTableMinimumWidth
        column.resizingMask = .userResizingMask
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        let scrollView = LibraryNoteScrollView(frame: NSRect(x: 0, y: 0, width: 340, height: 300))
        let clipView = LibraryNoteClipView(frame: scrollView.bounds)
        scrollView.contentView = clipView
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.usesPredominantAxisScrolling = true
        scrollView.documentView = tableView
        scrollView.contentView.bounds = NSRect(x: 0, y: 0, width: 340, height: 300)
        tableView.frame = NSRect(x: 92, y: 0, width: LibraryNotesLayout.noteTableInitialWidth, height: 300)

        scrollView.layout()

        let visibleWidth = scrollView.frame.width
        #expect(tableView.frame.origin.x == 0)
        #expect(tableView.frame.width >= visibleWidth)
        #expect(column.width == visibleWidth)
        #expect(scrollView.hasHorizontalScroller == false)
        #expect(scrollView.horizontalScrollElasticity == .none)
        #expect(scrollView.usesPredominantAxisScrolling)
        #expect(LibraryNoteScrollView.suppressesHorizontalScroll(deltaX: 20, deltaY: 0))
        #expect(LibraryNoteScrollView.suppressesHorizontalScroll(deltaX: -20, deltaY: 4))
        #expect(!LibraryNoteScrollView.suppressesHorizontalScroll(deltaX: 4, deltaY: 20))
        #expect(clipView.constrainBoundsRect(
            NSRect(x: 48, y: 20, width: 340, height: 300)
        ).origin.x == 0)
    }

    @MainActor
    @Test
    func libraryAllNotesIncludesPlainMarkdownOutsideRecents() throws {
        let suiteName = "mudsnote.library-all-notes-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-all-notes-tests-\(UUID().uuidString)", isDirectory: true)
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
        store.notesDirectory = notesDirectory
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        let externalNoteURL = notesDirectory.appendingPathComponent("External Seed.md")
        try "# External Seed\n\nBody from Finder".write(to: externalNoteURL, atomically: true, encoding: .utf8)

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        _ = try #require(controller.window)
        #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["External Seed"])
        #expect(controller.titleField.stringValue == "External Seed")
        #expect(controller.sourceCountTextForLibrary(titled: "Notes") == "1")
        controller.selectRecentScopeForLibrary()
        #expect(controller.noteListTitleLabel.stringValue == "最近")
        #expect(controller.noteListCountLabel.stringValue == "0 条笔记")
        #expect(controller.noteListSearchResultsForLibrary().isEmpty)
    }

    @MainActor
    @Test
    func libraryNavigationUsesCachedSnapshotThenValidatesExternalChanges() async throws {
        let suiteName = "mudsnote.library-navigation-snapshot-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-navigation-snapshot-tests-\(UUID().uuidString)", isDirectory: true)
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
        _ = try store.saveNewNote(title: "Cached Note", body: "Initial body")

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }
        #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["Cached Note"])

        let externalURL = notesDirectory.appendingPathComponent("External Note.md")
        try "# External Note\n\nAdded outside Mudsnote".write(
            to: externalURL,
            atomically: true,
            encoding: .utf8
        )

        controller.refreshSelectedScopeFromCachedSnapshotForLibrary()
        #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["Cached Note"])

        await controller.waitForSourceSnapshotValidationForLibrary()
        #expect(Set(controller.noteListSearchResultsForLibrary().map(\.title)) == ["Cached Note", "External Note"])
    }

    @Test
    func libraryFileSystemMonitorReportsEverySupportedNoteExtension() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-file-monitor-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let recorder = LibraryFileSystemChangeRecorder()
        let monitor = LibraryFileSystemMonitor(
            roots: [root],
            latency: 0.02,
            debounceInterval: .milliseconds(20)
        ) { changes in
            Task {
                await recorder.append(changes)
            }
        }
        #expect(monitor.start())
        defer { monitor.stop() }
        try await Task.sleep(for: .milliseconds(120))

        let externalURLs = ["md", "markdown", "txt"].map {
            root.appendingPathComponent("External Event.\($0)")
        }
        for externalURL in externalURLs {
            try "# External Event\n\nWritten outside Mudsnote\n".write(
                to: externalURL,
                atomically: true,
                encoding: .utf8
            )
        }

        var observedChanges: Set<LibraryFileSystemChange> = []
        for _ in 0..<80 {
            observedChanges = await recorder.snapshot()
            let observedPaths = Set(observedChanges.filter(\.isMarkdownFile).map {
                URL(fileURLWithPath: $0.path).standardizedFileURL.path
            })
            if externalURLs.allSatisfy({ observedPaths.contains($0.standardizedFileURL.path) }) {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        let observedPaths = Set(observedChanges.filter(\.isMarkdownFile).map {
            URL(fileURLWithPath: $0.path).standardizedFileURL.path
        })
        #expect(externalURLs.allSatisfy { observedPaths.contains($0.standardizedFileURL.path) })
    }

    @Test
    func libraryFileSystemMonitorRequiresFullRescanForDroppedOrInvalidatedEvents() {
        let flags = [
            kFSEventStreamEventFlagMustScanSubDirs,
            kFSEventStreamEventFlagUserDropped,
            kFSEventStreamEventFlagKernelDropped,
            kFSEventStreamEventFlagEventIdsWrapped,
            kFSEventStreamEventFlagRootChanged
        ]

        for flag in flags {
            let change = LibraryFileSystemChange(
                path: "/tmp/Mudsnote Notes",
                flags: FSEventStreamEventFlags(flag)
            )
            #expect(change.requiresFullRescan)
            #expect(
                change.requiresUnconditionalFullRescan
                    == (flag != kFSEventStreamEventFlagRootChanged)
            )
            #expect(change.changesDirectoryStructure)
            #expect(change.requiresLibraryRefresh)
        }

        #expect(LibraryFileSystemChange(
            path: "/tmp/Note.MARKDOWN",
            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)
        ).isMarkdownFile)
        #expect(LibraryFileSystemChange(
            path: "/tmp/Note.txt",
            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)
        ).isMarkdownFile)
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
    func librarySelectionChangePreservesExternalVersionAndLocalConflictCopy() async throws {
        let suiteName = "mudsnote.library-conflict-selection-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-conflict-selection-tests-\(UUID().uuidString)", isDirectory: true)
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
        _ = try store.saveNewNote(title: "Older", body: "Older body")
        _ = try store.saveNewNote(title: "Newer", body: "Newer body")
        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let originalURL = try #require(controller.selectedMarkdownFileURLForLibrary())
        let originalTitle = controller.titleField.stringValue
        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: MarkdownEditorDocument.composeEditorText(
                title: originalTitle,
                body: "Local protected edit"
            ),
            theme: controller.theme,
            baseURL: originalURL
        ))
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.editorTextView))
        try "# Changed outside\n\nExternal body\n".write(
            to: originalURL,
            atomically: true,
            encoding: .utf8
        )

        let otherRow = try #require((0..<controller.tableView.numberOfRows).first { row in
            guard let writer = controller.tableView(
                controller.tableView,
                pasteboardWriterForRow: row
            ) as? NSURL else {
                return false
            }
            return (writer as URL).standardizedFileURL != originalURL.standardizedFileURL
        })
        let targetURL = try #require(
            controller.tableView(controller.tableView, pasteboardWriterForRow: otherRow) as? NSURL
        ) as URL
        controller.tableView.selectRowIndexes(IndexSet(integer: otherRow), byExtendingSelection: false)
        await controller.waitForBackgroundAutosaveForTesting()

        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL == targetURL.standardizedFileURL)
        #expect(try store.loadNote(at: originalURL).body == "External body")
        let conflictURL = try #require(
            FileManager.default.contentsOfDirectory(
                at: store.notesDirectory,
                includingPropertiesForKeys: nil
            ).first { $0.lastPathComponent.contains("(Mudsnote Conflict)") }
        )
        #expect(try store.loadNote(at: conflictURL).body == "Local protected edit")
        #expect(!controller.currentNoteHasUnsavedChangesForLibrary)
    }

    @Test
    func libraryClosePreservesExternalVersionAndLocalConflictCopy() async throws {
        let suiteName = "mudsnote.library-conflict-close-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-conflict-close-tests-\(UUID().uuidString)", isDirectory: true)
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
        let noteURL = try store.saveNewNote(title: "Close Guard", body: "Initial body")
        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "# Close Guard\n\nUnsaved close edit",
            theme: controller.theme,
            baseURL: noteURL
        ))
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.editorTextView))
        try "# Close Guard\n\nChanged outside\n".write(
            to: noteURL,
            atomically: true,
            encoding: .utf8
        )

        let window = try #require(controller.window)
        #expect(controller.windowShouldClose(window))
        await controller.waitForBackgroundAutosaveForTesting()
        #expect(!controller.currentNoteHasUnsavedChangesForLibrary)
        #expect(try store.loadNote(at: noteURL).body == "Changed outside")
        let conflictURL = try #require(
            FileManager.default.contentsOfDirectory(
                at: store.notesDirectory,
                includingPropertiesForKeys: nil
            ).first { $0.lastPathComponent.contains("(Mudsnote Conflict)") }
        )
        #expect(try store.loadNote(at: conflictURL).body == "Unsaved close edit")
    }

    @Test
    func librarySelectionChangeCreatesOneConflictCopy() async throws {
        let suiteName = "mudsnote.library-conflict-copy-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-conflict-copy-tests-\(UUID().uuidString)", isDirectory: true)
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
        _ = try store.saveNewNote(title: "Other", body: "Other body")
        _ = try store.saveNewNote(title: "Current", body: "Initial body")
        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let originalURL = try #require(controller.selectedMarkdownFileURLForLibrary())
        let originalTitle = controller.titleField.stringValue
        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: MarkdownEditorDocument.composeEditorText(
                title: originalTitle,
                body: "Local copy body"
            ),
            theme: controller.theme,
            baseURL: originalURL
        ))
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.editorTextView))
        try "# Changed outside\n\nExternal original\n".write(
            to: originalURL,
            atomically: true,
            encoding: .utf8
        )

        let otherRow = try #require((0..<controller.tableView.numberOfRows).first { row in
            guard let writer = controller.tableView(
                controller.tableView,
                pasteboardWriterForRow: row
            ) as? NSURL else {
                return false
            }
            return (writer as URL).standardizedFileURL != originalURL.standardizedFileURL
        })
        let targetURL = try #require(
            controller.tableView(controller.tableView, pasteboardWriterForRow: otherRow) as? NSURL
        ) as URL
        controller.tableView.selectRowIndexes(IndexSet(integer: otherRow), byExtendingSelection: false)
        await controller.waitForBackgroundAutosaveForTesting()

        let noteURLs = try FileManager.default.contentsOfDirectory(
            at: store.notesDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "md" }
        #expect(noteURLs.count == 3)
        #expect(try store.loadNote(at: originalURL).body == "External original")
        let conflictURL = try #require(
            noteURLs.first { $0.lastPathComponent.contains("(Mudsnote Conflict)") }
        )
        #expect(try store.loadNote(at: conflictURL).body == "Local copy body")
        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL == targetURL.standardizedFileURL)
        #expect(!controller.currentNoteHasUnsavedChangesForLibrary)
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
    func libraryWindowShowsEmptyMarkdownFileAsBlankEditorNewNote() throws {
        let suiteName = "mudsnote.library-empty-new-note-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-empty-new-note-tests-\(UUID().uuidString)", isDirectory: true)
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
        let emptyNoteURL = notesDirectory.appendingPathComponent("New Note.md")
        try Data().write(to: emptyNoteURL)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: emptyNoteURL.path)

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["New Note"])
        #expect(controller.titleField.stringValue == "")
        #expect(controller.titleField.placeholderString == "")
        #expect(controller.editorTextView.string == "")
        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL.path == emptyNoteURL.standardizedFileURL.path)

        let noteCell = try #require(controller.tableView(controller.tableView, viewFor: nil, row: 1) as? LibraryNoteCellView)
        #expect(noteCell.titleLabel.attributedStringValue.string == "New Note")
        #expect(noteCell.snippetLabel.attributedStringValue.string.contains("无其他内容"))
        #expect(noteCell.metaLabel.stringValue == "Notes")
    }

    @MainActor
    @Test
    func librarySourceListDisplaysDefaultNotesFolderLikeAppleNotes() throws {
        let suiteName = "mudsnote.library-notes-folder-title-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-notes-folder-title-tests-\(UUID().uuidString)", isDirectory: true)
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
        store.notesDirectory = root.appendingPathComponent("Mudsnote", isDirectory: true)
        _ = try store.saveNewNote(title: "Default Root", body: "Body")

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        _ = try #require(controller.window)
        #expect(controller.sourceTitlesForLibrary().contains("Mudsnote"))
        #expect(!controller.sourceTitlesForLibrary().contains("Notes"))
        #expect(controller.selectSourceForLibrary(titled: "Mudsnote"))

        #expect(controller.noteListTitleLabel.stringValue == "Mudsnote")
        #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["Default Root"])
        let noteCell = try #require(controller.tableView(controller.tableView, viewFor: nil, row: 1) as? LibraryNoteCellView)
        #expect(noteCell.metaLabel.stringValue.contains("Mudsnote"))
        let moveMenu = try #require(controller.makeMoreActionsMenuForLibrary().items.first {
            $0.title == "移到文件夹"
        }?.submenu)
        #expect(moveMenu.items.contains {
            $0.title == "Mudsnote" && ($0.representedObject as? URL) == store.notesDirectory.standardizedFileURL
        })
    }

    @MainActor
    @Test
    func librarySourceRowsNavigateWithArrowKeys() async throws {
        let suiteName = "mudsnote.library-source-keyboard-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-source-keyboard-tests-\(UUID().uuidString)", isDirectory: true)
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
        let projectsFolder = try store.createFolder(named: "Projects")
        let clientFolder = projectsFolder.appendingPathComponent("Client", isDirectory: true)
        try FileManager.default.createDirectory(at: clientFolder, withIntermediateDirectories: true)
        _ = try store.saveNewNote(title: "Client Keyboard Seed", body: "Nested keyboard body", in: clientFolder)

        weak var controllerReference: LibraryWindowController?
        var selectedTextColorAtSave: NSColor?
        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in
                guard let controller = controllerReference else { return }
                let selectedRow = controller.sourceOutlineView.selectedRow
                selectedTextColorAtSave = (controller.sourceOutlineView.view(
                    atColumn: 0,
                    row: selectedRow,
                    makeIfNecessary: true
                ) as? LibrarySourceOutlineCellView)?.textField?.textColor
            },
            onClose: {}
        )
        controllerReference = controller
        defer { controller.close() }
        let window = try #require(controller.window)
        window.makeKeyAndOrderFront(nil)
        controller.loadSourceFoldersForLibrary()

        let outline = controller.sourceOutlineView
        #expect(outline.acceptsFirstResponder)
        #expect(controller.selectSourceForLibrary(titled: "Notes"))
        #expect(window.firstResponder === outline)

        outline.keyDown(with: try keyEvent(keyCode: 125, modifiers: [], characters: "\u{F701}"))
        #expect(controller.noteListTitleLabel.stringValue == "Projects")
        #expect(window.firstResponder === outline)
        outline.keyDown(with: try keyEvent(keyCode: 126, modifiers: [], characters: "\u{F700}"))
        #expect(controller.noteListTitleLabel.stringValue == "Notes")

        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(
            attributedString: MarkdownRichTextCodec.render(
                markdown: "# Client Keyboard Seed\n\nNested keyboard body updated",
                theme: controller.theme
            )
        ))
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.editorTextView))
        let projectsRow = try #require((0..<outline.numberOfRows).first { row in
            (outline.view(atColumn: 0, row: row, makeIfNecessary: true)
                as? LibrarySourceOutlineCellView)?.textField?.stringValue == "Projects"
        })
        outline.beginPrimaryMouseSelectionDeferral(visualSelectionRow: projectsRow)
        #expect(outline.selectedRow != projectsRow)
        #expect(controller.selectedSourceTitleForLibrary == "Notes")
        #expect(selectedTextColorAtSave == nil)
        let pressedProjectsRow = try #require(outline.rowView(
            atRow: projectsRow,
            makeIfNecessary: true
        ) as? LibrarySourceOutlineRowView)
        let previousSelectedRow = try #require(outline.rowView(
            atRow: outline.selectedRow,
            makeIfNecessary: true
        ) as? LibrarySourceOutlineRowView)
        #expect(!pressedProjectsRow.isVisuallySelected)
        #expect(previousSelectedRow.isVisuallySelected)
        let pressedProjectsCell = try #require(outline.view(
            atColumn: 0,
            row: projectsRow,
            makeIfNecessary: true
        ) as? LibrarySourceOutlineCellView)
        #expect(pressedProjectsCell.textField?.textColor == LibrarySourceSelectionPalette.unselectedForegroundColor)
        #expect(pressedProjectsCell.imageView?.contentTintColor == nil)
        #expect(pressedProjectsCell.imageView?.image?.isTemplate == false)

        outline.selectRowIndexes(IndexSet(integer: projectsRow), byExtendingSelection: false)
        #expect(controller.selectedSourceTitleForLibrary == "Notes")
        #expect(selectedTextColorAtSave == nil)
        #expect(outline.selectedRow == projectsRow)
        #expect(!outline.needsDisplay)
        #expect(pressedProjectsCell.textField?.textColor == LibrarySourceSelectionPalette.unselectedForegroundColor)
        #expect(pressedProjectsCell.imageView?.contentTintColor == nil)
        #expect(pressedProjectsCell.imageView?.image?.isTemplate == false)
        outline.finishPrimaryMouseSelectionDeferral()
        #expect(!outline.isDeferringPrimaryMouseSelectionCommit)
        #expect(controller.selectedSourceTitleForLibrary == "Projects")
        for _ in 0..<100 where selectedTextColorAtSave == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(selectedTextColorAtSave == LibrarySourceSelectionPalette.foregroundColor)
        #expect(pressedProjectsRow.isVisuallySelected)
        let selectionColor = try #require(
            LibrarySourceSelectionPalette.foregroundColor.usingColorSpace(.deviceRGB)
        )
        #expect(selectionColor.blueComponent > selectionColor.redComponent)
        #expect(selectionColor.blueComponent > selectionColor.greenComponent)
        #expect(controller.setSourceFolderExpandedForLibrary(projectsFolder, expanded: false))
        outline.keyDown(with: try keyEvent(keyCode: 124, modifiers: [], characters: "\u{F703}"))
        #expect(controller.sourceTitlesForLibrary().contains("Client"))
        outline.keyDown(with: try keyEvent(keyCode: 125, modifiers: [], characters: "\u{F701}"))
        #expect(controller.noteListTitleLabel.stringValue == "Client")
        #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["Client Keyboard Seed"])

        outline.keyDown(with: try keyEvent(keyCode: 123, modifiers: [], characters: "\u{F702}"))
        #expect(controller.noteListTitleLabel.stringValue == "Projects")

        outline.keyDown(with: try keyEvent(keyCode: 123, modifiers: [], characters: "\u{F702}"))
        #expect(!outline.isItemExpanded(outline.item(atRow: outline.selectedRow)))
        #expect(controller.noteListTitleLabel.stringValue == "Projects")
    }

    @MainActor
    @Test
    func libraryTopLevelFoldersUseEditablePersistentIcons() throws {
        let suiteName = "mudsnote.library-folder-icon-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-folder-icon-tests-\(UUID().uuidString)", isDirectory: true)
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
        store.notesDirectory = notesDirectory
        store.themeColorIdentifier = MudsnoteThemeColor.violet.rawValue
        try store.ensureNotesDirectory()
        _ = try store.createFolder(named: "Projects")

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }
        _ = try #require(controller.window)
        controller.loadSourceFoldersForLibrary()

        #expect(controller.sourceIconNameForLibrary(titled: "Notes") == "folder.fill")
        #expect(controller.sourceIconNameForLibrary(titled: "Projects") == "folder")

        let outline = controller.sourceOutlineView
        let rootRow = try #require((0..<outline.numberOfRows).first { row in
            (outline.view(atColumn: 0, row: row, makeIfNecessary: true)
                as? LibrarySourceOutlineCellView)?.textField?.stringValue == "Notes"
        })
        let rootCell = try #require(outline.view(
            atColumn: 0,
            row: rootRow,
            makeIfNecessary: true
        ) as? LibrarySourceOutlineCellView)
        #expect(rootCell.textField?.textColor == MudsnoteThemeColor.violet.foregroundColor)
        let originalSourceBackground = NSColor(calibratedWhite: 0.16, alpha: 0.86)
        let originalCountColor = NSColor.labelColor.withAlphaComponent(0.42)
        store.themeColorIdentifier = MudsnoteThemeColor.teal.rawValue
        controller.refreshThemeColorForLibrary()
        #expect(rootCell.textField?.textColor == MudsnoteThemeColor.teal.foregroundColor)
        #expect(rootCell.countLabel.textColor == originalCountColor)
        #expect(LibrarySourceSelectionPalette.backgroundColor == originalSourceBackground)
        #expect(LibraryNoteRowView.selectionFillColor == MudsnoteThemeColor.teal.noteSelectionColor)

        store.themeColorIdentifier = MudsnoteThemeColor.classicYellow.rawValue
        controller.refreshThemeColorForLibrary()
        #expect(rootCell.textField?.textColor == NSColor(
            calibratedRed: 1.0,
            green: 0.72,
            blue: 0.16,
            alpha: 1
        ))
        #expect(rootCell.countLabel.textColor == originalCountColor)
        #expect(LibrarySourceSelectionPalette.backgroundColor == originalSourceBackground)

        let rootMenu = try #require(controller.sourceContextMenuForLibrary(row: rootRow))
        let iconMenu = try #require(rootMenu.items.first { $0.title == "更改图标" }?.submenu)
        let workIndex = try #require(iconMenu.items.firstIndex { $0.title == "工作" })
        iconMenu.performActionForItem(at: workIndex)

        #expect(store.libraryFolderIconName(for: notesDirectory) == "briefcase.fill")
        #expect(controller.sourceIconNameForLibrary(titled: "Notes") == "briefcase.fill")

        let childRow = try #require((0..<outline.numberOfRows).first { row in
            (outline.view(atColumn: 0, row: row, makeIfNecessary: true)
                as? LibrarySourceOutlineCellView)?.textField?.stringValue == "Projects"
        })
        let childMenu = try #require(controller.sourceContextMenuForLibrary(row: childRow))
        #expect(!childMenu.items.contains { $0.title == "更改图标" })
    }

    @MainActor
    @Test
    func librarySourceListShowsZeroCountsForEmptyFoldersLikeAppleNotes() throws {
        let suiteName = "mudsnote.library-empty-folder-count-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-empty-folder-count-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let resourcesDirectory = root.appendingPathComponent("Resources", isDirectory: true)
        let archivesDirectory = root.appendingPathComponent("Archives", isDirectory: true)
        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.configurePreferredDirectories(
            [notesDirectory, resourcesDirectory, archivesDirectory],
            defaultDirectory: notesDirectory
        )
        _ = try store.saveNewNote(title: "Default Note", body: "Body", in: notesDirectory)
        _ = try store.saveNewNote(title: "Archived Note", body: "Old body", in: archivesDirectory)
        try FileManager.default.createDirectory(at: resourcesDirectory, withIntermediateDirectories: true)

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        _ = try #require(controller.window)
        #expect(controller.sourceCountTextForLibrary(titled: "Notes") == "1")
        #expect(controller.sourceCountTextForLibrary(titled: "Resources") == "0")
        #expect(controller.sourceCountTextForLibrary(titled: "Archives") == "1")
    }

    @MainActor
    @Test
    func libraryToolbarUsesNotesLikeDisabledStates() throws {
        let suiteName = "mudsnote.library-toolbar-state-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-toolbar-state-tests-\(UUID().uuidString)", isDirectory: true)
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

        let emptyController = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { emptyController.close() }

        func visibleEditorToolsView(in controller: LibraryWindowController) throws -> NSView {
            try #require((controller.window?.toolbar?.items ?? []).first {
                $0.itemIdentifier.rawValue == "mudsnote.library.toolbar.editor-tools"
            }?.view)
        }

        func visibleEditorToolButtons(in controller: LibraryWindowController) throws -> [NSButton] {
            try visibleEditorToolsView(in: controller).allSubviews.compactMap { $0 as? NSButton }
        }

        func toolbarItem(_ rawValue: String) -> NSToolbarItem {
            NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier(rawValue))
        }

        let formatItem = toolbarItem("mudsnote.library.toolbar.format")
        let checklistItem = toolbarItem("mudsnote.library.toolbar.checklist")
        let editorToolsItem = toolbarItem("mudsnote.library.toolbar.editor-tools")
        let saveItem = toolbarItem("mudsnote.library.toolbar.save")
        let moreItem = toolbarItem("mudsnote.library.toolbar.more")
        let openItem = toolbarItem("mudsnote.library.toolbar.open-separate")
        let deleteItem = toolbarItem("mudsnote.library.toolbar.delete")
        let restoreItem = toolbarItem("mudsnote.library.toolbar.restore")
        let exportItem = toolbarItem("mudsnote.library.toolbar.export")
        let newItem = toolbarItem("mudsnote.library.toolbar.new-note")

        #expect(!emptyController.validateToolbarItem(formatItem))
        #expect(!emptyController.validateToolbarItem(checklistItem))
        #expect(!emptyController.validateToolbarItem(editorToolsItem))
        #expect(!emptyController.validateToolbarItem(saveItem))
        #expect(!emptyController.validateToolbarItem(moreItem))
        #expect(!emptyController.validateToolbarItem(openItem))
        #expect(!emptyController.validateToolbarItem(deleteItem))
        #expect(!emptyController.validateToolbarItem(restoreItem))
        #expect(!emptyController.validateToolbarItem(exportItem))
        #expect(emptyController.validateToolbarItem(newItem))
        #expect(try visibleEditorToolButtons(in: emptyController).allSatisfy { !$0.isEnabled })
        #expect(try visibleEditorToolsView(in: emptyController).alphaValue == LibraryNotesLayout.toolbarEditorToolsDisabledAlpha)
        #expect(LibraryNotesLayout.toolbarIconEnabledAlpha == 0.76)
        let visibleNewItem = try #require((emptyController.window?.toolbar?.items ?? []).first {
            $0.itemIdentifier.rawValue == "mudsnote.library.toolbar.new-note"
        })
        let visibleNewButton = try #require(visibleNewItem.view?.allSubviews.compactMap { $0 as? NSButton }.first)
        visibleNewButton.performClick(nil)
        #expect(emptyController.window?.contentView?.allSubviews.compactMap { $0 as? NSTextField }.contains {
            $0.stringValue == "Select or create a note"
        } == false)
        #expect(emptyController.statusLabel.stringValue != "新笔记")
        #expect(emptyController.window?.firstResponder === emptyController.editorTextView)
        #expect(emptyController.validateToolbarItem(formatItem))
        #expect(emptyController.validateToolbarItem(checklistItem))
        #expect(emptyController.validateToolbarItem(editorToolsItem))
        #expect(emptyController.validateToolbarItem(saveItem))
        #expect(emptyController.validateToolbarItem(moreItem))
        #expect(try visibleEditorToolButtons(in: emptyController).allSatisfy(\.isEnabled))

        let noteURL = try store.saveNewNote(title: "Toolbar State", body: "Body line")
        let selectedController = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { selectedController.close() }

        #expect(selectedController.selectedMarkdownFileURLForLibrary()?.path == noteURL.standardizedFileURL.path)
        #expect(selectedController.validateToolbarItem(formatItem))
        #expect(selectedController.validateToolbarItem(editorToolsItem))
        #expect(selectedController.validateToolbarItem(saveItem))
        #expect(selectedController.validateToolbarItem(moreItem))
        #expect(selectedController.validateToolbarItem(openItem))
        #expect(selectedController.validateToolbarItem(deleteItem))
        #expect(selectedController.validateToolbarItem(exportItem))
        #expect(!selectedController.validateToolbarItem(restoreItem))
        #expect(try visibleEditorToolButtons(in: selectedController).allSatisfy(\.isEnabled))

        let normalMoreMenu = selectedController.makeMoreActionsMenuForLibrary()
        #expect(normalMoreMenu.items.first { $0.title == "保存" }?.isEnabled == true)
        #expect(normalMoreMenu.items.first { $0.title == "分享..." } == nil)
        #expect(normalMoreMenu.items.first { $0.title == "复制 Markdown 内容" }?.isEnabled == true)
        #expect(normalMoreMenu.items.first { $0.title == "导出 Markdown..." }?.isEnabled == true)
        #expect(normalMoreMenu.items.first { $0.title == "删除" }?.isEnabled == true)
        let normalExportMenu = selectedController.makeExportMenuForLibrary()
        #expect(normalExportMenu.items.map(\.title) == ["复制 Markdown 内容", "导出 Markdown..."])
        #expect(normalExportMenu.items.allSatisfy { $0.isEnabled })

        try selectedController.deleteSelectedNoteForLibrary()
        #expect(selectedController.selectSourceForLibrary(titled: "最近删除"))

        #expect(!selectedController.validateToolbarItem(formatItem))
        #expect(!selectedController.validateToolbarItem(checklistItem))
        #expect(!selectedController.validateToolbarItem(editorToolsItem))
        #expect(!selectedController.validateToolbarItem(saveItem))
        #expect(!selectedController.validateToolbarItem(exportItem))
        #expect(selectedController.validateToolbarItem(moreItem))
        #expect(selectedController.validateToolbarItem(deleteItem))
        #expect(selectedController.validateToolbarItem(restoreItem))
        #expect(try visibleEditorToolButtons(in: selectedController).allSatisfy { !$0.isEnabled })
        let trashMoreMenu = selectedController.makeMoreActionsMenuForLibrary()
        #expect(trashMoreMenu.items.first { $0.title == "保存" }?.isEnabled == false)
        #expect(trashMoreMenu.items.first { $0.title == "分享..." } == nil)
        #expect(trashMoreMenu.items.first { $0.title == "复制 Markdown 内容" }?.isEnabled == false)
        #expect(trashMoreMenu.items.first { $0.title == "导出 Markdown..." }?.isEnabled == false)
        #expect(trashMoreMenu.items.first { $0.title == "恢复" }?.isEnabled == true)
        #expect(trashMoreMenu.items.first { $0.title == "永久删除" }?.isEnabled == true)
        #expect(selectedController.makeExportMenuForLibrary().items.allSatisfy { !$0.isEnabled })
    }

    @MainActor
    @Test
    func libraryWindowCopiesExportsAndDeletesMultipleSelectedNotes() throws {
        let suiteName = "mudsnote.library-multi-note-actions-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-multi-note-actions-tests-\(UUID().uuidString)", isDirectory: true)
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
        let firstURL = try store.saveNewNote(title: "Multi One", body: "First body")
        let secondURL = try store.saveNewNote(title: "Multi Two", body: "Second body")
        let projectFolder = try store.createFolder(named: "Batch Project")

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let selectableRows = (0..<controller.tableView.numberOfRows).filter { row in
            guard let url = controller.tableView(
                controller.tableView,
                pasteboardWriterForRow: row
            ) as? NSURL else { return false }
            return [firstURL.standardizedFileURL.path, secondURL.standardizedFileURL.path].contains((url as URL).standardizedFileURL.path)
        }
        #expect(selectableRows.count == 2)
        controller.tableView.selectRowIndexes(IndexSet(selectableRows), byExtendingSelection: false)

        let selectedPaths = controller.selectedMarkdownFileURLsForLibrary().map(\.path)
        #expect(selectedPaths.count == 2)
        #expect(selectedPaths.contains(firstURL.standardizedFileURL.path))
        #expect(selectedPaths.contains(secondURL.standardizedFileURL.path))
        #expect(controller.noteDragPreviewCountForLibrary(rowIndexes: IndexSet(selectableRows)) == 2)
        #expect(controller.noteDragPreviewBadgeTitleForLibrary(rowIndexes: IndexSet(selectableRows)) == "2")
        let dragPreview = try #require(controller.noteDragPreviewImageForLibrary(rowIndexes: IndexSet(selectableRows)))
        #expect(dragPreview.size.width >= 240)
        #expect(dragPreview.size.height >= 60)
        #expect(controller.noteDragPreviewBadgeTitleForLibrary(rowIndexes: IndexSet(integer: selectableRows[0])) == nil)
        let exportMenu = controller.makeExportMenuForLibrary()
        #expect(exportMenu.items.map(\.title) == [
            "复制 2 条 Markdown 内容",
            "导出 2 个 Markdown 文件..."
        ])
        #expect(exportMenu.items.allSatisfy { $0.isEnabled })
        let moreMenu = controller.makeMoreActionsMenuForLibrary()
        #expect(moreMenu.items.first { $0.title == "独立窗口打开" }?.isEnabled == false)
        #expect(moreMenu.items.contains { $0.title == "移动 2 条笔记到文件夹" })
        #expect(moreMenu.items.contains { $0.title == "在 Finder 中显示 2 个文件" })
        #expect(moreMenu.items.contains { $0.title == "复制 2 个 Markdown 路径" })
        #expect(moreMenu.items.contains { $0.title == "删除 2 条笔记" })
        #expect(!controller.validateToolbarItem(NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier("mudsnote.library.toolbar.open-separate"))))
        let multiContextMenu = try #require(controller.noteContextMenuForLibrary(row: selectableRows[0]))
        #expect(multiContextMenu.items.contains { $0.title == "移动 2 条笔记到文件夹" })
        #expect(multiContextMenu.items.contains { $0.title == "复制 2 个 Markdown 路径" })
        #expect(multiContextMenu.items.contains { $0.title == "删除 2 条笔记" })
        #expect(controller.selectedMarkdownFileURLsForLibrary().count == 2)

        controller.tableView.selectRowIndexes(IndexSet(integer: selectableRows[0]), byExtendingSelection: false)
        let secondRowURL = try #require(controller.tableView(
            controller.tableView,
            pasteboardWriterForRow: selectableRows[1]
        ) as? NSURL) as URL
        let singleContextMenu = try #require(controller.noteContextMenuForLibrary(row: selectableRows[1]))
        #expect(controller.selectedMarkdownFileURLsForLibrary().map(\.path) == [secondRowURL.standardizedFileURL.path])
        #expect(singleContextMenu.items.contains { $0.title == "移到文件夹" })
        #expect(singleContextMenu.items.contains { $0.title == "复制 Markdown 路径" })
        #expect(singleContextMenu.items.contains { $0.title == "删除" })
        #expect(!singleContextMenu.items.contains { $0.title == "删除 2 条笔记" })
        #expect(controller.noteContextMenuForLibrary(row: 0) == nil)
        #expect(controller.selectedMarkdownFileURLsForLibrary().map(\.path) == [secondRowURL.standardizedFileURL.path])

        let copiedPaths = try #require(controller.copySelectedMarkdownPathForLibrary())
        #expect(copiedPaths == secondRowURL.standardizedFileURL.path)
        controller.tableView.selectRowIndexes(IndexSet(selectableRows), byExtendingSelection: false)

        let multiCopiedPaths = try #require(controller.copySelectedMarkdownPathForLibrary())
        #expect(multiCopiedPaths.contains(firstURL.standardizedFileURL.path))
        #expect(multiCopiedPaths.contains(secondURL.standardizedFileURL.path))
        #expect(multiCopiedPaths.contains("\n"))

        let copiedMarkdown = try #require(try controller.copySelectedMarkdownContentForLibrary())
        #expect(copiedMarkdown.contains("Multi One"))
        #expect(copiedMarkdown.contains("First body"))
        #expect(copiedMarkdown.contains("Multi Two"))
        #expect(copiedMarkdown.contains("Second body"))
        #expect(copiedMarkdown.contains("\n\n---\n\n"))

        let exportDirectory = root.appendingPathComponent("Exports", isDirectory: true)
        let exportedURLs = try controller.exportSelectedMarkdownFilesForLibrary(to: exportDirectory)
        #expect(exportedURLs.count == 2)
        #expect(exportedURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(Set(exportedURLs.map(\.lastPathComponent)) == Set([firstURL.lastPathComponent, secondURL.lastPathComponent]))

        let movedURLs = try controller.moveSelectedNotesForLibrary(to: projectFolder)
        #expect(movedURLs.count == 2)
        #expect(movedURLs.allSatisfy {
            $0.deletingLastPathComponent().standardizedFileURL.path == projectFolder.standardizedFileURL.path
        })
        #expect(movedURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(!FileManager.default.fileExists(atPath: firstURL.path))
        #expect(!FileManager.default.fileExists(atPath: secondURL.path))

        let movedRows = (0..<controller.tableView.numberOfRows).filter { row in
            guard let url = controller.tableView(
                controller.tableView,
                pasteboardWriterForRow: row
            ) as? NSURL else { return false }
            return Set(movedURLs.map(\.standardizedFileURL.path)).contains((url as URL).standardizedFileURL.path)
        }
        #expect(movedRows.count == 2)
        controller.tableView.selectRowIndexes(IndexSet(movedRows), byExtendingSelection: false)

        try controller.deleteSelectedNotesForLibrary()
        #expect(movedURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        #expect(store.listTrashedNotes(limit: 10).count == 2)
    }

    @MainActor
    @Test
    func libraryWindowEditorToolbarInsertsRichMarkdownTools() throws {
        let suiteName = "mudsnote.library-editor-tools-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-editor-tools-tests-\(UUID().uuidString)", isDirectory: true)
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
        let noteURL = try store.saveNewNote(title: "Editor Tools", body: "plain")
        let sourceAttachment = root.appendingPathComponent("source file.pdf")
        try "attachment".write(to: sourceAttachment, atomically: true, encoding: .utf8)

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let window = try #require(controller.window)
        let toolbarItemIDs = Set((window.toolbar?.items ?? []).map(\.itemIdentifier.rawValue))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.editor-tools"))
        let editorToolsView = try #require((window.toolbar?.items ?? []).first {
            $0.itemIdentifier.rawValue == "mudsnote.library.toolbar.editor-tools"
        }?.view)
        let editorToolButtons = editorToolsView.allSubviews.compactMap { $0 as? NSButton }
        #expect(editorToolButtons.count == 5)
        let sourceModeButton = try #require(editorToolButtons.first {
            $0.identifier?.rawValue == "mudsnote.library.toolbar.source-mode"
        })
        #expect(sourceModeButton.toolTip == "显示 Markdown 源码")
        #expect(NSApp.sendAction(try #require(sourceModeButton.action), to: sourceModeButton.target, from: sourceModeButton))
        #expect(controller.editorTextView.string == "# Editor Tools\n\nplain")
        #expect(sourceModeButton.toolTip == "显示渲染模式")
        #expect(NSApp.sendAction(try #require(sourceModeButton.action), to: sourceModeButton.target, from: sourceModeButton))
        #expect(sourceModeButton.toolTip == "显示 Markdown 源码")
        let bodyRange = try #require(
            (controller.editorTextView.string as NSString).range(of: "plain").location == NSNotFound
                ? nil
                : (controller.editorTextView.string as NSString).range(of: "plain")
        )
        controller.editorTextView.setSelectedRange(bodyRange)

        let contextMenu = NSMenu()
        let contextEvent = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))
        controller.editorTextView.configureContextMenu?(contextMenu, contextEvent)
        let insertMenu = try #require(contextMenu.items.last { $0.title == "插入" }?.submenu)
        #expect(insertMenu.items.map(\.title) == ["表格", "链接…", "附件…"])
        #expect(insertMenu.items.allSatisfy { $0.image != nil })

        let initialFormatMenu = controller.makeFormatMenuForLibrary()
        #expect(initialFormatMenu.items.filter { !$0.isSeparatorItem }.map(\.title) == [
            "标题", "副标题", "小标题", "正文",
            "加粗", "斜体", "下划线", "删除线",
            "待办列表", "项目符号列表", "编号列表"
        ])
        #expect(initialFormatMenu.items.first { $0.title == "正文" }?.state == .on)
        #expect(initialFormatMenu.items.first { $0.title == "副标题" }?.keyEquivalent == "2")
        #expect(initialFormatMenu.items.first { $0.title == "副标题" }?.keyEquivalentModifierMask == [.command, .option])
        #expect(initialFormatMenu.items.first { $0.title == "待办列表" }?.keyEquivalentModifierMask == [.command, .shift])

        let subtitleItem = try #require(initialFormatMenu.items.first { $0.title == "副标题" })
        #expect(NSApp.sendAction(try #require(subtitleItem.action), to: subtitleItem.target, from: subtitleItem))
        #expect(MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme) == "# Editor Tools\n\n## plain")
        let subtitleMenu = controller.makeFormatMenuForLibrary()
        #expect(subtitleMenu.items.first { $0.title == "副标题" }?.state == .on)
        let selectedSubtitleItem = try #require(subtitleMenu.items.first { $0.title == "副标题" })
        #expect(NSApp.sendAction(try #require(selectedSubtitleItem.action), to: selectedSubtitleItem.target, from: selectedSubtitleItem))
        #expect(MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme) == "# Editor Tools\n\n## plain")

        let bodyItem = try #require(controller.makeFormatMenuForLibrary().items.first { $0.title == "正文" })
        #expect(NSApp.sendAction(try #require(bodyItem.action), to: bodyItem.target, from: bodyItem))
        #expect(MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme) == "# Editor Tools\n\nplain")
        let checklistItem = try #require(controller.makeFormatMenuForLibrary().items.first { $0.title == "待办列表" })
        #expect(NSApp.sendAction(try #require(checklistItem.action), to: checklistItem.target, from: checklistItem))
        #expect(MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme) == "# Editor Tools\n\n- [ ] plain")
        let resetBodyItem = try #require(controller.makeFormatMenuForLibrary().items.first { $0.title == "正文" })
        #expect(NSApp.sendAction(try #require(resetBodyItem.action), to: resetBodyItem.target, from: resetBodyItem))
        #expect(MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme) == "# Editor Tools\n\nplain")

        controller.editorTextView.setSelectedRange(bodyRange)
        let selectionMenu = try #require(controller.makeSelectionFormattingMenuForLibrary())
        #expect(selectionMenu.items.map(\.title) == [
            "加粗", "斜体", "下划线", "删除线", "高亮", "转换为"
        ])
        #expect(selectionMenu.items.allSatisfy { $0.image != nil })
        #expect(selectionMenu.items.last?.submenu?.items.map(\.title) == [
            "正文", "标题", "副标题", "小标题", "项目符号列表", "编号列表", "待办列表"
        ])
        #expect(selectionMenu.items.last?.submenu?.items.allSatisfy { $0.image != nil } == true)
        let highlightItem = try #require(selectionMenu.items.first { $0.title == "高亮" })
        controller.editorTextView.undoManager?.removeAllActions()
        #expect(NSApp.sendAction(try #require(highlightItem.action), to: highlightItem.target, from: highlightItem))
        #expect(MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme) == "# Editor Tools\n\n<mark>plain</mark>")
        #expect(controller.editorTextView.undoManager?.canUndo == true)
        controller.editorTextView.undoManager?.undo()
        #expect(MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme) == "# Editor Tools\n\nplain")
        controller.editorTextView.undoManager?.redo()
        #expect(MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme) == "# Editor Tools\n\n<mark>plain</mark>")
        let highlightedSelectionMenu = try #require(controller.makeSelectionFormattingMenuForLibrary())
        let activeHighlightItem = try #require(highlightedSelectionMenu.items.first { $0.title == "高亮" })
        #expect(activeHighlightItem.state == .on)
        #expect(NSApp.sendAction(try #require(activeHighlightItem.action), to: activeHighlightItem.target, from: activeHighlightItem))
        #expect(MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme) == "# Editor Tools\n\nplain")

        controller.editorTextView.showSelectionMenuIfNeeded()
        #expect(controller.editorTextView.isSelectionFormattingPanelVisible)
        let selectionPanelSubviews: [NSView] = (window.childWindows ?? []).flatMap { childWindow in
            childWindow.contentView?.allSubviews ?? []
        }
        let selectionPanelButtons = selectionPanelSubviews.compactMap { $0 as? NSButton }
        let formattingButton = try #require(selectionPanelButtons.first { $0.toolTip == "加粗" })
        NSCursor.iBeam.set()
        formattingButton.mouseEntered(with: contextEvent)
        #expect(NSCursor.current === NSCursor.arrow)
        NSCursor.iBeam.set()
        formattingButton.performClick(nil)
        #expect(NSCursor.current === NSCursor.arrow)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        #expect(NSCursor.current === NSCursor.arrow)
        #expect(controller.editorTextView.isSelectionFormattingPanelVisible)
        #expect(controller.makeSelectionFormattingMenuForLibrary()?.items.first { $0.title == "加粗" }?.state == .on)
        let refreshedSelectionPanelButtons: [NSButton] = (window.childWindows ?? []).flatMap { childWindow in
            childWindow.contentView?.allSubviews.compactMap { $0 as? NSButton } ?? []
        }
        #expect(refreshedSelectionPanelButtons.first { $0.toolTip == "加粗" } === formattingButton)

        let underlineButton = try #require(refreshedSelectionPanelButtons.first { $0.toolTip == "下划线" })
        underlineButton.performClick(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        #expect((controller.editorTextView.textStorage?.attribute(.underlineStyle, at: bodyRange.location, effectiveRange: nil) as? Int) == NSUnderlineStyle.single.rawValue)
        controller.editorTextView.textStorage?.addAttribute(.underlineColor, value: NSColor.controlAccentColor, range: bodyRange)
        underlineButton.performClick(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        #expect(controller.editorTextView.textStorage?.attribute(.underlineStyle, at: bodyRange.location, effectiveRange: nil) == nil)
        #expect(controller.editorTextView.textStorage?.attribute(.underlineColor, at: bodyRange.location, effectiveRange: nil) == nil)
        #expect(controller.editorTextView.typingAttributes[.underlineStyle] == nil)

        controller.editorTextView.undoManager?.removeAllActions()
        let boldShortcut = try keyEvent(keyCode: UInt16(kVK_ANSI_B), modifiers: [.command], characters: "b")
        #expect(controller.editorTextView.performKeyEquivalent(with: boldShortcut))
        #expect(MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme) == "# Editor Tools\n\nplain")
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        #expect(controller.editorTextView.performKeyEquivalent(with: boldShortcut))
        #expect(MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme) == "# Editor Tools\n\n**plain**")
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        let undoShortcut = try keyEvent(keyCode: UInt16(kVK_ANSI_Z), modifiers: [.command], characters: "z")
        #expect(controller.editorTextView.performKeyEquivalent(with: undoShortcut))
        #expect(MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme) == "# Editor Tools\n\nplain")
        controller.editorTextView.undoManager?.redo()
        #expect(MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme) == "# Editor Tools\n\n**plain**")

        controller.editorTextView.setSelectedRange(NSRange(location: controller.editorTextView.attributedString().length, length: 0))
        let checklistButton = try #require(editorToolButtons.first {
            $0.identifier?.rawValue == "mudsnote.library.toolbar.checklist"
        })
        #expect(NSApp.sendAction(try #require(checklistButton.action), to: checklistButton.target, from: checklistButton))

        controller.insertTableForLibrary()
        controller.insertLinkForLibrary(label: "Muds", url: "https://muds.top")
        let copiedAttachment = try controller.insertAttachmentReferenceForLibrary(from: sourceAttachment)

        #expect(FileManager.default.fileExists(atPath: copiedAttachment.path))
        #expect(copiedAttachment.path.contains("/Attachments/"))
        var editorAttachmentMarkdowns: [String] = []
        var editorAttachmentFilePaths: [String] = []
        var editorAttachmentMetadata: [String] = []
        var editorAttachmentRange: NSRange?
        controller.editorTextView.attributedString().enumerateAttribute(
            .qmAttachmentMarkdown,
            in: NSRange(location: 0, length: controller.editorTextView.attributedString().length)
        ) { value, _, _ in
            if let value = value as? String {
                editorAttachmentMarkdowns.append(value)
            }
        }
        controller.editorTextView.attributedString().enumerateAttribute(
            .qmAttachmentFilePath,
            in: NSRange(location: 0, length: controller.editorTextView.attributedString().length)
        ) { value, range, _ in
            if let value = value as? String {
                editorAttachmentFilePaths.append(value)
                if value == copiedAttachment.path {
                    editorAttachmentRange = range
                }
            }
        }
        controller.editorTextView.attributedString().enumerateAttribute(
            .qmAttachmentMetadata,
            in: NSRange(location: 0, length: controller.editorTextView.attributedString().length)
        ) { value, _, _ in
            if let value = value as? String {
                editorAttachmentMetadata.append(value)
            }
        }
        #expect(editorAttachmentMarkdowns.contains { $0.contains("source%20file.pdf") })
        #expect(editorAttachmentFilePaths.contains(copiedAttachment.path))
        #expect(editorAttachmentMetadata.contains { $0.hasPrefix("PDF · ") })
        let attachmentMenu = NSMenu()
        let insertedAttachmentMarkdown = try #require(editorAttachmentMarkdowns.first { $0.contains("source%20file.pdf") })
        #expect(controller.configureAttachmentContextMenu(
            attachmentMenu,
            forAttachmentPath: copiedAttachment.path,
            markdown: insertedAttachmentMarkdown
        ))
        #expect(Array(attachmentMenu.items.map(\.title).prefix(5)) == [
            "快速查看",
            "打开附件",
            "在 Finder 中显示",
            "复制 Markdown 链接",
            "复制附件路径"
        ])
        #expect(attachmentMenu.items[0].representedObject as? String == copiedAttachment.path)
        #expect(attachmentMenu.items[1].representedObject as? String == copiedAttachment.path)
        #expect(attachmentMenu.items[2].representedObject as? String == copiedAttachment.path)
        #expect((attachmentMenu.items[3].representedObject as? String)?.contains("source%20file.pdf") == true)
        #expect(attachmentMenu.items[4].representedObject as? String == copiedAttachment.path)

        controller.editorTextView.setSelectedRange(try #require(editorAttachmentRange))
        #expect(controller.editorTextView.fileAttachmentReferenceNearSelection()?.path == copiedAttachment.path)
        let spaceEvent = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: UInt16(kVK_Space)
        ))
        #expect(controller.markdownTextView(controller.editorTextView, handleKeyDown: spaceEvent))
        #expect(controller.attachmentQuickLookController.previewedURL == copiedAttachment.standardizedFileURL)
        controller.attachmentQuickLookController.dismiss()

        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(!controller.markdownTextView(controller.editorTextView, handleKeyDown: spaceEvent))

        _ = try controller.saveCurrentNoteForLibrary()

        let saved = try store.loadNote(at: noteURL)
        #expect(saved.body.contains("**plain**"))
        #expect(saved.body.contains("- [ ]"))
        #expect(saved.body.contains("| Column 1 | Column 2 |"))
        #expect(saved.body.contains("[Muds](https://muds.top)"))
        #expect(saved.body.contains("[source file](Attachments/"))
        #expect(saved.body.contains("source%20file.pdf"))
        let attachmentCell = try #require(controller.tableView(controller.tableView, viewFor: nil, row: 1) as? LibraryNoteCellView)
        #expect(!attachmentCell.attachmentImageView.isHidden)
        #expect(controller.noteListSearchResultsForLibrary().first?.hasAttachments == true)
    }

    @MainActor
    @Test
    func libraryAndFloatingEditorsPasteFilesAndImagesAsLocalMarkdownAttachments() throws {
        let suiteName = "mudsnote.attachment-paste-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-attachment-paste-tests-\(UUID().uuidString)", isDirectory: true)
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
        let noteURL = try store.saveNewNote(title: "Paste Attachments", body: "Start")
        let sourceFile = root.appendingPathComponent("source file.pdf")
        try "PDF fixture".write(to: sourceFile, atomically: true, encoding: .utf8)
        let pngData = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="))

        let filePasteboard = NSPasteboard.withUniqueName()
        filePasteboard.clearContents()
        #expect(filePasteboard.writeObjects([sourceFile as NSURL]))
        guard case .files(let pastedFileURLs) = MarkdownAttachmentStorage.pastePayload(from: filePasteboard) else {
            Issue.record("Expected file paste payload")
            return
        }
        #expect(pastedFileURLs == [sourceFile])

        let imagePasteboard = NSPasteboard.withUniqueName()
        imagePasteboard.clearContents()
        #expect(imagePasteboard.setData(pngData, forType: .png))
        guard case .imagePNG(let pastedPNGData) = MarkdownAttachmentStorage.pastePayload(from: imagePasteboard) else {
            Issue.record("Expected image paste payload")
            return
        }
        #expect(pastedPNGData == pngData)

        let libraryController = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { libraryController.close() }
        libraryController.editorTextView.setSelectedRange(NSRange(
            location: libraryController.editorTextView.attributedString().length,
            length: 0
        ))
        libraryController.window?.makeFirstResponder(libraryController.editorTextView)
        libraryController.editorTextView.pasteboardForPaste = { filePasteboard }
        let pasteEvent = try keyEvent(
            keyCode: UInt16(kVK_ANSI_V),
            modifiers: [.command],
            characters: "v"
        )
        #expect(libraryController.editorTextView.performKeyEquivalent(with: pasteEvent))
        #expect(libraryController.editorTextView.pasteContents(from: imagePasteboard))

        let libraryMarkdown = MarkdownRichTextCodec.serialize(
            libraryController.editorTextView.attributedString(),
            theme: libraryController.theme
        )
        #expect(libraryMarkdown.contains("[source file](Attachments/"))
        #expect(libraryMarkdown.contains("source%20file.pdf"))
        #expect(libraryMarkdown.contains("![Image](Attachments/"))
        var pastedImageMarkdown: String?
        libraryController.editorTextView.attributedString().enumerateAttribute(
            .qmImageMarkdown,
            in: NSRange(location: 0, length: libraryController.editorTextView.attributedString().length)
        ) { value, _, stop in
            if let value = value as? String {
                pastedImageMarkdown = value
                stop.pointee = true
            }
        }
        #expect(pastedImageMarkdown?.contains("Attachments/") == true)

        _ = try libraryController.saveCurrentNoteForLibrary()
        let saved = try store.loadNote(at: noteURL)
        #expect(saved.body.contains("[source file](Attachments/"))
        #expect(saved.body.contains("![Image](Attachments/"))

        let storedAttachments = FileManager.default.enumerator(
            at: store.notesDirectory.appendingPathComponent("Attachments", isDirectory: true),
            includingPropertiesForKeys: [.isRegularFileKey]
        )?.allObjects.compactMap { $0 as? URL } ?? []
        #expect(storedAttachments.contains { $0.lastPathComponent == "source file.pdf" })
        #expect(storedAttachments.contains { $0.pathExtension.lowercased() == "png" })

        let harness = try makeEditorControllerHarness(
            draftID: "floating-attachment-paste",
            showsSaveButton: false,
            configureStore: { configuredStore in
                configuredStore.notesDirectory = root.appendingPathComponent("Floating Notes", isDirectory: true)
            }
        )
        defer { harness.tearDown() }
        let floatingController = harness.controller
        floatingController.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "Floating",
            theme: floatingController.theme
        ))
        floatingController.editorTextView.setSelectedRange(NSRange(location: 8, length: 0))
        #expect(floatingController.editorTextView.pasteContents(from: imagePasteboard))
        let floatingMarkdown = MarkdownRichTextCodec.serialize(
            floatingController.editorTextView.attributedString(),
            theme: floatingController.theme
        )
        #expect(floatingMarkdown.contains("![Image](Attachments/"))
        #expect(FileManager.default.fileExists(atPath: floatingController.selectedDirectoryURL
            .appendingPathComponent("Attachments", isDirectory: true).path))
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

    @MainActor
    @Test
    func libraryAndFloatingEditorsManageMarkdownLinks() throws {
        let suiteName = "mudsnote.link-management-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-link-management-tests-\(UUID().uuidString)", isDirectory: true)
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
        _ = try store.saveNewNote(title: "Links", body: "[Muds](https://muds.top)")

        let libraryController = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { libraryController.close() }

        let linkLocation = (libraryController.editorTextView.string as NSString).range(of: "Muds").location
        let libraryLink = try #require(libraryController.editorTextView.linkReference(atCharacterIndex: linkLocation))
        #expect(libraryLink.range == NSRange(location: linkLocation, length: 4))
        #expect(libraryLink.label == "Muds")
        #expect(libraryLink.url == "https://muds.top")
        #expect(libraryController.editorTextView.linkReference(for: NSRange(location: linkLocation + 1, length: 0))?.url == "https://muds.top")
        #expect(libraryController.editorTextView.linkReference(for: NSRange(location: linkLocation + 1, length: 2))?.url == "https://muds.top")
        #expect(libraryController.editorTextView.linkReference(for: NSRange(location: linkLocation, length: 5)) == nil)
        #expect(openableMarkdownLinkURL("muds.top")?.absoluteString == "https://muds.top")
        #expect(openableMarkdownLinkURL("custom-scheme:value") == nil)

        libraryController.editorTextView.setSelectedRange(NSRange(location: linkLocation + 1, length: 0))
        libraryController.linkPressed()
        let linkSheet = try #require(libraryController.window?.attachedSheet)
        let destinationField = try #require(linkSheet.contentView?.allSubviews.first {
            $0.identifier?.rawValue == "LinkEditorDestinationField"
        } as? NSTextField)
        let nameField = try #require(linkSheet.contentView?.allSubviews.first {
            $0.identifier?.rawValue == "LinkEditorNameField"
        } as? NSTextField)
        #expect(destinationField.stringValue == "https://muds.top")
        #expect(nameField.stringValue == "Muds")
        destinationField.stringValue = "https://example.com"
        let confirmButton = try #require(linkSheet.contentView?.allSubviews.first {
            $0.identifier?.rawValue == "LinkEditorConfirmButton"
        } as? NSButton)
        #expect(NSApp.sendAction(try #require(confirmButton.action), to: confirmButton.target, from: confirmButton))
        #expect(MarkdownRichTextCodec.serialize(
            libraryController.editorTextView.attributedString(),
            theme: libraryController.theme
        ) == "[Muds](https://example.com)")

        let libraryMenu = NSMenu()
        let editedLibraryLink = try #require(libraryController.editorTextView.linkReference(atCharacterIndex: linkLocation))
        #expect(libraryController.configureLinkContextMenuForLibrary(libraryMenu, for: editedLibraryLink))
        #expect(libraryMenu.items.map(\.title) == ["打开链接", "编辑链接...", "复制链接", "移除链接"])
        let copyItem = try #require(libraryMenu.items.dropFirst(2).first)
        #expect(NSApp.sendAction(try #require(copyItem.action), to: copyItem.target, from: copyItem))
        #expect(NSPasteboard.general.string(forType: .string) == "https://example.com")

        libraryController.updateLinkForLibrary(editedLibraryLink, label: "Example", url: "https://example.com")
        #expect(MarkdownRichTextCodec.serialize(
            libraryController.editorTextView.attributedString(),
            theme: libraryController.theme
        ) == "[Example](https://example.com)")

        let updatedLibraryLink = try #require(libraryController.editorTextView.linkReference(atCharacterIndex: linkLocation))
        libraryController.updateLinkForLibrary(updatedLibraryLink, url: nil)
        #expect(MarkdownRichTextCodec.serialize(
            libraryController.editorTextView.attributedString(),
            theme: libraryController.theme
        ) == "Example")
        #expect(libraryController.editorTextView.linkReference(atCharacterIndex: linkLocation) == nil)

        let harness = try makeEditorControllerHarness(draftID: "link-management", showsSaveButton: false)
        defer { harness.tearDown() }
        let floatingController = harness.controller
        floatingController.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "[OpenAI](https://openai.com)",
            theme: floatingController.theme
        ))
        let floatingLink = try #require(floatingController.editorTextView.linkReference(atCharacterIndex: 0))
        let floatingMenu = NSMenu()
        #expect(floatingController.configureLinkContextMenu(floatingMenu, for: floatingLink))
        #expect(floatingMenu.items.map(\.title) == ["打开链接", "编辑链接...", "复制链接", "移除链接"])

        floatingController.applyLinkURL("https://platform.openai.com", label: "Platform", to: floatingLink)
        #expect(MarkdownRichTextCodec.serialize(
            floatingController.editorTextView.attributedString(),
            theme: floatingController.theme
        ) == "[Platform](https://platform.openai.com)")

        let undoManager = try #require(floatingController.editorTextView.undoManager)
        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(MarkdownRichTextCodec.serialize(
            floatingController.editorTextView.attributedString(),
            theme: floatingController.theme
        ) == "[OpenAI](https://openai.com)")
        undoManager.redo()
        #expect(MarkdownRichTextCodec.serialize(
            floatingController.editorTextView.attributedString(),
            theme: floatingController.theme
        ) == "[Platform](https://platform.openai.com)")

        let updatedFloatingLink = try #require(floatingController.editorTextView.linkReference(atCharacterIndex: 0))
        floatingController.applyLinkURL(nil, to: updatedFloatingLink)
        #expect(MarkdownRichTextCodec.serialize(
            floatingController.editorTextView.attributedString(),
            theme: floatingController.theme
        ) == "Platform")
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
        let linkLocation = (navigationController.editorTextView.string as NSString).range(of: "Target").location
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
    func libraryTableButtonAddsRowsInsideExistingMarkdownTables() throws {
        let suiteName = "mudsnote.library-table-editing-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-table-editing-tests-\(UUID().uuidString)", isDirectory: true)
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
        _ = try store.saveNewNote(
            title: "Table Editing",
            body: """
            | Name | Status |
            | --- | --- |
            | Alpha | Todo |
            """
        )

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let alphaLocation = (controller.editorTextView.string as NSString).range(of: "Alpha").location
        #expect(alphaLocation != NSNotFound)
        controller.editorTextView.setSelectedRange(NSRange(location: alphaLocation, length: 0))
        controller.insertTableForLibrary()

        var tableMarkdown = MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme)
        #expect(tableMarkdown.components(separatedBy: "\n") == [
            "| Name | Status |",
            "| --- | --- |",
            "| Alpha | Todo |",
            "|  |  |"
        ])

        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: """
            | Name | Status |
            | --- | --- |
            | Alpha | Todo |
            """,
            theme: controller.theme
        ))
        let headerLocation = (controller.editorTextView.string as NSString).range(of: "Name").location
        #expect(headerLocation != NSNotFound)
        controller.editorTextView.setSelectedRange(NSRange(location: headerLocation, length: 0))
        controller.insertTableForLibrary()

        tableMarkdown = MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme)
        #expect(tableMarkdown.components(separatedBy: "\n") == [
            "| Name | Status |",
            "| --- | --- |",
            "|  |  |",
            "| Alpha | Todo |"
        ])

        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "Plain paragraph",
            theme: controller.theme
        ))
        controller.editorTextView.setSelectedRange(NSRange(location: controller.editorTextView.attributedString().length, length: 0))
        controller.insertTableForLibrary()
        tableMarkdown = MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme)
        #expect(tableMarkdown.contains("| Column 1 | Column 2 |"))
        #expect(tableMarkdown.contains("| --- | --- |"))
    }

    @MainActor
    @Test
    func libraryEditorTabsBetweenMarkdownTableCells() throws {
        let suiteName = "mudsnote.library-table-tab-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-table-tab-tests-\(UUID().uuidString)", isDirectory: true)
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
        _ = try store.saveNewNote(
            title: "Table Tabs",
            body: """
            | Name | Status |
            | --- | --- |
            | Alpha | Todo |
            """
        )

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let text = controller.editorTextView.string as NSString
        let alphaLocation = text.range(of: "Alpha").location
        let todoLocation = text.range(of: "Todo").location
        #expect(alphaLocation != NSNotFound)
        #expect(todoLocation != NSNotFound)

        controller.editorTextView.setSelectedRange(NSRange(location: alphaLocation, length: 0))
        #expect(controller.textView(controller.editorTextView, doCommandBy: #selector(NSResponder.insertTab(_:))))
        #expect(controller.editorTextView.selectedRange().location == todoLocation)
        #expect(controller.editorTextView.typingAttributes[.qmTableID] != nil)
        #expect(controller.editorTextView.typingAttributes[.qmTablePlaceholder] == nil)

        #expect(controller.textView(controller.editorTextView, doCommandBy: #selector(NSResponder.insertBacktab(_:))))
        #expect(controller.editorTextView.selectedRange().location == alphaLocation)

        controller.editorTextView.setSelectedRange(NSRange(location: todoLocation, length: 0))
        #expect(controller.textView(controller.editorTextView, doCommandBy: #selector(NSResponder.insertTab(_:))))
        let tableMarkdown = MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme)
        #expect(tableMarkdown.components(separatedBy: "\n") == [
            "| Name | Status |",
            "| --- | --- |",
            "| Alpha | Todo |",
            "|  |  |"
        ])
        let insertedRowRange = try #require(tableCellRange(row: 2, column: 0, in: controller.editorTextView.attributedString()))
        #expect(controller.editorTextView.selectedRange().location == insertedRowRange.location)
        #expect(controller.editorTextView.typingAttributes[.qmTableID] != nil)
        #expect(controller.editorTextView.typingAttributes[.qmTablePlaceholder] == nil)

        #expect(controller.textView(controller.editorTextView, doCommandBy: #selector(NSResponder.insertBacktab(_:))))
        #expect(controller.editorTextView.selectedRange().location == todoLocation)

        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "Plain paragraph",
            theme: controller.theme
        ))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(!controller.textView(controller.editorTextView, doCommandBy: #selector(NSResponder.insertTab(_:))))
    }

    @MainActor
    @Test
    func libraryEditorCommandDeleteRemovesMarkdownTableDataRows() throws {
        let suiteName = "mudsnote.library-table-delete-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-table-delete-tests-\(UUID().uuidString)", isDirectory: true)
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
        _ = try store.saveNewNote(
            title: "Table Delete",
            body: """
            | Name | Status |
            | --- | --- |
            | Alpha | Todo |
            | Beta | Done |
            """
        )

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let deleteEvent = try keyEvent(keyCode: UInt16(kVK_Delete), modifiers: [.command], characters: "\u{7F}")
        var text = controller.editorTextView.string as NSString
        let alphaLocation = text.range(of: "Alpha").location
        #expect(alphaLocation != NSNotFound)
        controller.editorTextView.setSelectedRange(NSRange(location: alphaLocation, length: 0))
        controller.editorTextView.keyDown(with: deleteEvent)

        var tableMarkdown = MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme)
        #expect(tableMarkdown.components(separatedBy: "\n") == [
            "| Name | Status |",
            "| --- | --- |",
            "| Beta | Done |"
        ])
        let remainingBetaLocation = (controller.editorTextView.string as NSString).range(of: "Beta").location
        #expect(remainingBetaLocation != NSNotFound)
        #expect(controller.editorTextView.selectedRange().location == remainingBetaLocation)

        text = controller.editorTextView.string as NSString
        let betaLocation = text.range(of: "Beta").location
        #expect(betaLocation != NSNotFound)
        controller.editorTextView.setSelectedRange(NSRange(location: betaLocation, length: 0))
        controller.editorTextView.keyDown(with: deleteEvent)

        tableMarkdown = MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme)
        #expect(tableMarkdown.components(separatedBy: "\n") == [
            "| Name | Status |",
            "| --- | --- |"
        ])

        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: """
            | Name | Status |
            | --- | --- |
            | Alpha | Todo |
            """,
            theme: controller.theme
        ))
        let headerLocation = (controller.editorTextView.string as NSString).range(of: "Name").location
        #expect(headerLocation != NSNotFound)
        controller.editorTextView.setSelectedRange(NSRange(location: headerLocation, length: 0))
        #expect(!controller.markdownTextView(controller.editorTextView, handleKeyDown: deleteEvent))

        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "Plain paragraph",
            theme: controller.theme
        ))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 0))
        #expect(!controller.markdownTextView(controller.editorTextView, handleKeyDown: deleteEvent))
    }

    @MainActor
    @Test
    func libraryEditorTableContextMenuEditsMarkdownRowsAndColumns() throws {
        let suiteName = "mudsnote.library-table-menu-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-table-menu-tests-\(UUID().uuidString)", isDirectory: true)
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
        _ = try store.saveNewNote(
            title: "Table Menu",
            body: """
            | Name | Status |
            | --- | --- |
            | Alpha | Todo |
            """
        )

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let headerLocation = (controller.editorTextView.string as NSString).range(of: "Name").location
        #expect(headerLocation != NSNotFound)
        let headerMenu = NSMenu()
        #expect(controller.configureMarkdownTableContextMenuForLibrary(headerMenu, atCharacterIndex: headerLocation))
        #expect(headerMenu.items.map(\.title) == ["插入表格行", "插入右侧列", "删除表格行", "删除表格列"])
        let headerInsertRowItem = try #require(headerMenu.items.first)
        let headerInsertColumnItem = try #require(headerMenu.items.dropFirst().first)
        let headerDeleteRowItem = try #require(headerMenu.items.dropFirst(2).first)
        let headerDeleteColumnItem = try #require(headerMenu.items.last)
        #expect(headerInsertRowItem.isEnabled)
        #expect(headerInsertColumnItem.isEnabled)
        #expect(!headerDeleteRowItem.isEnabled)
        #expect(!headerDeleteColumnItem.isEnabled)
        #expect(NSApp.sendAction(try #require(headerInsertColumnItem.action), to: headerInsertColumnItem.target, from: headerInsertColumnItem))

        var tableMarkdown = MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme)
        #expect(tableMarkdown.components(separatedBy: "\n") == [
            "| Name |  | Status |",
            "| --- | --- | --- |",
            "| Alpha |  | Todo |"
        ])
        let insertedColumnLocation = try #require(tableCellRange(row: 0, column: 1, in: controller.editorTextView.attributedString())).location
        let columnMenu = NSMenu()
        #expect(controller.configureMarkdownTableContextMenuForLibrary(columnMenu, atCharacterIndex: insertedColumnLocation))
        #expect(columnMenu.items.map(\.title) == ["插入表格行", "插入右侧列", "删除表格行", "删除表格列"])
        let deleteColumnItem = try #require(columnMenu.items.last)
        #expect(deleteColumnItem.isEnabled)
        #expect(NSApp.sendAction(try #require(deleteColumnItem.action), to: deleteColumnItem.target, from: deleteColumnItem))

        tableMarkdown = MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme)
        #expect(tableMarkdown.components(separatedBy: "\n") == [
            "| Name | Status |",
            "| --- | --- |",
            "| Alpha | Todo |"
        ])

        #expect(NSApp.sendAction(try #require(headerInsertRowItem.action), to: headerInsertRowItem.target, from: headerInsertRowItem))

        tableMarkdown = MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme)
        #expect(tableMarkdown.components(separatedBy: "\n") == [
            "| Name | Status |",
            "| --- | --- |",
            "|  |  |",
            "| Alpha | Todo |"
        ])

        let alphaLocation = (controller.editorTextView.string as NSString).range(of: "Alpha").location
        #expect(alphaLocation != NSNotFound)
        let dataMenu = NSMenu()
        #expect(controller.configureMarkdownTableContextMenuForLibrary(dataMenu, atCharacterIndex: alphaLocation))
        #expect(dataMenu.items.map(\.title) == ["插入表格行", "插入右侧列", "删除表格行", "删除表格列"])
        let dataDeleteRowItem = try #require(dataMenu.items.dropFirst(2).first)
        let dataDeleteColumnItem = try #require(dataMenu.items.last)
        #expect(dataDeleteRowItem.isEnabled)
        #expect(dataDeleteRowItem.keyEquivalent == "\u{7F}")
        #expect(dataDeleteRowItem.keyEquivalentModifierMask == [.command])
        #expect(!dataDeleteColumnItem.isEnabled)
        #expect(NSApp.sendAction(try #require(dataDeleteRowItem.action), to: dataDeleteRowItem.target, from: dataDeleteRowItem))

        tableMarkdown = MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme)
        #expect(tableMarkdown.components(separatedBy: "\n") == [
            "| Name | Status |",
            "| --- | --- |",
            "|  |  |"
        ])

        let paragraphLocation = (controller.editorTextView.string as NSString).length
        let paragraphMenu = NSMenu()
        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "Plain paragraph",
            theme: controller.theme
        ))
        #expect(!controller.configureMarkdownTableContextMenuForLibrary(paragraphMenu, atCharacterIndex: paragraphLocation))
        #expect(paragraphMenu.items.isEmpty)
    }

    @MainActor
    @Test
    func libraryWindowAutosavesEditedExistingNote() async throws {
        let suiteName = "mudsnote.library-autosave-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-autosave-tests-\(UUID().uuidString)", isDirectory: true)
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
        let noteURL = try store.saveNewNote(title: "Autosave Seed", body: "Original body")
        let writeThreadRecorder = ThreadObservationRecorder()
        let sourceCountThreadRecorder = ThreadObservationRecorder()
        let oldModifiedAt = Date().addingTimeInterval(-86_400)
        try FileManager.default.setAttributes([.modificationDate: oldModifiedAt], ofItemAtPath: noteURL.path)

        let controller = LibraryWindowController(
            noteStore: store,
            backgroundAutosaveWillPersist: writeThreadRecorder.recordCurrentThread,
            backgroundSourceCountWillLoad: sourceCountThreadRecorder.recordCurrentThread,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        await controller.waitForNoteLinksRefreshForLibrary()
        await controller.waitForSourceCountRefreshForLibrary()
        let displayedTimeBeforeEdit = controller.statusLabel.stringValue
        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "# Autosave Seed\n\nAutosaved body",
            theme: controller.theme,
            baseURL: noteURL
        ))
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.editorTextView))

        #expect(controller.statusLabel.stringValue == displayedTimeBeforeEdit)

        controller.flushBackgroundAutosaveForTesting()
        let loaded = try store.loadNote(at: noteURL)
        #expect(loaded.title == "Autosave Seed")
        #expect(loaded.body == "Autosaved body")
        #expect(!writeThreadRecorder.didObserveMainThread())
        #expect(controller.statusLabel.stringValue != displayedTimeBeforeEdit)
        #expect(!controller.statusLabel.stringValue.contains("保存"))
        #expect(controller.statusLabel.accessibilityValue() == controller.statusLabel.stringValue)
        #expect(controller.statusLabel.toolTip == nil)
        #expect(controller.noteListSearchResultsForLibrary().first?.snippet == "Autosaved body")
        await controller.waitForNoteLinksRefreshForLibrary()
        await controller.waitForSourceCountRefreshForLibrary()
        #expect(controller.sourceCountTextForLibrary(titled: "Notes") == "1")
        #expect(!sourceCountThreadRecorder.didObserveMainThread())
    }

    @MainActor
    @Test
    func libraryBackgroundAutosaveCoalescesToLatestEditorRevision() async throws {
        let suiteName = "mudsnote.library-autosave-coalescing-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-autosave-coalescing-tests-\(UUID().uuidString)", isDirectory: true)
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
        let noteURL = try store.saveNewNote(title: "Coalescing", body: "Original")
        let recorder = BlockingAutosaveRecorder()
        let controller = LibraryWindowController(
            noteStore: store,
            backgroundAutosaveWillPersist: recorder.record,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        controller.editorTextView.string = "First revision"
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

        controller.editorTextView.string = "Latest revision"
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.editorTextView))
        controller.triggerBackgroundAutosaveForTesting()
        recorder.releaseFirstWrite.signal()
        await controller.waitForBackgroundAutosaveForTesting()

        #expect(try store.loadNote(at: noteURL).body == "Latest revision")
        #expect(!controller.currentNoteHasUnsavedChangesForLibrary)
        let observation = recorder.snapshot()
        #expect(observation.callCount == 2)
        #expect(!observation.observedMainThread)
    }

    @MainActor
    @Test
    func libraryNavigationDoesNotWaitForMatchingBackgroundAutosave() async throws {
        let suiteName = "mudsnote.library-autosave-navigation-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-autosave-navigation-tests-\(UUID().uuidString)", isDirectory: true)
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
        _ = try store.saveNewNote(title: "First note", body: "First body")
        _ = try store.saveNewNote(title: "Second note", body: "Second body")
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

        let editedURL = try #require(controller.selectedMarkdownFileURLForLibrary())
        let displayedTimeBeforeEdit = controller.statusLabel.stringValue
        controller.editorTextView.string = "Edited without blocking navigation"
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
        #expect(controller.statusLabel.stringValue == displayedTimeBeforeEdit)

        let otherRow = try #require((0..<controller.tableView.numberOfRows).first { row in
            guard let writer = controller.tableView(
                controller.tableView,
                pasteboardWriterForRow: row
            ) as? NSURL else {
                return false
            }
            return (writer as URL).standardizedFileURL != editedURL.standardizedFileURL
        })
        let selectionStartedAt = Date()
        controller.tableView.selectRowIndexes(IndexSet(integer: otherRow), byExtendingSelection: false)
        let selectionDuration = Date().timeIntervalSince(selectionStartedAt)

        #expect(selectionDuration < 0.15)
        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL != editedURL.standardizedFileURL)
        #expect(!controller.statusLabel.stringValue.contains("保存"))

        recorder.releaseFirstWrite.signal()
        await controller.waitForBackgroundAutosaveForTesting()
        #expect(try store.loadNote(at: editedURL).body == "Edited without blocking navigation")
        #expect(!controller.statusLabel.stringValue.contains("保存"))
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
        controller.editorTextView.string = "Existing updated body"
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
    func floatingDraftAutosaveDoesNotReplaceStatusText() throws {
        let harness = try makeEditorControllerHarness(draftID: "quiet-autosave-status", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let statusBeforeEdit = controller.statusLabel.stringValue

        controller.editorTextView.string = "Quiet draft"
        controller.markDocumentDirty()
        #expect(controller.statusLabel.stringValue == statusBeforeEdit)

        try controller.persistDraft(force: true)
        #expect(controller.statusLabel.stringValue == statusBeforeEdit)
        #expect(harness.store.loadDraft(id: "quiet-autosave-status")?.title == "Quiet draft")
    }

    @MainActor
    @Test
    func floatingDraftAutosaveWritesOffMainAndClearsMatchingRevision() async throws {
        let recorder = DraftPersistenceRecorder()
        let harness = try makeEditorControllerHarness(
            draftID: "background-draft-autosave",
            showsSaveButton: false,
            saveDraftSnapshot: recorder.record
        )
        defer { harness.tearDown() }
        let controller = harness.controller

        controller.editorTextView.string = "Background draft"
        controller.markDocumentDirty()
        await controller.flushPendingDraftAutosaveForTesting()

        let recorded = recorder.snapshot()
        #expect(recorded.savedTitles == ["Background draft"])
        #expect(!recorded.observedMainThread)
        #expect(!controller.isDirty)
    }

    @MainActor
    @Test
    func floatingReturnInsertsNewlineAndAutosavesWithoutCrashing() async throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        controller.editorTextView.string = "Before"
        controller.editorTextView.setSelectedRange(NSRange(location: 6, length: 0))

        controller.editorTextView.keyDown(with: try keyEvent(
            keyCode: UInt16(kVK_Return),
            modifiers: [],
            characters: "\r",
            windowNumber: controller.window?.windowNumber ?? 0
        ))
        await Task.yield()
        await controller.flushPendingDraftAutosaveForTesting()

        #expect(controller.editorTextView.string == "Before\n")
        #expect(harness.store.loadDraft(id: controller.currentDraftID)?.title == "Before")
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
    func libraryNoteListShowsImageAttachmentThumbnail() throws {
        let suiteName = "mudsnote.library-thumbnail-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-thumbnail-tests-\(UUID().uuidString)", isDirectory: true)
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
            title: "Image Attachment",
            body: "![Preview](Attachments/thumb.png)"
        )
        let imageURL = noteURL.deletingLastPathComponent()
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent("thumb.png")
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let pngData = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="))
        try pngData.write(to: imageURL)

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let cell = try #require(controller.tableView(controller.tableView, viewFor: nil, row: 1) as? LibraryNoteCellView)
        let decodeCountAfterFirstCell = controller.thumbnailImageDecodeCountForLibrary
        let reusedThumbnailCell = try #require(controller.tableView(
            controller.tableView,
            viewFor: nil,
            row: 1
        ) as? LibraryNoteCellView)

        #expect(controller.noteListSearchResultsForLibrary().first?.thumbnailURL?.path == imageURL.standardizedFileURL.path)
        #expect(!cell.thumbnailImageView.isHidden)
        #expect(cell.thumbnailImageView.image != nil)
        #expect(cell.thumbnailImageView.constraints.contains {
            $0.firstAttribute == .width && $0.constant == 44
        })
        #expect(cell.thumbnailImageView.constraints.contains {
            $0.firstAttribute == .height && $0.constant == 44
        })
        #expect(cell.attachmentImageView.isHidden)
        #expect(reusedThumbnailCell.thumbnailImageView.image != nil)
        #expect(controller.thumbnailImageDecodeCountForLibrary == decodeCountAfterFirstCell)
        #expect(decodeCountAfterFirstCell == 1)

        var editorHasImagePreview = false
        let editorContent = controller.editorTextView.attributedString()
        editorContent.enumerateAttribute(.attachment, in: NSRange(location: 0, length: editorContent.length)) { value, _, stop in
            guard value as? NSTextAttachment != nil else { return }
            editorHasImagePreview = true
            stop.pointee = true
        }
        #expect(editorHasImagePreview)
        #expect(MarkdownRichTextCodec.serialize(editorContent, theme: controller.theme) == "![Preview](Attachments/thumb.png)")
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
    func libraryWindowSearchScopesAndHighlightsMatches() throws {
        let suiteName = "mudsnote.library-search-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-search-tests-\(UUID().uuidString)", isDirectory: true)
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
        let projectsFolder = try store.createFolder(named: "Projects")
        let archiveFolder = try store.createFolder(named: "Archive")
        _ = try store.saveNewNote(title: "Alpha Project", body: "current folder alpha body", in: projectsFolder)
        _ = try store.saveNewNote(title: "Archive Note", body: "global alpha body", in: archiveFolder)

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let window = try #require(controller.window)
        controller.loadSourceFoldersForLibrary()
        let scopeControl = try #require((window.toolbar?.items ?? []).flatMap { item in
            item.view?.allSubviews.compactMap { $0 as? NSSegmentedControl } ?? []
        }.first {
            $0.identifier?.rawValue == "LibrarySearchScopeControl"
        })
        #expect(scopeControl.selectedSegment == 0)
        #expect(scopeControl.isHidden)

        #expect(controller.selectSourceForLibrary(titled: "Projects"))

        controller.searchForLibrary(query: "alpha", allNotes: false)
        let scopedSearchSession = try #require(controller.activeSearchSessionForLibrary())
        #expect(!scopeControl.isHidden)
        #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["Alpha Project"])
        #expect(controller.noteListSearchResultsForLibrary().first?.snippet == "current folder alpha body")
        #expect(controller.noteListTitleLabel.stringValue == "Projects")
        #expect(controller.noteListCountLabel.stringValue == "1 条结果")

        let cell = try #require(controller.tableView(controller.tableView, viewFor: nil, row: 1) as? LibraryNoteCellView)
        let titleHighlight = cell.titleLabel.attributedStringValue.attribute(
            .backgroundColor,
            at: 0,
            effectiveRange: nil
        )
        let snippetRange = (cell.snippetLabel.attributedStringValue.string as NSString).range(of: "alpha")
        let snippetHighlight = cell.snippetLabel.attributedStringValue.attribute(
            .backgroundColor,
            at: snippetRange.location,
            effectiveRange: nil
        )
        #expect(titleHighlight != nil)
        #expect(snippetRange.location != NSNotFound)
        #expect(snippetHighlight != nil)

        let fieldEditor = NSTextView()
        #expect(controller.control(controller.searchField, textView: fieldEditor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        let editorText = controller.editorTextView.attributedString()
        let editorMatchRange = (editorText.string as NSString).range(of: "alpha")
        #expect(editorMatchRange.location != NSNotFound)
        #expect(editorText.attribute(.qmSearchHighlight, at: editorMatchRange.location, effectiveRange: nil) != nil)
        #expect(editorText.attribute(.backgroundColor, at: editorMatchRange.location, effectiveRange: nil) != nil)
        #expect(MarkdownRichTextCodec.serialize(editorText, theme: controller.theme) == "current folder alpha body")

        #expect(controller.control(controller.searchField, textView: fieldEditor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(controller.searchField.stringValue.isEmpty)
        #expect(controller.activeSearchSessionForLibrary() == nil)
        #expect(controller.editorTextView.attributedString().attribute(.qmSearchHighlight, at: editorMatchRange.location, effectiveRange: nil) == nil)
        let removalScanCount = controller.editorSearchHighlightRemovalScanCountForLibrary
        controller.removeEditorSearchHighlights()
        #expect(controller.editorSearchHighlightRemovalScanCountForLibrary == removalScanCount)
        controller.textDidChange(Notification(
            name: NSText.didChangeNotification,
            object: controller.editorTextView
        ))
        #expect(controller.editorSearchHighlightRemovalScanCountForLibrary == removalScanCount)

        controller.searchForLibrary(query: "alpha", allNotes: true)
        let allNotesSearchSession = try #require(controller.activeSearchSessionForLibrary())
        let allTitles = Set(controller.noteListSearchResultsForLibrary().map(\.title))
        #expect(allTitles == Set(["Alpha Project", "Archive Note"]))
        #expect(scopeControl.selectedSegment == 1)
        #expect(controller.noteListTitleLabel.stringValue == "所有 iCloud 笔记")
        #expect(controller.noteListCountLabel.stringValue == "2 条结果")

        controller.searchForLibrary(query: "not-present-anywhere", allNotes: true)
        #expect(controller.activeSearchSessionForLibrary() === allNotesSearchSession)
        #expect(scopedSearchSession !== allNotesSearchSession)
        let emptyLabel = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.first {
            $0.identifier?.rawValue == "LibraryNoteListEmptyLabel"
        })
        #expect(controller.noteListSearchResultsForLibrary().isEmpty)
        #expect(controller.tableView.numberOfRows == 0)
        #expect(!emptyLabel.isHidden)
        #expect(emptyLabel.stringValue == "没有结果")
    }

    @MainActor
    @Test
    func librarySearchFieldKeyboardNavigatesResultsAndClearsQuery() throws {
        let suiteName = "mudsnote.library-search-keyboard-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-search-keyboard-tests-\(UUID().uuidString)", isDirectory: true)
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
        _ = try store.saveNewNote(title: "Alpha First", body: "first keyboard body")
        _ = try store.saveNewNote(title: "Alpha Last", body: "last keyboard body")
        _ = try store.saveNewNote(title: "Beta Note", body: "other body")

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        controller.searchForLibrary(query: "alpha", allNotes: true)
        controller.tableView.deselectAll(nil)
        let fieldEditor = NSTextView()
        let firstResultTitle = try #require(controller.noteListSearchResultsForLibrary().first?.title)
        let lastResultTitle = try #require(controller.noteListSearchResultsForLibrary().last?.title)

        #expect(controller.control(controller.searchField, textView: fieldEditor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        #expect(controller.tableView.selectedRow == 1)
        #expect(controller.control(controller.searchField, textView: fieldEditor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        #expect(controller.tableView.selectedRow == 2)

        #expect(controller.control(controller.searchField, textView: fieldEditor, doCommandBy: #selector(NSResponder.moveUp(_:))))
        #expect(controller.tableView.selectedRow == 1)

        #expect(controller.control(controller.searchField, textView: fieldEditor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(controller.titleField.stringValue == firstResultTitle)
        #expect(MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme).contains("keyboard body"))

        controller.searchForLibrary(query: "alpha", allNotes: true)
        controller.tableView.deselectAll(nil)
        #expect(controller.control(controller.searchField, textView: fieldEditor, doCommandBy: #selector(NSResponder.moveUp(_:))))
        #expect(controller.tableView.selectedRow == 2)
        #expect(controller.control(controller.searchField, textView: fieldEditor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(controller.titleField.stringValue == lastResultTitle)

        #expect(controller.control(controller.searchField, textView: fieldEditor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(controller.searchField.stringValue.isEmpty)
        #expect(controller.searchScopeControl.isHidden)
        #expect(controller.noteListTitleLabel.stringValue == "Notes")
    }

    @MainActor
    @Test
    func librarySearchFieldDebouncesTypingButFlushesKeyboardActions() async throws {
        let suiteName = "mudsnote.library-search-debounce-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-search-debounce-tests-\(UUID().uuidString)", isDirectory: true)
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
        _ = try store.saveNewNote(title: "Alpha Debounced", body: "debounced body")
        _ = try store.saveNewNote(title: "Beta Debounced", body: "other body")

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        controller.searchField.stringValue = "a"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.searchField))
        controller.searchField.stringValue = "alpha"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.searchField))

        #expect(controller.noteListSearchResultsForLibrary().map(\.title) != ["Alpha Debounced"])
        #expect(!controller.searchScopeControl.isHidden)
        #expect(controller.noteListCountLabel.stringValue == "正在搜索…")

        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline,
              controller.noteListSearchResultsForLibrary().map(\.title) != ["Alpha Debounced"]
                || controller.noteListCountLabel.stringValue != "1 条结果" {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["Alpha Debounced"])
        #expect(controller.noteListCountLabel.stringValue == "1 条结果")

        controller.searchField.stringValue = "beta"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.searchField))
        let fieldEditor = NSTextView()
        #expect(controller.control(controller.searchField, textView: fieldEditor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(controller.titleField.stringValue == "Beta Debounced")

        controller.searchField.stringValue = ""
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.searchField))
        #expect(controller.searchScopeControl.isHidden)
        #expect(Set(controller.noteListSearchResultsForLibrary().map(\.title)) == Set(["Alpha Debounced", "Beta Debounced"]))
        #expect(controller.noteListCountLabel.stringValue == "2 条笔记")
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
    func libraryWindowHidesEmptyTagPlaceholderLikeAppleNotes() throws {
        let suiteName = "mudsnote.library-empty-tag-source-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-empty-tag-source-tests-\(UUID().uuidString)", isDirectory: true)
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
        _ = try store.saveNewNote(title: "Plain Seed", body: "plain body")

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let window = try #require(controller.window)
        controller.loadSourceTagsForLibrary()

        #expect(controller.sourceTitlesForLibrary().filter { $0.hasPrefix("#") }.isEmpty)
        #expect(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.contains {
            $0.identifier?.rawValue == "LibrarySourceTagStatus"
        } == false)
        #expect(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.contains {
            $0.stringValue == "No Tags"
        } == false)
    }

    @MainActor
    @Test
    func libraryWindowLoadsTagRowsAfterShellIsVisible() throws {
        let suiteName = "mudsnote.library-tag-source-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-tag-source-tests-\(UUID().uuidString)", isDirectory: true)
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
        _ = try store.saveNewNote(title: "Tagged Seed", body: "tag body", tags: ["library"])
        for index in 0..<245 {
            _ = try store.saveNewNote(title: "Plain Seed \(index)", body: "plain body")
        }

        #expect(!store.libraryTagsSectionCollapsed)
        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let window = try #require(controller.window)
        #expect(!store.libraryTagsSectionCollapsed)
        #expect(!controller.sourceTitlesForLibrary().contains("library"))
        #expect(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.contains {
            $0.identifier?.rawValue == "LibrarySourceTagStatus"
        } == false)

        controller.loadSourceTagsForLibrary()
        #expect(!store.libraryTagsSectionCollapsed)

        #expect(controller.sourceTitlesForLibrary().contains("library"))
        #expect(controller.sourceCountTextForLibrary(titled: "library") == "1")
        #expect(controller.sourceCountTextForLibrary(titled: "Notes") == "246")
        #expect(controller.sourceOutlineLevelForLibrary(titled: "Notes") == 1)
        #expect(controller.sourceOutlineLevelForLibrary(titled: "library") == 1)
        #expect(controller.isSourceGroupExpandedForLibrary(titled: "iCloud") == true)
        #expect(controller.isSourceGroupExpandedForLibrary(titled: "标签") == true)
        #expect(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.contains {
            $0.identifier?.rawValue == "LibrarySourceTagStatus"
        } == false)

        controller.toggleSourceTagsSectionForLibrary()
        #expect(controller.sourceTitlesForLibrary().contains("library"))
        #expect(!controller.visibleSourceTitlesForLibrary().contains("library"))
        #expect(controller.isSourceGroupExpandedForLibrary(titled: "标签") == false)
        #expect(store.libraryTagsSectionCollapsed)

        let reopenedCollapsedTagsController = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { reopenedCollapsedTagsController.close() }
        reopenedCollapsedTagsController.loadSourceTagsForLibrary()
        #expect(reopenedCollapsedTagsController.sourceTitlesForLibrary().contains("library"))
        #expect(!reopenedCollapsedTagsController.visibleSourceTitlesForLibrary().contains("library"))
        #expect(reopenedCollapsedTagsController.isSourceGroupExpandedForLibrary(titled: "标签") == false)

        controller.toggleSourceTagsSectionForLibrary()
        #expect(!store.libraryTagsSectionCollapsed)
        #expect(controller.visibleSourceTitlesForLibrary().contains("library"))
        #expect(controller.isSourceGroupExpandedForLibrary(titled: "标签") == true)

        #expect(controller.selectSourceForLibrary(titled: "library"))
        #expect(controller.noteListTitleLabel.stringValue == "#library")
        #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["Tagged Seed"])
    }

    @MainActor
    @Test
    func libraryWindowShowsNestedFoldersInSourceList() throws {
        let suiteName = "mudsnote.library-nested-folder-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-nested-folder-tests-\(UUID().uuidString)", isDirectory: true)
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
        let projectsFolder = try store.createFolder(named: "Projects")
        let clientFolder = projectsFolder.appendingPathComponent("Client", isDirectory: true)
        try FileManager.default.createDirectory(at: clientFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: store.notesDirectory.appendingPathComponent(NoteStore.attachmentDirectoryName, isDirectory: true),
            withIntermediateDirectories: true
        )
        _ = try store.saveNewNote(title: "Client Seed", body: "Nested body", in: clientFolder)

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let window = try #require(controller.window)
        #expect(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.contains {
            $0.identifier?.rawValue == "LibrarySourceFolderStatus"
        } == false)
        controller.loadSourceFoldersForLibrary()
        #expect(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.contains {
            $0.identifier?.rawValue == "LibrarySourceFolderStatus"
        } == false)
        #expect(controller.sourceCountTextForLibrary(titled: "Notes") == "1")
        #expect(controller.visibleSourceTitlesForLibrary().contains("Projects"))
        #expect(!controller.visibleSourceTitlesForLibrary().contains("Client"))
        #expect(!controller.sourceTitlesForLibrary().contains(NoteStore.attachmentDirectoryName))
        #expect(controller.sourceOutlineLevelForLibrary(titled: "Notes") == 1)
        #expect(controller.sourceOutlineLevelForLibrary(titled: "Projects") == 2)
        #expect(controller.sourceOutlineLevelForLibrary(titled: "Client") == 3)
        #expect(controller.sourceOutlineLevelForLibrary(titled: "最近删除") == 1)
        #expect(controller.isSourceGroupExpandedForLibrary(titled: "iCloud") == true)

        controller.toggleSourceFoldersSectionForLibrary()
        #expect(store.libraryFoldersSectionCollapsed)
        #expect(controller.isSourceGroupExpandedForLibrary(titled: "iCloud") == false)
        #expect(!controller.visibleSourceTitlesForLibrary().contains("Notes"))
        #expect(!controller.visibleSourceTitlesForLibrary().contains("Projects"))

        controller.toggleSourceFoldersSectionForLibrary()
        #expect(!store.libraryFoldersSectionCollapsed)
        #expect(controller.isSourceGroupExpandedForLibrary(titled: "iCloud") == true)
        #expect(controller.visibleSourceTitlesForLibrary().contains("Notes"))
        #expect(controller.visibleSourceTitlesForLibrary().contains("Projects"))

        #expect(window.contentView?.allSubviews.compactMap { $0 as? NSButton }.contains {
            $0.identifier?.rawValue == "LibrarySourceGroup-Folders"
        } == false)
        #expect(controller.visibleSourceTitlesForLibrary().contains("Projects"))
        #expect(!controller.isSourceFolderExpandedForLibrary(projectsFolder))
        #expect(controller.setSourceFolderExpandedForLibrary(projectsFolder, expanded: true))
        #expect(controller.visibleSourceTitlesForLibrary().contains("Client"))
        #expect(controller.selectSourceForLibrary(titled: "Client"))

        #expect(controller.noteListTitleLabel.stringValue == "Client")
        #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["Client Seed"])
        #expect(controller.canMoveSelectedNotesFromMenuForLibrary)
        #expect(controller.makeMoveNoteMenuForLibrary().items.contains { item in
            item.representedObject as? URL == projectsFolder.standardizedFileURL
        })

        let moveMenu = try #require(controller.makeMoreActionsMenuForLibrary().items.first {
            $0.title == "移到文件夹"
        }?.submenu)
        let clientMoveItem = try #require(moveMenu.items.first {
            $0.representedObject as? URL == clientFolder.standardizedFileURL
        })
        #expect(clientMoveItem.title.hasPrefix("    "))
        #expect(clientMoveItem.title.trimmingCharacters(in: .whitespaces) == "Client")

        #expect(controller.isSourceFolderExpandedForLibrary(projectsFolder))
        #expect(controller.setSourceFolderExpandedForLibrary(projectsFolder, expanded: false))
        #expect(controller.noteListTitleLabel.stringValue == "Projects")
        #expect(!controller.visibleSourceTitlesForLibrary().contains("Client"))

        #expect(controller.setSourceFolderExpandedForLibrary(projectsFolder, expanded: true))
        #expect(controller.visibleSourceTitlesForLibrary().contains("Client"))
        #expect(store.libraryExpandedFolderPaths.contains(projectsFolder.standardizedFileURL.path))

        let reopenedController = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { reopenedController.close() }
        reopenedController.loadSourceFoldersForLibrary()
        #expect(reopenedController.visibleSourceTitlesForLibrary().contains("Client"))
    }

    @MainActor
    @Test
    func folderDisclosureProjectsLoadedSnapshotWithoutSynchronousRescan() throws {
        let suiteName = "mudsnote.folder-snapshot-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-folder-snapshot-tests-\(UUID().uuidString)", isDirectory: true)
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
        let projectsFolder = try store.createFolder(named: "Projects")
        let clientFolder = projectsFolder.appendingPathComponent("Client", isDirectory: true)
        try FileManager.default.createDirectory(at: clientFolder, withIntermediateDirectories: true)

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }
        _ = try #require(controller.window)
        controller.loadSourceFoldersForLibrary()
        #expect(!controller.visibleSourceTitlesForLibrary().contains("Client"))

        try FileManager.default.removeItem(at: clientFolder)
        #expect(controller.setSourceFolderExpandedForLibrary(projectsFolder, expanded: true))
        #expect(controller.visibleSourceTitlesForLibrary().contains("Client"))

        controller.loadSourceFoldersForLibrary()
        #expect(!controller.visibleSourceTitlesForLibrary().contains("Client"))
    }

    @Test
    func folderTreeProjectionMaintainsHierarchyAcrossLifecycleMutations() throws {
        let root = URL(fileURLWithPath: "/tmp/Mudsnote Projection/Notes", isDirectory: true)
        let alpha = root.appendingPathComponent("Alpha", isDirectory: true)
        let child = alpha.appendingPathComponent("Child", isDirectory: true)
        let gamma = root.appendingPathComponent("Gamma", isDirectory: true)
        let initial = [
            LibraryFolderRow(url: root, depth: 0, hasChildren: true),
            LibraryFolderRow(url: alpha, depth: 1, hasChildren: true),
            LibraryFolderRow(url: child, depth: 2, hasChildren: false),
            LibraryFolderRow(url: gamma, depth: 1, hasChildren: false)
        ]

        let beta = root.appendingPathComponent("Beta", isDirectory: true)
        let inserted = LibraryFolderTreeProjection.inserting(beta, under: root, into: initial)
        #expect(inserted.map(\.url.lastPathComponent) == ["Notes", "Alpha", "Child", "Beta", "Gamma"])
        #expect(inserted.first?.hasChildren == true)

        let zeta = root.appendingPathComponent("Zeta", isDirectory: true)
        let renamed = LibraryFolderTreeProjection.renaming(alpha, to: zeta, in: inserted)
        #expect(renamed.map(\.url.lastPathComponent) == ["Notes", "Beta", "Gamma", "Zeta", "Child"])
        #expect(renamed.last?.url == zeta.appendingPathComponent("Child", isDirectory: true))
        #expect(renamed[3].hasChildren == true)

        let withoutRenamedSubtree = LibraryFolderTreeProjection.removing(zeta, from: renamed)
        #expect(withoutRenamedSubtree.map(\.url.lastPathComponent) == ["Notes", "Beta", "Gamma"])
        let emptyRoot = LibraryFolderTreeProjection.removing(
            gamma,
            from: LibraryFolderTreeProjection.removing(beta, from: withoutRenamedSubtree)
        )
        #expect(emptyRoot == [LibraryFolderRow(url: root, depth: 0, hasChildren: false)])

        let depthThreeFolder = child.appendingPathComponent("Depth Three", isDirectory: true)
        let depthLimited = initial + [
            LibraryFolderRow(url: depthThreeFolder, depth: 3, hasChildren: false)
        ]
        let depthFourFolder = depthThreeFolder.appendingPathComponent("Depth Four", isDirectory: true)
        #expect(LibraryFolderTreeProjection.inserting(
            depthFourFolder,
            under: depthThreeFolder,
            into: depthLimited
        ) == depthLimited)
    }

    @Test
    func folderTreeProjectionStaysInteractiveAtSnapshotLimit() {
        let root = URL(fileURLWithPath: "/tmp/Mudsnote Projection Performance/Notes", isDirectory: true)
        var rows = [LibraryFolderRow(url: root, depth: 0, hasChildren: true)]
        rows.append(contentsOf: (0..<10_000).map { index in
            LibraryFolderRow(
                url: root.appendingPathComponent(String(format: "Folder %05d", index), isDirectory: true),
                depth: 1,
                hasChildren: false
            )
        })

        let insertedURL = root.appendingPathComponent("Folder 05000a", isDirectory: true)
        let clock = ContinuousClock()
        var projected: [LibraryFolderRow] = []
        let elapsed = clock.measure {
            projected = LibraryFolderTreeProjection.inserting(insertedURL, under: root, into: rows)
        }

        #expect(elapsed < .milliseconds(50))
        #expect(projected.count == 10_002)
        #expect(projected[5_002].url == insertedURL)
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
    func folderLifecycleProjectsLoadedSnapshotWithoutSynchronousRescan() async throws {
        let suiteName = "mudsnote.folder-lifecycle-snapshot-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-folder-lifecycle-snapshot-tests-\(UUID().uuidString)", isDirectory: true)
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
        _ = try store.createFolder(named: "Existing")

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }
        _ = try #require(controller.window)
        controller.loadSourceFoldersForLibrary()

        let externalFolder = store.notesDirectory.appendingPathComponent("External Drift", isDirectory: true)
        try FileManager.default.createDirectory(at: externalFolder, withIntermediateDirectories: true)
        let created = try controller.createLibraryFolder(named: "Created")
        #expect(controller.sourceTitlesForLibrary().contains("Created"))
        #expect(!controller.sourceTitlesForLibrary().contains("External Drift"))
        #expect(controller.selectedSourceTitleForLibrary == "Created")

        let renamed = try controller.renameSelectedFolderForLibrary(to: "Renamed")
        #expect(renamed.deletingLastPathComponent() == created.deletingLastPathComponent())
        #expect(controller.sourceTitlesForLibrary().contains("Renamed"))
        #expect(!controller.sourceTitlesForLibrary().contains("External Drift"))
        #expect(controller.selectedSourceTitleForLibrary == "Renamed")

        try controller.deleteSelectedFolderForLibrary()
        #expect(!controller.sourceTitlesForLibrary().contains("Renamed"))
        #expect(!controller.sourceTitlesForLibrary().contains("External Drift"))

        let externalNote = store.notesDirectory.appendingPathComponent("External Note.md")
        try "# External Note\n\nAdded after the internal deletion".write(
            to: externalNote,
            atomically: true,
            encoding: .utf8
        )
        controller.handleLibraryFileSystemChangesForTesting([
            LibraryFileSystemChange(
                path: renamed.appendingPathComponent("Nested.md").path,
                flags: FSEventStreamEventFlags(
                    kFSEventStreamEventFlagItemRemoved | kFSEventStreamEventFlagItemIsFile
                )
            ),
            LibraryFileSystemChange(
                path: renamed.path,
                flags: FSEventStreamEventFlags(
                    kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagItemIsDir
                )
            )
        ])
        await controller.waitForExternalLibraryRefreshForTesting()
        #expect(!controller.noteListSearchResultsForLibrary().contains { $0.title == "External Note" })
    }

    @MainActor
    @Test
    func libraryWindowCreatesMovesRenamesAndDeletesFolders() throws {
        let suiteName = "mudsnote.library-folder-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-folder-tests-\(UUID().uuidString)", isDirectory: true)
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
        let projectsFolder = try store.createFolder(named: "Projects")
        let archiveFolder = try store.createFolder(named: "Archive")

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let window = try #require(controller.window)
        controller.loadSourceFoldersForLibrary()
        #expect(controller.selectSourceForLibrary(titled: "Projects"))
        #expect(controller.selectedSourceTitleForLibrary == "Projects")

        let newItem = try #require((window.toolbar?.items ?? []).first {
            $0.itemIdentifier.rawValue == "mudsnote.library.toolbar.new-note"
        })
        let newButton = try #require(newItem.view?.allSubviews.compactMap { $0 as? NSButton }.first)
        newButton.performClick(nil)
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(
            string: "Folder Seed\nFolder body",
            attributes: controller.theme.baseAttributes(for: .paragraph)
        ))
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.editorTextView))
        _ = try controller.saveCurrentNoteForLibrary()

        let savedInProjects = try #require(store.listNotes(limit: 10, roots: [projectsFolder]).first)
        #expect(savedInProjects.title == "Folder Seed")
        let secondProjectNoteURL = try store.saveNewNote(title: "Second Drag Seed", body: "Second body", in: projectsFolder)
        let externalMarkdownURL = root.appendingPathComponent("external.md")
        try "outside library".write(to: externalMarkdownURL, atomically: true, encoding: .utf8)
        let nonMarkdownURL = root.appendingPathComponent("drag-seed.txt")
        try "not markdown".write(to: nonMarkdownURL, atomically: true, encoding: .utf8)
        let attachmentDirectory = projectsFolder.appendingPathComponent(
            NoteStore.attachmentDirectoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: attachmentDirectory, withIntermediateDirectories: true)
        let attachmentMarkdownURL = attachmentDirectory.appendingPathComponent("embedded.md")
        try "attachment markdown".write(to: attachmentMarkdownURL, atomically: true, encoding: .utf8)
        #expect(controller.canMoveDraggedNoteForLibrary(at: savedInProjects.url, to: archiveFolder))
        #expect(controller.canMoveDraggedNotesForLibrary(at: [savedInProjects.url, secondProjectNoteURL], to: archiveFolder))
        #expect(!controller.canMoveDraggedNoteForLibrary(at: savedInProjects.url, to: projectsFolder))
        #expect(!controller.canMoveDraggedNotesForLibrary(at: [savedInProjects.url, secondProjectNoteURL], to: projectsFolder))
        #expect(!controller.canMoveDraggedNotesForLibrary(at: [savedInProjects.url, externalMarkdownURL], to: archiveFolder))
        #expect(!controller.canMoveDraggedNotesForLibrary(at: [savedInProjects.url, nonMarkdownURL], to: archiveFolder))
        #expect(!controller.canMoveDraggedNoteForLibrary(at: attachmentMarkdownURL, to: archiveFolder))
        #expect(controller.sourceTitlesForLibrary().contains("Archive"))
        #expect(controller.sourceOutlineView.registeredDraggedTypes.contains(.fileURL))

        let movedURLs = try controller.moveDraggedNotesForLibrary(at: [savedInProjects.url, secondProjectNoteURL], to: archiveFolder)
        #expect(movedURLs.count == 2)
        #expect(movedURLs.allSatisfy {
            $0.deletingLastPathComponent().standardizedFileURL.path == archiveFolder.standardizedFileURL.path
        })
        let movedURL = try #require(movedURLs.first { $0.lastPathComponent == savedInProjects.url.lastPathComponent })
        #expect(movedURL.deletingLastPathComponent().standardizedFileURL.path == archiveFolder.standardizedFileURL.path)
        #expect(!controller.canMoveDraggedNoteForLibrary(at: savedInProjects.url, to: archiveFolder))
        #expect(!controller.canMoveDraggedNotesForLibrary(at: [savedInProjects.url, secondProjectNoteURL], to: archiveFolder))
        #expect(controller.canMoveDraggedNoteForLibrary(at: movedURL, to: projectsFolder))
        #expect(store.listNotes(limit: 10, roots: [projectsFolder]).isEmpty)
        let archiveTitles = store.listNotes(limit: 10, roots: [archiveFolder]).map(\.title)
        #expect(archiveTitles.contains("Folder Seed"))
        #expect(archiveTitles.contains("Second Drag Seed"))
        #expect(controller.selectedSourceTitleForLibrary == "Projects")
        #expect(controller.selectedMarkdownFileURLForLibrary() == nil)

        #expect(controller.selectSourceForLibrary(titled: "Archive"))
        let renamedArchive = try controller.renameSelectedFolderForLibrary(to: "Renamed Archive")
        #expect(FileManager.default.fileExists(atPath: renamedArchive.path))
        #expect(!FileManager.default.fileExists(atPath: archiveFolder.path))
        #expect(controller.sourceTitlesForLibrary().contains("Renamed Archive"))

        try controller.deleteSelectedFolderForLibrary()
        #expect(!FileManager.default.fileExists(atPath: renamedArchive.path))
        let trashedTitles = store.listTrashedNotes(limit: 10).map(\.title)
        #expect(trashedTitles.contains("Folder Seed"))
        #expect(trashedTitles.contains("Second Drag Seed"))
        #expect(controller.sourceCountTextForLibrary(titled: "最近删除") == "2")
    }

    @MainActor
    @Test
    func folderContextMenuMovesAndDeletesWithoutConfirmation() throws {
        let suiteName = "mudsnote.library-folder-menu-actions-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-folder-menu-actions-tests-\(UUID().uuidString)", isDirectory: true)
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
        let projects = try store.createFolder(named: "Projects")
        let archive = try store.createFolder(named: "Archive")
        let active = try store.createFolder(named: "Active", in: projects)
        _ = try store.saveNewNote(title: "Move Seed", body: "Body", in: active)

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }
        _ = try #require(controller.window)
        controller.loadSourceFoldersForLibrary()
        #expect(controller.selectSourceForLibrary(titled: "Active"))

        let contextMenu = try #require(controller.sourceContextMenuForLibrary(
            row: controller.sourceOutlineView.selectedRow
        ))
        let moveItem = try #require(contextMenu.items.first { $0.title == "移动到文件夹" })
        let moveMenu = try #require(moveItem.submenu)
        let archiveItem = try #require(moveMenu.items.first {
            $0.title.trimmingCharacters(in: .whitespaces) == "Archive"
        })
        let projectsItem = try #require(moveMenu.items.first {
            $0.title.trimmingCharacters(in: .whitespaces) == "Projects"
        })
        #expect(archiveItem.isEnabled)
        #expect(!projectsItem.isEnabled)
        #expect(!moveMenu.items.contains {
            $0.title.trimmingCharacters(in: .whitespaces) == "Active"
        })

        #expect(NSApp.sendAction(
            try #require(archiveItem.action),
            to: archiveItem.target,
            from: archiveItem
        ))
        let moved = archive.appendingPathComponent("Active", isDirectory: true)
        #expect(moved.deletingLastPathComponent().standardizedFileURL == archive.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: moved.path))
        #expect(!FileManager.default.fileExists(atPath: active.path))
        #expect(controller.selectedSourceTitleForLibrary == "Active")
        #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["Move Seed"])

        let deleteItem = NSMenuItem()
        deleteItem.representedObject = moved
        controller.deleteFolderMenuItemPressed(deleteItem)
        #expect(!FileManager.default.fileExists(atPath: moved.path))
        #expect(store.listTrashedNotes(limit: 10).map(\.title) == ["Move Seed"])
    }

    @MainActor
    @Test
    func libraryWindowCreatesRenamesAndCancelsFoldersInline() throws {
        let suiteName = "mudsnote.library-inline-folder-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-inline-folder-tests-\(UUID().uuidString)", isDirectory: true)
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

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }
        let window = try #require(controller.window)
        controller.loadSourceFoldersForLibrary()

        controller.beginInlineFolderCreationForLibrary()
        let field = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.first {
            $0.identifier?.rawValue == "LibraryInlineFolderEditField"
        })
        #expect(field.stringValue == "新建文件夹")
        #expect(window.contentView?.allSubviews.contains {
            $0.identifier?.rawValue == "LibraryInlineFolderEditRow"
        } == true)
        #expect(field.isEditable)
        #expect(field.isSelectable)
        #expect(!field.drawsBackground)
        #expect(!field.isBezeled)
        #expect(!field.isBordered)
        #expect(field.focusRingType == .none)
        #expect(field.constraints.first { $0.firstAttribute == .height }?.constant == 20)

        controller.beginInlineFolderCreationForLibrary()
        #expect(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.filter {
            $0.identifier?.rawValue == "LibraryInlineFolderEditField"
        }.count == 1)

        let fieldEditor = NSTextView()
        field.stringValue = "中文文件夹"
        #expect(controller.control(field, textView: fieldEditor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        let createdURL = store.notesDirectory.appendingPathComponent("中文文件夹", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: createdURL.path))
        #expect(controller.sourceTitlesForLibrary().contains("中文文件夹"))
        #expect(window.contentView?.allSubviews.contains {
            $0.identifier?.rawValue == "LibraryInlineFolderEditRow"
        } == false)

        controller.beginInlineFolderRenameForLibrary(at: createdURL)
        let renameField = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.first {
            $0.identifier?.rawValue == "LibraryInlineFolderEditField"
        })
        #expect(renameField.stringValue == "中文文件夹")
        #expect(!controller.visibleSourceTitlesForLibrary().contains("中文文件夹"))
        let renameEditor = NSTextView()
        renameField.stringValue = "Renamed Inline Folder"
        #expect(controller.control(renameField, textView: renameEditor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        let renamedURL = store.notesDirectory.appendingPathComponent("Renamed Inline Folder", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: renamedURL.path))
        #expect(!FileManager.default.fileExists(atPath: createdURL.path))
        #expect(controller.sourceTitlesForLibrary().contains("Renamed Inline Folder"))

        controller.beginInlineFolderCreationForLibrary()
        let cancelledField = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.first {
            $0.identifier?.rawValue == "LibraryInlineFolderEditField"
        })
        cancelledField.stringValue = "Cancelled Folder"
        #expect(controller.control(cancelledField, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(!FileManager.default.fileExists(atPath: renamedURL.appendingPathComponent("Cancelled Folder").path))
        #expect(window.contentView?.allSubviews.contains {
            $0.identifier?.rawValue == "LibraryInlineFolderEditRow"
        } == false)
    }

    @MainActor
    @Test
    func libraryWindowRegistersRemovesAndRevealsTopLevelFoldersWithoutDeletingFiles() throws {
        let suiteName = "mudsnote.library-source-registration-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-source-registration-tests-\(UUID().uuidString)", isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let externalDirectory = root.appendingPathComponent("External Library", isDirectory: true)
        let externalNote = externalDirectory.appendingPathComponent("Keep Me.md")
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
        try "# Keep Me\n\nBody".write(to: externalNote, atomically: true, encoding: .utf8)
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
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }
        controller.loadSourceFoldersForLibrary()

        let groupMenu = try #require(controller.sourceContextMenuForLibrary(row: 0))
        #expect(groupMenu.items.map(\.title) == ["将文件夹添加到资料库…"])

        try controller.addExistingLibraryFolderForLibrary(at: externalDirectory)
        #expect(store.preferredDirectories.map(\.standardizedFileURL.path).contains(externalDirectory.standardizedFileURL.path))
        #expect(!controller.sourceTitlesForLibrary().contains("所有 iCloud 笔记"))
        #expect(controller.sourceTitlesForLibrary().contains("External Library"))
        #expect(controller.selectSourceForLibrary(titled: "External Library"))
        let externalMenu = try #require(controller.sourceContextMenuForLibrary(row: controller.sourceOutlineView.selectedRow))
        #expect(externalMenu.items.map(\.title) == ["在 Finder 中显示", "从资料库移除"])

        #expect(throws: (any Error).self) {
            try controller.addExistingLibraryFolderForLibrary(at: externalDirectory)
        }
        #expect(throws: (any Error).self) {
            try controller.addExistingLibraryFolderForLibrary(at: externalDirectory.appendingPathComponent("Nested"))
        }

        try controller.removeRegisteredLibraryFolderForLibrary(at: externalDirectory)
        #expect(!store.preferredDirectories.map(\.standardizedFileURL.path).contains(externalDirectory.standardizedFileURL.path))
        #expect(FileManager.default.fileExists(atPath: externalDirectory.path))
        #expect(FileManager.default.fileExists(atPath: externalNote.path))
        #expect(!controller.sourceTitlesForLibrary().contains("所有 iCloud 笔记"))
        #expect(!controller.sourceTitlesForLibrary().contains("External Library"))
        #expect(throws: (any Error).self) {
            try controller.removeRegisteredLibraryFolderForLibrary(at: notesDirectory)
        }
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
        while Date() < deadline, controller.editorTextView.string != "Library body" {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL.path == managedNote.standardizedFileURL.path)
        #expect(controller.titleField.stringValue == "Managed")
        #expect(controller.editorTextView.string == "Library body")
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
    func libraryWindowDeletesRestoresAndPermanentlyDeletesNotes() throws {
        let suiteName = "mudsnote.library-trash-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-trash-tests-\(UUID().uuidString)", isDirectory: true)
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
        let noteURL = try store.saveNewNote(title: "Trash Seed", body: "Body line")

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        _ = try #require(controller.window)
        let moreMenu = controller.makeMoreActionsMenuForLibrary()
        let moreMenuTitles = moreMenu.items.map(\.title)
        #expect(moreMenuTitles.contains("独立窗口打开"))
        #expect(moreMenuTitles.contains("移到文件夹"))
        #expect(moreMenuTitles.contains("保存"))
        #expect(moreMenuTitles.contains("在 Finder 中显示"))
        #expect(!moreMenuTitles.contains("分享..."))
        #expect(moreMenuTitles.contains("复制 Markdown 路径"))
        #expect(moreMenuTitles.contains("复制 Markdown 内容"))
        #expect(moreMenuTitles.contains("导出 Markdown..."))
        #expect(moreMenuTitles.contains("删除"))
        #expect(controller.selectedMarkdownFileURLForLibrary()?.path == noteURL.standardizedFileURL.path)
        #expect(controller.canDeleteSelectedNotesFromMenuForLibrary)
        #expect(!controller.canRestoreSelectedNotesFromMenuForLibrary)
        #expect(controller.revealSelectedNoteInFinderForLibrary()?.path == noteURL.standardizedFileURL.path)
        #expect(controller.copySelectedMarkdownPathForLibrary() == noteURL.standardizedFileURL.path)
        #expect(NSPasteboard.general.string(forType: .string) == noteURL.standardizedFileURL.path)
        let copiedMarkdown = try #require(try controller.copySelectedMarkdownContentForLibrary())
        #expect(copiedMarkdown.contains("Trash Seed"))
        #expect(copiedMarkdown.contains("Body line"))
        #expect(NSPasteboard.general.string(forType: .string) == copiedMarkdown)
        let exportURL = root.appendingPathComponent("Exported Toolbar Seed.md")
        #expect(try controller.exportSelectedMarkdownForLibrary(to: exportURL)?.path == exportURL.standardizedFileURL.path)
        let exportedMarkdown = try String(contentsOf: exportURL, encoding: .utf8)
        #expect(exportedMarkdown.contains("Trash Seed"))
        #expect(exportedMarkdown.contains("Body line"))
        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "Updated body",
            theme: controller.theme,
            baseURL: noteURL
        ))
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.editorTextView))
        _ = try controller.copySelectedMarkdownContentForLibrary()
        #expect(try store.loadNote(at: noteURL).body == "Updated body")

        try controller.deleteSelectedNoteForLibrary()
        #expect(!controller.canDeleteSelectedNotesFromMenuForLibrary)
        #expect(!FileManager.default.fileExists(atPath: noteURL.path))
        let trashedURL = try #require(store.listTrashedNotes(limit: 10).first?.url)
        #expect(FileManager.default.fileExists(atPath: trashedURL.path))

        #expect(controller.selectSourceForLibrary(titled: "最近删除"))
        #expect(!controller.canDeleteSelectedNotesFromMenuForLibrary)
        #expect(controller.canRestoreSelectedNotesFromMenuForLibrary)
        #expect(controller.titleField.stringValue == "Trash Seed")
        #expect(!controller.titleField.isEditable)
        #expect(!controller.editorTextView.isEditable)
        #expect(controller.sourceCountTextForLibrary(titled: "最近删除") == "1")

        let trashMoreMenu = controller.makeMoreActionsMenuForLibrary()
        let trashMenuTitles = trashMoreMenu.items.map(\.title)
        #expect(trashMenuTitles.contains("恢复"))
        #expect(trashMenuTitles.contains("永久删除"))
        let trashedNoteRow = try #require((0..<controller.tableView.numberOfRows).first { row in
            controller.tableView(controller.tableView, pasteboardWriterForRow: row) != nil
        })
        let trashContextMenu = try #require(controller.noteContextMenuForLibrary(row: trashedNoteRow))
        let trashContextTitles = trashContextMenu.items.map(\.title)
        #expect(trashContextTitles.contains("恢复"))
        #expect(trashContextTitles.contains("永久删除"))
        #expect(trashContextTitles.contains("在 Finder 中显示"))
        #expect(trashContextTitles.contains("复制 Markdown 路径"))
        #expect(!trashContextTitles.contains("移到文件夹"))
        #expect(!trashContextTitles.contains("分享..."))
        #expect(!trashContextTitles.contains("导出 Markdown..."))
        #expect(!trashContextTitles.contains("删除"))

        _ = try controller.restoreSelectedNoteForLibrary()
        #expect(controller.canDeleteSelectedNotesFromMenuForLibrary)
        #expect(!controller.canRestoreSelectedNotesFromMenuForLibrary)
        #expect(FileManager.default.fileExists(atPath: noteURL.path))
        #expect(store.listTrashedNotes(limit: 10).isEmpty)
        #expect(controller.titleField.stringValue == "Trash Seed")
        #expect(controller.titleField.isEditable)
        #expect(controller.editorTextView.isEditable)

        try controller.deleteSelectedNoteForLibrary()
        #expect(controller.selectSourceForLibrary(titled: "最近删除"))
        #expect(controller.titleField.stringValue == "Trash Seed")
        try controller.deleteSelectedNoteForLibrary()
        #expect(store.listTrashedNotes(limit: 10).isEmpty)
        #expect(controller.tableView.numberOfRows == 0)
        #expect(controller.noteListEmptyLabel.stringValue == "最近删除为空")
        #expect(!controller.noteListEmptyLabel.isHidden)
    }

    @MainActor
    @Test
    func libraryDeletionUpdatesProjectionBeforeBackgroundPersistenceCompletes() async throws {
        let suiteName = "mudsnote.library-background-delete-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-background-delete-tests-\(UUID().uuidString)", isDirectory: true)
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
        let noteURL = try store.saveNewNote(title: "Background Delete", body: "Body")
        let allowPersistence = DispatchSemaphore(value: 0)
        let threadRecorder = ThreadObservationRecorder()
        let controller = LibraryWindowController(
            noteStore: store,
            backgroundDeletionWillPersist: {
                threadRecorder.recordCurrentThread()
                _ = allowPersistence.wait(timeout: .now() + 2)
            },
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer {
            allowPersistence.signal()
            controller.close()
        }

        try controller.deleteSelectedNotesInBackgroundForLibrary()

        #expect(controller.noteListSearchResultsForLibrary().isEmpty)
        #expect(FileManager.default.fileExists(atPath: noteURL.path))
        let persistenceDeadline = ContinuousClock.now.advanced(by: .seconds(1))
        while threadRecorder.snapshot().callCount == 0,
              ContinuousClock.now < persistenceDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(threadRecorder.snapshot().callCount == 1)
        #expect(!threadRecorder.didObserveMainThread())

        allowPersistence.signal()
        await controller.waitForBackgroundDeletionsForLibrary()

        #expect(!FileManager.default.fileExists(atPath: noteURL.path))
        #expect(store.listTrashedNotes(limit: 10).first?.title == "Background Delete")
    }

    @MainActor
    @Test
    func libraryWindowNoteListKeyboardOpensAndDeletesNotes() async throws {
        let suiteName = "mudsnote.library-keyboard-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-keyboard-tests-\(UUID().uuidString)", isDirectory: true)
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
        let noteURL = try store.saveNewNote(title: "Keyboard Seed", body: "Keyboard body")
        var openedURL: URL?

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { openedURL = $0 },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        _ = try #require(controller.window)
        controller.tableView.keyDown(with: try keyEvent(keyCode: 36, modifiers: [], characters: "\r"))
        #expect(openedURL?.standardizedFileURL.path == noteURL.standardizedFileURL.path)

        controller.tableView.keyDown(with: try keyEvent(keyCode: 51, modifiers: [], characters: "\u{7F}"))
        await controller.waitForBackgroundDeletionsForLibrary()
        #expect(!FileManager.default.fileExists(atPath: noteURL.path))
        #expect(store.listTrashedNotes(limit: 10).first?.title == "Keyboard Seed")

        #expect(controller.selectSourceForLibrary(titled: "最近删除"))
        #expect(controller.titleField.stringValue == "Keyboard Seed")

        controller.tableView.keyDown(with: try keyEvent(keyCode: 117, modifiers: [], characters: "\u{F728}"))
        await controller.waitForBackgroundDeletionsForLibrary()
        #expect(store.listTrashedNotes(limit: 10).isEmpty)
        #expect(controller.tableView.numberOfRows == 0)
    }

    @MainActor
    @Test
    func libraryWindowNoteListArrowKeysSkipGroupRowsAndLoadNotes() throws {
        let suiteName = "mudsnote.library-arrow-key-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-arrow-key-tests-\(UUID().uuidString)", isDirectory: true)
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
        _ = try store.saveNewNote(title: "Older Keyboard Seed", body: "Older body")
        _ = try store.saveNewNote(title: "Newer Keyboard Seed", body: "Newer body")

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        #expect(controller.tableView(controller.tableView, isGroupRow: 0))
        #expect(controller.tableView.selectedRow == 1)
        #expect(controller.titleField.stringValue == "Newer Keyboard Seed")
        let initiallySelectedURL = try #require(controller.selectedMarkdownFileURLForLibrary())
        #expect(controller.hasCachedLoadedNoteForLibrary(at: initiallySelectedURL))

        controller.tableView.keyDown(with: try keyEvent(keyCode: 125, modifiers: [], characters: "\u{F701}"))
        #expect(controller.tableView.selectedRow == 2)
        #expect(controller.titleField.stringValue == "Older Keyboard Seed")
        let secondSelectedURL = try #require(controller.selectedMarkdownFileURLForLibrary())
        #expect(controller.hasCachedLoadedNoteForLibrary(at: secondSelectedURL))

        controller.tableView.keyDown(with: try keyEvent(keyCode: 125, modifiers: [], characters: "\u{F701}"))
        #expect(controller.tableView.selectedRow == 2)
        #expect(controller.titleField.stringValue == "Older Keyboard Seed")

        controller.tableView.keyDown(with: try keyEvent(keyCode: 126, modifiers: [], characters: "\u{F700}"))
        #expect(controller.tableView.selectedRow == 1)
        #expect(controller.titleField.stringValue == "Newer Keyboard Seed")

        controller.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        controller.tableView.keyDown(with: try keyEvent(keyCode: 125, modifiers: [], characters: "\u{F701}"))
        #expect(controller.tableView.selectedRow == 1)
        #expect(controller.titleField.stringValue == "Newer Keyboard Seed")
    }

    @MainActor
    @Test
    func libraryLoadedNoteCacheInvalidatesAfterExternalMarkdownChange() async throws {
        let suiteName = "mudsnote.library-load-cache-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-load-cache-tests-\(UUID().uuidString)", isDirectory: true)
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
        let olderURL = try store.saveNewNote(title: "Cache Older", body: "Old body")
        _ = try store.saveNewNote(title: "Cache Newer", body: "New body")

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let olderRow = try #require((0..<controller.tableView.numberOfRows).first { row in
            (controller.tableView(controller.tableView, viewFor: nil, row: row) as? LibraryNoteCellView)?
                .titleLabel.stringValue == "Cache Older"
        })
        controller.tableView.selectRowIndexes(IndexSet(integer: olderRow), byExtendingSelection: false)
        #expect(controller.editorTextView.string == "Old body")
        #expect(controller.hasCachedLoadedNoteForLibrary(at: olderURL))

        try "Cache Older\n\nExternally changed body".write(to: olderURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)],
            ofItemAtPath: olderURL.path
        )
        let newerRow = try #require((0..<controller.tableView.numberOfRows).first { row in
            (controller.tableView(controller.tableView, viewFor: nil, row: row) as? LibraryNoteCellView)?
                .titleLabel.stringValue == "Cache Newer"
        })
        controller.tableView.selectRowIndexes(IndexSet(integer: newerRow), byExtendingSelection: false)
        controller.tableView.selectRowIndexes(IndexSet(integer: olderRow), byExtendingSelection: false)
        controller.editorTextView.setSelectedRange(NSRange(location: 4, length: 0))
        await controller.waitForActiveNoteLoadForLibrary()

        #expect(controller.editorTextView.string.contains("Externally changed body"))
        #expect(controller.editorTextView.selectedRange() == NSRange(location: 4, length: 0))
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
        #expect(controller.editorTextView.string == "Async body 4")
        #expect(controller.hasCachedLoadedNoteForLibrary(at: targetURL))
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
    func externalMarkdownOpensAndSavesInPlaceInLibraryWindow() throws {
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

        let managedSavedURL = try #require(savedURL)
        #expect(!FileManager.default.fileExists(atPath: managedURL.path))
        #expect(FileManager.default.fileExists(atPath: managedSavedURL.path))
        #expect(managedSavedURL.lastPathComponent.localizedCaseInsensitiveContains("managed-updated"))
        #expect(!(controller.window is NSPanel))
        #expect(controller.selectedMarkdownFileURLForLibrary() == externalURL.standardizedFileURL)
        #expect(controller.titleField.stringValue == "Original Heading")
        #expect(controller.editorTextView.string == "Original body")
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
        #expect(previewFolderMenu.items.map(\.title) == ["在 Finder 中显示"])

        let updated = MarkdownRichTextCodec.render(markdown: "Updated body", theme: controller.theme)
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
        #expect(controller.editorTextView.string == "Visible external body")
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
    func libraryWindowVisualQASelectionLoadsRequestedContentNote() throws {
        let suiteName = "mudsnote.visual-qa-selection-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-visual-qa-selection-tests-\(UUID().uuidString)", isDirectory: true)
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
        let contentURL = try store.saveNewNote(title: "Content Visual", body: "Visible editor body")
        let emptyURL = try store.saveNewNote(title: "Empty Visual", body: "")
        let now = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-120)],
            ofItemAtPath: contentURL.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: now],
            ofItemAtPath: emptyURL.path
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
        controller.selectNoteForVisualQA(at: contentURL)

        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL == contentURL.standardizedFileURL)
        #expect(controller.titleField.stringValue == "Content Visual")
        #expect(controller.editorTextView.string == "Visible editor body")
        #expect(controller.window?.firstResponder === controller.tableView)

        controller.selectNoteForVisualQA(at: emptyURL)
        let selectedRow = controller.tableView.selectedRow
        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL == emptyURL.standardizedFileURL)
        #expect(selectedRow >= 0)
        #expect(controller.tableView.visibleRect.intersects(controller.tableView.rect(ofRow: selectedRow)))
        #expect(controller.tableView.enclosingScrollView?.contentView.bounds.origin.y == 0)
    }

    @MainActor
    @Test
    func libraryWindowDoesNotFocusSearchOnDefaultShow() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-focus-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let suiteName = "mudsnote.library-focus-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)

        let controller = LibraryWindowController(
            noteStore: store,
            defersInitialNoteHydration: true,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer {
            controller.close()
            defaults.removePersistentDomain(forName: suiteName)
        }

        controller.showWindowAndFocus()
        #expect(controller.searchField.currentEditor() == nil)
        #expect(controller.window?.firstResponder === controller.tableView)
    }

    @MainActor
    @Test
    func libraryWindowDeferredShowLoadsFirstNoteWithoutFocusingSearch() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-deferred-focus-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let suiteName = "mudsnote.library-deferred-focus-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        _ = try store.saveNewNote(title: "Deferred Seed", body: "Deferred body")

        let controller = LibraryWindowController(
            noteStore: store,
            defersInitialNoteHydration: true,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer {
            controller.close()
            defaults.removePersistentDomain(forName: suiteName)
        }

        #expect(controller.sourceCountTextForLibrary(titled: "Notes") == "")
        controller.showWindowAndFocus()
        #expect(controller.noteListCountLabel.stringValue == "1 条笔记")
        let initialListTitle = try #require(controller.noteListSearchResultsForLibrary().first?.title)
        #expect(controller.titleField.stringValue == initialListTitle)
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline,
              controller.editorTextView.string != "Deferred body"
                || controller.sourceCountTextForLibrary(titled: "Notes") != "1" {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(controller.searchField.currentEditor() == nil)
        #expect(controller.titleField.stringValue == "Deferred Seed")
        #expect(controller.editorTextView.string == "Deferred body")
        #expect(controller.sourceCountTextForLibrary(titled: "Notes") == "1")
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
        #expect(controller.editorTextView.string == "Cached body is immediate")
        #expect(!controller.editorTextView.isEditable)
        #expect(!controller.hasReleasedDeferredLaunchWorkForLibrary)

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, controller.editorTextView.string != "Fresh source body" {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(controller.editorTextView.string == "Fresh source body")
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
        while Date() < deadline, controller.editorTextView.string != "First body wins" {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(controller.editorTextView.string == "First body wins")
        #expect(controller.hasReleasedDeferredLaunchWorkForLibrary)
    }

    @MainActor
    @Test
    func libraryWindowRestoresCountsAndTagsFromPresentationCacheBeforeShow() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-presentation-cache-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let suiteName = "mudsnote.library-presentation-cache-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let notes = [
            NoteSearchResult(
                url: store.notesDirectory.appendingPathComponent("One.md"),
                title: "One",
                snippet: "",
                modifiedAt: Date(),
                tags: ["cached-tag"]
            ),
            NoteSearchResult(
                url: store.notesDirectory.appendingPathComponent("Two.md"),
                title: "Two",
                snippet: "",
                modifiedAt: Date().addingTimeInterval(-60),
                tags: ["cached-tag", "second-tag"]
            )
        ]
        store.cacheLibraryPresentationSnapshot(notes)

        let controller = LibraryWindowController(
            noteStore: store,
            defersInitialNoteHydration: true,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        #expect(controller.noteListCountLabel.stringValue == "2 条笔记")
        #expect(controller.sourceCountTextForLibrary(titled: "cached-tag") == "2")
        #expect(controller.sourceCountTextForLibrary(titled: "second-tag") == "1")
    }

    @MainActor
    @Test
    func libraryWindowRestoresLastVisibleDocumentBeforeSlowFileRefresh() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-launch-cache-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let suiteName = "mudsnote.library-launch-cache-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let noteURL = try store.saveNewNote(title: "Cached Launch", body: "Immediate cached body")
        let cachedDocument = try store.loadNoteDocument(at: noteURL)
        store.cacheLibraryLaunchNote(cachedDocument, at: noteURL, modifiedAt: Date())

        let controller = LibraryWindowController(
            noteStore: store,
            defersInitialNoteHydration: true,
            noteLoader: { url in
                Thread.sleep(forTimeInterval: 1)
                let loaded = try store.loadNoteDocument(at: url)
                return (loaded.title, loaded.body, loaded.tags)
            },
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        let startedAt = ContinuousClock.now
        controller.showWindowAndFocus()
        let elapsed = startedAt.duration(to: .now)

        #expect(elapsed < .milliseconds(250))
        #expect(controller.titleField.stringValue == "Cached Launch")
        #expect(controller.editorTextView.string.contains("Immediate cached body"))
        #expect(controller.selectedMarkdownFileURLForLibrary() == noteURL.standardizedFileURL)
    }

    @MainActor
    @Test
    func libraryWindowDeferredShowSkipsMissingRecentNoteWithoutAlert() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-missing-recent-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let suiteName = "mudsnote.library-missing-recent-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        let existingURL = try store.saveNewNote(title: "Existing Recent", body: "Existing body")
        let missingURL = store.notesDirectory.appendingPathComponent("Missing Recent.md")
        defaults.set(
            [missingURL.path, existingURL.path],
            forKey: "mudsnote.recentFiles"
        )

        let controller = LibraryWindowController(
            noteStore: store,
            defersInitialNoteHydration: true,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer {
            controller.close()
            defaults.removePersistentDomain(forName: suiteName)
        }

        controller.showWindowAndFocus()
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline, controller.editorTextView.string != "Existing body" {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(controller.titleField.stringValue == "Existing Recent")
        #expect(controller.editorTextView.string == "Existing body")
        #expect(!store.listRecentFiles(limit: 5).contains { $0.url.standardizedFileURL == missingURL.standardizedFileURL })
        #expect(NSApp.modalWindow == nil)
    }

    @MainActor
    @Test
    func libraryWindowDeferredShowLoadsFirstPlainMarkdownWhenRecentsAreEmpty() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-deferred-plain-markdown-tests-\(UUID().uuidString)", isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let suiteName = "mudsnote.library-deferred-plain-markdown-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("AppSupport", isDirectory: true)
        )
        store.notesDirectory = notesDirectory
        try "# External Deferred\n\nExternal body\n".write(
            to: notesDirectory.appendingPathComponent("External Deferred.md"),
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
        defer {
            controller.close()
            defaults.removePersistentDomain(forName: suiteName)
        }

        controller.showWindowAndFocus()
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline, controller.editorTextView.string != "External body" {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(controller.noteListCountLabel.stringValue == "1 条笔记")
        #expect(controller.tableView.selectedRow >= 0)
        #expect(controller.searchField.currentEditor() == nil)
        #expect(controller.titleField.stringValue == "External Deferred")
        #expect(controller.editorTextView.string == "External body")
    }

    @Test
    func librarySourceNavigationUsesSnapshotBeforeBackgroundLibraryRefresh() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-library-navigation-snapshot-tests-\(UUID().uuidString)", isDirectory: true)
        let notesDirectory = root.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let suiteName = "mudsnote.library-navigation-snapshot-tests.\(UUID().uuidString)"
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
            defersInitialNoteHydration: true,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        try "# Background Refresh\n\nLoaded off the navigation path.\n".write(
            to: notesDirectory.appendingPathComponent("Background Refresh.md"),
            atomically: true,
            encoding: .utf8
        )
        #expect(controller.selectSourceForLibrary(titled: "Notes"))
        #expect(controller.noteListSearchResultsForLibrary().isEmpty)

        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline, controller.noteListSearchResultsForLibrary().isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["Background Refresh"])
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

        let controller = LibraryWindowController(
            noteStore: store,
            defersInitialNoteHydration: true,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

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
    func floatingSlashSuggestionsStayTextOnlyAndKeepAnEmptyStateVisible() async throws {
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

        let scrollView = try #require(
            controller.suggestionController.view.subviews.compactMap { $0 as? NSScrollView }.first
        )
        let listView = try #require(scrollView.documentView as? SuggestionListView)
        #expect(listView.items.map(\.title) == SlashCommand.allCases.map(\.title))
        #expect(listView.items.allSatisfy { $0.symbolName == nil })
        #expect(recorder.beginCalls.last?.hasMarkedText == false)
        #expect(recorder.beginCalls.last?.editorIsFirstResponder == true)

        controller.editorTextView.string = "/does-not-exist"
        controller.editorTextView.setSelectedRange(NSRange(location: 15, length: 0))
        controller.updateInlineSuggestions()
        try await Task.sleep(for: .milliseconds(10))

        guard case .slash(_, _, let commands) = controller.inlineSuggestionContext else {
            Issue.record("Expected a slash context with no command matches")
            return
        }
        #expect(commands.isEmpty)
        #expect(!controller.suggestionController.view.isHidden)
        #expect(listView.items == [
            SuggestionItem(title: "无匹配命令", subtitle: nil, symbolName: nil)
        ])
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
    func quickCaptureFooterRemovesTagActionAndAlignsRemainingControls() throws {
        let harness = try makeEditorControllerHarness(
            draftID: "quick-capture",
            showsSaveButton: true,
            configureStore: { store in
                let inbox = store.notesDirectory.appendingPathComponent("000-Inbox", isDirectory: true)
                let projects = store.notesDirectory.appendingPathComponent("100_Projects", isDirectory: true)
                let areas = store.notesDirectory.appendingPathComponent("200_Areas", isDirectory: true)
                try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
                try? FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
                try? FileManager.default.createDirectory(at: areas, withIntermediateDirectories: true)
                store.configurePreferredDirectories([store.notesDirectory], defaultDirectory: store.notesDirectory)
            }
        )
        defer { harness.tearDown() }

        let directoryButton = try #require(harness.controller.quickCaptureDirectoryButton)
        let saveButton = try #require(harness.controller.saveButton as? HoverToolbarButton)
        let cancelButton = try #require(harness.controller.cancelButton as? HoverToolbarButton)

        #expect(harness.controller.selectedDirectoryURL == harness.store.notesDirectory)
        #expect(harness.controller.quickCaptureDestinationTitle() == "Notes")
        let directoryMenu = harness.controller.makeQuickCaptureDirectoryMenu()
        #expect(directoryMenu.items.compactMap { ($0.representedObject as? URL)?.lastPathComponent } == [
            "000-Inbox",
            "200_Areas",
            "100_Projects"
        ])
        #expect(directoryMenu.items.map(\.title) == ["Inbox", "Areas", "Projects"])
        #expect(saveButton.title.isEmpty)
        #expect(saveButton.toolTip == "保存")
        #expect(saveButton.preferredSize == NSSize(width: 28, height: 28))
        #expect(cancelButton.title.isEmpty)
        #expect(cancelButton.toolTip == "取消")
        #expect(cancelButton.preferredSize == NSSize(width: 28, height: 28))
        let tagButtons = harness.controller.window?.contentView?.allSubviews
            .compactMap { $0 as? NSButton }
            .filter { $0.accessibilityIdentifier() == "QuickCapture标签Button" } ?? []
        #expect(tagButtons.isEmpty)
        #expect(directoryButton.frame.midY == cancelButton.frame.midY)
        #expect(cancelButton.frame.midY == saveButton.frame.midY)
        #expect(saveButton.layer?.backgroundColor == NSColor.clear.cgColor)
        #expect(cancelButton.layer?.backgroundColor == NSColor.clear.cgColor)

        let saveRestingBackground = saveButton.layer?.backgroundColor
        saveButton.highlight(true)
        #expect(saveButton.layer?.backgroundColor == saveRestingBackground)
        #expect(saveButton.alphaValue < 1)
        saveButton.highlight(false)
        #expect(saveButton.alphaValue == 1)
    }

    @MainActor
    @Test
    func quickCaptureUsesOneEditorAndRestoresLegacyDraftWithoutDuplication() throws {
        let harness = try makeEditorControllerHarness(
            draftID: "quick-capture",
            showsSaveButton: true,
            configureStore: { store in
                store.configurePreferredDirectories([store.notesDirectory], defaultDirectory: store.notesDirectory)
                try? store.saveDraft(DraftSnapshot(
                    id: "quick-capture",
                    sourcePath: nil,
                    selectedDirectoryPath: store.notesDirectory.path,
                    title: "Recovered title.",
                    body: "Recovered title. Body remains\nSecond line",
                    updatedAt: Date()
                ))
            }
        )
        defer { harness.tearDown() }
        let controller = harness.controller

        let separateTitleEditors = controller.window?.contentView?.allSubviews
            .compactMap { $0 as? FocusableTitleTextView } ?? []
        #expect(separateTitleEditors.isEmpty)
        #expect(controller.editorTextView.string == "Recovered title. Body remains\nSecond line")
        #expect(controller.currentDocument().title == "Recovered title.")
        #expect(controller.currentDocument().body == "Recovered title. Body remains\nSecond line")

        controller.showWindowAndFocus()
        #expect(controller.window?.firstResponder === controller.editorTextView)
    }

    @MainActor
    @Test
    func quickCaptureSaveUsesFirstSentenceAsTitleAndPreservesFullBody() throws {
        var savedURL: URL?
        let harness = try makeEditorControllerHarness(
            draftID: "quick-capture",
            showsSaveButton: true,
            configureStore: { store in
                store.configurePreferredDirectories([store.notesDirectory], defaultDirectory: store.notesDirectory)
            },
            onSave: { savedURL = $0 }
        )
        defer { harness.tearDown() }
        let controller = harness.controller
        controller.editorTextView.string = "\nProject / Alpha? Keep this sentence.\nSecond line"

        controller.savePressed()

        let url = try #require(savedURL)
        let saved = try harness.store.loadNote(at: url)
        #expect(saved.title == "Project / Alpha?")
        #expect(saved.body == "Project / Alpha? Keep this sentence.\nSecond line")
        #expect(!url.lastPathComponent.contains("/"))
        #expect(url.deletingLastPathComponent() == harness.store.notesDirectory)
    }

    @MainActor
    @Test
    func floatingNoteUsesHeaderChromeAndEmptyBodyPlaceholder() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller

        #expect(controller.floatingNotePlaceholderLabel?.isHidden == false)
        #expect(controller.toolbarButtonsByAction.isEmpty)
        #expect(controller.toolbarButtons.isEmpty)
        #expect(controller.toolbarButtonVisualHeight < controller.toolbarButtonHeight)
        #expect(controller.window?.contentView?.allSubviews.contains { $0 is DragHandleView } == false)
        #expect(controller.floatingNoteTitlebarChromeViews.count == 1)
        #expect(controller.floatingNoteTitlebarChromeViews.allSatisfy { $0.alphaValue == 1 })
        #expect(controller.floatingNoteBrowseButton?.toolTip == "管理悬浮笔记")
        #expect(controller.shellContentView?.subviews.contains { $0 is NSBox } == false)
        let managerButton = try #require(controller.floatingNoteBrowseButton as? HoverToolbarButton)
        #expect(managerButton.target === controller)
        #expect(managerButton.action == #selector(EditorWindowController.floatingBrowseNotesPressed(_:)))
        #expect(managerButton.superview === controller.window?.contentView)
        #expect(managerButton.accessibilityIdentifier() == "FloatingNoteManagerButton")
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let managerCenter = managerButton.convert(
            NSPoint(x: managerButton.bounds.midX, y: managerButton.bounds.midY),
            to: controller.window?.contentView
        )
        #expect(controller.window?.contentView?.hitTest(managerCenter) === managerButton)

        controller.setFloatingNoteTitlebarChromeVisible(true)

        #expect(controller.floatingNoteTitlebarChromeViews.allSatisfy { $0.alphaValue == 1 })

        controller.editorTextView.string = "qqq\nbody"
        controller.userDidEdit()

        #expect(controller.floatingNotePlaceholderLabel?.isHidden == true)
    }

    @MainActor
    @Test
    func floatingNoteCanSwitchToExistingNoteAndSaveBackToIt() throws {
        var savedURL: URL?
        let harness = try makeEditorControllerHarness(
            draftID: "floating-note",
            showsSaveButton: false,
            onSave: { savedURL = $0 }
        )
        defer { harness.tearDown() }

        try harness.store.ensureNotesDirectory()
        let noteURL = try harness.store.saveNewNote(title: "Existing", body: "Original body", in: harness.store.notesDirectory)

        harness.controller.loadFloatingNote(at: noteURL)

        #expect(harness.controller.activeFloatingNoteURL == noteURL)
        #expect(harness.controller.currentDocument().title == "Existing")
        #expect(harness.controller.currentDocument().body == "Original body")

        let updated = MarkdownRichTextCodec.render(markdown: "# Existing\n\nUpdated body", theme: harness.controller.theme)
        harness.controller.editorTextView.textStorage?.setAttributedString(updated)
        harness.controller.savePressed()

        let loaded = try harness.store.loadNote(at: noteURL)
        #expect(loaded.title == "Existing")
        #expect(loaded.body == "Updated body")
        #expect(savedURL == noteURL)
    }

    @MainActor
    @Test
    func floatingBrowseButtonDispatchesCompleteClicksToBrowserPanel() async throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller

        controller.showWindowAndFocus()
        controller.window?.setContentSize(NSSize(width: 300, height: 314))
        let managerButton = try #require(controller.floatingNoteBrowseButton)
        controller.window?.contentView?.layoutSubtreeIfNeeded()

        func dispatchClick(expectedPresentationCount: Int) async throws {
            let location = managerButton.convert(
                NSPoint(x: managerButton.bounds.midX, y: managerButton.bounds.midY),
                to: nil
            )
            let windowNumber = controller.window?.windowNumber ?? 0
            let mouseDown = try #require(NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: location,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            ))
            let mouseUp = try #require(NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: location,
                modifierFlags: [],
                timestamp: 0.01,
                windowNumber: windowNumber,
                context: nil,
                eventNumber: 2,
                clickCount: 1,
                pressure: 0
            ))
            NSApp.postEvent(mouseDown, atStart: false)
            NSApp.postEvent(mouseUp, atStart: false)

            let deadline = Date().addingTimeInterval(1)
            while (controller.floatingNoteBrowserController?.presentationCount ?? 0) < expectedPresentationCount,
                  Date() < deadline {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }

        try await dispatchClick(expectedPresentationCount: 1)

        let browser = try #require(controller.floatingNoteBrowserController)
        #expect(browser.presentationCount == 1)
        #expect(browser.window?.isVisible == true)
        #expect(browser.window?.isKeyWindow == true)
        #expect(browser.window?.parent === controller.window)
        if let browserFrame = browser.window?.frame,
           let parentFrame = controller.window?.frame,
           let visibleFrame = controller.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            #expect(browserFrame.intersects(visibleFrame))
            #expect(browserFrame.minX >= parentFrame.minX)
            #expect(browserFrame.maxX <= parentFrame.maxX)
            #expect(browserFrame.minY >= parentFrame.minY)
            #expect(browserFrame.maxY <= parentFrame.maxY)
        }

        browser.window?.close()
        controller.window?.resignKey()
        #expect(controller.window?.isKeyWindow == false)
        try await dispatchClick(expectedPresentationCount: 2)
        #expect(browser.presentationCount == 2)
        #expect(browser.window?.isVisible == true)
        #expect(browser.window?.parent === controller.window)
        #expect(browser.window?.frame.width == FloatingNoteBrowserController.compactPanelWidth)
        #expect(browser.window?.frame.height == 116)
        #expect(browser.window?.contentView?.allSubviews.contains {
            ($0 as? NSButton)?.title == "关闭窗口"
        } == false)
        browser.window?.close()
    }

    @MainActor
    @Test
    func floatingWindowManagerShowsAllOpenWindowsWithIndividualCloseActions() throws {
        var openWindows: [FloatingNoteWindowDescriptor] = []
        var closedWindowID: UUID?
        var addedURL: URL?
        var createCount = 0
        let harness = try makeEditorControllerHarness(
            draftID: "floating-note",
            showsSaveButton: false,
            floatingNoteWindows: { openWindows },
            onRequestOpenFloatingNote: { addedURL = $0 },
            onRequestCloseFloatingNote: { closedWindowID = $0 },
            onRequestCreateFloatingNote: { createCount += 1 }
        )
        defer { harness.tearDown() }

        try harness.store.ensureNotesDirectory()
        let firstURL = try harness.store.saveNewNote(title: "First", body: "One", in: harness.store.notesDirectory)
        let secondURL = try harness.store.saveNewNote(title: "Second", body: "Two", in: harness.store.notesDirectory)
        let firstID = UUID()
        openWindows = [
            FloatingNoteWindowDescriptor(id: firstID, url: firstURL, title: "First", subtitle: "One"),
            FloatingNoteWindowDescriptor(id: UUID(), url: secondURL, title: "Second", subtitle: "Two")
        ]

        harness.controller.showWindowAndFocus()
        harness.controller.showFloatingNoteBrowser(relativeTo: harness.controller.floatingNoteBrowseButton)
        let browser = try #require(harness.controller.floatingNoteBrowserController)

        #expect(browser.displayedURLs.map(\.standardizedFileURL) == [firstURL, secondURL].map(\.standardizedFileURL))
        #expect(browser.displayedOpenStates == [true, true])
        #expect(browser.window?.frame.width == 300)
        #expect(browser.window?.frame.height == 156)
        #expect(browser.resultRowHeight == 36)
        #expect(browser.usesVerticalScroller == false)
        #expect(browser.verticalScrollElasticity == .none)
        browser.window?.contentView?.layoutSubtreeIfNeeded()
        let firstCell = try #require(browser.resultCell(at: 0))
        firstCell.layoutSubtreeIfNeeded()
        #expect(firstCell.frame.width > 270)
        let titleFrame = firstCell.convert(firstCell.titleLabel.frame, from: firstCell.titleLabel.superview)
        #expect(titleFrame.minX >= 10)
        #expect(abs(firstCell.titleLabel.frame.midY - firstCell.snippetLabel.frame.midY) < 1)
        #expect(firstCell.actionButton.frame.width == 24)
        #expect(firstCell.layer?.cornerRadius == 9)
        let firstCloseButton = try #require(browser.rowActionButton(at: 0))
        #expect(firstCloseButton.toolTip?.hasPrefix("关闭") == true)

        openWindows += (0..<4).map {
            FloatingNoteWindowDescriptor(id: UUID(), url: nil, title: "Window \($0)", subtitle: "Unsaved")
        }
        browser.refresh()
        #expect(browser.usesVerticalScroller == true)
        #expect(browser.verticalScrollElasticity == .automatic)

        openWindows.removeLast(4)
        browser.refresh()
        #expect(browser.usesVerticalScroller == false)
        #expect(browser.verticalScrollElasticity == .none)
        #expect(browser.verticalScrollOffset == 0)

        let action = try #require(firstCloseButton.action)
        _ = NSApp.sendAction(action, to: firstCloseButton.target, from: firstCloseButton)
        #expect(closedWindowID == firstID)
        #expect(addedURL == nil)
        #expect(browser.newWindowButton.toolTip == "新建悬浮窗口")
        browser.newWindowButton.performClick(nil)
        #expect(createCount == 1)
        #expect(browser.window?.isVisible == false)
        browser.window?.close()
    }

    @MainActor
    @Test
    func floatingWindowManagerSupportsKeyboardNavigationAndPreservesSelection() throws {
        var openWindows: [FloatingNoteWindowDescriptor] = []
        var activatedWindowID: UUID?
        let harness = try makeEditorControllerHarness(
            draftID: "floating-note",
            showsSaveButton: false,
            floatingNoteWindows: { openWindows },
            onRequestActivateFloatingNote: { activatedWindowID = $0 }
        )
        defer { harness.tearDown() }

        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        openWindows = [
            FloatingNoteWindowDescriptor(id: firstID, url: nil, title: "First", subtitle: "One"),
            FloatingNoteWindowDescriptor(id: secondID, url: nil, title: "Second", subtitle: "Two"),
            FloatingNoteWindowDescriptor(id: thirdID, url: nil, title: "Third", subtitle: "Three")
        ]

        harness.controller.showWindowAndFocus()
        harness.controller.showFloatingNoteBrowser(relativeTo: harness.controller.floatingNoteBrowseButton)
        let browser = try #require(harness.controller.floatingNoteBrowserController)
        let fieldEditor = NSTextView()

        #expect(browser.selectedResultRow == 0)
        browser.window?.contentView?.layoutSubtreeIfNeeded()
        #expect(browser.resultCell(at: 0)?.isSelectedForPresentation == true)
        #expect(browser.control(
            browser.searchField,
            textView: fieldEditor,
            doCommandBy: #selector(NSResponder.moveDown(_:))
        ))
        #expect(browser.selectedResultRow == 1)
        #expect(browser.resultCell(at: 1)?.isSelectedForPresentation == true)

        #expect(browser.control(
            browser.searchField,
            textView: fieldEditor,
            doCommandBy: #selector(NSResponder.moveDown(_:))
        ))
        #expect(browser.control(
            browser.searchField,
            textView: fieldEditor,
            doCommandBy: #selector(NSResponder.moveDown(_:))
        ))
        #expect(browser.selectedResultRow == 2)
        #expect(browser.control(
            browser.searchField,
            textView: fieldEditor,
            doCommandBy: #selector(NSResponder.moveUp(_:))
        ))
        #expect(browser.selectedResultRow == 1)

        openWindows = [
            FloatingNoteWindowDescriptor(id: thirdID, url: nil, title: "Third", subtitle: "Three"),
            FloatingNoteWindowDescriptor(id: firstID, url: nil, title: "First", subtitle: "One"),
            FloatingNoteWindowDescriptor(id: secondID, url: nil, title: "Second", subtitle: "Two")
        ]
        browser.refresh()
        #expect(browser.selectedResultRow == 2)

        #expect(browser.control(
            browser.searchField,
            textView: fieldEditor,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))
        #expect(activatedWindowID == secondID)
        #expect(browser.window?.isVisible == false)

        harness.controller.showFloatingNoteBrowser(relativeTo: harness.controller.floatingNoteBrowseButton)
        #expect(browser.window?.isVisible == true)
        #expect(browser.control(
            browser.searchField,
            textView: fieldEditor,
            doCommandBy: #selector(NSResponder.cancelOperation(_:))
        ))
        #expect(browser.window?.isVisible == false)
    }

    @MainActor
    @Test
    func floatingWindowManagerBoundsSearchCandidates() async throws {
        let harness = try makeEditorControllerHarness(
            draftID: "floating-note",
            showsSaveButton: false
        )
        defer { harness.tearDown() }

        try harness.store.ensureNotesDirectory()
        for index in 0..<(FloatingNoteBrowserController.maximumSearchResults + 5) {
            _ = try harness.store.saveNewNote(
                title: "Needle \(index)",
                body: "Bounded floating search result",
                in: harness.store.notesDirectory
            )
        }

        harness.controller.showWindowAndFocus()
        harness.controller.showFloatingNoteBrowser(relativeTo: harness.controller.floatingNoteBrowseButton)
        let browser = try #require(harness.controller.floatingNoteBrowserController)
        browser.searchField.stringValue = "Needle"
        browser.controlTextDidChange(Notification(
            name: NSControl.textDidChangeNotification,
            object: browser.searchField
        ))
        await browser.waitForSearchForTesting()

        #expect(browser.displayedURLs.count == FloatingNoteBrowserController.maximumSearchResults)
        #expect(browser.selectedResultRow == 0)
        browser.window?.close()
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
    func floatingNotesDefaultToConfiguredFolderAndHighlightDirectly() throws {
        let harness = try makeEditorControllerHarness(
            draftID: "floating-note",
            showsSaveButton: false,
            configureStore: { store in
                let inbox = store.notesDirectory.appendingPathComponent("000-Inbox", isDirectory: true)
                try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            }
        )
        defer { harness.tearDown() }

        let expectedInbox = harness.store.notesDirectory.appendingPathComponent("000-Inbox", isDirectory: true)
        #expect(harness.store.preferredInboxDirectory == expectedInbox.standardizedFileURL)
        // A new floating note defaults to the configured default folder, not
        // the auto-detected inbox.
        #expect(harness.controller.selectedDirectoryURL == harness.store.notesDirectory)

        let controller = harness.controller
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(
            string: "highlight me",
            attributes: controller.theme.baseAttributes(for: .paragraph)
        ))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 9))
        let menu = try #require(controller.makeSelectionFormattingMenu())
        let highlight = try #require(menu.items.first { $0.title == "高亮" })
        #expect(NSApp.sendAction(try #require(highlight.action), to: highlight.target, from: highlight))
        #expect(MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme) == "<mark>highlight</mark> me")
    }

    @Test
    func floatingSelectionPanelCentersHorizontallyOnPointerAndPreservesSelectionY() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 800, height: 600)
        let panelSize = NSSize(width: 240, height: 40)

        #expect(MarkdownTextView.selectionFormattingPanelOrigin(
            centeredAtPointerX: 400,
            verticalOrigin: 182,
            panelSize: panelSize,
            visibleFrame: visibleFrame
        ) == NSPoint(x: 280, y: 182))
        #expect(MarkdownTextView.selectionFormattingPanelOrigin(
            centeredAtPointerX: 10,
            verticalOrigin: -24,
            panelSize: panelSize,
            visibleFrame: visibleFrame
        ) == NSPoint(x: 0, y: -24))
    }

    @Test
    func floatingWindowsPreferASeparateOnScreenFrame() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let first = NSRect(x: 514, y: 514, width: 412, height: 314)
        let second = nonOverlappingPanelFrame(first, occupiedFrames: [first], visibleFrames: [screen])

        #expect(screen.contains(second))
        #expect(!first.intersects(second))
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
    func floatingEditorQuickLooksSelectedFileAttachment() throws {
        let harness = try makeEditorControllerHarness(draftID: "floating-note", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let notesDirectory = harness.store.notesDirectory
        try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
        let noteURL = notesDirectory.appendingPathComponent("Attachment Note.md")
        let attachmentURL = notesDirectory.appendingPathComponent("preview.pdf")
        try Data("PDF preview".utf8).write(to: attachmentURL)

        let attributed = MarkdownRichTextCodec.render(
            markdown: "[Preview](preview.pdf)",
            theme: controller.theme,
            baseURL: noteURL
        )
        controller.editorTextView.textStorage?.setAttributedString(attributed)
        var attachmentRange: NSRange?
        attributed.enumerateAttribute(
            .qmAttachmentFilePath,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, range, _ in
            if value as? String == attachmentURL.path {
                attachmentRange = range
            }
        }

        controller.editorTextView.setSelectedRange(try #require(attachmentRange))
        let spaceEvent = try keyEvent(keyCode: UInt16(kVK_Space), modifiers: [], characters: " ")
        #expect(controller.markdownTextView(controller.editorTextView, handleKeyDown: spaceEvent))
        #expect(controller.attachmentQuickLookController.previewedURL == attachmentURL.standardizedFileURL)

        let menu = NSMenu()
        #expect(controller.configureAttachmentContextMenu(
            menu,
            forAttachmentPath: attachmentURL.path,
            markdown: "[Preview](preview.pdf)"
        ))
        #expect(menu.items.first?.title == "快速查看")
        #expect(menu.items.first?.keyEquivalent == " ")
        controller.attachmentQuickLookController.dismiss()
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

    private struct EditorControllerHarness {
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

    private func makeEditorControllerHarness(
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

    private func keyEvent(
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

    private func paragraphKind(after event: NSEvent, controller: EditorWindowController) throws -> MarkdownParagraphKind {
        controller.editorTextView.textStorage?.setAttributedString(NSAttributedString(
            string: "item",
            attributes: controller.theme.baseAttributes(for: .paragraph)
        ))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 4))
        #expect(controller.handleShortcutEvent(event))

        let storage = try #require(controller.editorTextView.textStorage)
        return MarkdownRichTextCodec.paragraphKind(at: NSRange(location: 0, length: storage.length), in: storage)
    }

    private func tableCellRange(row: Int, column: Int, in attributedString: NSAttributedString) -> NSRange? {
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

private extension MarkdownParagraphKind {
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
