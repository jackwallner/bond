import XCTest

/// Persona audit walkthroughs for a first-time user who does not know the
/// app's vocabulary. Both flows run offline against the DEBUG-only
/// `-BondAuditFirstRun` / `-BondAuditSoloHome` fixtures: no Supabase, no
/// RevenueCat, no production data. Every step is captured as a kept screenshot
/// attachment and failures never stop the walk, so one run yields the whole
/// evidence set.
final class NewcomerAuditUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(_ flag: String) {
        app = XCUIApplication(bundleIdentifier: "com.jackwallner.bond")
        app.launchArguments += [flag]
        app.launch()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func tap(_ label: String, wait: TimeInterval = 5) {
        let button = app.buttons[label].exists ? app.buttons[label] : element(label)
        if button.waitForExistence(timeout: wait) {
            button.tap()
        } else {
            XCTFail("Missing control: \(label)")
        }
    }

    /// A fresh simulator shows iOS's "slide to type" intro over the keyboard the
    /// first time a field is focused; it swallows typing until dismissed. This is
    /// system UI, not the app, but it is what a real first-install user meets too.
    private func dismissKeyboardIntro() {
        let intro = app.otherElements["UIContinuousPathIntroductionView"]
        if intro.waitForExistence(timeout: 4) {
            shot("00-system-slide-to-type-intro")
            intro.buttons["Continue"].tap()
            sleep(1)
        }
    }

    /// Closes whatever sheet is up through its own toolbar button, the way a
    /// user would, instead of a gesture that may not dismiss it.
    private func closeSheet(_ labels: [String] = ["Cancel", "Done", "Close"]) {
        for label in labels where app.buttons[label].firstMatch.waitForExistence(timeout: 2) {
            app.buttons[label].firstMatch.tap()
            sleep(1)
            return
        }
        XCTFail("No sheet close button among \(labels)")
    }

