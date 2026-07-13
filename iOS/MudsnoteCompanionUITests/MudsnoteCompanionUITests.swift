import XCTest

final class MudsnoteCompanionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnboardingPresentsFolderPicker() {
        let app = launchApp(reset: true, fixtureFolder: false)
        let chooseFolderButton = app.buttons["choose-folder-button"]

        XCTAssertTrue(chooseFolderButton.waitForExistence(timeout: 5))
        chooseFolderButton.tap()

        XCTAssertTrue(waitForNotHittable(chooseFolderButton))
    }

    func testInvalidFolderPermissionCanBeClearedBackToOnboarding() {
        let app = launchApp(reset: true, fixtureFolder: false, invalidBookmark: true)

        XCTAssertTrue(app.staticTexts["Folder Unavailable"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["choose-folder-again-button"].exists)

        let clearButton = app.buttons["clear-folder-permission-button"]
        XCTAssertTrue(clearButton.exists)
        clearButton.tap()

        XCTAssertTrue(app.buttons["choose-folder-button"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Folder Unavailable"].exists)
    }

    func testDamagedQuickDraftCanBeDiscardedWithoutChangingLibrary() {
        let app = launchApp(
            reset: true,
            fixtureFolder: true,
            damagedDraft: true
        )
        let settings = app.buttons["settings-link"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()
        XCTAssertTrue(app.staticTexts["Quick Note Recovery"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["The saved quick note is damaged and could not be restored."].exists)
        XCTAssertTrue(app.buttons["Try Recovery Again"].exists)
        app.buttons["Discard Unrecoverable Draft"].tap()
        XCTAssertTrue(app.alerts["Discard Unrecoverable Draft?"].waitForExistence(timeout: 3))
        app.alerts.buttons["Discard"].tap()
        XCTAssertTrue(app.staticTexts["Unrecoverable quick note discarded"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Quick Note Recovery"].exists)
    }

    func testDamagedPendingQueueIsolatedWithoutBlockingNewCaptures() {
        let app = launchApp(
            reset: true,
            fixtureFolder: true,
            damagedQueue: true
        )
        let quickNoteButton = app.buttons["quick-note-button"]
        XCTAssertTrue(quickNoteButton.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["all-notes-link"].exists)

        quickNoteButton.tap()
        let editor = app.textViews["capture-body-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Capture after damaged queue")
        app.buttons["save-memo-button"].tap()
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 5))
        XCTAssertFalse(editor.exists)

        app.buttons["settings-link"].tap()
        XCTAssertTrue(app.staticTexts["Needs Attention"].waitForExistence(timeout: 5))
        let warning = app.staticTexts.matching(
            NSPredicate(
                format: "label BEGINSWITH %@",
                "A damaged pending queue was preserved as queue-damaged-"
            )
        ).firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
    }

    func testSuccessfulCaptureDismissesComposer() {
        let app = launchApp(reset: true, fixtureFolder: true)
        let quickNoteButton = app.buttons["quick-note-button"]
        XCTAssertTrue(quickNoteButton.waitForExistence(timeout: 8))
        quickNoteButton.tap()

        let editor = app.textViews["capture-body-editor"]
        let saveButton = app.buttons["save-memo-button"]
        let targetMenu = app.buttons["capture-target-menu"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertFalse(saveButton.isEnabled)
        XCTAssertEqual(targetMenu.value as? String, "Inbox")

        editor.tap()
        editor.typeText("First UI memo")
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 5))
        XCTAssertTrue(quickNoteButton.waitForExistence(timeout: 5))
        XCTAssertFalse(editor.exists)
    }

    func testHomeCommandsStayInOneNotesStyleBottomRow() {
        let app = launchApp(reset: true, fixtureFolder: true)
        let search = app.textFields["library-search-field"]
        let quickNote = app.buttons["quick-note-button"]
        let newNote = app.buttons["new-note-button"]
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        XCTAssertTrue(quickNote.exists)
        XCTAssertTrue(newNote.exists)
        XCTAssertEqual(quickNote.frame.midY, search.frame.midY, accuracy: 3)
        XCTAssertEqual(newNote.frame.midY, search.frame.midY, accuracy: 3)
        XCTAssertLessThan(quickNote.frame.maxX, newNote.frame.minX)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Notes-style home command row"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testFolderRowContextMenuCreatesNestedFolder() {
        let app = launchApp(reset: true, fixtureFolder: true)
        let projects = app.buttons["folder-row-Projects"]
        XCTAssertTrue(projects.waitForExistence(timeout: 8))
        projects.press(forDuration: 1)

        let newSubfolder = app.buttons["New Subfolder"]
        XCTAssertTrue(newSubfolder.waitForExistence(timeout: 5))
        newSubfolder.tap()
        let alert = app.alerts["New Subfolder"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.textFields["Folder Name"].typeText("Launch")
        alert.buttons["Create"].tap()

        XCTAssertTrue(waitForHittable(projects))
        projects.tap()
        XCTAssertTrue(app.buttons["folder-row-Projects/Launch"].waitForExistence(timeout: 5))
    }

    func testFolderContextMenuMovesNestedFolderToTopLevel() {
        let app = launchApp(reset: true, fixtureFolder: true)
        let projects = app.buttons["folder-row-Projects"]
        XCTAssertTrue(projects.waitForExistence(timeout: 8))
        projects.press(forDuration: 1)
        app.buttons["New Subfolder"].tap()
        let alert = app.alerts["New Subfolder"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.textFields["Folder Name"].typeText("Launch")
        alert.buttons["Create"].tap()
        XCTAssertTrue(waitForHittable(projects))
        projects.tap()

        let launch = app.buttons["folder-row-Projects/Launch"]
        XCTAssertTrue(launch.waitForExistence(timeout: 5))
        launch.press(forDuration: 1)
        let moveFolder = app.buttons["Move Folder"]
        XCTAssertTrue(moveFolder.waitForExistence(timeout: 5))
        moveFolder.tap()
        let topLevel = app.buttons["Top Level"]
        XCTAssertTrue(topLevel.waitForExistence(timeout: 3))
        topLevel.tap()
        XCTAssertTrue(waitForNonexistence(launch))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["folder-row-Launch"].waitForExistence(timeout: 5))
    }

    func testNewNoteCreatesStandaloneMarkdownAndOpensFullEditor() {
        let app = launchApp(reset: true, fixtureFolder: true)
        let newNoteButton = app.buttons["new-note-button"]
        XCTAssertTrue(newNoteButton.waitForExistence(timeout: 8))
        newNoteButton.tap()

        let editor = app.textViews["markdown-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["collapse-markdown-editor"].exists)
        editor.tap()
        editor.typeText("Standalone UI Note\n\nIndependent Markdown note")
        app.buttons["save-markdown-button"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["rendered-markdown"].waitForExistence(timeout: 5))

        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(waitForHittable(newNoteButton))
        let allNotes = app.buttons["all-notes-link"]
        XCTAssertTrue(waitForHittable(allNotes))
        allNotes.tap()
        let row = app.buttons["markdown-file-row-Standalone UI Note.md"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Standalone UI Note"))
    }

    func testEmptyStandaloneNoteIsDiscardedWhenSheetCloses() {
        let app = launchApp(reset: true, fixtureFolder: true)
        let newNoteButton = app.buttons["new-note-button"]
        XCTAssertTrue(newNoteButton.waitForExistence(timeout: 8))
        newNoteButton.tap()
        let editor = app.textViews["markdown-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        app.buttons["save-markdown-button"].tap()
        XCTAssertTrue(waitForNonexistence(editor))

        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(waitForHittable(newNoteButton))
        let allNotes = app.buttons["all-notes-link"]
        XCTAssertTrue(waitForHittable(allNotes))
        let restoredCount = NSPredicate(format: "label == %@", "All Notes, 3")
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: restoredCount, object: allNotes)],
                timeout: 5
            ),
            .completed
        )
        allNotes.tap()
        let emptyRow = app.buttons["markdown-file-row-Untitled Note.md"]
        XCTAssertTrue(waitForNonexistence(emptyRow))
    }

    func testQuickCaptureDraftRestoresAfterProcessTermination() {
        let app = launchApp(reset: true, fixtureFolder: true)
        let quickNoteButton = app.buttons["quick-note-button"]
        XCTAssertTrue(quickNoteButton.waitForExistence(timeout: 8))
        quickNoteButton.tap()
        let editor = app.textViews["capture-body-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Recovered after termination")
        let persisted = expectation(description: "Draft debounce completed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { persisted.fulfill() }
        wait(for: [persisted], timeout: 2)

        app.terminate()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-ui-testing-fixture-folder"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Unsaved quick note restored"].waitForExistence(timeout: 8))
        XCTAssertTrue(quickNoteButton.waitForExistence(timeout: 5))
        quickNoteButton.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String)?.contains("Recovered after termination") == true)
    }

    func testSimplifiedLibraryOpensRealMarkdownFile() {
        let app = launchApp(reset: true, fixtureFolder: true)
        let allNotes = app.buttons["all-notes-link"]
        XCTAssertTrue(allNotes.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Quick Notes"].exists)
        XCTAssertFalse(app.staticTexts["Call Recordings"].exists)
        XCTAssertFalse(app.staticTexts["All Tags"].exists)
        XCTAssertFalse(app.staticTexts["Templates"].exists)

        allNotes.tap()
        let inbox = app.buttons["markdown-file-row-Inbox.md"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 5))
        inbox.tap()
        XCTAssertTrue(app.staticTexts["Inbox.md"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Raw"].exists)
        let rendered = app.descendants(matching: .any)["rendered-markdown"]
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))
        rendered.tap()
        let editor = app.textViews["markdown-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["collapse-markdown-editor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["markdown-add-image"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["markdown-add-file"].exists)
        XCTAssertTrue(app.buttons["markdown-scan-document"].exists)
        XCTAssertTrue(app.buttons["markdown-format-table"].exists)
        let displayMode = app.buttons["markdown-display-mode"]
        XCTAssertTrue(displayMode.exists)
        displayMode.tap()
        XCTAssertTrue(app.buttons["Rich Text"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Markdown Source"].exists)
        app.buttons["Rich Text"].tap()
        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))

        let richEditorScreenshot = XCTAttachment(screenshot: app.screenshot())
        richEditorScreenshot.name = "Rendered Markdown editor"
        richEditorScreenshot.lifetime = .keepAlways
        add(richEditorScreenshot)

        let bold = app.buttons["markdown-format-bold"]
        XCTAssertTrue(bold.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["markdown-format-ordered"].exists)
        XCTAssertTrue(app.buttons["markdown-format-outdent"].exists)
        XCTAssertTrue(app.buttons["markdown-format-indent"].exists)
        bold.tap()
        editor.typeText("Styled")
        XCTAssertTrue((editor.value as? String)?.contains("**Styled**") == true)
        XCTAssertTrue(app.buttons["save-markdown-button"].exists)
    }

    func testMarkdownEditorAutosavesBeforeSheetDismissal() {
        let app = launchApp(reset: true, fixtureFolder: true)
        XCTAssertTrue(app.buttons["all-notes-link"].waitForExistence(timeout: 8))
        app.buttons["all-notes-link"].tap()
        let note = app.buttons["markdown-file-row-Projects/UI Lifecycle.md"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()

        let rendered = app.descendants(matching: .any)["rendered-markdown"]
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))
        let bodyText = rendered.staticTexts["Restore this note end to end."]
        XCTAssertTrue(bodyText.waitForExistence(timeout: 5))
        bodyText.tap()
        let editor = app.textViews["markdown-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("\nAutosaved UI edit")

        let saved = app.staticTexts["markdown-save-status"]
        XCTAssertTrue(saved.waitForExistence(timeout: 3))
        let savedPredicate = NSPredicate(format: "label == %@", "Saved")
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: savedPredicate, object: saved)],
                timeout: 5
            ),
            .completed
        )

        app.buttons["save-markdown-button"].tap()
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(waitForHittable(note))
        note.tap()
        XCTAssertTrue(app.staticTexts["Autosaved UI edit"].waitForExistence(timeout: 5))
    }

    func testGenericAttachmentOpensSystemQuickLook() {
        let app = launchApp(reset: true, fixtureFolder: true)
        XCTAssertTrue(app.buttons["all-notes-link"].waitForExistence(timeout: 8))
        app.buttons["all-notes-link"].tap()
        let note = app.buttons["markdown-file-row-Projects/UI Lifecycle.md"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        XCTAssertTrue(app.descendants(matching: .any)["rendered-markdown-table"].waitForExistence(timeout: 5))

        let preview = app.buttons["preview-attachment-Attachments/ui-test.txt"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.tap()
        let quickLook = app.otherElements["QLPreviewControllerView"]
        let close = app.buttons["QLOverlayDoneButtonAccessibilityIdentifier"]
        XCTAssertTrue(quickLook.waitForExistence(timeout: 5))
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["ui-test"].waitForExistence(timeout: 5))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Generic attachment Quick Look"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        close.tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
    }

    func testAttachmentContextMenuRenamesAndOffersSystemShare() {
        let app = launchApp(reset: true, fixtureFolder: true)
        XCTAssertTrue(app.buttons["all-notes-link"].waitForExistence(timeout: 8))
        app.buttons["all-notes-link"].tap()
        let note = app.buttons["markdown-file-row-Projects/UI Lifecycle.md"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()

        let preview = app.buttons["preview-attachment-Attachments/ui-test.txt"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Share Attachment"].waitForExistence(timeout: 3))
        app.buttons["Rename Attachment"].tap()
        let alert = app.alerts["Rename Attachment"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        let name = alert.textFields["Attachment Name"]
        XCTAssertEqual(name.value as? String, "ui-test")
        name.tap()
        name.typeText("-renamed")
        alert.buttons["Rename"].tap()

        XCTAssertTrue(
            app.buttons["preview-attachment-Attachments/ui-test-renamed.txt"]
                .waitForExistence(timeout: 5)
        )
    }

    func testLibrarySearchScopesNotesAndInboxWithoutStaleResults() {
        let app = launchApp(reset: true, fixtureFolder: true)
        XCTAssertTrue(app.buttons["all-notes-link"].waitForExistence(timeout: 8))

        let search = app.textFields["library-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Restore")

        let result = app.buttons["search-result-file:Projects/UI Lifecycle.md"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        let highlightedScreenshot = XCTAttachment(screenshot: app.screenshot())
        highlightedScreenshot.name = "Highlighted search result"
        highlightedScreenshot.lifetime = .keepAlways
        add(highlightedScreenshot)
        let scope = app.segmentedControls["search-scope-picker"]
        XCTAssertTrue(scope.exists)

        scope.buttons["Inbox"].tap()
        XCTAssertTrue(app.staticTexts["No Results"].waitForExistence(timeout: 5))
        XCTAssertFalse(result.exists)

        scope.buttons["Notes"].tap()
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        app.buttons["clear-library-search"].tap()
        XCTAssertTrue(app.buttons["all-notes-link"].waitForExistence(timeout: 5))
    }

    func testNotesStyleListShowsMetadataAndSortControls() {
        let app = launchApp(reset: true, fixtureFolder: true)
        let allNotes = app.buttons["all-notes-link"]
        XCTAssertTrue(allNotes.waitForExistence(timeout: 8))
        allNotes.tap()

        let lifecycleNote = app.buttons["markdown-file-row-Projects/UI Lifecycle.md"]
        XCTAssertTrue(lifecycleNote.waitForExistence(timeout: 5))
        XCTAssertTrue(lifecycleNote.label.contains("UI Lifecycle"))
        XCTAssertTrue(lifecycleNote.label.contains("Restore this note end to end."))
        XCTAssertTrue(lifecycleNote.label.contains("Projects"))
        XCTAssertTrue(app.staticTexts["Today"].exists)

        let sortButton = app.buttons["Sort Notes"]
        XCTAssertTrue(sortButton.exists)
        sortButton.tap()
        XCTAssertTrue(app.buttons["Date Edited"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Date Created"].exists)
        XCTAssertTrue(app.buttons["Title"].exists)

        app.tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Notes-style metadata list"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testCaptureCommandsStayInSingleRow() {
        let app = launchApp(reset: true, fixtureFolder: true)
        let quickNoteButton = app.buttons["quick-note-button"]
        XCTAssertTrue(quickNoteButton.waitForExistence(timeout: 8))
        quickNoteButton.tap()

        let labels = ["Add image", "Record audio", "Formatting", "capture-target-menu", "save-memo-button"]
        let controls = labels.map { app.buttons[$0] }
        for control in controls {
            XCTAssertTrue(control.waitForExistence(timeout: 5))
        }

        let centerY = controls[0].frame.midY
        for control in controls.dropFirst() {
            XCTAssertEqual(control.frame.midY, centerY, accuracy: 2)
        }

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Single-row capture console"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testAttachmentLibraryShowsStoredFiles() {
        let app = launchApp(reset: true, fixtureFolder: true)
        let attachments = app.buttons["attachments-link"]
        XCTAssertTrue(attachments.waitForExistence(timeout: 8))
        attachments.tap()

        let storedImage = app.buttons["attachment-row-Attachments/ui-test.png"]
        XCTAssertTrue(storedImage.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ui-test.png"].exists)
        XCTAssertFalse(app.staticTexts["Images and audio are stored in Attachments/yyyy/mm and referenced by relative Markdown links."].exists)
    }

    func testNoteMovesToRecentlyDeletedAndRestoresThroughUI() {
        let app = launchApp(reset: true, fixtureFolder: true)
        let allNotes = app.buttons["all-notes-link"]
        XCTAssertTrue(allNotes.waitForExistence(timeout: 8))
        allNotes.tap()

        let note = app.buttons["markdown-file-row-Projects/UI Lifecycle.md"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        XCTAssertTrue(waitForNonexistence(note))

        app.navigationBars["All Notes"].buttons.firstMatch.tap()
        let recentlyDeleted = app.buttons["recently-deleted-link"]
        XCTAssertTrue(recentlyDeleted.waitForExistence(timeout: 5))
        recentlyDeleted.tap()

        let deletedTitle = app.staticTexts["UI Lifecycle"]
        XCTAssertTrue(deletedTitle.waitForExistence(timeout: 5))
        deletedTitle.swipeRight()
        let restore = app.buttons["Restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 3))
        restore.tap()
        XCTAssertTrue(waitForNonexistence(deletedTitle))

        app.navigationBars["Recently Deleted"].buttons.firstMatch.tap()
        allNotes.tap()
        XCTAssertTrue(note.waitForExistence(timeout: 5))
    }

    func testNotePinsAndUnpinsThroughSwipeActions() {
        let app = launchApp(reset: true, fixtureFolder: true)
        let allNotes = app.buttons["all-notes-link"]
        XCTAssertTrue(allNotes.waitForExistence(timeout: 8))
        allNotes.tap()

        let note = app.buttons["markdown-file-row-Projects/UI Lifecycle.md"]
        let pinIndicator = app.images["pin-indicator-Projects/UI Lifecycle.md"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.swipeRight()
        let pin = app.buttons["Pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 3))
        pin.tap()
        XCTAssertTrue(pinIndicator.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Pinned"].exists)

        note.swipeRight()
        let unpin = app.buttons["Unpin"]
        XCTAssertTrue(unpin.waitForExistence(timeout: 3))
        unpin.tap()
        XCTAssertTrue(waitForNonexistence(pinIndicator))
    }

    func testNoteContextMenuCreatesPortableDuplicate() {
        let app = launchApp(reset: true, fixtureFolder: true)
        let allNotes = app.buttons["all-notes-link"]
        XCTAssertTrue(allNotes.waitForExistence(timeout: 8))
        allNotes.tap()

        let note = app.buttons["markdown-file-row-Projects/UI Lifecycle.md"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.press(forDuration: 1)
        let duplicate = app.buttons["Duplicate Note"]
        XCTAssertTrue(duplicate.waitForExistence(timeout: 3))
        duplicate.tap()

        XCTAssertTrue(
            app.buttons["markdown-file-row-Projects/UI Lifecycle Copy.md"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Note Duplicated"].exists)
    }

    @discardableResult
    private func launchApp(
        reset: Bool,
        fixtureFolder: Bool,
        invalidBookmark: Bool = false,
        damagedDraft: Bool = false,
        damagedQueue: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            reset ? "-ui-testing-reset" : nil,
            fixtureFolder ? "-ui-testing-fixture-folder" : nil,
            invalidBookmark ? "-ui-testing-invalid-bookmark" : nil,
            damagedDraft ? "-ui-testing-damaged-draft" : nil,
            damagedQueue ? "-ui-testing-damaged-queue" : nil
        ].compactMap { $0 }
        app.launch()
        return app
    }

    private func waitForEmptyValue(of element: XCUIElement) -> Bool {
        let predicate = NSPredicate { evaluated, _ in
            guard let element = evaluated as? XCUIElement else { return false }
            return (element.value as? String)?.isEmpty == true
        }
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: 5
        ) == .completed
    }

    private func waitForNotHittable(_ element: XCUIElement) -> Bool {
        let predicate = NSPredicate { _, _ in
            element.isHittable == false
        }
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)],
            timeout: 5
        ) == .completed
    }

    private func waitForHittable(_ element: XCUIElement) -> Bool {
        let predicate = NSPredicate { _, _ in element.isHittable }
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: 5
        ) == .completed
    }

    private func waitForNonexistence(_ element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: 5
        ) == .completed
    }
}
