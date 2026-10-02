import AppKit
import Carbon.HIToolbox
import CoreServices
import ImageIO
@_spi(Testing) import MudsnoteCore
import Testing
@testable import Mudsnote

extension MarkdownRichEditorTests {
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
    func libraryCreatesNotesImmediatelyAndSupportsSlashCommands() async throws {
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
        let seedURL = try store.saveNewNote(title: "Seed", body: "Body")
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

        controller.editorTextView.textStorage?.setAttributedString(
            MarkdownRichTextCodec.render(markdown: "@Seed", theme: controller.theme)
        )
        controller.editorTextView.setSelectedRange(NSRange(location: 5, length: 0))
        controller.editorTextView.onTextInputStateChanged?()
        await controller.waitForEditorNoteSuggestionsForTesting()
        let seedIndex = try #require(
            controller.editorSlashSuggestionTitlesForLibrary.firstIndex(of: "Seed")
        )
        controller.acceptEditorSlashSuggestionForLibrary(at: seedIndex)
        let mentionMarkdown = MarkdownRichTextCodec.serialize(
            controller.editorTextView.attributedString(),
            theme: controller.theme
        )
        try #require(mentionMarkdown.hasPrefix("[Seed]("))
        let openingParen = try #require(mentionMarkdown.firstIndex(of: "("))
        let closingParen = try #require(mentionMarkdown.lastIndex(of: ")"))
        try #require(openingParen < closingParen)
        #expect(MarkdownLocalLinkResolver.fileURL(
            for: String(mentionMarkdown[mentionMarkdown.index(after: openingParen)..<closingParen]),
            relativeTo: createdURL
        ) == seedURL)

        // Main-window tags must use UTF-16 offsets even after emoji and Chinese text.
        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(markdown: "", theme: controller.theme))
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 0))
        controller.editorTextView.insertText("中文😀 #项目", replacementRange: controller.editorTextView.selectedRange())
        #expect(!suggestionView.isHidden)
        let tagIndex = try #require(controller.editorSlashSuggestionTitlesForLibrary.firstIndex(of: "#项目"))
        controller.acceptEditorSlashSuggestionForLibrary(at: tagIndex)
        #expect(controller.editorTextView.string == "中文😀 ")
        #expect(suggestionView.isHidden)
        controller.editorTextView.insertText("#第二个", replacementRange: controller.editorTextView.selectedRange())
        controller.editorTextView.insertText(" ", replacementRange: controller.editorTextView.selectedRange())
        #expect(controller.editorTextView.string == "中文😀  ")
        #expect(suggestionView.isHidden)

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
        #expect(controller.noteLinksView.superview === controller.editorTextView)
        #expect(!controller.noteLinksView.isPinned)
        let pin = try #require(controller.noteLinksView.allSubviews.compactMap { $0 as? NSButton }.first {
            $0.identifier?.rawValue == "LibraryRelationsPin"
        })
        pin.performClick(nil)
        #expect(controller.noteLinksView.isPinned)
        #expect(controller.noteLinksView.superview !== controller.editorTextView)
        pin.performClick(nil)
        #expect(!controller.noteLinksView.isPinned)
        #expect(controller.noteLinksView.superview === controller.editorTextView)
        #expect(window.title == "Mudsnote 笔记")
        #expect(window.titleVisibility == .hidden)
        #expect(window.titlebarAppearsTransparent)
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.contentViewController is NSSplitViewController)
        let splitController = try #require(window.contentViewController as? NSSplitViewController)
        #expect(splitController.splitViewItems.count == 2)
        #expect(controller.sourceOutlineView.numberOfRows >= 3)
        #expect(controller.sourceTreeNoteTitlesForLibrary().contains("Library Seed"))
        let treePresentationButton = try #require(window.toolbar?.items.compactMap { $0.view }.compactMap { $0 as? NSButton }.first {
            $0.identifier?.rawValue == "LibrarySidebarPresentationButton"
        })
        window.contentView?.layoutSubtreeIfNeeded()
        let toggleFrameBefore = treePresentationButton.convert(treePresentationButton.bounds, to: nil)
        let titleFrameBefore = controller.noteListTitleLabel.convert(controller.noteListTitleLabel.bounds, to: nil)
        #expect(!controller.noteListTitleLabel.isHiddenOrHasHiddenAncestor)
        window.makeFirstResponder(controller.editorTextView)
        let editorResponderBeforePresentationChange = window.firstResponder
        #expect(treePresentationButton.toolTip == "切换到列表")
        treePresentationButton.performClick(nil)
        #expect(store.librarySidebarPresentationRawValue == 1)
        #expect(controller.selectedSourceTitleForLibrary == "全部笔记")
        #expect(window.firstResponder === editorResponderBeforePresentationChange)
        let listPresentationButton = try #require(window.toolbar?.items.compactMap { $0.view as? NSButton }.first {
            $0.identifier?.rawValue == "LibrarySidebarPresentationButton"
        })
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(listPresentationButton === treePresentationButton)
        #expect(!controller.noteListTitleLabel.isHiddenOrHasHiddenAncestor)
        #expect(controller.noteListTitleLabel.convert(controller.noteListTitleLabel.bounds, to: nil) == titleFrameBefore)
        #expect(listPresentationButton.convert(listPresentationButton.bounds, to: nil).origin == toggleFrameBefore.origin)
        #expect(window.contentView?.allSubviews.contains {
            $0.identifier?.rawValue == "LibraryListSmartNavigation"
        } == false)
        #expect(listPresentationButton.toolTip == "切换到文件树")
        #expect(window.contentView?.allSubviews.first {
            $0.identifier?.rawValue == "LibrarySourceSurface"
        }?.isHidden == true)
        listPresentationButton.performClick(nil)
        #expect(store.librarySidebarPresentationRawValue == 0)
        #expect(controller.selectedSourceTitleForLibrary == "全部笔记")
        #expect(treePresentationButton.toolTip == "切换到列表")
        let allNotesButton = try #require(window.contentView?.allSubviews.first {
            $0.identifier?.rawValue == "LibraryReturnToAllNotes"
        } as? NSButton)
        #expect(allNotesButton.isHidden)
        controller.selectRecentScopeForLibrary()
        #expect(!allNotesButton.isHidden)
        allNotesButton.performClick(nil)
        #expect(controller.selectedSourceTitleForLibrary == "全部笔记")
        #expect(allNotesButton.isHidden)
        #expect(window.styleMask.contains(.resizable))
        let titlebarSeparators = window.contentView?.allSubviews.compactMap { $0 as? NSBox }.filter {
            $0.identifier?.rawValue.hasSuffix("TitlebarSeparator") == true
        } ?? []
        #expect(titlebarSeparators.isEmpty)
        #expect(window.titlebarSeparatorStyle == .none)
        #expect(window.minSize.width == LibraryNotesLayout.minimumWindowSize.width)
        #expect(LibraryNotesLayout.minimumWindowSize.width == 896)
        #expect(window.minSize.height >= LibraryNotesLayout.minimumWindowSize.height)
        #expect(!controller.tableView.floatsGroupRows)
        #expect(!controller.sourceOutlineView.floatsGroupRows)
        #expect(LibraryNotesLayout.storedLayoutScaleVersion == 9)
        #expect(LibraryNotesLayout.initialWindowSize == NSSize(width: 921, height: 613))
        #expect(LibraryNotesLayout.presentedWindowSize == NSSize(width: 921, height: 613))
        #expect(LibraryNotesLayout.sourceColumnWidth == 240)
        #expect(LibraryNotesLayout.noteColumnWidth == 280)
        #expect(LibraryNotesLayout.noteTableInitialWidth == 276)
        #expect(LibraryNotesLayout.noteTableMinimumWidth == 194)
        #expect(LibraryNotesLayout.noteTableInitialWidth + LibraryNotesLayout.noteListLeadingInset + LibraryNotesLayout.noteListTrailingInset == LibraryNotesLayout.noteColumnWidth)
        #expect(LibraryNotesLayout.toolbarSearchWidth == 160)
        #expect(LibraryNotesLayout.toolbarSearchHorizontalFocusRingInset == 4)
        #expect(LibraryNotesLayout.toolbarSearchWrapperWidth == LibraryNotesLayout.toolbarSearchWidth + 8)
        #expect(LibraryNotesLayout.toolbarSearchWrapperHeight == 28)
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
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.sidebar-presentation"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.add-folder"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.toggle-sidebar"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.source-separator"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.note-list-title"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.note-list-actions"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.new-note"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.document-tabs"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.note-separator"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.editor-tools"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.format"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.checklist"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.table"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.link"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.attachment"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.file-actions"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.export"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.more"))
        #expect(toolbarItemIDs.contains("mudsnote.library.toolbar.search"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.reveal"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.save"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.move"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.delete"))
        #expect(!toolbarItemIDs.contains("mudsnote.library.toolbar.restore"))
        let toolbarItemOrder = try #require(window.toolbar).items.map(\.itemIdentifier.rawValue)
        let sourceSeparatorIndex = try #require(toolbarItemOrder.firstIndex(
            of: "mudsnote.library.toolbar.source-separator"
        ))
        let newNoteIndex = try #require(toolbarItemOrder.firstIndex(
            of: "mudsnote.library.toolbar.new-note"
        ))
        #expect(newNoteIndex < sourceSeparatorIndex)
        let allowedItems = controller.toolbarAllowedItemIdentifiers(try #require(window.toolbar))
        #expect(allowedItems.contains(NSToolbarItem.Identifier("mudsnote.library.toolbar.navigation-back")))
        #expect(allowedItems.contains(NSToolbarItem.Identifier("mudsnote.library.toolbar.navigation-forward")))
        for toolbarButtonID in ["mudsnote.library.toolbar.toggle-sidebar"] {
            let item = try #require((window.toolbar?.items ?? []).first {
                $0.itemIdentifier.rawValue == toolbarButtonID
            })
            #expect(!item.isBordered)
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
        #expect(LibraryNotesLayout.toolbarNewNoteWrapperWidth == 30)
        let newNoteToolbarButton = try #require(newNoteToolbarWrapper.allSubviews.compactMap { $0 as? NSButton }.first)
        #expect(!newNoteToolbarItem.isBordered)
        #expect(newNoteToolbarButton.target === controller)
        #expect(newNoteToolbarButton.action != nil)
        #expect(newNoteToolbarButton.identifier?.rawValue == "mudsnote.library.toolbar.new-note")
        #expect(!newNoteToolbarButton.isBordered)
        #expect(newNoteToolbarButton.bezelStyle == .shadowlessSquare)
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
        #expect(LibraryNotesLayout.toolbarNewNoteSymbolPointSize == 18)

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
        #expect(toolbarSearchField.focusRingType == .default)
        #expect(LibraryNotesLayout.toolbarSymbolPointSize == 19)
        let toolbarSearchWrapper = try #require(toolbarSearchField.superview)
        #expect(toolbarSearchWrapper.frame.width == LibraryNotesLayout.toolbarSearchWrapperWidth)
        #expect(toolbarSearchWrapper.frame.height >= LibraryNotesLayout.toolbarSearchWrapperHeight)
        #expect(abs(toolbarSearchField.frame.midX - toolbarSearchWrapper.bounds.midX) < 0.5)
        #expect(toolbarSearchField.frame.minX >= LibraryNotesLayout.toolbarSearchHorizontalFocusRingInset)
        #expect(toolbarSearchWrapper.bounds.maxX - toolbarSearchField.frame.maxX >= LibraryNotesLayout.toolbarSearchHorizontalFocusRingInset)
        let visibleToolbarItemIDs = Set((window.toolbar?.visibleItems ?? []).map(\.itemIdentifier.rawValue))
        #expect(visibleToolbarItemIDs.contains("mudsnote.library.toolbar.new-note"))
        #expect(visibleToolbarItemIDs.contains("mudsnote.library.toolbar.document-tabs"))
        #expect(!visibleToolbarItemIDs.contains("mudsnote.library.toolbar.editor-tools"))
        #expect(visibleToolbarItemIDs.contains("mudsnote.library.toolbar.search"))
        #expect(!visibleToolbarItemIDs.contains("mudsnote.library.toolbar.reveal"))
        let sidebarListHeader = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSStackView }.first {
            $0.identifier?.rawValue == "LibrarySidebarListHeader"
        })
        #expect(sidebarListHeader.allSubviews.contains(controller.noteListTitleLabel))
        #expect(sidebarListHeader.allSubviews.contains(controller.noteListCountLabel))
        #expect(sidebarListHeader.allSubviews.contains(controller.searchScopeControl))
        #expect(controller.searchScopeControl.isHidden)
        #expect(controller.searchScopeControl.accessibilityLabel() == "搜索范围")
        sidebarListHeader.layoutSubtreeIfNeeded()
        #expect(controller.noteListTitleLabel.frame.width + 1 >= controller.noteListTitleLabel.intrinsicContentSize.width)
        let libraryToolbar = try #require(window.toolbar)
        let editorToolsItem = try #require(controller.toolbar(
            libraryToolbar,
            itemForItemIdentifier: NSToolbarItem.Identifier("mudsnote.library.toolbar.editor-tools"),
            willBeInsertedIntoToolbar: false
        ))
        #expect(!editorToolsItem.isBordered)
        let editorToolsSlot = try #require(editorToolsItem.view)
        #expect(editorToolsSlot.identifier?.rawValue == "LibraryToolbarEditorToolsSlot")
        #expect(editorToolsSlot.frame.width == LibraryNotesLayout.toolbarEditorToolsSlotWidth)
        #expect(LibraryNotesLayout.toolbarEditorToolsSlotWidth == 162)
        let editorToolsGlass = try #require(editorToolsSlot.allSubviews.compactMap { $0 as? NSGlassEffectView }.first)
        #expect(editorToolsGlass.frame.width == LibraryNotesLayout.toolbarEditorToolsWidth)
        #expect(LibraryNotesLayout.toolbarEditorToolsWidth == 155)
        #expect(editorToolsGlass.frame.height == LibraryNotesLayout.toolbarEditorToolsHeight)
        #expect(editorToolsGlass.cornerRadius == LibraryNotesLayout.toolbarEditorToolsHeight / 2)
        #expect(editorToolsGlass.style == .regular)
        let editorToolButtons = editorToolsGlass.allSubviews.compactMap { $0 as? NSButton }
        #expect(Set(editorToolButtons.compactMap { $0.identifier?.rawValue }) == [
            "mudsnote.library.toolbar.format",
            "mudsnote.library.toolbar.checklist",
            "mudsnote.library.toolbar.link",
            "mudsnote.library.toolbar.source-mode",
            "mudsnote.library.toolbar.reveal"
        ])
        #expect(Set(editorToolButtons.compactMap(\.toolTip)) == Set([
            "格式", "待办列表", "插入链接", "显示 Markdown 源码", "打开文件位置"
        ]))
        #expect(editorToolButtons.allSatisfy { $0.bezelStyle == .toolbar })
        #expect(editorToolButtons.allSatisfy { $0.isBordered })
        #expect(editorToolButtons.allSatisfy { $0.showsBorderOnlyWhileMouseInside })
        let revealButton = try #require(editorToolButtons.first {
            $0.identifier?.rawValue == "mudsnote.library.toolbar.reveal"
        })
        #expect(revealButton.target === controller)
        #expect(revealButton.action != nil)
        #expect(revealButton.isEnabled)
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
        #expect(unfocusedFormatColor.alphaComponent <= focusedFormatColor.alphaComponent)
        #expect(LibraryNotesLayout.toolbarEditorFormatFontSize == 17)
        #expect(LibraryNotesLayout.toolbarEditorToolSymbolPointSize == 13)
        let splitView = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSSplitView }.first)
        #expect(splitView.arrangedSubviews.count == 2)
        let sourceTrackingSeparator = try #require((window.toolbar?.items ?? []).first {
            $0.itemIdentifier.rawValue == "mudsnote.library.toolbar.source-separator"
        } as? NSTrackingSeparatorToolbarItem)
        #expect(sourceTrackingSeparator.splitView === splitView)
        #expect(sourceTrackingSeparator.dividerIndex == 0)
        let sourceList = splitView.arrangedSubviews[0]
        let noteList = sourceList
        let navigationSurface = try #require(sourceList.allSubviews.first {
            $0.identifier?.rawValue == "LibraryNavigationSidebar"
        })
        let sourceSurface = try #require(sourceList.allSubviews.first {
            $0.identifier?.rawValue == "LibrarySourceSurface"
        })
        #expect(sourceSurface.identifier?.rawValue == "LibrarySourceSurface")
        #expect(sourceSurface.accessibilityLabel() == "资料库")
        #expect(controller.tableView.accessibilityLabel() == "笔记列表")
        #expect(navigationSurface.identifier?.rawValue == "LibraryNavigationSidebar")
        #expect(sourceSurface.layer?.backgroundColor == nil)
        #expect(!sourceSurface.allSubviews.contains {
            $0.identifier?.rawValue == "LibrarySourceDarkeningTint"
        })
        #expect(LibraryNotesLayout.sourceCollapseAnimationDuration == 0.22)
        #expect(sourceList.frame.width >= LibraryNotesLayout.sourceColumnMinimumWidth)
        #expect(noteList.frame.width >= LibraryNotesLayout.noteColumnMinimumWidth)
        #expect(LibraryNotesLayout.sourceColumnMinimumWidth == 220)
        #expect(LibraryNotesLayout.sourceColumnMaximumWidth == 380)
        #expect(LibraryNotesLayout.noteColumnMinimumWidth == 200)
        #expect(LibraryNotesLayout.noteColumnMaximumWidth == 320)
        #expect(LibraryNotesLayout.editorColumnMinimumWidth == 480)
        let toggleSourceItem = try #require((window.toolbar?.items ?? []).first {
            $0.itemIdentifier.rawValue == "mudsnote.library.toolbar.toggle-sidebar"
        })
        let sourceTrackingSeparatorItem = try #require((window.toolbar?.items ?? []).first {
            $0.itemIdentifier.rawValue == "mudsnote.library.toolbar.source-separator"
        })
        #expect(controller.isSourceListVisibleForLibrary)
        #expect(!sourceTrackingSeparatorItem.isHidden)
        #expect(!toggleSourceItem.isBordered)
        let expandedToggleWrapper = try #require(toggleSourceItem.view)
        let expandedToggleButton = try #require(expandedToggleWrapper.subviews.first as? NSButton)
        let expandedImageSize = expandedToggleButton.image?.size
        #expect(expandedToggleButton.image != nil)
        #expect(treePresentationButton.image != nil)
        #expect(treePresentationButton.toolTip == "切换到列表")
        #expect(expandedToggleButton.image?.size.height == 22)
        #expect(expandedToggleButton.image?.size.width == 24)
        #expect(toggleSourceItem.label == "隐藏资料库")
        #expect(toggleSourceItem.toolTip == "隐藏资料库")
        expandedToggleButton.performClick(nil)
        #expect(!controller.isSourceListVisibleForLibrary)
        #expect(sourceList.isHidden)
        #expect(sourceTrackingSeparatorItem.isHidden)
        #expect(!toggleSourceItem.isBordered)
        let collapsedToggleWrapper = try #require(toggleSourceItem.view)
        #expect(collapsedToggleWrapper.identifier?.rawValue == "LibraryToolbarSidebarWrapper")
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
        #expect(collapsedToggleButton.bezelStyle == .shadowlessSquare)
        #expect(!collapsedToggleButton.isBordered)
        #expect(collapsedToggleButton.imageScaling == .scaleNone)
        #expect(toggleSourceItem.label == "显示资料库")
        #expect(toggleSourceItem.toolTip == "显示资料库")
        collapsedToggleButton.performClick(nil)
        #expect(controller.isSourceListVisibleForLibrary)
        #expect(!sourceList.isHidden)
        #expect(!sourceTrackingSeparatorItem.isHidden)
        #expect(!toggleSourceItem.isBordered)
        #expect(toggleSourceItem.view === expandedToggleWrapper)
        #expect(collapsedToggleButton === expandedToggleButton)
        #expect(collapsedToggleButton.image?.size == expandedImageSize)
        #expect(toggleSourceItem.label == "隐藏资料库")
        #expect(toggleSourceItem.toolTip == "隐藏资料库")
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
        #expect(window.contentView?.allSubviews.contains {
            $0.identifier?.rawValue == "LibrarySidebarBrandTitle"
        } == false)
        #expect(window.contentView?.allSubviews.contains {
            $0.identifier?.rawValue.hasPrefix("LibraryListSmartScope-") == true
        } == false)
        #expect(LibraryNotesLayout.sourceGroupFontSize == 12)
        #expect(LibraryNotesLayout.sourceRowHeight == 32)
        #expect(LibraryNotesLayout.sourceListTopInset == 0)
        #expect(LibraryNotesLayout.sourceListLeadingInset == 4)
        #expect(LibraryNotesLayout.sourceListBottomInset == 14)
        #expect(LibraryNotesLayout.sourceListTrailingInset == 4)
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
        #expect(LibraryNotesLayout.sourceButtonFontSize == 14)
        #expect(LibraryNotesLayout.sourceButtonFontWeight == LibraryNotesLayout.sourceSelectedButtonFontWeight)
        #expect(LibraryNotesLayout.sourceSelectedButtonFontWeight == .regular)
        #expect(LibraryNotesLayout.sourceUnselectedButtonFontWeight == .regular)
        #expect(LibraryNotesLayout.sourceCountFontSize == 12)
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
        #expect(sourceTitles.contains("全部笔记"))
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
        let sidebarTextFields = window.contentView?.allSubviews.compactMap { $0 as? NSTextField } ?? []
        let noteListTitle = try #require(sidebarTextFields.first {
            $0.identifier?.rawValue == "LibraryNoteListTitle"
        })
        let noteListCount = try #require(sidebarTextFields.first {
            $0.identifier?.rawValue == "LibraryNoteListCount"
        })
        let noteListEmpty = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSTextField }.first {
            $0.identifier?.rawValue == "LibraryNoteListEmptyLabel"
        })
        #expect(noteListTitle.stringValue == "全部笔记")
        #expect(noteListTitle.font?.pointSize == LibraryNotesLayout.noteListHeaderTitleFontSize)
        #expect(LibraryNotesLayout.noteListHeaderTitleFontSize == 14)
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
        #expect(LibraryGroupHeaderCellView.firstTitleBottomInset == 6)
        groupCell.isFirstGroup = false
        #expect(groupCell.titleBottomInset == LibraryGroupHeaderCellView.followingTitleBottomInset)
        #expect(LibraryGroupHeaderCellView.followingTitleBottomInset == 6)
        groupCell.isFirstGroup = true
        #expect(
            LibraryNotesLayout.noteGroupRowHeight - LibraryGroupHeaderCellView.firstTitleBottomInset == 24
        )
        let groupRowView = try #require(controller.tableView(controller.tableView, rowViewForRow: 0) as? LibraryNoteRowView)
        groupRowView.setPointerHovered(true)
        #expect(!groupRowView.isPointerHovered)
        #expect(controller.tableView(controller.tableView, heightOfRow: 0) == LibraryNotesLayout.noteGroupRowHeight)
        #expect(LibraryNotesLayout.noteGroupRowHeight == 30)
        #expect(controller.tableView(controller.tableView, heightOfRow: 1) == LibraryNotesLayout.noteRowHeight)
        #expect(LibraryNotesLayout.noteRowHeight == 68)
        let notePasteboardWriter = try #require(controller.tableView(controller.tableView, pasteboardWriterForRow: 1) as? NSURL)
        #expect(notePasteboardWriter as URL == noteURL)
        let noteRowView = try #require(controller.tableView(controller.tableView, rowViewForRow: 1) as? LibraryNoteRowView)
        #expect(!noteRowView.isGroupRow)
        #expect(LibraryNoteRowView.selectionLeadingInset == 6)
        #expect(LibraryNoteRowView.selectionTrailingInset == 6)
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
        #expect(LibraryNoteRowView.separatorTrailingInset == 16)
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
        #expect(LibraryNoteCellView.contentTopInset == 4.5)
        #expect(LibraryNoteCellView.contentLeadingInset == 16)
        #expect(LibraryNoteCellView.contentBottomInset == 7.5)
        #expect(LibraryNoteCellView.contentTrailingInset == 18)
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
        #expect(LibraryNotesLayout.noteGroupFontSize == 12)
        #expect(LibraryNotesLayout.noteGroupFontWeight == .medium)
        #expect(LibraryNotesLayout.noteTitleFontSize == 14)
        #expect(LibraryNotesLayout.noteTitleFontWeight == .medium)
        #expect(LibraryNotesLayout.noteSnippetFontSize == 12)
        #expect(LibraryNotesLayout.noteSnippetFontWeight == .regular)
        #expect(LibraryNotesLayout.noteMetaFontSize == 12)
        #expect(LibraryNotesLayout.noteMetaFontWeight == .regular)
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
        #expect(controller.statusLabel.alignment == .right)
        #expect(controller.statusLabel.stringValue == "编辑于 \(noteDateFormatter.string(from: noteModifiedAt))")
        #expect(!controller.statusLabel.stringValue.contains("·"))
        #expect(controller.statusLabel.font?.pointSize == 11)
        #expect(controller.titleField.font?.pointSize == LibraryNotesLayout.editorTitleFontSize)
        #expect(LibraryNotesLayout.editorTitleFontSize == 24)
        #expect(controller.titleField.placeholderString == "")
        #expect(controller.titleField.accessibilityLabel() == "笔记标题")
        #expect(controller.editorTextView.accessibilityLabel() == "笔记内容")
        #expect(controller.statusLabel.accessibilityLabel() == "编辑时间或保存状态")
        #expect(controller.statusLabel.superview !== controller.editorTextView)
        #expect(controller.createdDateLabel.accessibilityLabel() == "创建时间")
        #expect(controller.createdDateLabel.superview === controller.statusLabel.superview)
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
                == 14
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
        let footerFrame = controller.statusLabel.convert(controller.statusLabel.bounds, to: editorBodyContainer)
        #expect(abs(footerFrame.maxX - (editorBodyContainer.bounds.maxX - 20)) <= 2)
        editorScrollView.contentView.scroll(to: NSPoint(x: 0, y: 100))
        editorScrollView.reflectScrolledClipView(editorScrollView.contentView)
        #expect(controller.statusLabel.convert(controller.statusLabel.bounds, to: editorBodyContainer) == footerFrame)
        #expect(!editorStack.arrangedSubviews.contains(controller.statusLabel))
        #expect(!editorStack.arrangedSubviews.contains(controller.titleField))
        // Dates stay in the footer, while document tabs occupy
        // the editor side of the native toolbar.
        #expect(editorStack.edgeInsets.top == 0)
        #expect(LibraryNotesLayout.editorTopInset == 6.25)
        #expect(LibraryNotesLayout.editorDateToTitleSpacing < LibraryNotesLayout.editorDateRowHeight)
        #expect(editorStack.edgeInsets.left == LibraryNotesLayout.editorHorizontalInset)
        #expect(editorStack.edgeInsets.right == LibraryNotesLayout.editorHorizontalInset)
        #expect(LibraryNotesLayout.editorHorizontalInset == 23)
        #expect(LibraryNotesLayout.editorTextContainerHorizontalInset == 2)
        let editorPane = try #require(editorStack.superview)
        let documentTabToolbarItem = try #require(window.toolbar?.items.first {
            $0.itemIdentifier.rawValue == "mudsnote.library.toolbar.document-tabs"
        })
        let documentTabHeader = try #require(documentTabToolbarItem.view as? NSStackView)
        #expect(documentTabHeader.identifier?.rawValue == "LibraryDocumentTabHeader")
        #expect(!documentTabToolbarItem.isBordered)
        #expect(documentTabHeader.arrangedSubviews.count == 2)
        let documentTabScrollView = try #require(documentTabHeader.arrangedSubviews.first as? NSScrollView)
        #expect(documentTabScrollView.borderType == .noBorder)
        let documentTab = try #require(documentTabHeader.allSubviews.first {
            $0.identifier?.rawValue.hasPrefix("LibraryDocumentTab-") == true
        } as? LibraryDocumentTabView)
        #expect(documentTab.frame.height == LibraryDocumentTabView.height)
        #expect(documentTab.frame.width >= LibraryDocumentTabView.minimumWidth)
        #expect(documentTab.frame.width <= LibraryDocumentTabView.maximumWidth)
        #expect(editorPane.constraints.contains {
            $0.firstItem === editorStack
                && $0.firstAttribute == .top
                && $0.secondItem === editorPane.safeAreaLayoutGuide
                && $0.secondAttribute == .top
        })
        #expect(documentTabHeader.allSubviews.contains {
            $0.identifier?.rawValue == "LibraryDocumentTabTitle"
        })
        #expect(documentTabHeader.allSubviews.contains {
            $0.identifier?.rawValue == "LibraryNewDocumentTab"
        })
        #expect(controller.titleField.superview == nil)
        #expect(
            MarkdownRichTextCodec.serialize(
                controller.editorTextView.attributedString(),
                theme: controller.theme
            ) == "# Library Seed\nBody line"
        )
        let folderSourceCell = try #require(window.contentView?.allSubviews.compactMap {
            $0 as? LibrarySourceOutlineCellView
        }.first {
            $0.identifier?.rawValue == "LibrarySourceRow-10"
        })
        let folderSourceRowIndex = controller.sourceOutlineView.row(for: folderSourceCell)
        let folderSourceRow = try #require(controller.sourceOutlineView.rowView(
            atRow: folderSourceRowIndex,
            makeIfNecessary: false
        ) as? LibrarySourceOutlineRowView)
        #expect(LibrarySourceOutlineRowView.leadingInset == LibraryNotesLayout.sourceRowHighlightLeadingInset)
        #expect(LibrarySourceOutlineRowView.trailingInset == LibraryNotesLayout.sourceRowHighlightTrailingInset)
        #expect(LibrarySourceOutlineRowView.verticalInset == LibraryNotesLayout.sourceRowHighlightVerticalInset)
        #expect(LibrarySourceOutlineRowView.hoverColor.alphaComponent == 0.52)
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
        #expect(!folderSourceRow.isPointerHovered)
        let selectedSourceRect = sourceOutline.rect(ofRow: folderSourceRowIndex)
        sourceOutline.reconcilePointerHover(at: NSPoint(
            x: selectedSourceRect.midX,
            y: selectedSourceRect.midY
        ))
        #expect(folderSourceRow.isPointerHovered)
        #expect(sourceOutline.pointerHoveredRow === folderSourceRow)
        let replacementSourceHoverRow = LibrarySourceOutlineRowView()
        sourceOutline.setPointerHoveredRow(replacementSourceHoverRow)
        #expect(!folderSourceRow.isPointerHovered)
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
    func libraryExposesAddTagForNotesWithoutTags() throws {
        let harness = try makeEditorControllerHarness(draftID: "add-tag-ui", showsSaveButton: false)
        defer { harness.tearDown() }
        _ = try harness.store.saveNewNote(title: "Untagged", body: "Body")
        let controller = LibraryWindowController(noteStore: harness.store,
            onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close() }
        #expect(!controller.editorTextView.allSubviews.contains { $0.identifier?.rawValue == "AddNoteTagButton" })
        controller.editorTextView.onAddMetadataTag?()
        let input = try #require(controller.editorTextView.allSubviews.compactMap { $0 as? NSComboBox }
            .first { $0.identifier?.rawValue == "InlineNoteTagInput" })
        #expect(NSApp.modalWindow == nil)
        #expect(controller.window?.firstResponder === input.currentEditor())
        input.cancelOperation(nil)
        #expect(!controller.editorTextView.allSubviews.contains { $0.identifier?.rawValue == "AddNoteTagButton" })
        #expect(!controller.editorTextView.allSubviews.contains { $0.identifier?.rawValue == "InlineNoteTagInput" })
        controller.editorTextView.onAddMetadataTag?()
        let committedInput = try #require(controller.editorTextView.allSubviews.compactMap { $0 as? NSComboBox }
            .first { $0.identifier?.rawValue == "InlineNoteTagInput" })
        committedInput.stringValue = "#Created"
        #expect(NSApp.sendAction(try #require(committedInput.action), to: committedInput.target, from: committedInput))
        controller.addSelectedMetadataTag("created")
        let badges = controller.editorTextView.allSubviews.compactMap { $0 as? NSButton }
        #expect(badges.filter { $0.title == "#Created" }.count == 1)
        #expect(controller.editorTextView.string.contains("Body"))
    }

    @MainActor
    @Test
    func libraryGalleryBulkSelectionUsesBoundedWork() throws {
        let harness = try makeEditorControllerHarness(draftID: "gallery-selection-performance", showsSaveButton: false)
        defer { harness.tearDown() }
        let root = harness.store.notesDirectory
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<1_200 {
            try "# Note \(index)\n\nBody".write(to: root.appendingPathComponent("gallery-\(index).md"), atomically: true, encoding: .utf8)
        }
        let controller = LibraryWindowController(noteStore: harness.store,
            onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close() }
        let entryElapsed = ContinuousClock().measure {
            controller.setNoteListViewModeForLibrary(.gallery)
        }
        print("Gallery entry including indexing: \(entryElapsed)")
        #expect(entryElapsed < .milliseconds(250))
        let paths = controller.noteListSearchResultsForLibrary().map { $0.url.standardizedFileURL.path }
        #expect(paths.count == 1_200)
        for pass in 0..<3 {
            var selectedPaths = Set<IndexPath>()
            let elapsed = ContinuousClock().measure {
                selectedPaths = Set(paths.compactMap(controller.galleryIndexPath(for:)))
            }
            print("Gallery bulk selection lookup \(pass): \(elapsed)")
            #expect(selectedPaths.count == 1_200)
            #expect(elapsed < .milliseconds(250))
        }
        controller.setNoteListGroupingForLibrary(false)
        controller.setNoteListSortOrderForLibrary(.title)
        let firstPath = try #require(controller.noteListSearchResultsForLibrary().first?.url.standardizedFileURL.path)
        #expect(controller.galleryIndexPath(for: firstPath) == IndexPath(item: 0, section: 0))
        #expect(controller.selectSourceForLibrary(titled: "最近删除"))
        #expect(controller.noteListSearchResultsForLibrary().isEmpty)
        #expect(controller.galleryIndexPath(for: firstPath) == nil)
    }

    @MainActor
    @Test
    func libraryReturnToAllNotesUsesBoundedWork() throws {
        let harness = try makeEditorControllerHarness(draftID: "category-performance", showsSaveButton: false)
        defer { harness.tearDown() }
        let root = harness.store.notesDirectory
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<1_200 {
            let url = root.appendingPathComponent("category-\(index).md")
            try "# Note \(index)\n\nBody".write(to: url, atomically: true, encoding: .utf8)
        }
        harness.store.setLibraryNotePinned(true, at: root.appendingPathComponent("category-0.md"))
        harness.store.librarySidebarPresentationRawValue = 1
        let controller = LibraryWindowController(noteStore: harness.store,
            onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close() }
        #expect(controller.noteListSearchResultsForLibrary().count == 1_200)
        let returnButton = try #require(controller.window?.contentView?.allSubviews.first {
            $0.identifier?.rawValue == "LibraryReturnToAllNotes"
        } as? NSButton)
        for _ in 0..<3 {
            controller.selectRecentScopeForLibrary()
            #expect(!returnButton.isHidden)
            let elapsed = ContinuousClock().measure { returnButton.performClick(nil) }
            #expect(elapsed < .milliseconds(150))
            #expect(controller.noteListSearchResultsForLibrary().count == 1_200)
            #expect(returnButton.isHidden)
        }
        #expect(controller.noteListSearchResultsForLibrary().first?.url.lastPathComponent == "category-0.md")
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
        #expect(splitController.splitViewItems.count == 2)
        #expect(!splitController.splitViewItems[1].isCollapsed)
        #expect(!editorStack.isHidden)
        #expect(galleryScroll.isHidden)
        let initialSelectedURL = try #require(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL)

        controller.setNoteListViewModeForLibrary(.gallery)
        splitController.view.layoutSubtreeIfNeeded()

        #expect(controller.noteListViewMode == .gallery)
        #expect(store.libraryNoteViewModeRawValue == LibraryNoteViewMode.gallery.rawValue)
        #expect(!splitController.splitViewItems[1].isCollapsed)
        #expect(editorStack.isHidden)
        #expect(!galleryScroll.isHidden)
        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL == initialSelectedURL)
        let galleryToolbarIDs = Set((window.toolbar?.items ?? []).map { $0.itemIdentifier.rawValue })
        #expect(!galleryToolbarIDs.contains("mudsnote.library.toolbar.note-list-title"))
        #expect(!galleryToolbarIDs.contains("mudsnote.library.toolbar.note-separator"))
        #expect(!galleryToolbarIDs.contains("mudsnote.library.toolbar.editor-tools"))

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
        let reopenedToolbarIDs = Set((reopenedWindow.toolbar?.items ?? []).map { $0.itemIdentifier.rawValue })
        #expect(reopenedController.noteListViewMode == .gallery)
        #expect(!reopenedToolbarIDs.contains("mudsnote.library.toolbar.note-list-title"))
        #expect(!reopenedToolbarIDs.contains("mudsnote.library.toolbar.note-separator"))
        #expect(!reopenedToolbarIDs.contains("mudsnote.library.toolbar.editor-tools"))
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
        let desiredSourceWidth: CGFloat = 300

        firstSplitView.setPosition(desiredSourceWidth, ofDividerAt: 0)
        firstSplitView.layoutSubtreeIfNeeded()
        firstController.persistLibrarySplitLayoutForLibrary()

        try await Task.sleep(for: .milliseconds(260))

        #expect(abs((store.librarySourceColumnWidth ?? 0) - Double(desiredSourceWidth)) < 1)
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

        #expect(restoredSplitView.arrangedSubviews.count == 2)
        #expect(restoredSplitView.arrangedSubviews[0].isHidden)
        #expect(!restoredController.isSourceListVisibleForLibrary)
        #expect(restoredController.setSourceListVisibleForLibrary(true))
        restoredWindow.contentView?.layoutSubtreeIfNeeded()

        #expect(abs(restoredSplitView.arrangedSubviews[0].frame.width - desiredSourceWidth) < 1)
        #expect(restoredSplitView.arrangedSubviews[1].frame.width >= LibraryNotesLayout.editorColumnMinimumWidth)
        #expect(abs(restoredWindow.frame.origin.x - desiredWindowFrame.origin.x) < 1)
        #expect(abs(restoredWindow.frame.origin.y - desiredWindowFrame.origin.y) < 1)
        #expect(abs(restoredWindow.frame.width - desiredWindowFrame.width) < 1)
        #expect(abs(restoredWindow.frame.height - desiredWindowFrame.height) < 1)
        #expect(store.librarySourceListVisible)
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
    func libraryShowsAndCountsNotesBeyondTheFormerDisplayLimit() throws {
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
        #expect(listedNoteTitles().count == 241)
        #expect(listedNoteTitles().contains("Alpha Global"))
        #expect(controller.noteListCountLabel.stringValue == "241 条笔记")

        controller.setNoteListSortOrderForLibrary(.title)
        #expect(listedNoteTitles().count == 241)
        #expect(listedNoteTitles().first == "Alpha Global")

        controller.searchForLibrary(query: "Body", allNotes: true)
        #expect(controller.noteListSearchResultsForLibrary().count == 241)
        #expect(controller.noteListCountLabel.stringValue == "241 条结果")
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
        #expect(controller.sourceCountTextForLibrary(titled: "收藏") == "1")
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
    func libraryOldPinnedNoteSurvivesModifiedDateSnapshotLimit() throws {
        let suiteName = "mudsnote-old-pinned-note-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-old-pinned-note-tests-\(UUID().uuidString)", isDirectory: true)
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

        let now = Date()
        for index in 0..<240 {
            let url = notesDirectory.appendingPathComponent(String(format: "Recent %03d.md", index))
            try "# Recent \(index)\n".write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(TimeInterval(-index))],
                ofItemAtPath: url.path
            )
        }
        let pinnedURL = notesDirectory.appendingPathComponent("Pinned Old.md")
        try "# Pinned Old\n".write(to: pinnedURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-86_400)],
            ofItemAtPath: pinnedURL.path
        )
        store.setLibraryNotePinned(true, at: pinnedURL)

        let controller = LibraryWindowController(
            noteStore: store,
            onOpenInSeparateWindow: { _ in },
            onSave: { _ in },
            onClose: {}
        )
        defer { controller.close() }

        #expect(controller.noteListSearchResultsForLibrary().count == 241)
        #expect(
            controller.noteListSearchResultsForLibrary().first?.url.standardizedFileURL
                == pinnedURL.standardizedFileURL
        )
        let pinnedHeader = try #require(
            controller.tableView(controller.tableView, viewFor: nil, row: 0)
                as? LibraryGroupHeaderCellView
        )
        #expect(pinnedHeader.titleLabel.stringValue == "置顶")
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
        tableView.style = .plain
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("library-note"))
        column.width = LibraryNotesLayout.noteTableInitialWidth
        column.minWidth = LibraryNotesLayout.noteTableMinimumWidth
        column.resizingMask = .userResizingMask
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        let scrollView = LibraryNoteScrollView(frame: NSRect(x: 0, y: 0, width: 340, height: 300))
        scrollView.scrollerStyle = .legacy
        scrollView.hasVerticalScroller = true
        let clipView = LibraryNoteClipView(frame: scrollView.bounds)
        scrollView.contentView = clipView
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.usesPredominantAxisScrolling = true
        scrollView.documentView = tableView
        scrollView.tile()
        tableView.frame = NSRect(x: 92, y: 0, width: LibraryNotesLayout.noteTableInitialWidth, height: 600)

        scrollView.layout()

        let visibleWidth = scrollView.contentView.bounds.width
        #expect(tableView.frame.origin.x == 0)
        #expect(tableView.frame.width == visibleWidth)
        #expect(visibleWidth < scrollView.frame.width)
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
    func libraryRecentSearchMatchesVisibleEditedNotesWithoutOpenHistory() async throws {
        let harness = try makeEditorControllerHarness(draftID: "recent-search-scope", showsSaveButton: false)
        defer { harness.tearDown() }
        let root = harness.store.notesDirectory
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<81 {
            let url = root.appendingPathComponent("imported-\(index).md")
            try "# 阅读摘录 \(index)\n\nFirst line\n\n深层正文".write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(index))], ofItemAtPath: url.path)
        }
        let controller = LibraryWindowController(noteStore: harness.store,
            onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close() }
        controller.selectRecentScopeForLibrary()
        let visiblePaths = Set(controller.noteListSearchResultsForLibrary().map { $0.url.standardizedFileURL.path })
        #expect(visiblePaths.count == 80)
        controller.searchForLibrary(query: "阅读", allNotes: false)
        #expect(Set(controller.noteListSearchResultsForLibrary().map { $0.url.standardizedFileURL.path }) == visiblePaths)
        controller.searchForLibrary(query: "深层正文", allNotes: false)
        #expect(Set(controller.noteListSearchResultsForLibrary().map { $0.url.standardizedFileURL.path }) == visiblePaths)
        controller.searchForLibrary(query: "深层正文", allNotes: true)
        #expect(controller.noteListSearchResultsForLibrary().count == 81)
        controller.searchForLibrary(query: "", allNotes: false)
        controller.searchField.stringValue = "深层正文"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.searchField))
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline, controller.noteListCountLabel.stringValue != "80 条结果" {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(controller.noteListCountLabel.stringValue == "80 条结果")
        #expect(Set(controller.noteListSearchResultsForLibrary().map { $0.url.standardizedFileURL.path }) == visiblePaths)
    }

    @MainActor
    @Test
    func libraryAllNotesAndRecentlyEditedIncludePlainMarkdown() throws {
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
        #expect(controller.noteListTitleLabel.stringValue == "最近编辑")
        #expect(controller.noteListCountLabel.stringValue == "1 条笔记")
        #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["External Seed"])
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
    func libraryFileSystemMonitorMapsPhysicalEventsToRegisteredRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let physical = root.appendingPathComponent("Physical")
        let alias = root.appendingPathComponent("Alias")
        try FileManager.default.createDirectory(at: physical, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: physical)
        let monitor = LibraryFileSystemMonitor(roots: [alias]) { _ in }
        let resolvedPath = try #require(realpath(physical.path, nil))
        defer { free(resolvedPath) }
        let physicalPath = String(cString: resolvedPath)
        #expect(monitor.libraryPath(for: physicalPath) == alias.path)
        #expect(monitor.libraryPath(for: physicalPath + "/deleted.png") == alias.path + "/deleted.png")
        #expect(monitor.libraryPath(for: physicalPath + "-other/file.png") == physicalPath + "-other/file.png")
        let temporaryMonitor = LibraryFileSystemMonitor(roots: [URL(fileURLWithPath: "/tmp")]) { _ in }
        #expect(temporaryMonitor.libraryPath(for: "/private/tmp/deleted.png") == "/tmp/deleted.png")
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
        let imageChange = LibraryFileSystemChange(
            path: "/tmp/Attachments/Photo.HEIC",
            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)
        )
        #expect(imageChange.isImageFile)
        #expect(imageChange.requiresLibraryRefresh)
        #expect(!imageChange.changesDirectoryStructure)
        #expect(!LibraryFileSystemChange(path: "/tmp/unrelated.log", flags: 0).requiresLibraryRefresh)
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
        #expect(rootCell.accessibilityPerformPress())
        #expect(rootCell.textField?.textColor == MudsnoteThemeColor.violet.foregroundColor)
        let originalSourceBackground = NSColor(calibratedWhite: 0.20, alpha: 0.86)
        let originalSourceHover = NSColor(calibratedWhite: 0.20, alpha: 0.52)
        let originalCountColor = NSColor.labelColor.withAlphaComponent(0.42)
        store.themeColorIdentifier = MudsnoteThemeColor.teal.rawValue
        controller.refreshThemeColorForLibrary()
        #expect(rootCell.textField?.textColor == MudsnoteThemeColor.teal.foregroundColor)
        #expect(rootCell.countLabel.textColor == originalCountColor)
        #expect(LibrarySourceSelectionPalette.backgroundColor == originalSourceBackground)
        #expect(LibrarySourceOutlineRowView.hoverColor == originalSourceHover)
        #expect(LibraryNoteRowView.selectionFillColor == MudsnoteThemeColor.teal.noteSelectionColor)

        store.themeColorIdentifier = MudsnoteThemeColor.classicYellow.rawValue
        controller.refreshThemeColorForLibrary()
        #expect(rootCell.textField?.textColor == MudsnoteThemeColor.classicYellow.foregroundColor)
        #expect(rootCell.countLabel.textColor == originalCountColor)
        #expect(LibrarySourceSelectionPalette.backgroundColor == originalSourceBackground)
        #expect(LibrarySourceOutlineRowView.hoverColor == originalSourceHover)
        #expect(LibraryNoteRowView.selectionFillColor == MudsnoteThemeColor.classicYellow.noteSelectionColor)

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
        defer {
            if let toolbar = emptyController.window?.toolbar,
               let index = toolbar.items.firstIndex(where: { $0.itemIdentifier.rawValue == "mudsnote.library.toolbar.editor-tools" }) {
                toolbar.removeItem(at: index)
            }
            emptyController.close()
        }

        func visibleEditorToolsView(in controller: LibraryWindowController) throws -> NSView {
            let window = try #require(controller.window)
            // Toolbar customization propagates to every toolbar with the same identifier.
            // Give each fixture its own family before customizing it.
            let toolbar = NSToolbar(identifier: "test-editor-tools-" + UUID().uuidString)
            toolbar.delegate = controller
            window.toolbar = toolbar
            let identifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.editor-tools")
            if !toolbar.items.contains(where: { $0.itemIdentifier == identifier }) {
                #expect(controller.toolbarAllowedItemIdentifiers(toolbar).contains(identifier))
                toolbar.insertItem(withItemIdentifier: identifier, at: toolbar.items.count)
            }
            return try #require((controller.window?.toolbar?.items ?? []).first {
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
        #expect(selectedController.validateToolbarItem(editorToolsItem))
        #expect(!selectedController.validateToolbarItem(saveItem))
        #expect(!selectedController.validateToolbarItem(exportItem))
        #expect(selectedController.validateToolbarItem(moreItem))
        #expect(selectedController.validateToolbarItem(deleteItem))
        #expect(selectedController.validateToolbarItem(restoreItem))
        let trashEditorToolButtons = try visibleEditorToolButtons(in: selectedController)
        #expect(trashEditorToolButtons.first {
            $0.identifier?.rawValue == "mudsnote.library.toolbar.reveal"
        }?.isEnabled == true)
        #expect(trashEditorToolButtons.filter {
            $0.identifier?.rawValue != "mudsnote.library.toolbar.reveal"
        }.allSatisfy { !$0.isEnabled })
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
        #expect(!multiContextMenu.items.contains { $0.title == "复制 2 个 Markdown 路径" })
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
        #expect(!singleContextMenu.items.contains { $0.title == "复制 Markdown 路径" })
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
        let toolbar = NSToolbar(identifier: "test-rich-tools-" + UUID().uuidString)
        toolbar.delegate = controller
        window.toolbar = toolbar
        let toolsIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.editor-tools")
        #expect(controller.toolbarAllowedItemIdentifiers(toolbar).contains(toolsIdentifier))
        if !toolbar.items.contains(where: { $0.itemIdentifier == toolsIdentifier }) {
            toolbar.insertItem(withItemIdentifier: toolsIdentifier, at: toolbar.items.count)
        }
        defer {
            if let index = toolbar.items.firstIndex(where: { $0.itemIdentifier == toolsIdentifier }) {
                toolbar.removeItem(at: index)
            }
        }
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
        #expect(contextMenu.items.first?.title == "插入")
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
            "转换为", "加粗", "斜体", "高亮", "添加链接"
        ])
        #expect(selectionMenu.items.allSatisfy { $0.image != nil })
        #expect(selectionMenu.items.first?.submenu?.items.map(\.title) == [
            "正文", "标题", "副标题", "小标题", "项目符号列表", "编号列表", "待办列表"
        ])
        #expect(selectionMenu.items.first?.submenu?.items.allSatisfy { $0.image != nil } == true)
        let highlightItem = try #require(selectionMenu.items.first { $0.title == "高亮" })
        controller.editorTextView.undoManager?.removeAllActions()
        #expect(NSApp.sendAction(try #require(highlightItem.action), to: highlightItem.target, from: highlightItem))
        #expect(MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme) == "# Editor Tools\n\n<mark>plain</mark>")
        #expect(controller.editorTextView.undoManager?.canUndo == true)
        #expect(controller.editorTextView.textStorage?.attribute(
            .backgroundColor,
            at: bodyRange.location,
            effectiveRange: nil
        ) != nil)
        let selectionColor = try #require(
            controller.editorTextView.selectedTextAttributes[.backgroundColor] as? NSColor
        )
        #expect(selectionColor.alphaComponent < 1)
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

        #expect(refreshedSelectionPanelButtons.first { $0.toolTip == "下划线" } == nil)
        #expect(refreshedSelectionPanelButtons.first { $0.toolTip == "删除线" } == nil)
        #expect(refreshedSelectionPanelButtons.first { $0.toolTip == "添加链接" } != nil)

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
        ) == "# Links\n\n[Muds](https://example.com)")

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
        ) == "# Links\n\n[Example](https://example.com)")

        let updatedLibraryLink = try #require(libraryController.editorTextView.linkReference(atCharacterIndex: linkLocation))
        libraryController.updateLinkForLibrary(updatedLibraryLink, url: nil)
        #expect(MarkdownRichTextCodec.serialize(
            libraryController.editorTextView.attributedString(),
            theme: libraryController.theme
        ) == "# Links\n\nExample")
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
            "# Table Editing", "",
            "| Name | Status |",
            "| --- | --- |",
            "| Alpha | Todo |",
            "|  |  |"
        ])

        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: """
            # Table Editing

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
            "# Table Editing", "",
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
            "# Table Tabs", "",
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
            "# Table Delete", "",
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
            "# Table Delete", "",
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
            "# Table Menu", "",
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
            "# Table Menu", "",
            "| Name | Status |",
            "| --- | --- |",
            "| Alpha | Todo |"
        ])

        #expect(NSApp.sendAction(try #require(headerInsertRowItem.action), to: headerInsertRowItem.target, from: headerInsertRowItem))

        tableMarkdown = MarkdownRichTextCodec.serialize(controller.editorTextView.attributedString(), theme: controller.theme)
        #expect(tableMarkdown.components(separatedBy: "\n") == [
            "# Table Menu", "",
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
            "# Table Menu", "",
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

        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "# " + "Coalescing\n\nFirst revision", theme: controller.theme
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

        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "# " + "Coalescing\n\nLatest revision", theme: controller.theme
        ))
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
        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "# " + controller.titleField.stringValue + "\n\nEdited without blocking navigation", theme: controller.theme
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
    func libraryNoteListShowsImageAttachmentThumbnail() async throws {
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
        #expect(MarkdownRichTextCodec.serialize(editorContent, theme: controller.theme) == "# Image Attachment\n\n![Preview](Attachments/thumb.png)")
        var bodyImageCell: AsyncImageAttachmentCell?
        editorContent.enumerateAttribute(.attachment, in: NSRange(location: 0, length: editorContent.length)) { value, _, _ in
            bodyImageCell = (value as? NSTextAttachment)?.attachmentCell as? AsyncImageAttachmentCell ?? bodyImageCell
        }
        let bodyCell = try #require(bodyImageCell)
        bodyCell.beginDecodingIfNeeded(in: controller.editorTextView)
        for _ in 0..<100 where !bodyCell.hasDecodedImage {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(bodyCell.hasDecodedImage)
        let selectedRange = NSRange(location: 2, length: 3)
        controller.editorTextView.setSelectedRange(selectedRange)
        let bodyBeforeRefresh = controller.editorTextView.string

        // External deletion must discard the successful cache entry; recreation
        // must also discard a cached decoding failure without rescanning notes.
        try FileManager.default.removeItem(at: imageURL)
        controller.handleLibraryFileSystemChangesForTesting([
            LibraryFileSystemChange(path: imageURL.path, flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemRemoved))
        ])
        let deletedCell = try #require(controller.tableView(controller.tableView, viewFor: nil, row: 1) as? LibraryNoteCellView)
        #expect(deletedCell.thumbnailImageView.image == nil)
        #expect(controller.thumbnailImageDecodeCountForLibrary == decodeCountAfterFirstCell + 1)
        #expect(!bodyCell.hasDecodedImage)
        #expect(controller.editorTextView.string == bodyBeforeRefresh)
        #expect(controller.editorTextView.selectedRange() == selectedRange)

        try pngData.write(to: imageURL)
        controller.handleLibraryFileSystemChangesForTesting([
            LibraryFileSystemChange(path: imageURL.path, flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated))
        ])
        let restoredCell = try #require(controller.tableView(controller.tableView, viewFor: nil, row: 1) as? LibraryNoteCellView)
        #expect(restoredCell.thumbnailImageView.image != nil)
        #expect(controller.thumbnailImageDecodeCountForLibrary == decodeCountAfterFirstCell + 2)
        for _ in 0..<100 where !bodyCell.hasDecodedImage {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(bodyCell.hasDecodedImage)
        #expect(controller.editorTextView.string == bodyBeforeRefresh)
        #expect(controller.editorTextView.selectedRange() == selectedRange)
    }

    @MainActor
    @Test
    func libraryWindowSearchScopesAndHighlightsMatches() async throws {
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
        store.includesArchivedNotesInSearchAndKnowledge = true
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
        let scopeControl = try #require(window.contentView?.allSubviews.compactMap { $0 as? NSSegmentedControl }.first {
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
        #expect(MarkdownRichTextCodec.serialize(editorText, theme: controller.theme) == "# Alpha Project\n\ncurrent folder alpha body")

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

        await controller.waitForBackgroundAutosaveForTesting()
        controller.searchForLibrary(query: "alpha", allNotes: true)
        let allNotesSearchSession = try #require(controller.activeSearchSessionForLibrary())
        let allTitles = Set(controller.noteListSearchResultsForLibrary().map(\.title))
        #expect(allTitles == Set(["Alpha Project", "Archive Note"]))
        #expect(scopeControl.selectedSegment == 1)
        #expect(controller.noteListTitleLabel.stringValue == "全部笔记")
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
        #expect(controller.noteListTitleLabel.stringValue == LibraryCopy.allNotes)
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

        #expect(!controller.sourceOutlineView.isHiddenOrHasHiddenAncestor)
        let originalPresentation = store.librarySidebarPresentationRawValue
        controller.searchField.stringValue = "a"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.searchField))
        controller.searchField.stringValue = "alpha"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.searchField))

        #expect(controller.noteListSearchResultsForLibrary().map(\.title) != ["Alpha Debounced"])
        #expect(!controller.tableView.isHiddenOrHasHiddenAncestor)
        #expect(controller.sourceOutlineView.isHiddenOrHasHiddenAncestor)
        #expect(store.librarySidebarPresentationRawValue == originalPresentation)
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
        for command in [#selector(NSResponder.deleteBackward(_:)), #selector(NSResponder.moveLeft(_:))] {
            #expect(!controller.control(controller.searchField, textView: fieldEditor, doCommandBy: command))
            #expect(controller.noteListSearchResultsForLibrary().map(\.title) == ["Alpha Debounced"])
            #expect(controller.noteListCountLabel.stringValue == "正在搜索…")
        }
        #expect(controller.control(controller.searchField, textView: fieldEditor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(controller.titleField.stringValue == "Beta Debounced")

        controller.searchField.stringValue = ""
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: controller.searchField))
        #expect(controller.searchScopeControl.isHidden)
        #expect(Set(controller.noteListSearchResultsForLibrary().map(\.title)) == Set(["Alpha Debounced", "Beta Debounced"]))
        #expect(controller.noteListCountLabel.stringValue == "2 条笔记")
        #expect(!controller.sourceOutlineView.isHiddenOrHasHiddenAncestor)
        #expect(controller.tableView.isHiddenOrHasHiddenAncestor)
        #expect(store.librarySidebarPresentationRawValue == originalPresentation)
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
        #expect(controller.isSourceGroupExpandedForLibrary(titled: "FILES") == true)
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
        #expect(controller.isSourceGroupExpandedForLibrary(titled: "FILES") == true)

        controller.toggleSourceFoldersSectionForLibrary()
        #expect(store.libraryFoldersSectionCollapsed)
        #expect(controller.isSourceGroupExpandedForLibrary(titled: "FILES") == false)
        #expect(!controller.visibleSourceTitlesForLibrary().contains("Notes"))
        #expect(!controller.visibleSourceTitlesForLibrary().contains("Projects"))

        controller.toggleSourceFoldersSectionForLibrary()
        #expect(!store.libraryFoldersSectionCollapsed)
        #expect(controller.isSourceGroupExpandedForLibrary(titled: "FILES") == true)
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
    func libraryWindowCreatesMovesRenamesAndDeletesFolders() async throws {
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
        await controller.waitForSourceCountRefreshForLibrary()
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
        #expect(externalMenu.items.filter { !$0.isSeparatorItem }.map(\.title) == ["以列表显示", "在 Finder 中显示", "更改图标", "从资料库移除"])

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
    func libraryWindowDeletesRestoresAndPermanentlyDeletesNotes() async throws {
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
            markdown: "# Trash Seed\n\nUpdated body",
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
        controller.tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        await controller.waitForActiveNoteLoadForLibrary()
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
        #expect(!trashContextTitles.contains("复制 Markdown 路径"))
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
        controller.tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        await controller.waitForActiveNoteLoadForLibrary()
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
        controller.tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        await controller.waitForActiveNoteLoadForLibrary()
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
        #expect(controller.editorTextView.string == "Cache Older\n\nOld body")
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
        controller.selectNoteForVisualQA(at: contentURL)

        #expect(controller.selectedMarkdownFileURLForLibrary()?.standardizedFileURL == contentURL.standardizedFileURL)
        #expect(controller.titleField.stringValue == "Content Visual")
        #expect(controller.editorTextView.string == "Content Visual\n\nVisible editor body")
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

        #expect(controller.sourceCountTextForLibrary(titled: "Notes") == "1")
        controller.showWindowAndFocus()
        #expect(controller.noteListCountLabel.stringValue == "1 条笔记")
        let initialListTitle = try #require(controller.noteListSearchResultsForLibrary().first?.title)
        #expect(controller.titleField.stringValue == initialListTitle)
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline,
              controller.editorTextView.string != "Deferred Seed\n\nDeferred body"
                || controller.sourceCountTextForLibrary(titled: "Notes") != "1" {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(controller.searchField.currentEditor() == nil)
        #expect(controller.titleField.stringValue == "Deferred Seed")
        #expect(controller.editorTextView.string == "Deferred Seed\n\nDeferred body")
        #expect(controller.sourceCountTextForLibrary(titled: "Notes") == "1")
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
        while Date() < deadline, controller.editorTextView.string != "Existing Recent\n\nExisting body" {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(controller.titleField.stringValue == "Existing Recent")
        #expect(controller.editorTextView.string == "Existing Recent\n\nExisting body")
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
        while Date() < deadline, controller.editorTextView.string != "External Deferred\n\nExternal body" {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(controller.noteListCountLabel.stringValue == "1 条笔记")
        #expect(controller.tableView.selectedRow >= 0)
        #expect(controller.searchField.currentEditor() == nil)
        #expect(controller.titleField.stringValue == "External Deferred")
        #expect(controller.editorTextView.string == "External Deferred\n\nExternal body")
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
}
