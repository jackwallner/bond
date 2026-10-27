import XCTest

@MainActor
final class ReleaseJourneysUITests: XCTestCase {
    private let reminderTitle = "Bring home flowers for Sam"

    override func setUp() {
        continueAfterFailure = false
    }

    /// Fresh install, solo setup, add a reminder, mark it done, and find it
    /// under Handled, all of it still true after a relaunch.
    func testCoreLoopAddReminderMarkDoneSurvivesRelaunch() {
        let app = XCUIApplication(bundleIdentifier: "com.jackwallner.bond")
        addUIInterruptionMonitor(withDescription: "system alert") { alert in
            for label in ["Don\u{2019}t Allow", "Don't Allow", "Not Now", "Cancel"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        QA.launch(app)

        let name = app.textFields["Their name"]
        XCTAssertTrue(name.waitForExistence(timeout: 30), "onboarding name step never appeared")
        QA.checkpoint(app, "welcome")
        name.tap()
        name.typeText("Sam")
        app.buttons["Continue"].firstMatch.tap()

        let commit = app.buttons["I commit to showing up for Sam"]
        XCTAssertTrue(commit.waitForExistence(timeout: 10))
        QA.checkpoint(app, "commit")
        commit.tap()

        XCTAssertTrue(app.buttons["Continue"].firstMatch.waitForExistence(timeout: 10))
        QA.checkpoint(app, "love-language")
        app.buttons["Continue"].firstMatch.tap()

        let focus = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Little gestures'")).firstMatch
        XCTAssertTrue(focus.waitForExistence(timeout: 10))
        focus.tap()
        QA.checkpoint(app, "focus-areas")
        app.buttons["Start using Little Gestures"].tap()

        let free = app.buttons["Continue for free"]
        XCTAssertTrue(free.waitForExistence(timeout: 15))
        QA.checkpoint(app, "onboarding-trial")
        free.tap()

        // The notification primer arrives once the first fetch settles.
        let later = app.buttons["Maybe later"]
        if later.waitForExistence(timeout: 20) { later.tap() }
        let addButton = app.buttons["Add reminder"]
        if !addButton.waitForExistence(timeout: 20) {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.lifetime = .keepAlways
            add(shot)
            XCTFail("home never showed the add button\n\(app.debugDescription)")
            return
        }
        QA.checkpoint(app, "home-empty")

        addButton.tap()
        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        title.typeText(reminderTitle)
        QA.checkpoint(app, "editor-filled")
        app.buttons["Save"].tap()

        XCTAssertTrue(row(app).waitForExistence(timeout: 30), "saved reminder is not listed")
        QA.checkpoint(app, "reminder-listed")

        app.buttons["Mark as done"].firstMatch.tap()
        let handled = handledLink(app)
        XCTAssertTrue(handled.waitForExistence(timeout: 20), "no Handled entry after marking done")
        XCTAssertTrue(handled.label.contains("1"), "Handled count is \(handled.label)")
        XCTAssertFalse(row(app).exists, "done reminder still in the active list")
        QA.checkpoint(app, "reminder-done")

        QA.relaunch(app)
        let handledAfter = handledLink(app)
        XCTAssertTrue(handledAfter.waitForExistence(timeout: 30), "Handled entry lost after relaunch")
        XCTAssertTrue(handledAfter.label.contains("1"), "Handled count is \(handledAfter.label)")
        QA.checkpoint(app, "home-after-relaunch")
        handledAfter.tap()
        XCTAssertTrue(row(app).waitForExistence(timeout: 15), "done reminder missing from Handled after relaunch")
        QA.checkpoint(app, "handled-after-relaunch")
    }

    private func row(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", reminderTitle)).firstMatch
    }

    private func handledLink(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Handled'")).firstMatch
    }
}
