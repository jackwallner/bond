import XCTest

/// Persona audit flows for an experienced user repeating core tasks on the
/// paired demo fixture (`-BondScreenshotSeed`, local only, no Supabase or
/// RevenueCat). Each test attaches screenshots and a text dump of what it saw;
/// the tests are exploratory and only assert that the app launched.
final class ExperiencedAuditUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(free: Bool = false, extra: [String] = []) {
        app = XCUIApplication(bundleIdentifier: "com.jackwallner.bond")
        app.launchArguments += ["-BondScreenshotSeed"] + (free ? ["-BondSeedFree"] : []) + extra
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Reminders"].waitForExistence(timeout: 30), "tab bar never appeared")
        dismissPrimerIfPresent()
    }

    private func dismissPrimerIfPresent() {
        let later = app.buttons["Maybe later"]
        if later.waitForExistence(timeout: 6) {
            shot("00-notification-primer")
            note("Maybe later frame", "\(later.frame)")
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
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(80).map { $0.label }
        let buttons = app.buttons.allElementsBoundByIndex.prefix(60).map { "\($0.label) \($0.frame)" }
        note(name, "TEXTS:\n" + texts.joined(separator: "\n") + "\n\nBUTTONS:\n" + buttons.joined(separator: "\n"))
    }

    private func tab(_ name: String) {
        app.tabBars.buttons[name].tap()
        sleep(1)
    }

    // MARK: - Reminders: repeat tasks (done, undo, delete, edit)

    func testHomeRepeatActions() {
        launch()
        shot("01-home")
        dumpTexts("01-home-dump")

        let circles = app.buttons.matching(identifier: "Mark as done")
        note("check circle count", "\(circles.count)")
        if circles.count > 0 {
            note("check circle frame", "\(circles.firstMatch.frame)")
            circles.firstMatch.tap()
            sleep(2)
            shot("02-after-tap-check-circle-backend-unreachable")
            dumpTexts("02-dump")
        }

        // Swipe right (leading) to reveal Done on the second row.
        let row = app.staticTexts["Plan a ten-minute walk together"]
        if row.waitForExistence(timeout: 5) {
            row.swipeRight()
            sleep(1)
            shot("03-leading-swipe-done")
            row.swipeLeft()
            sleep(1)
            shot("04-trailing-swipe-delete")
            // Full swipe, as an experienced user flicking through the list would.
            row.swipeLeft(velocity: .fast)
            sleep(2)
            shot("05-after-fast-swipe-left")
            note("row still present after fast swipe", "\(app.staticTexts["Plan a ten-minute walk together"].exists)")
        }

        // Partner request card actions.
        let handled = app.buttons["Handled"]
        note("Handled button exists", "\(handled.exists) \(handled.exists ? "\(handled.frame)" : "")")
    }

    func testEditorEditAndDiscard() {
        launch()
        app.staticTexts["Tell Sam one thing you appreciate"].tap()
        sleep(1)
        shot("10-editor-existing")
        dumpTexts("10-editor-dump")

        // Schedule picker options.
        let schedule = app.buttons["Schedule"]
        if schedule.exists {
            schedule.tap()
            sleep(1)
            shot("11-schedule-options")
            app.tap()
        }

        // Repeat options (no weekday choice expected).
        let repeatRow = app.buttons["Repeat"]
        if repeatRow.exists {
            repeatRow.tap()
            sleep(1)
            shot("12-repeat-options")
            dumpTexts("12-repeat-dump")
            app.tap()
        }

        // Edit then swipe-down to dismiss: is there a discard prompt?
        let title = app.textFields["Title"]
        if title.exists {
            title.tap()
            title.typeText(" EDITED")
            shot("13-editor-typed-keyboard")
            app.swipeDown()
            sleep(1)
            app.swipeDown(velocity: .fast)
            sleep(2)
            shot("14-after-swipe-dismiss-unsaved")
            note("editor still showing", "\(app.navigationBars["Edit reminder"].exists)")
            note("alert/dialog shown", "\(app.alerts.count) alerts, \(app.sheets.count) sheets")
        }
    }

    func testNewReminderSaveOfflineAndKeyboard() {
        launch()
        app.buttons["Add reminder"].tap()
        sleep(1)
        shot("20-new-reminder-empty")
        dumpTexts("20-dump")
        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Pick up flowers")
        let note = app.textFields["Note (optional)"]
        if note.exists { note.tap() }
        shot("21-keyboard-on-note")
        let dismiss = app.buttons["Save"]
        self.note("Save frame", "\(dismiss.frame) enabled=\(dismiss.isEnabled)")
        dismiss.tap()
        sleep(3)
        shot("22-after-save-backend-unreachable")
        dumpTexts("22-dump")
    }

    // MARK: - Templates

    func testTemplatesImport() {
        launch()
        let row = app.buttons["Browse reminder templates"]
        if !row.exists { app.swipeUp() }
        if row.waitForExistence(timeout: 5) {
            row.tap()
            sleep(1)
            shot("30-templates-list")
            let first = app.cells.firstMatch
            if first.exists {
                first.tap()
                sleep(1)
                shot("31-template-group")
                let add = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add '")).firstMatch
                if !add.exists { app.swipeUp() }
                if add.exists {
                    shot("32-template-group-bottom")
                    add.tap()
                    sleep(3)
                    shot("33-after-add-backend-unreachable")
                    dumpTexts("33-dump")
                }
            }
        }
    }

    // MARK: - Check-in

    func testCheckInFromHomeAndTab() {
        launch()
        let card = app.staticTexts["Today's check-in"]
        let ready = app.buttons.matching(NSPredicate(format: "label CONTAINS 'answered'")).firstMatch
        shot("40-home-checkin-card")
        dumpTexts("40-dump")
        if ready.exists { ready.tap() } else if card.exists { card.tap() }
        sleep(2)
        shot("41-checkin-pushed-from-home")
        dumpTexts("41-dump")
        note("nav bars after push", app.navigationBars.allElementsBoundByIndex.map { $0.identifier }.joined(separator: ", "))
        app.navigationBars.buttons.firstMatch.tap()
        sleep(1)

        tab("Check-In")
        shot("42-checkin-tab")
        let sealed = app.staticTexts["Tap to reveal"]
        if sealed.waitForExistence(timeout: 3) {
            sealed.tap()
            sleep(1)
            shot("43-checkin-revealed")
        }
        dumpTexts("43-dump")
    }

    // MARK: - Milestones

    func testMilestonesAccuracy() {
        launch()
        tab("Milestones")
        shot("50-milestones")
        dumpTexts("50-dump")
        let first = app.buttons.containing(.staticText, identifier: "Our anniversary").firstMatch
        if first.exists {
            first.tap()
            sleep(1)
            shot("51-milestone-editor")
            dumpTexts("51-dump")
        }
    }

    // MARK: - Insights

    func testInsightsAccuracy() {
        launch()
        tab("Insights")
        shot("60-insights-top")
        dumpTexts("60-dump")
        app.swipeUp()
        sleep(1)
        shot("61-insights-mid")
        app.swipeUp()
        sleep(1)
        shot("62-insights-lower")
        app.swipeUp()
        sleep(1)
        shot("63-insights-bottom")
        dumpTexts("63-dump")
    }

    // MARK: - Settings

    func testSettings() {
        launch()
        tab("Settings")
        shot("70-settings-top")
        dumpTexts("70-dump")
        app.swipeUp()
        sleep(1)
        shot("71-settings-mid")
        app.swipeUp()
        sleep(1)
        shot("72-settings-bottom")
    }

    // MARK: - Free-state gates an experienced user re-meets

    func testFreeGates() {
        launch(free: true)
        shot("80-free-home")
        tab("Check-In")
        shot("81-free-checkin")
        tab("Insights")
        shot("82-free-insights")
        tab("Reminders")
        let row = app.buttons["Preview reminder templates"]
        if !row.exists { app.swipeUp() }
        if row.waitForExistence(timeout: 5) {
            row.tap()
            sleep(1)
            shot("83-free-templates")
        }
    }

    // MARK: - Large text

    func testLargeTextHomeAndEditor() {
        launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        shot("90-ax-home")
        app.buttons["Add reminder"].tap()
        sleep(1)
        shot("91-ax-editor")
        app.swipeUp()
        sleep(1)
        shot("92-ax-editor-scrolled")
        app.buttons["Cancel"].tap()
        tab("Milestones")
        shot("93-ax-milestones")
    }
}
