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

    func testContinuousCaptureClearsDraftAndKeepsSelectedTarget() {
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
        XCTAssertTrue(app.staticTexts["Saved. Ready for next"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForEmptyValue(of: editor))
        XCTAssertTrue(editor.exists)

        targetMenu.tap()
        let dailyButton = app.buttons["Daily"]
        XCTAssertTrue(dailyButton.waitForExistence(timeout: 5))
        dailyButton.tap()
        XCTAssertEqual(targetMenu.value as? String, "Daily")

        editor.tap()
        editor.typeText("Second UI memo")
        saveButton.tap()
        XCTAssertTrue(waitForEmptyValue(of: editor))
        XCTAssertEqual(targetMenu.value as? String, "Daily")
        XCTAssertTrue(editor.exists)
    }

    @discardableResult
    private func launchApp(reset: Bool, fixtureFolder: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            reset ? "-ui-testing-reset" : nil,
            fixtureFolder ? "-ui-testing-fixture-folder" : nil
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
}
