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

    func testAttachmentFailureStaysInCaptureAndRestoresEditing() {
        let app = launchApp(
            reset: true,
            fixtureFolder: true,
            attachmentError: true
        )
        let quickNoteButton = app.buttons["quick-note-button"]
        XCTAssertTrue(quickNoteButton.waitForExistence(timeout: 8))
        quickNoteButton.tap()

        let alert = app.alerts["Couldn’t Add Attachment"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["The attachment is empty."].exists)
        XCTAssertTrue(app.textViews["capture-body-editor"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Quick capture attachment recovery"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        alert.buttons["OK"].tap()
        let editor = app.textViews["capture-body-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.typeText("Draft continues after attachment failure")
        XCTAssertTrue((editor.value as? String)?.contains("Draft continues") == true)
    }

    func testInterruptedWriteKeepsDraftVisibleAndOffersRetry() {
        let app = launchApp(
            reset: true,
            fixtureFolder: true,
            interruptedWrite: true
        )
        let quickNoteButton = app.buttons["quick-note-button"]
        XCTAssertTrue(quickNoteButton.waitForExistence(timeout: 8))
        quickNoteButton.tap()
        let editor = app.textViews["capture-body-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Keep this interrupted draft")

        app.buttons["save-memo-button"].tap()

        let recoveryTitle = app.staticTexts["Couldn’t Save Quick Note"]
        XCTAssertTrue(recoveryTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["retry-capture-save"].exists)
        XCTAssertTrue(editor.exists)
        XCTAssertTrue((editor.value as? String)?.contains("Keep this interrupted draft") == true)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Quick capture interrupted-write recovery"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["retry-capture-save"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertTrue((editor.value as? String)?.contains("Keep this interrupted draft") == true)
    }

    func testConflictCopyCanBeSafelyKeptAsSeparateNote() {
        let app = launchApp(reset: true, fixtureFolder: true, conflictCopy: true)
        let settings = app.buttons["settings-link"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()

        let review = app.buttons["review-conflicts-link"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        review.tap()

        let conflict = app.buttons["conflict-file-row-Projects/UI Lifecycle conflicted copy.md"]
        XCTAssertTrue(conflict.waitForExistence(timeout: 5))
        let actions = app.buttons["conflict-actions-Projects/UI Lifecycle conflicted copy.md"]
        XCTAssertTrue(actions.exists)
        actions.tap()
        let keep = app.buttons["Keep as Separate Note"]
        XCTAssertTrue(keep.waitForExistence(timeout: 3))
        keep.tap()

        XCTAssertTrue(waitForNonexistence(conflict))
        XCTAssertTrue(app.staticTexts["No Conflicts"].waitForExistence(timeout: 5))
        app.navigationBars["Conflicts"].buttons.firstMatch.tap()
        app.navigationBars["Settings"].buttons.firstMatch.tap()
        app.buttons["all-notes-link"].tap()
        XCTAssertTrue(
            app.buttons["markdown-file-row-Projects/UI Lifecycle 2.md"]
                .waitForExistence(timeout: 5)
        )
    }

    func testMarkdownFileTagsAppearInUnifiedTagNavigation() {
        let app = launchApp(reset: true, fixtureFolder: true, fileTag: true)
        let tag = app.buttons["tag-link-#project"]
        XCTAssertTrue(tag.waitForExistence(timeout: 8))
        if !tag.isHittable {
            app.swipeUp()
        }
        if tag.frame.maxY > app.frame.maxY - 180 {
            app.swipeUp()
        }
        XCTAssertTrue(waitForHittable(tag))
        tag.tap()

        XCTAssertTrue(app.navigationBars["#project"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Notes"].exists)
        XCTAssertTrue(app.staticTexts["Quick Notes"].exists)
        XCTAssertTrue(
            app.buttons["markdown-file-row-Projects/UI Lifecycle.md"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Tagged quick capture #project #quick"].exists)
    }

    func testAllTagsBrowserCombinesAndExcludesTags() {
        let app = launchApp(reset: true, fixtureFolder: true, fileTag: true)
        let allTags = app.buttons["all-tags-link"]
        XCTAssertTrue(allTags.waitForExistence(timeout: 8))
        allTags.tap()

        XCTAssertTrue(app.navigationBars["All Tags"].waitForExistence(timeout: 5))
        let note = app.buttons["markdown-file-row-Projects/UI Lifecycle.md"]
        let quickNote = app.staticTexts["Tagged quick capture #project #quick"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue(quickNote.exists)

        let work = app.buttons["tag-filter-#work"]
        XCTAssertTrue(work.exists)
        work.tap()
        XCTAssertTrue(note.exists)
        XCTAssertTrue(waitForNonexistence(quickNote))

        work.tap()
        XCTAssertTrue(waitForNonexistence(note))
        XCTAssertTrue(quickNote.waitForExistence(timeout: 5))

        work.tap()
        let project = app.buttons["tag-filter-#project"]
        let quick = app.buttons["tag-filter-#quick"]
        project.tap()
        quick.tap()
        XCTAssertTrue(app.segmentedControls["tag-match-mode"].exists)
        XCTAssertTrue(note.exists)
        XCTAssertTrue(quickNote.exists)

        app.buttons["All"].tap()
        XCTAssertTrue(waitForNonexistence(note))
        XCTAssertTrue(quickNote.exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Notes-style multi-tag browser"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["clear-tag-filters"].tap()
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue(quickNote.exists)
    }

    func testTagContextMenuRenamesAndDeletesAcrossNotes() {
        let app = launchApp(reset: true, fixtureFolder: true, fileTag: true)
        let allTags = app.buttons["all-tags-link"]
        XCTAssertTrue(allTags.waitForExistence(timeout: 8))
        allTags.tap()

        let project = app.buttons["tag-filter-#project"]
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        project.press(forDuration: 1)
        let rename = app.buttons["Rename #project"]
        XCTAssertTrue(rename.waitForExistence(timeout: 3))
        rename.tap()

        let renameAlert = app.alerts["Rename Tag"]
        XCTAssertTrue(renameAlert.waitForExistence(timeout: 3))
        let name = renameAlert.textFields["Tag Name"]
        XCTAssertEqual(name.value as? String, "project")
        name.tap()
        name.typeText("-client")
        renameAlert.buttons["Rename"].tap()

        let renamed = app.buttons["tag-filter-#project-client"]
        XCTAssertTrue(renamed.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForNonexistence(project))
        XCTAssertTrue(app.staticTexts["Tagged quick capture #project-client #quick"].exists)

        let quick = app.buttons["tag-filter-#quick"]
        quick.press(forDuration: 1)
        let delete = app.buttons["Delete #quick"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        XCTAssertTrue(
            app.staticTexts[
                "The tag will be removed from every active note and quick note. This cannot be undone."
            ].waitForExistence(timeout: 3)
        )
        app.buttons["Remove Tag"].tap()

        XCTAssertTrue(waitForNonexistence(quick))
        XCTAssertTrue(
            app.staticTexts["Tagged quick capture #project-client"].waitForExistence(timeout: 8)
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Notes-style tag rename and delete"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testNotesStyleSelectionPinsMultipleMarkdownNotes() {
        let app = launchApp(reset: true, fixtureFolder: true, batchNotes: true)
        let allNotes = app.buttons["all-notes-link"]
        XCTAssertTrue(allNotes.waitForExistence(timeout: 8))
        allNotes.tap()

        let options = app.buttons["note-list-options"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        app.buttons["Select Notes"].tap()

        let first = app.buttons["selectable-note-row-Projects/UI Lifecycle.md"]
        let second = app.buttons["selectable-note-row-Projects/Second UI Note.md"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.exists)
        first.tap()
        second.tap()
        XCTAssertTrue(app.navigationBars["2 Selected"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["toggle-select-all-notes"].exists)

        let pin = app.buttons["pin-selected-notes"]
        XCTAssertTrue(pin.exists)
        pin.tap()
        XCTAssertTrue(app.navigationBars["All Notes"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.images["pin-indicator-Projects/UI Lifecycle.md"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.images["pin-indicator-Projects/Second UI Note.md"].exists)
    }

    func testNotesStyleSelectionMovesMultipleNotesToTopLevel() {
        let app = launchApp(reset: true, fixtureFolder: true, batchNotes: true)
        XCTAssertTrue(app.buttons["all-notes-link"].waitForExistence(timeout: 8))
        app.buttons["all-notes-link"].tap()

        let options = app.buttons["note-list-options"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        app.buttons["Select Notes"].tap()

        let first = app.buttons["selectable-note-row-Projects/UI Lifecycle.md"]
        let second = app.buttons["selectable-note-row-Projects/Second UI Note.md"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.exists)
        first.tap()
        second.tap()

        let move = app.buttons["move-selected-notes"]
        XCTAssertTrue(move.waitForExistence(timeout: 5))
        move.tap()
        let topLevel = app.buttons["Top Level"]
        XCTAssertTrue(topLevel.waitForExistence(timeout: 3))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Move selected notes to top level"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        topLevel.tap()
        XCTAssertTrue(app.navigationBars["All Notes"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons["markdown-file-row-UI Lifecycle.md"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["markdown-file-row-Second UI Note.md"].exists)
        XCTAssertFalse(app.buttons["markdown-file-row-Projects/UI Lifecycle.md"].exists)
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

    func testFolderEditModeExposesManagementActionsAndRenamesFolder() {
        let app = launchApp(reset: true, fixtureFolder: true)
        let editButton = app.buttons["edit-folders-button"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 8))
        XCTAssertEqual(editButton.label, "Edit")

        editButton.tap()
        XCTAssertEqual(editButton.label, "Done")

        let managementButton = app.buttons["folder-management-Projects"]
        XCTAssertTrue(managementButton.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["folder-row-Projects"].isHittable)

        let managementScreenshot = XCTAttachment(screenshot: app.screenshot())
        managementScreenshot.name = "Notes-style folder edit mode"
        managementScreenshot.lifetime = .keepAlways
        add(managementScreenshot)

        managementButton.tap()
        XCTAssertTrue(app.buttons["New Subfolder"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Delete Folder"].exists)
        app.buttons["Rename Folder"].tap()

        let alert = app.alerts["Rename Folder"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        let nameField = alert.textFields["Folder Name"]
        nameField.tap()
        nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8))
        nameField.typeText("Work")
        alert.buttons["Rename"].tap()

        XCTAssertTrue(app.buttons["folder-management-Work"].waitForExistence(timeout: 5))
        editButton.tap()
        XCTAssertEqual(editButton.label, "Edit")
        XCTAssertTrue(app.buttons["folder-row-Work"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["folder-management-Work"].exists)
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

    func testSmartFolderCreatesEditsAndDeletesWithoutMovingNotes() {
        let app = launchApp(reset: true, fixtureFolder: true, fileTag: true)
        let newFolder = app.buttons["new-folder-button"]
        XCTAssertTrue(newFolder.waitForExistence(timeout: 8))
        newFolder.tap()

        let folderAlert = app.alerts["New Folder"]
        XCTAssertTrue(folderAlert.waitForExistence(timeout: 3))
        let name = folderAlert.textFields["Folder Name"]
        name.tap()
        name.typeText("Project Notes")
        folderAlert.buttons["Make Into Smart Folder"].tap()

        XCTAssertTrue(app.navigationBars["New Smart Folder"].waitForExistence(timeout: 5))
        let project = app.buttons["smart-folder-tag-#project"]
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        project.tap()
        app.buttons["save-smart-folder"].tap()

        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "smart-folder-row-")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Project Notes"].exists)
        row.tap()

        XCTAssertTrue(app.navigationBars["Project Notes"].waitForExistence(timeout: 5))
        let note = app.buttons["markdown-file-row-Projects/UI Lifecycle.md"]
        let quickNote = app.staticTexts["Tagged quick capture #project #quick"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue(quickNote.exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Notes-style Smart Folder"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.navigationBars["Project Notes"].buttons.firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 1)
        let edit = app.buttons["Edit Smart Folder"]
        XCTAssertTrue(edit.waitForExistence(timeout: 3))
        edit.tap()

        XCTAssertTrue(app.navigationBars["Edit Smart Folder"].waitForExistence(timeout: 5))
        let quick = app.buttons["smart-folder-tag-#quick"]
        XCTAssertTrue(quick.waitForExistence(timeout: 3))
        quick.tap()
        app.buttons["save-smart-folder"].tap()

        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        XCTAssertTrue(quickNote.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForNonexistence(note))

        app.navigationBars["Project Notes"].buttons.firstMatch.tap()
        row.press(forDuration: 1)
        let delete = app.buttons["Delete Smart Folder"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        XCTAssertTrue(app.staticTexts["Notes stay in their original folders."].waitForExistence(timeout: 3))
        app.buttons["Delete Smart Folder"].tap()
        XCTAssertTrue(waitForNonexistence(row))

        app.buttons["all-notes-link"].tap()
        XCTAssertTrue(note.waitForExistence(timeout: 5))
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
        let app = launchApp(reset: true, fixtureFolder: true, scanText: true)
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
        XCTAssertTrue(app.staticTexts["note-modified-date"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Inbox.md"].exists)
        XCTAssertFalse(app.buttons["Raw"].exists)
        let rendered = app.descendants(matching: .any)["rendered-markdown"]
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))
        rendered.tap()
        let editor = app.textViews["markdown-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["collapse-markdown-editor"].waitForExistence(timeout: 5))
        let attachmentMenu = app.buttons["markdown-attachment-menu"]
        XCTAssertTrue(attachmentMenu.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["markdown-record-audio"].exists)
        XCTAssertTrue(app.buttons["markdown-format-menu"].exists)
        XCTAssertTrue(app.buttons["markdown-format-checklist"].exists)
        XCTAssertTrue(app.buttons["markdown-format-table"].exists)
        XCTAssertTrue(app.buttons["markdown-format-undo"].exists)
        XCTAssertTrue(app.buttons["markdown-format-redo"].exists)
        attachmentMenu.tap()
        XCTAssertTrue(app.buttons["Choose Photo or Video"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Take Photo or Video"].exists)
        XCTAssertTrue(app.buttons["Add Drawing"].exists)
        XCTAssertTrue(app.buttons["Add File"].exists)
        XCTAssertTrue(app.buttons["Scan Document"].exists)
        let scanText = app.buttons["Scan Text"]
        XCTAssertTrue(scanText.exists)
        scanText.tap()
        XCTAssertTrue(
            waitForValue(of: editor, containing: "Scanned into Markdown")
        )
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

        app.buttons["markdown-format-menu"].tap()
        let bold = app.buttons["Bold"]
        XCTAssertTrue(bold.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Title"].exists)
        XCTAssertTrue(app.buttons["Heading"].exists)
        XCTAssertTrue(app.buttons["Subheading"].exists)
        XCTAssertTrue(app.buttons["Body"].exists)
        XCTAssertTrue(app.buttons["Underline"].exists)
        XCTAssertTrue(app.buttons["Highlight"].exists)
        XCTAssertTrue(app.buttons["Strikethrough"].exists)
        XCTAssertTrue(app.buttons["Numbered List"].exists)
        XCTAssertTrue(app.buttons["Decrease Indent"].exists)
        XCTAssertTrue(app.buttons["Increase Indent"].exists)

        let paragraphStylesScreenshot = XCTAttachment(screenshot: app.screenshot())
        paragraphStylesScreenshot.name = "Paragraph styles menu"
        paragraphStylesScreenshot.lifetime = .keepAlways
        add(paragraphStylesScreenshot)

        bold.tap()
        editor.typeText("Styled")
        XCTAssertTrue((editor.value as? String)?.contains("**Styled**") == true)
        app.buttons["markdown-format-menu"].tap()
        let underline = app.buttons["Underline"]
        XCTAssertTrue(underline.waitForExistence(timeout: 3))
        underline.tap()
        editor.typeText("Important")
        XCTAssertTrue((editor.value as? String)?.contains("<u>Important</u>") == true)
        app.buttons["markdown-format-menu"].tap()
        let highlight = app.buttons["Highlight"]
        XCTAssertTrue(highlight.waitForExistence(timeout: 3))
        highlight.tap()
        editor.typeText("Emphasized")
        XCTAssertTrue((editor.value as? String)?.contains("<mark>Emphasized</mark>") == true)
        app.buttons["markdown-format-menu"].tap()
        let strikethrough = app.buttons["Strikethrough"]
        XCTAssertTrue(strikethrough.waitForExistence(timeout: 3))
        strikethrough.tap()
        editor.typeText("Archived")
        XCTAssertTrue((editor.value as? String)?.contains("~~Archived~~") == true)
        app.buttons["markdown-format-menu"].tap()
        let insertLink = app.buttons["Insert Link"]
        XCTAssertTrue(insertLink.waitForExistence(timeout: 3))
        insertLink.tap()
        XCTAssertTrue(app.navigationBars["Add Link"].waitForExistence(timeout: 3))
        let linkName = app.textFields["markdown-link-name"]
        let linkDestination = app.textFields["markdown-link-destination"]
        XCTAssertTrue(linkName.exists)
        XCTAssertTrue(linkDestination.exists)

        let linkEditorScreenshot = XCTAttachment(screenshot: app.screenshot())
        linkEditorScreenshot.name = "Notes-style link editor"
        linkEditorScreenshot.lifetime = .keepAlways
        add(linkEditorScreenshot)

        linkName.tap()
        linkName.typeText("Mudsnote")
        linkDestination.tap()
        linkDestination.typeText("muds.top")
        app.buttons["apply-markdown-link"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertTrue(
            (editor.value as? String)?.contains("[Mudsnote](https://muds.top)") == true
        )
        app.buttons["markdown-format-menu"].tap()
        XCTAssertTrue(insertLink.waitForExistence(timeout: 3))
        insertLink.tap()
        XCTAssertTrue(app.navigationBars["Edit Link"].waitForExistence(timeout: 3))
        let removeLink = app.buttons["remove-markdown-link"]
        XCTAssertTrue(removeLink.exists)
        removeLink.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        let unlinkedValue = editor.value as? String
        XCTAssertTrue(unlinkedValue?.contains("Mudsnote") == true)
        XCTAssertFalse(unlinkedValue?.contains("[Mudsnote](https://muds.top)") == true)
        let save = app.buttons["save-markdown-button"]
        XCTAssertTrue(save.exists)
        save.tap()
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))
        let renderedImportant = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Important")
        ).firstMatch
        XCTAssertTrue(renderedImportant.waitForExistence(timeout: 3))
        let renderedEmphasized = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Emphasized")
        ).firstMatch
        XCTAssertTrue(renderedEmphasized.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "<u>")
        ).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "<mark>")
        ).firstMatch.exists)

        let renderedFormatsScreenshot = XCTAttachment(screenshot: app.screenshot())
        renderedFormatsScreenshot.name = "Rendered inline formats"
        renderedFormatsScreenshot.lifetime = .keepAlways
        add(renderedFormatsScreenshot)
    }

    func testEditorLinksToAnotherNoteAndReturnsThroughHistory() {
        let app = launchApp(reset: true, fixtureFolder: true)
        let allNotes = app.buttons["all-notes-link"]
        XCTAssertTrue(allNotes.waitForExistence(timeout: 8))
        allNotes.tap()

        let inbox = app.buttons["markdown-file-row-Inbox.md"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 5))
        inbox.tap()
        let rendered = app.descendants(matching: .any)["rendered-markdown"]
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))
        rendered.tap()

        let editor = app.textViews["markdown-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        app.buttons["markdown-format-menu"].tap()
        let insertLink = app.buttons["Insert Link"]
        XCTAssertTrue(insertLink.waitForExistence(timeout: 3))
        insertLink.tap()

        XCTAssertTrue(app.navigationBars["Add Link"].waitForExistence(timeout: 3))
        let chooseNote = app.buttons["choose-note-link"]
        XCTAssertTrue(chooseNote.waitForExistence(timeout: 3))
        chooseNote.tap()
        XCTAssertTrue(app.navigationBars["Link to Note"].waitForExistence(timeout: 3))

        let candidate = app.buttons["note-link-candidate-Projects/UI Lifecycle.md"]
        XCTAssertTrue(candidate.waitForExistence(timeout: 3))
        candidate.tap()
        XCTAssertTrue(app.navigationBars["Add Link"].waitForExistence(timeout: 3))

        let name = app.textFields["markdown-link-name"]
        let destination = app.textFields["markdown-link-destination"]
        XCTAssertEqual(name.value as? String, "UI Lifecycle")
        XCTAssertEqual(destination.value as? String, "./Projects/UI%20Lifecycle.md")
        app.buttons["apply-markdown-link"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertTrue(
            (editor.value as? String)?.contains(
                "[UI Lifecycle](./Projects/UI%20Lifecycle.md)"
            ) == true
        )

        app.buttons["save-markdown-button"].tap()
        let linkedText = app.links["UI Lifecycle"]
        XCTAssertTrue(linkedText.waitForExistence(timeout: 5))
        let readerSettled = expectation(description: "Reader toolbar transition settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { readerSettled.fulfill() }
        wait(for: [readerSettled], timeout: 1)

        let linkScreenshot = XCTAttachment(screenshot: app.screenshot())
        linkScreenshot.name = "Rendered local note link"
        linkScreenshot.lifetime = .keepAlways
        add(linkScreenshot)

        linkedText.tap()
        let targetBody = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Restore this note end to end.")
        ).firstMatch
        XCTAssertTrue(targetBody.waitForExistence(timeout: 5))
        let previous = app.buttons["previous-linked-note"]
        XCTAssertTrue(previous.exists)
        previous.tap()
        XCTAssertTrue(app.links["UI Lifecycle"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["previous-linked-note"].exists)
    }

    func testRenderedNoteDetectsEmailAndPhoneActions() {
        let app = launchApp(reset: true, fixtureFolder: true)
        let allNotes = app.buttons["all-notes-link"]
        XCTAssertTrue(allNotes.waitForExistence(timeout: 8))
        allNotes.tap()

        let note = app.buttons["markdown-file-row-Projects/UI Lifecycle.md"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()

        let email = app.links["support@example.com"]
        let phone = app.links["+1 (415) 555-0123"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        XCTAssertTrue(phone.exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Notes-style detected email and phone actions"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testDocumentDrawingSavesAsPortableMarkdownImage() {
        let app = launchApp(reset: true, fixtureFolder: true)
        let allNotes = app.buttons["all-notes-link"]
        XCTAssertTrue(allNotes.waitForExistence(timeout: 8))
        allNotes.tap()

        let inbox = app.buttons["markdown-file-row-Inbox.md"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 5))
        inbox.tap()
        let rendered = app.descendants(matching: .any)["rendered-markdown"]
        XCTAssertTrue(rendered.waitForExistence(timeout: 5))
        rendered.tap()

        let attachmentMenu = app.buttons["markdown-attachment-menu"]
        XCTAssertTrue(attachmentMenu.waitForExistence(timeout: 5))
        attachmentMenu.tap()
        let addDrawing = app.buttons["Add Drawing"]
        XCTAssertTrue(addDrawing.waitForExistence(timeout: 3))
        addDrawing.tap()

        let canvas = app.descendants(matching: .any)["markdown-drawing-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let saveDrawing = app.buttons["save-markdown-drawing"]
        XCTAssertTrue(saveDrawing.exists)
        XCTAssertFalse(saveDrawing.isEnabled)

        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.3))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.55))
        start.press(forDuration: 0.1, thenDragTo: end)
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: saveDrawing
        )
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)

        let drawingScreenshot = XCTAttachment(screenshot: app.screenshot())
        drawingScreenshot.name = "Notes-style drawing editor"
        drawingScreenshot.lifetime = .keepAlways
        add(drawingScreenshot)

        saveDrawing.tap()
        let editor = app.textViews["markdown-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        let displayMode = app.buttons["markdown-display-mode"]
        XCTAssertTrue(displayMode.waitForExistence(timeout: 5))
        displayMode.tap()
        XCTAssertTrue(app.buttons["Markdown Source"].waitForExistence(timeout: 3))
        app.buttons["Markdown Source"].tap()

        let containsPortableImage = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "![Image](Attachments/"),
            object: editor
        )
        XCTAssertEqual(XCTWaiter.wait(for: [containsPortableImage], timeout: 8), .completed)
        XCTAssertTrue((editor.value as? String)?.contains(".png)") == true)
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

    func testRenderedNoteExposesLocalSystemShare() {
        let app = launchApp(reset: true, fixtureFolder: true)
        XCTAssertTrue(app.buttons["all-notes-link"].waitForExistence(timeout: 8))
        app.buttons["all-notes-link"].tap()
        let note = app.buttons["markdown-file-row-Projects/UI Lifecycle.md"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()

        let options = app.buttons["note-options-menu"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        XCTAssertTrue(app.buttons["Share Note"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Find in Note"].exists)
        XCTAssertTrue(app.buttons["Pin"].exists)
        XCTAssertTrue(app.buttons["Move Note"].exists)
        XCTAssertTrue(app.buttons["Duplicate Note"].exists)
        XCTAssertTrue(app.buttons["Rename Note"].exists)
        XCTAssertTrue(app.buttons["Move to Recently Deleted"].exists)
    }

    func testRenderedNoteFindHighlightsAndNavigatesMatches() {
        let app = launchApp(reset: true, fixtureFolder: true)
        XCTAssertTrue(app.buttons["all-notes-link"].waitForExistence(timeout: 8))
        app.buttons["all-notes-link"].tap()
        let note = app.buttons["markdown-file-row-Projects/UI Lifecycle.md"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()

        let options = app.buttons["note-options-menu"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        let find = app.buttons["Find in Note"]
        XCTAssertTrue(find.waitForExistence(timeout: 3))
        find.tap()

        let field = app.textFields["find-in-note-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
        field.typeText("Restore")
        let count = app.staticTexts["find-in-note-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 3))
        XCTAssertEqual(count.label, "1 of 1")
        XCTAssertTrue(app.buttons["find-in-note-previous"].isEnabled)
        XCTAssertTrue(app.buttons["find-in-note-next"].isEnabled)
        app.buttons["find-in-note-next"].tap()

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Find in rendered note"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["finish-find-in-note"].tap()
        XCTAssertTrue(waitForNonexistence(field))
        XCTAssertTrue(app.descendants(matching: .any)["rendered-markdown"].exists)
    }

    func testRenderedHeadingCollapsesSectionAndFindRevealsItsContent() {
        let app = launchApp(reset: true, fixtureFolder: true)
        XCTAssertTrue(app.buttons["all-notes-link"].waitForExistence(timeout: 8))
        app.buttons["all-notes-link"].tap()
        let note = app.buttons["markdown-file-row-Projects/UI Lifecycle.md"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()

        let body = app.staticTexts["Restore this note end to end."]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        let toggle = app.buttons["markdown-section-toggle-0"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        XCTAssertTrue(waitForNonexistence(body))

        let collapsedScreenshot = XCTAttachment(screenshot: app.screenshot())
        collapsedScreenshot.name = "Collapsed Markdown heading"
        collapsedScreenshot.lifetime = .keepAlways
        add(collapsedScreenshot)

        toggle.tap()
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        toggle.tap()
        XCTAssertTrue(waitForNonexistence(body))

        let options = app.buttons["note-options-menu"]
        XCTAssertTrue(options.exists)
        options.tap()
        let find = app.buttons["Find in Note"]
        XCTAssertTrue(find.waitForExistence(timeout: 3))
        find.tap()
        let field = app.textFields["find-in-note-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Restore")
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["find-in-note-count"].label, "1 of 1")
    }

    func testOpenedNoteCanBeRenamedWithoutLeavingTheReader() {
        let app = launchApp(reset: true, fixtureFolder: true)
        XCTAssertTrue(app.buttons["all-notes-link"].waitForExistence(timeout: 8))
        app.buttons["all-notes-link"].tap()
        let note = app.buttons["markdown-file-row-Projects/UI Lifecycle.md"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()

        let options = app.buttons["note-options-menu"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        let rename = app.buttons["Rename Note"]
        XCTAssertTrue(rename.waitForExistence(timeout: 3))

        let optionsScreenshot = XCTAttachment(screenshot: app.screenshot())
        optionsScreenshot.name = "Opened note options"
        optionsScreenshot.lifetime = .keepAlways
        add(optionsScreenshot)

        rename.tap()
        let alert = app.alerts["Rename Note"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        let name = alert.textFields["Note Name"]
        XCTAssertEqual(name.value as? String, "UI Lifecycle")
        name.tap()
        name.typeText("-Renamed")
        alert.buttons["Rename"].tap()

        XCTAssertTrue(options.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["rendered-markdown"].exists)
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        let renamed = app.buttons["markdown-file-row-Projects/UI Lifecycle-Renamed.md"]
        XCTAssertTrue(renamed.waitForExistence(timeout: 5))
        renamed.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Rename Note"].waitForExistence(timeout: 3))
    }

    func testOpenedNoteCanMoveAndDeleteWithoutReturningForListActions() {
        let app = launchApp(reset: true, fixtureFolder: true)
        XCTAssertTrue(app.buttons["all-notes-link"].waitForExistence(timeout: 8))
        app.buttons["all-notes-link"].tap()
        let note = app.buttons["markdown-file-row-Projects/UI Lifecycle.md"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()

        let options = app.buttons["note-options-menu"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        app.buttons["Move Note"].tap()
        let topLevel = app.buttons["Top Level"]
        XCTAssertTrue(topLevel.waitForExistence(timeout: 3))
        topLevel.tap()

        XCTAssertTrue(options.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["rendered-markdown"].exists)
        options.tap()

        let optionsScreenshot = XCTAttachment(screenshot: app.screenshot())
        optionsScreenshot.name = "Complete opened note actions"
        optionsScreenshot.lifetime = .keepAlways
        add(optionsScreenshot)

        app.buttons["Move to Recently Deleted"].tap()
        let confirmation = app.sheets["Move Note to Recently Deleted?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.buttons["Move to Recently Deleted"].tap()

        XCTAssertTrue(waitForNonexistence(options))
        XCTAssertTrue(waitForNonexistence(app.buttons["markdown-file-row-UI Lifecycle.md"]))
        app.navigationBars["All Notes"].buttons.firstMatch.tap()
        app.buttons["recently-deleted-link"].tap()
        XCTAssertTrue(app.staticTexts["UI Lifecycle"].waitForExistence(timeout: 5))
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

    func testLibrarySearchSuggestionsFilterAndReturnToTextSearch() {
        let app = launchApp(reset: true, fixtureFolder: true)
        XCTAssertTrue(app.buttons["all-notes-link"].waitForExistence(timeout: 8))

        let search = app.textFields["library-search-field"]
        search.tap()
        let attachments = app.buttons["search-suggestion-attachments"]
        XCTAssertTrue(attachments.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["search-suggestion-pinned"].exists)
        XCTAssertTrue(app.buttons["search-suggestion-checklists"].exists)
        XCTAssertTrue(app.buttons["search-suggestion-editedToday"].exists)
        attachments.tap()

        let result = app.buttons["search-result-file:Projects/UI Lifecycle.md"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Notes-style attachment search suggestion"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let scope = app.segmentedControls["search-scope-picker"]
        scope.buttons["Inbox"].tap()
        XCTAssertTrue(app.staticTexts["No Results"].waitForExistence(timeout: 5))
        scope.buttons["All"].tap()
        XCTAssertTrue(result.waitForExistence(timeout: 5))

        search.tap()
        search.typeText("Restore")
        XCTAssertFalse(attachments.exists)
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        app.buttons["clear-library-search"].tap()
        XCTAssertTrue(app.buttons["all-notes-link"].waitForExistence(timeout: 5))
    }

    func testLibrarySearchFindsTextInsideImageAttachment() {
        let app = launchApp(
            reset: true,
            fixtureFolder: true,
            ocrAttachment: true
        )
        XCTAssertTrue(app.buttons["all-notes-link"].waitForExistence(timeout: 8))
        let search = app.textFields["library-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("ORBITAL")

        let result = app.buttons["search-result-file:Projects/OCR Attachment.md"]
        XCTAssertTrue(result.waitForExistence(timeout: 20))
        XCTAssertTrue(result.label.localizedCaseInsensitiveContains("ORBITAL"))
        XCTAssertTrue(result.label.contains("ocr-search.png"))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Attachment OCR search result"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        result.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["preview-attachment-Attachments/ocr-search.png"]
                .waitForExistence(timeout: 8)
        )
    }

    func testFindInNoteIncludesReferencedAttachmentText() {
        let app = launchApp(
            reset: true,
            fixtureFolder: true,
            ocrAttachment: true
        )
        XCTAssertTrue(app.buttons["all-notes-link"].waitForExistence(timeout: 8))
        app.buttons["all-notes-link"].tap()
        let note = app.buttons["markdown-file-row-Projects/OCR Attachment.md"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()

        let options = app.buttons["note-options-menu"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        let find = app.buttons["Find in Note"]
        XCTAssertTrue(find.waitForExistence(timeout: 3))
        find.tap()

        let findOptions = app.buttons["find-in-note-options"]
        XCTAssertTrue(findOptions.waitForExistence(timeout: 5))
        findOptions.tap()
        let includeAttachments = app.buttons["Include Attachments"]
        XCTAssertTrue(includeAttachments.waitForExistence(timeout: 3))
        includeAttachments.tap()

        let field = app.textFields["find-in-note-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("ORBITAL")
        let match = app.descendants(matching: .any)[
            "find-attachment-match-Attachments/ocr-search.png"
        ]
        XCTAssertTrue(match.waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["find-in-note-count"].label, "1 of 1")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Find text inside current note attachment"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testRecordedAudioTranscriptRendersAndRemainsFindable() {
        let app = launchApp(
            reset: true,
            fixtureFolder: true,
            audioTranscript: true
        )
        XCTAssertTrue(app.buttons["all-notes-link"].waitForExistence(timeout: 8))
        app.buttons["all-notes-link"].tap()
        let note = app.buttons["markdown-file-row-Projects/Recorded Meeting.md"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()

        XCTAssertTrue(app.staticTexts["Audio transcription"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Project ORBITAL is approved for launch."].exists)
        let options = app.buttons["note-options-menu"]
        options.tap()
        app.buttons["Find in Note"].tap()
        let field = app.textFields["find-in-note-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("ORBITAL")
        XCTAssertEqual(app.staticTexts["find-in-note-count"].label, "1 of 1")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Searchable recorded audio transcript"
        screenshot.lifetime = .keepAlways
        add(screenshot)
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
        XCTAssertTrue(app.buttons["Newest First"].exists)
        XCTAssertTrue(app.buttons["Oldest First"].exists)
        XCTAssertTrue(app.buttons["View as Gallery"].exists)

        app.tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Notes-style metadata list"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testNoteListKeepsCaptureBarAndScopesFullTextSearch() {
        let app = launchApp(reset: true, fixtureFolder: true)
        XCTAssertTrue(app.buttons["all-notes-link"].waitForExistence(timeout: 8))
        app.buttons["all-notes-link"].tap()

        let search = app.textFields["library-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quick-note-button"].exists)
        XCTAssertTrue(app.buttons["new-note-button"].exists)

        search.tap()
        search.typeText("Restore this note")

        let result = app.buttons["list-search-result-file:Projects/UI Lifecycle.md"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["list-search-result-file:Daily/2026-07-17.md"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Notes-style searchable list capture bar"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        result.tap()
        XCTAssertTrue(app.descendants(matching: .any)["rendered-markdown"].waitForExistence(timeout: 5))
    }

    func testNotesGalleryViewPersistsAndKeepsSelectionActions() {
        let app = launchApp(reset: true, fixtureFolder: true, batchNotes: true)
        let allNotes = app.buttons["all-notes-link"]
        XCTAssertTrue(allNotes.waitForExistence(timeout: 8))
        allNotes.tap()

        let options = app.buttons["note-list-options"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        let gallery = app.buttons["View as Gallery"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 3))
        gallery.tap()

        let galleryContainer = app.scrollViews["note-gallery"]
        XCTAssertTrue(galleryContainer.waitForExistence(timeout: 5))
        let first = app.buttons["markdown-file-row-Projects/UI Lifecycle.md"]
        let second = app.buttons["markdown-file-row-Projects/Second UI Note.md"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.exists)
        XCTAssertTrue(second.label.contains("Capture the idea"))
        XCTAssertTrue(second.label.contains("Refine the draft"))
        XCTAssertLessThan(first.frame.width, app.frame.width * 0.48)
        XCTAssertEqual(first.frame.midY, second.frame.midY, accuracy: 3)
        let gallerySearch = app.textFields["library-search-field"]
        let galleryNewNote = app.buttons["new-note-button"]
        XCTAssertTrue(waitForHittable(gallerySearch))
        XCTAssertTrue(waitForHittable(galleryNewNote))
        XCTAssertLessThanOrEqual(galleryNewNote.frame.maxY, app.frame.maxY)
        XCTAssertGreaterThan(galleryNewNote.frame.minY, app.frame.height * 0.75)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Notes-style gallery view"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        first.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Duplicate Note"].waitForExistence(timeout: 3))
        app.tap()

        options.tap()
        let select = app.buttons["Select Notes"]
        XCTAssertTrue(select.waitForExistence(timeout: 3))
        select.tap()
        let selectable = app.buttons["selectable-note-row-Projects/UI Lifecycle.md"]
        XCTAssertTrue(selectable.waitForExistence(timeout: 5))
        selectable.tap()
        XCTAssertTrue(app.navigationBars["1 Selected"].exists)
        app.buttons["finish-note-selection"].tap()

        app.navigationBars["All Notes"].buttons.firstMatch.tap()
        allNotes.tap()
        XCTAssertTrue(galleryContainer.waitForExistence(timeout: 5))

        options.tap()
        let list = app.buttons["View as List"]
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        list.tap()
        XCTAssertTrue(waitForNonexistence(galleryContainer))
        XCTAssertTrue(first.waitForExistence(timeout: 5))
    }

    func testCaptureCommandsStayInSingleRow() {
        let app = launchApp(reset: true, fixtureFolder: true, scanText: true)
        let quickNoteButton = app.buttons["quick-note-button"]
        XCTAssertTrue(quickNoteButton.waitForExistence(timeout: 8))
        quickNoteButton.tap()

        let labels = ["capture-attachment-menu", "Record audio", "Formatting", "capture-target-menu", "save-memo-button"]
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

        controls[0].tap()
        let attachmentActions = [
            "Choose Photo or Video",
            "Take Photo or Video",
            "Add File",
            "Scan Document",
            "Scan Text",
        ].map { app.buttons[$0] }
        for action in attachmentActions {
            XCTAssertTrue(action.waitForExistence(timeout: 3))
        }
        for name in ["Choose Photo or Video", "Add File", "Scan Text"] {
            XCTAssertTrue(waitForHittable(app.buttons[name]))
        }
        let scanText = app.buttons["Scan Text"]

        let attachmentMenuScreenshot = XCTAttachment(screenshot: app.screenshot())
        attachmentMenuScreenshot.name = "Quick capture attachment menu"
        attachmentMenuScreenshot.lifetime = .keepAlways
        add(attachmentMenuScreenshot)

        scanText.tap()
        let editor = app.textViews["capture-body-editor"]
        XCTAssertTrue(waitForValue(of: editor, containing: "Scanned into Markdown"))
    }

    func testAttachmentLibraryShowsStoredFiles() {
        let app = launchApp(reset: true, fixtureFolder: true)
        let attachments = app.buttons["attachments-link"]
        XCTAssertTrue(attachments.waitForExistence(timeout: 8))
        attachments.tap()

        let storedImage = app.buttons["attachment-row-Attachments/ui-test.png"]
        XCTAssertTrue(storedImage.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ui-test.png"].exists)
        let storedDocument = app.buttons["attachment-row-Attachments/ui-test.txt"]
        XCTAssertTrue(storedDocument.exists)
        let storedVideo = app.buttons["attachment-row-Attachments/ui-test.mp4"]
        XCTAssertTrue(storedVideo.exists)
        XCTAssertTrue(app.buttons["attachment-category-all"].exists)
        XCTAssertTrue(app.buttons["attachment-category-photos"].exists)
        XCTAssertTrue(app.buttons["attachment-category-videos"].exists)
        XCTAssertTrue(app.buttons["attachment-category-audio"].exists)
        XCTAssertTrue(app.buttons["attachment-category-documents"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Notes-style categorized attachment browser"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["attachment-category-videos"].tap()
        XCTAssertTrue(storedVideo.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForNonexistence(storedImage))
        XCTAssertTrue(waitForNonexistence(storedDocument))

        app.buttons["attachment-category-documents"].tap()
        XCTAssertTrue(storedDocument.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForNonexistence(storedImage))

        storedDocument.press(forDuration: 1)
        let showInNote = app.buttons["show-attachment-in-note-Attachments/ui-test.txt"]
        XCTAssertTrue(showInNote.waitForExistence(timeout: 3))
        showInNote.tap()
        XCTAssertTrue(
            app.buttons["preview-attachment-Attachments/ui-test.txt"]
                .waitForExistence(timeout: 5)
        )
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

    func testRecentlyDeletedSelectionRestoresAndPermanentlyDeletesMultipleNotes() {
        let app = launchApp(reset: true, fixtureFolder: true, batchNotes: true)
        let allNotes = app.buttons["all-notes-link"]
        XCTAssertTrue(allNotes.waitForExistence(timeout: 8))
        allNotes.tap()

        app.buttons["Sort Notes"].tap()
        let selectNotes = app.buttons["Select Notes"]
        XCTAssertTrue(selectNotes.waitForExistence(timeout: 3))
        selectNotes.tap()
        app.buttons["selectable-note-row-Projects/UI Lifecycle.md"].tap()
        app.buttons["selectable-note-row-Projects/Second UI Note.md"].tap()
        app.buttons["delete-selected-notes"].tap()
        let moveToDeleted = app.buttons["Move to Recently Deleted"]
        XCTAssertTrue(moveToDeleted.waitForExistence(timeout: 3))
        moveToDeleted.tap()
        XCTAssertTrue(app.navigationBars["All Notes"].waitForExistence(timeout: 5))

        app.navigationBars["All Notes"].buttons.firstMatch.tap()
        let recentlyDeleted = app.buttons["recently-deleted-link"]
        XCTAssertTrue(recentlyDeleted.waitForExistence(timeout: 5))
        recentlyDeleted.tap()

        let options = app.buttons["Recently Deleted Options"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        XCTAssertTrue(selectNotes.waitForExistence(timeout: 3))
        selectNotes.tap()
        let first = app.staticTexts["UI Lifecycle"]
        let second = app.staticTexts["Second UI Note"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(second.exists)
        first.tap()
        second.tap()
        XCTAssertTrue(app.navigationBars["2 Selected"].exists)

        app.buttons["restore-selected-deleted-notes"].tap()
        XCTAssertTrue(app.staticTexts["No Recently Deleted Notes"].waitForExistence(timeout: 5))
        app.navigationBars["Recently Deleted"].buttons.firstMatch.tap()
        allNotes.tap()
        XCTAssertTrue(
            app.buttons["markdown-file-row-Projects/UI Lifecycle.md"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["markdown-file-row-Projects/Second UI Note.md"].exists)

        app.buttons["Sort Notes"].tap()
        XCTAssertTrue(selectNotes.waitForExistence(timeout: 3))
        selectNotes.tap()
        app.buttons["selectable-note-row-Projects/UI Lifecycle.md"].tap()
        app.buttons["selectable-note-row-Projects/Second UI Note.md"].tap()
        app.buttons["delete-selected-notes"].tap()
        XCTAssertTrue(moveToDeleted.waitForExistence(timeout: 3))
        moveToDeleted.tap()
        XCTAssertTrue(app.navigationBars["All Notes"].waitForExistence(timeout: 5))

        app.navigationBars["All Notes"].buttons.firstMatch.tap()
        recentlyDeleted.tap()
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        XCTAssertTrue(selectNotes.waitForExistence(timeout: 3))
        selectNotes.tap()
        let selectAll = app.buttons["toggle-select-all-deleted-notes"]
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5))
        selectAll.tap()
        XCTAssertTrue(app.navigationBars["2 Selected"].exists)
        app.buttons["permanently-delete-selected-notes"].tap()
        let deletePermanently = app.buttons["Delete Permanently"]
        XCTAssertTrue(deletePermanently.waitForExistence(timeout: 3))
        deletePermanently.tap()
        XCTAssertTrue(app.staticTexts["No Recently Deleted Notes"].waitForExistence(timeout: 5))
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
    }

    @discardableResult
    private func launchApp(
        reset: Bool,
        fixtureFolder: Bool,
        invalidBookmark: Bool = false,
        damagedDraft: Bool = false,
        damagedQueue: Bool = false,
        conflictCopy: Bool = false,
        fileTag: Bool = false,
        batchNotes: Bool = false,
        ocrAttachment: Bool = false,
        audioTranscript: Bool = false,
        attachmentError: Bool = false,
        interruptedWrite: Bool = false,
        scanText: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            reset ? "-ui-testing-reset" : nil,
            fixtureFolder ? "-ui-testing-fixture-folder" : nil,
            invalidBookmark ? "-ui-testing-invalid-bookmark" : nil,
            damagedDraft ? "-ui-testing-damaged-draft" : nil,
            damagedQueue ? "-ui-testing-damaged-queue" : nil,
            conflictCopy ? "-ui-testing-conflict-copy" : nil,
            fileTag ? "-ui-testing-file-tag" : nil,
            batchNotes ? "-ui-testing-batch-notes" : nil,
            ocrAttachment ? "-ui-testing-ocr-attachment" : nil,
            audioTranscript ? "-ui-testing-audio-transcript" : nil,
            attachmentError ? "-ui-testing-attachment-error" : nil,
            interruptedWrite ? "-ui-testing-interrupted-write" : nil,
            scanText ? "-ui-testing-scan-text" : nil
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

    private func waitForValue(of element: XCUIElement, containing text: String) -> Bool {
        let predicate = NSPredicate(format: "value CONTAINS %@", text)
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