    private func log(_ message: String) {
        let attachment = XCTAttachment(string: message)
        attachment.name = "note"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - First run

    func testFirstRunOnboarding() {
        launch("-BondAuditFirstRun")

        XCTAssertTrue(element("Who do you want to show up for?").waitForExistence(timeout: 20))
        sleep(1)
        shot("01-name-step")
        let continueButton = app.buttons["Continue"]
        log("name step: Continue enabled with empty name = \(continueButton.isEnabled)")
        log("name step: Back button exists = \(app.buttons["Back"].exists)")

        tap("Have an invite from your partner?")
        sleep(2)
        shot("02-invite-sheet")
        app.swipeDown(velocity: .fast)
        sleep(1)

        let field = app.textFields["Their name"]
        if field.waitForExistence(timeout: 3) {
            field.tap()
            dismissKeyboardIntro()
            field.typeText("Sam")
        }
        sleep(1)
        shot("03-name-typed-keyboard")
        tap("Continue")
        sleep(1)
        shot("04-commit-step")
        log("commit step: Back button exists = \(app.buttons["Back"].exists)")

        tap("I commit to showing up for Sam")
        sleep(1)
        shot("05-love-language-step")
        log("love language step: Continue enabled with nothing picked = \(app.buttons["Continue"].isEnabled)")
        tap("Continue")
        sleep(1)
        shot("06-focus-step-nothing-selected")
        log("focus step: CTA enabled with nothing picked = \(app.buttons["Start using Little Gestures"].isEnabled)")

        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Little gestures'")).firstMatch.tap()
        sleep(1)
        shot("07-focus-step-selected")
        tap("Start using Little Gestures")
        sleep(2)
        shot("08-trial-step")

        tap("Continue for free")
        sleep(3)
        shot("09-after-onboarding-primer")
        if app.buttons["Maybe later"].waitForExistence(timeout: 5) {
            app.buttons["Maybe later"].tap()
        }
        sleep(2)
        shot("10-home-first-visit")
    }

    func testFirstRunTrialPrimaryCTA() {
        launch("-BondAuditFirstRun")
        XCTAssertTrue(element("Who do you want to show up for?").waitForExistence(timeout: 20))
        app.textFields["Their name"].tap()
        dismissKeyboardIntro()
        app.textFields["Their name"].typeText("Sam")
        tap("Continue")
        tap("I commit to showing up for Sam")
        tap("Continue")
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Little gestures'")).firstMatch.tap()
        tap("Start using Little Gestures")
        sleep(2)
        // No offerings on a simulator, so the primary CTA falls through to the
        // full paywall. This is what a user sees when the store is slow.
        tap("Get Little Gestures+")
        sleep(3)
        shot("20-trial-primary-cta-result")
    }

    // MARK: - Solo home

    func testSoloHomeTour() {
        launch("-BondAuditSoloHome")

        XCTAssertTrue(app.tabBars.buttons["Reminders"].waitForExistence(timeout: 20))
        sleep(2)
        shot("30-first-home-with-primer")
        if app.buttons["Turn on notifications"].exists {
            app.buttons["Maybe later"].tap()
            sleep(2)
        }
        shot("31-home-empty")

        // Starter chip -> editor
        let chip = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Tell them'")).firstMatch
        if chip.waitForExistence(timeout: 3) {
            chip.tap()
            sleep(2)
            shot("32-editor-from-chip")
            let titleField = app.textFields["Title"]
            XCTAssertTrue(titleField.waitForExistence(timeout: 3), "Editor has no Title field")
            let titleValue = (titleField.value as? String) ?? "<nil>"
            log("chip editor: Title value = '\(titleValue)', Save enabled = \(app.buttons["Save"].isEnabled)")
            XCTAssertTrue(titleValue.contains("Tell them"), "Starter chip did not prefill Title, got '\(titleValue)'")
            app.swipeUp()
            sleep(1)
            shot("33-editor-scrolled")
            app.swipeUp()
            sleep(1)
            shot("34-editor-scrolled-more")
            if app.buttons["Save"].isEnabled {
                tap("Save")
            } else {
                closeSheet(["Cancel"])
            }
            sleep(2)
            shot("35-home-after-editor")
        } else {
            XCTFail("No starter chip on empty home")
        }
        // The editor must be gone before the tab bar is meaningful.
        XCTAssertTrue(app.tabBars.buttons["Check-In"].waitForExistence(timeout: 5))

        // Tabs
        for tab in ["Check-In", "Milestones", "Insights", "Settings"] {
            guard app.tabBars.buttons[tab].waitForExistence(timeout: 5) else {
                XCTFail("Missing tab: \(tab)")
                continue
            }
            app.tabBars.buttons[tab].tap()
            sleep(2)
            shot("40-tab-\(tab)")
        }
        app.swipeUp()
        sleep(1)
        shot("41-settings-scrolled")
        app.swipeUp()
        sleep(1)
        shot("42-settings-scrolled-more")
    }

    func testSoloHomeSecondaryActions() {
        launch("-BondAuditSoloHome")
        XCTAssertTrue(app.tabBars.buttons["Reminders"].waitForExistence(timeout: 20))
        sleep(2)
        if app.buttons["Maybe later"].exists { app.buttons["Maybe later"].tap(); sleep(2) }

        tap("Browse templates")
        sleep(2)
        shot("50-templates")
        closeSheet(["Done"])

        tap("Add reminder")
        sleep(2)
        shot("51-new-reminder-empty")
        let title = app.textFields["Title"]
        if title.waitForExistence(timeout: 3) {
            title.tap()
            sleep(1)
            shot("52-new-reminder-keyboard")
        }
        closeSheet(["Cancel"])

        app.tabBars.buttons["Milestones"].tap()
        sleep(1)
        shot("53-milestones")
        let add = app.navigationBars.buttons.matching(NSPredicate(format: "label CONTAINS 'Add'")).firstMatch
        if add.exists {
            add.tap()
            sleep(2)
            shot("54-milestone-editor")
        }
    }
}
