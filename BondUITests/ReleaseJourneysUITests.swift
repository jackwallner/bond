import XCTest

/// The release gate's journeys (`qa-gate run`): onboarding through the trial
/// page to home, every tab on seeded data, and a return visit with an
/// interruption. Each step ends in `QA.checkpoint`, which runs the fleet
/// oracles on the screen. Assert reachability only.
///
/// Simulator runs never configure the production RevenueCat key, so the
/// onboarding journey launches with `-rcfunnelprobe`: the Test Store, a separate
/// RevenueCat app, supplies the trial page's prices. Its customer never buys.
/// `-BondOnboardingSeed` keeps Supabase out of it: a signed-in user with no
/// couple, and the solo couple made on device.
@MainActor
final class ReleaseJourneysUITests: XCTestCase {

    private static let bundle = "com.jackwallner.bond"
    private static let seeded = ["-BondScreenshotSeed"]

    func test01OnboardingToTrialAndHome() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: Self.bundle)
        QA.launch(app, environment: ["RC_PROBE_USER": "qa-bond-journeys", "RC_PROBE_SURFACE": "qa_journeys"],
                  arguments: ["-rcfunnelprobe", "-BondOnboardingSeed"])
        let name = app.textFields["Their name"]
        XCTAssertTrue(name.waitForExistence(timeout: 45), "name step never rendered")
        QA.checkpoint(app, "partner-name")

        name.tap()
        name.typeText("Sam")
        tap(onScreenButton("Continue", in: app), in: app)
        let commit = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "I commit")).firstMatch
        XCTAssertTrue(commit.waitForExistence(timeout: 15))
        QA.checkpoint(app, "commit")

        tap(commit, in: app)
        XCTAssertTrue(app.buttons["Continue"].firstMatch.waitForExistence(timeout: 15))
        QA.checkpoint(app, "love-language")

        tap(onScreenButton("Continue", in: app), in: app)
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
        if !free.waitForNonExistence(timeout: 20), free.exists, free.isHittable { free.tap() }
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

    /// The hittable button with this label. A step change cross-fades, so the
    /// outgoing step's button can still be in the tree for a moment.
    private func onScreenButton(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", label))
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if let hit = matches.allElementsBoundByIndex.first(where: { $0.isHittable }) { return hit }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        return matches.firstMatch
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 15))
        for _ in 0..<4 where !element.isHittable { app.swipeUp() }
        element.tap()
    }
}
