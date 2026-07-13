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

    func testSuccessfulCaptureDismissesComposer() {
        let app = launchApp(reset: true, fixtureFolder: true)
        let newNoteButton = app.buttons["new-note-button"]
        XCTAssertTrue(newNoteButton.waitForExistence(timeout: 8))
        newNoteButton.tap()

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
        XCTAssertTrue(newNoteButton.waitForExistence(timeout: 5))
        XCTAssertFalse(editor.exists)
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
        rendered.tap()
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

    func testLibrarySearchScopesNotesAndInboxWithoutStaleResults() {
        let app = launchApp(reset: true, fixtureFolder: true)
        XCTAssertTrue(app.buttons["all-notes-link"].waitForExistence(timeout: 8))

        let search = app.textFields["library-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Restore")

        let result = app.buttons["search-result-file:Projects/UI Lifecycle.md"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
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
        let newNoteButton = app.buttons["new-note-button"]
        XCTAssertTrue(newNoteButton.waitForExistence(timeout: 8))
        newNoteButton.tap()

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

    @discardableResult
    private func launchApp(
        reset: Bool,
        fixtureFolder: Bool,
        invalidBookmark: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            reset ? "-ui-testing-reset" : nil,
            fixtureFolder ? "-ui-testing-fixture-folder" : nil,
            invalidBookmark ? "-ui-testing-invalid-bookmark" : nil
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
