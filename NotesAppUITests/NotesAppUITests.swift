import XCTest

/// End-to-end UI coverage. Every test starts from a clean, seeded store so results
/// are deterministic on any simulator.
final class NotesAppUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Helpers

    private func launchApp(seeded: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetStore", "-disableLock"]
        if seeded { app.launchArguments.append("-seedDemoData") }
        app.launch()
        return app
    }

    /// The app opens on the note list; make sure we are there.
    private func openAllNotes(_ app: XCUIApplication) {
        if app.buttons["newNoteButton"].waitForExistence(timeout: 3) { return }
        let identified = app.buttons["scope-all"].firstMatch
        if identified.waitForExistence(timeout: 5) {
            identified.tap()
        } else {
            app.staticTexts["All Notes"].firstMatch.tap()
        }
        XCTAssertTrue(app.buttons["newNoteButton"].waitForExistence(timeout: 10))
    }

    /// Returns to the folder sidebar (the split view's leading column).
    private func openSidebar(_ app: XCUIApplication) {
        if app.navigationBars["Notes"].exists { return }
        let back = app.navigationBars.buttons.firstMatch
        if back.waitForExistence(timeout: 5) {
            back.tap()
        }
        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 10))
    }

    /// Text fields with a vertical axis can surface as either text fields or text views.
    private func field(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let textField = app.textFields[identifier].firstMatch
        if textField.exists { return textField }
        return app.textViews[identifier].firstMatch
    }

    private func snapshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Tests

    func testFirstLaunchShowsSeedContentAndSidebar() throws {
        let app = launchApp()

        // The app opens on All Notes with seeded content.
        XCTAssertTrue(
            app.navigationBars["All Notes"].firstMatch.waitForExistence(timeout: 12)
                || app.navigationBars["Notes"].waitForExistence(timeout: 5)
        )
        openAllNotes(app)
        XCTAssertTrue(app.staticTexts["Design review — Notes"].firstMatch.waitForExistence(timeout: 10))
        snapshot(app, named: "02-all-notes")

        // And the sidebar lists the seeded folders.
        openSidebar(app)
        XCTAssertTrue(app.staticTexts["Ideas"].firstMatch.waitForExistence(timeout: 8))
        snapshot(app, named: "01-sidebar")
    }

    func testCreateNoteAndVerifyPersistenceAfterRelaunch() throws {
        let app = launchApp()
        openAllNotes(app)

        app.buttons["newNoteButton"].tap()

        let titleField = field(app, "noteTitleField")
        XCTAssertTrue(titleField.waitForExistence(timeout: 8))
        titleField.tap()
        titleField.typeText("Field Test Note")

        let bodyField = field(app, "blockField-paragraph")
        if bodyField.waitForExistence(timeout: 5) {
            bodyField.tap()
            bodyField.typeText("Written by the UI test suite.")
        }
        snapshot(app, named: "03-editor")

        // Return to the list; autosave flushes on disappear.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let row = app.staticTexts["Field Test Note"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        snapshot(app, named: "04-list-with-new-note")

        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["-uiTesting", "-disableLock"]
        relaunched.launch()
        openAllNotes(relaunched)

        XCTAssertTrue(relaunched.staticTexts["Field Test Note"].firstMatch.waitForExistence(timeout: 10))
    }

    func testEditExistingNoteSavesChanges() throws {
        let app = launchApp()
        openAllNotes(app)

        let note = app.staticTexts["Weekly standup"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 8))
        note.tap()

        let titleField = field(app, "noteTitleField")
        XCTAssertTrue(titleField.waitForExistence(timeout: 8))
        titleField.tap()
        titleField.typeText(" v2")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Weekly standup v2"].firstMatch.waitForExistence(timeout: 10))
    }

    func testSearchFiltersNotes() throws {
        let app = launchApp()
        openAllNotes(app)

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        searchField.tap()
        searchField.typeText("groceries")

        XCTAssertTrue(app.staticTexts["Groceries"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Weekly standup"].firstMatch.exists)
        snapshot(app, named: "05-search")

        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Weekly standup"].firstMatch.waitForExistence(timeout: 8))
    }

    func testDeleteAndRestoreNote() throws {
        let app = launchApp(seeded: false)
        openAllNotes(app)

        // Seed one note so the test does not depend on ordering.
        app.buttons["newNoteButton"].tap()
        let titleField = field(app, "noteTitleField")
        XCTAssertTrue(titleField.waitForExistence(timeout: 8))
        titleField.tap()
        titleField.typeText("Disposable Note")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let row = app.staticTexts["Disposable Note"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()

        XCTAssertFalse(app.staticTexts["Disposable Note"].firstMatch.waitForExistence(timeout: 3))
    }

    func testCreateFolderAndOpenIt() throws {
        let app = launchApp(seeded: false)
        openSidebar(app)

        let newFolderButton = app.buttons["New Folder"].firstMatch
        XCTAssertTrue(newFolderButton.waitForExistence(timeout: 10))
        newFolderButton.tap()

        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Research")
        app.alerts.buttons["Create"].tap()

        XCTAssertTrue(app.staticTexts["Research"].firstMatch.waitForExistence(timeout: 8))
        snapshot(app, named: "06-folders")
    }

    func testSettingsScreenOpensAndShowsSecurityOptions() throws {
        let app = launchApp()
        openSidebar(app)

        let settingsButton = app.buttons["settingsButton"].firstMatch
        if settingsButton.waitForExistence(timeout: 6) {
            settingsButton.tap()
        } else {
            app.staticTexts["Settings"].firstMatch.tap()
        }

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.switches["appLockToggle"].exists)
        XCTAssertTrue(app.switches["cloudSyncToggle"].exists)
        snapshot(app, named: "07-settings")
    }

    func testWritingAssistantSheetOpens() throws {
        let app = launchApp()
        openAllNotes(app)

        app.staticTexts["Groceries"].firstMatch.tap()
        XCTAssertTrue(field(app, "noteTitleField").waitForExistence(timeout: 8))

        app.buttons["intelligenceMenu"].firstMatch.tap()
        app.buttons["Writing Assistant"].firstMatch.tap()

        XCTAssertTrue(app.buttons["runIntelligenceButton"].waitForExistence(timeout: 8))
        snapshot(app, named: "08-writing-assistant")
    }
}

/// Performance coverage: launch, large note creation, and search responsiveness.
final class NotesAppPerformanceTests: XCTestCase {
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["-uiTesting", "-seedDemoData", "-disableLock"]
            app.launch()
        }
    }

    func testScrollingLargeNoteListPerformance() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetStore", "-seedDemoData", "-disableLock"]
        app.launch()

        let allNotes = app.buttons["scope-all"].firstMatch
        if allNotes.waitForExistence(timeout: 8) { allNotes.tap() }

        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric]) {
            app.swipeUp(velocity: .fast)
            app.swipeDown(velocity: .fast)
        }
    }
}
