import XCTest

/// The release gate's journeys (`qa-gate run`): onboarding through the trial
/// page to home, every tab on seeded data, and a return visit with an
/// interruption. Each step ends in `QA.checkpoint`, which runs the fleet
/// oracles on the screen. Assert reachability only.
///
/// Simulator runs never configure the production RevenueCat key, so the
/// onboarding journey launches with `-rcfunnelprobe`: the Test Store, a separate
/// RevenueCat app, supplies the trial page's prices. Its customer never buys.
@MainActor
final class ReleaseJourneysUITests: XCTestCase {

    private static let bundle = "com.jackwallner.bond"
    private static let seeded = ["-BondScreenshotSeed"]

    func test01OnboardingToTrialAndHome() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: Self.bundle)
        QA.launch(app, environment: ["RC_PROBE_USER": "qa-bond-journeys", "RC_PROBE_SURFACE": "qa_journeys"],
                  arguments: ["-rcfunnelprobe"])
        let name = app.textFields["Their name"]
        XCTAssertTrue(name.waitForExistence(timeout: 45), "name step never rendered")
        QA.checkpoint(app, "partner-name")

        name.tap()
        name.typeText("Sam")
        tap(app.buttons["Continue"], in: app)
        let commit = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "I commit")).firstMatch
        XCTAssertTrue(commit.waitForExistence(timeout: 15))
        QA.checkpoint(app, "commit")

        tap(commit, in: app)
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 15))
        QA.checkpoint(app, "love-language")

        tap(app.buttons["Continue"], in: app)
        let start = app.buttons["Start using Little Gestures"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        if !start.isEnabled {
            tap(app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Little gestures")).firstMatch, in: app)
        }
        QA.checkpoint(app, "focus-areas")

        tap(start, in: app)
        let free = app.buttons["Continue for free"]
        XCTAssertTrue(free.waitForExistence(timeout: 20), "trial page never rendered")
        QA.checkpoint(app, "onboarding-trial", paywall: true)

        tap(free, in: app)
        XCTAssertTrue(free.waitForNonExistence(timeout: 30), "free path never left the trial page")
        sleep(2)
        QA.checkpoint(app, "first-home", paywall: false)
    }

    func test02EveryTabOnSeededData() {
        continueAfterFailure = false
        let app = launchSeeded()
        QA.checkpoint(app, "reminders")
        for tab in ["Check-In", "Milestones", "Insights", "Settings"] {
            app.tabBars.buttons[tab].tap()
            QA.checkpoint(app, tab.lowercased())
        }
    }

    func test03ReturnVisitWithInterruption() {
        continueAfterFailure = false
        let app = launchSeeded()
        app.tabBars.buttons["Milestones"].tap()
        QA.checkpoint(app, "milestones-before-interruption")

        QA.interrupt(app)
        QA.checkpoint(app, "milestones-after-interruption")

        QA.relaunch(app)
        XCTAssertTrue(app.tabBars.buttons["Reminders"].waitForExistence(timeout: 25))
        QA.checkpoint(app, "reminders-after-relaunch")
    }

    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: Self.bundle)
        QA.launch(app, arguments: Self.seeded)
        XCTAssertTrue(app.tabBars.buttons["Reminders"].waitForExistence(timeout: 25), "seeded home never rendered")
        return app
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 15))
        for _ in 0..<4 where !element.isHittable { app.swipeUp() }
        element.tap()
    }
}
