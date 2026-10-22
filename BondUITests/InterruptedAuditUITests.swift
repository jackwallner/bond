import XCTest

/// Persona audit flows for a tired, busy user who is interrupted mid-task
/// (home button, another app, a notification tap, a relaunch) and expects the
/// half-finished work and their place in the app to survive. Runs on the paired
/// demo fixture (`-BondScreenshotSeed`, local only). Each test attaches
/// screenshots and notes; the tests are exploratory and only assert that the
/// app launched.
final class InterruptedAuditUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(extra: [String] = []) {
        app = XCUIApplication(bundleIdentifier: "com.jackwallner.bond")
        app.launchArguments += ["-BondScreenshotSeed"] + extra
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Reminders"].waitForExistence(timeout: 30), "tab bar never appeared")
        dismissPrimerIfPresent()
    }

    private func dismissPrimerIfPresent() {
        let later = app.buttons["Maybe later"]
        if later.waitForExistence(timeout: 6) {
            later.tap()
            sleep(1)
        }
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func note(_ name: String, _ text: String) {
        let a = XCTAttachment(string: text)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    private func dumpTexts(_ name: String) {
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(60).map { $0.label }
        let fields = app.textFields.allElementsBoundByIndex.prefix(10).map { "\($0.label)=\($0.value ?? "nil")" }
        note(name, "TEXTS:\n" + texts.joined(separator: "\n") + "\n\nFIELDS:\n" + fields.joined(separator: "\n"))
    }

    private func tab(_ name: String) {
        app.tabBars.buttons[name].tap()
        sleep(1)
    }

    /// Send the app to the background and bring it back, as a phone call, a
    /// text or a quick app switch would.
    private func interruptWithHome(seconds: UInt32 = 3) {
        XCUIDevice.shared.press(.home)
        sleep(seconds)
        app.activate()
        sleep(2)
    }

    private func fieldValue(_ element: XCUIElement) -> String {
        "\(element.value ?? "nil")"
    }

    // MARK: - 1. New reminder: home button mid-typing

    func testNewReminderSurvivesBackgrounding() {
        launch()
        app.buttons["Add reminder"].tap()
        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Pick up flowers on the way home")
        let noteField = app.textFields["Note (optional)"]
        if noteField.exists {
            noteField.tap()
            noteField.typeText("Tulips, she likes the yellow ones")
        }
        shot("10-editor-typed-before-interrupt")
        interruptWithHome()
        shot("11-editor-after-home-and-return")
        note("title after background", fieldValue(app.textFields["Title"]))
        note("note after background", fieldValue(app.textFields["Note (optional)"]))
        note("keyboard shown after return", "\(app.keyboards.count)")
        note("editor still presented", "\(app.navigationBars["New reminder"].exists)")
    }

    // MARK: - 2. New reminder: terminate and relaunch

    func testNewReminderAfterRelaunch() {
        launch()
        app.buttons["Add reminder"].tap()
        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Book the table for Friday")
        shot("20-editor-typed-before-kill")
        app.terminate()
        sleep(2)
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Reminders"].waitForExistence(timeout: 30))
        dismissPrimerIfPresent()
        sleep(1)
        shot("21-after-relaunch")
        note("editor visible after relaunch", "\(app.navigationBars["New reminder"].exists)")
        app.buttons["Add reminder"].tap()
        sleep(1)
        shot("22-new-editor-after-relaunch")
        note("title after relaunch", fieldValue(app.textFields["Title"]))
    }

    // MARK: - 3. Accidental swipe-down on an edited form (no keyboard)

    func testSwipeDownDiscardsTypedReminder() {
        launch()
        app.buttons["Add reminder"].tap()
        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Text from the car about tonight")
        // Dismiss the keyboard the way a user would (tap outside the fields),
        // then swipe the sheet down by accident.
        app.navigationBars["New reminder"].tap()
        sleep(1)
        shot("30-typed-keyboard-down")
        let start = app.navigationBars["New reminder"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 0, dy: 600))
        start.press(forDuration: 0.1, thenDragTo: end)
        sleep(2)
        shot("31-after-swipe-down")
        note("editor still presented", "\(app.navigationBars["New reminder"].exists)")
        note("alerts/sheets/dialogs",
             "alerts=\(app.alerts.count) sheets=\(app.sheets.count) dialogs=\(app.dialogs.count)")
        app.buttons["Add reminder"].tap()
        sleep(1)
        shot("32-reopened-editor")
        note("title after reopen", fieldValue(app.textFields["Title"]))
    }

    // MARK: - 4. Cancel with typed text

    func testCancelWithTypedTextHasNoConfirmation() {
        launch()
        app.buttons["Add reminder"].tap()
        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("A long thoughtful note I do not want to lose")
        let cancel = app.buttons["Cancel"]
        note("Cancel frame", "\(cancel.frame)")
        cancel.tap()
        sleep(1)
        shot("40-after-cancel-with-text")
        note("alerts/dialogs after cancel", "alerts=\(app.alerts.count) dialogs=\(app.dialogs.count)")
        note("editor dismissed", "\(!app.navigationBars["New reminder"].exists)")
    }

    // MARK: - 5. Check-in answer draft

    func testCheckInDraftSurvivesTabSwitchAndBackground() {
        launch(extra: ["-BondSeedUnanswered"])
        tab("Check-In")
        shot("50-checkin-empty")
        dumpTexts("50-dump")
        let field = app.textFields["Type your answer..."]
        guard field.waitForExistence(timeout: 5) else {
            note("check-in input", "answer field not found, see 50 dump")
            return
        }
        field.tap()
        field.typeText("I felt closest to you when we cooked together last week")
        shot("51-checkin-typed")
        // Quick look at another tab, as if checking a reminder.
        app.tap()
        tab("Reminders")
        tab("Check-In")
        shot("52-checkin-after-tab-switch")
        note("draft after tab switch", fieldValue(app.textFields["Type your answer..."]))
        interruptWithHome()
        shot("53-checkin-after-home")
        note("draft after background", fieldValue(app.textFields["Type your answer..."]))
        app.terminate()
        sleep(2)
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Reminders"].waitForExistence(timeout: 30))
        dismissPrimerIfPresent()
        tab("Check-In")
        shot("54-checkin-after-relaunch")
        note("draft after relaunch", fieldValue(app.textFields["Type your answer..."]))
    }

    func testCheckInDraftLostWhenLeavingPushedScreen() {
        launch(extra: ["-BondSeedUnanswered"])
        shot("55-home-with-unanswered-card")
        dumpTexts("55-dump")
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'check-in'")).firstMatch
        if card.waitForExistence(timeout: 5) { card.tap() } else { app.staticTexts["Today's check-in"].tap() }
        sleep(2)
        let field = app.textFields["Type your answer..."]
        guard field.waitForExistence(timeout: 5) else {
            shot("56-checkin-pushed-no-field")
            return
        }
        field.tap()
        field.typeText("Draft that should not vanish")
        app.tap()
        shot("56-checkin-pushed-typed")
        app.navigationBars.buttons.firstMatch.tap()
        sleep(1)
        shot("57-back-on-home")
        if card.exists { card.tap() } else { app.staticTexts["Today's check-in"].tap() }
        sleep(2)
        shot("58-checkin-reopened")
        note("draft after back and reopen", fieldValue(app.textFields["Type your answer..."]))
    }

    // MARK: - 6. Place in the app after relaunch

    func testTabAndScrollPositionAfterBackgroundAndRelaunch() {
        launch()
        tab("Insights")
        app.swipeUp()
        sleep(1)
        shot("60-insights-scrolled")
        interruptWithHome(seconds: 5)
        shot("61-insights-after-home")
        note("insights tab selected after background", "\(app.tabBars.buttons["Insights"].isSelected)")
        app.terminate()
        sleep(2)
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Reminders"].waitForExistence(timeout: 30))
        dismissPrimerIfPresent()
        sleep(1)
        shot("62-after-relaunch")
        note("reminders tab selected after relaunch", "\(app.tabBars.buttons["Reminders"].isSelected)")
        note("insights tab selected after relaunch", "\(app.tabBars.buttons["Insights"].isSelected)")
    }

    // MARK: - 7. Template picker interrupted

    func testTemplateGroupAfterBackground() {
        launch()
        let row = app.buttons["Browse reminder templates"]
        if !row.exists { app.swipeUp() }
        guard row.waitForExistence(timeout: 5) else { return }
        row.tap()
        sleep(1)
        let first = app.cells.firstMatch
        if first.exists { first.tap(); sleep(1) }
        shot("70-template-group-before")
        interruptWithHome()
        shot("71-template-group-after")
        note("nav bars after return", app.navigationBars.allElementsBoundByIndex.map { $0.identifier }.joined(separator: ", "))
    }

    // MARK: - 8. Milestone editor interrupted

    func testMilestoneEditorAfterBackground() {
        launch()
        tab("Milestones")
        let add = app.navigationBars.buttons["Add"]
        note("Add button exists", "\(add.exists)")
        if add.exists { add.tap() } else { app.navigationBars.buttons.element(boundBy: 0).tap() }
        sleep(1)
        let label = app.textFields.firstMatch
        if label.waitForExistence(timeout: 5) {
            label.tap()
            label.typeText("First date anniversary")
        }
        shot("80-milestone-typed")
        interruptWithHome()
        shot("81-milestone-after-home")
        note("label after background", fieldValue(app.textFields.firstMatch))
    }

    // MARK: - 9. Notification tap arrives while an editor is open

    func testNotificationTapWhileEditorOpen() {
        launch(extra: ["-BondSeedNotificationTapAfter", "14"])
        app.buttons["Add reminder"].tap()
        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Half typed new reminder")
        shot("90-editor-typed-before-notification")
        sleep(16)
        shot("91-after-notification-tap")
        note("nav title after notification",
             "new=\(app.navigationBars["New reminder"].exists) edit=\(app.navigationBars["Edit reminder"].exists)")
        note("title field after notification", fieldValue(app.textFields["Title"]))
        dumpTexts("91-dump")
    }

    // MARK: - 10. Partial swipe then interruption

    func testSwipeActionsAfterBackground() {
        launch()
        let row = app.staticTexts["Plan a ten-minute walk together"]
        guard row.waitForExistence(timeout: 10) else { return }
        row.swipeRight()
        sleep(1)
        shot("100-swipe-revealed-before-home")
        interruptWithHome()
        shot("101-swipe-after-home")
        note("Done button visible after return", "\(app.buttons["Done"].exists)")
    }

    // MARK: - 11. Confirmation: tapping an existing item opens it, not a blank form

    func testExistingItemsOpenInEditor() {
        launch()
        for attempt in 1...3 {
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Tell Sam one thing you appreciate'")).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            row.tap()
            sleep(2)
            let edit = app.navigationBars["Edit reminder"].exists
            let new = app.navigationBars["New reminder"].exists
            note("reminder attempt \(attempt)", "edit=\(edit) new=\(new) title=\(fieldValue(app.textFields["Title"]))")
            shot("110-reminder-tap-\(attempt)")
            app.buttons["Cancel"].tap()
            sleep(2)
        }
    }
}
