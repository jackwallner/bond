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
        let name = localized(app.textFields, "Their name", "Name deines Partners")
        XCTAssertTrue(name.waitForExistence(timeout: 45), "name step never rendered")
        QA.checkpoint(app, "partner-name")

        name.tap()
        // Return submits the step; at large text the keyboard covers Continue.
        name.typeText("Sam\n")
        let commit = localized(app.buttons, "I commit to showing up for Sam", "Ich verspreche, für Sam da zu sein")
        XCTAssertTrue(commit.waitForExistence(timeout: 15))
        QA.checkpoint(app, "commit")

        tap(commit, in: app)
        XCTAssertTrue(localized(app.buttons, "Continue", "Weiter").waitForExistence(timeout: 15))
        QA.checkpoint(app, "love-language")

        tap(onScreenButton("Continue", "Weiter", in: app), in: app)
        let start = localized(app.buttons, "Start using Little Gestures", "Little Gestures nutzen")
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        if !start.isEnabled {
            tap(app.buttons.containing(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "Little gestures", "Kleine Gesten")).firstMatch, in: app)
        }
        QA.checkpoint(app, "focus-areas")

        tap(start, in: app)
        let free = localized(app.buttons, "Continue for free", "Kostenlos weiter")
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
        for name in ["Check-In", "Milestones", "Insights", "Settings"] {
            // The unfolded iPhone Duo shows Insights in its own pane, not as a tab.
            let button = tab(name, in: app)
            if name == "Insights", !button.exists {
                QA.checkpoint(app, "insights")
                continue
            }
            button.tap()
            QA.checkpoint(app, name.lowercased())
        }
    }

    func test03ReturnVisitWithInterruption() {
        continueAfterFailure = false
        let app = launchSeeded()
        tab("Milestones", in: app).tap()
        QA.checkpoint(app, "milestones-before-interruption")

        QA.interrupt(app)
        QA.checkpoint(app, "milestones-after-interruption")

        QA.relaunch(app)
        XCTAssertTrue(tab("Reminders", in: app).waitForExistence(timeout: 25))
        QA.checkpoint(app, "reminders-after-relaunch")
    }

    /// The core loop: write a gesture, see it listed, mark it done so it moves
    /// to Handled, and find both outcomes again after a relaunch. The seed's
    /// session id keeps the changes on disk across `QA.relaunch`; no network.
    func testCoreLoopAddThenMarkGestureDone() {
        continueAfterFailure = false
        let title = "Note \(Int.random(in: 1000...9999))"
        let app = XCUIApplication(bundleIdentifier: Self.bundle)
        QA.launch(app, arguments: Self.seeded + ["-BondSeedSession", UUID().uuidString])
        XCTAssertTrue(tab("Reminders", in: app).waitForExistence(timeout: 25), "seeded home never rendered")
        XCTAssertFalse(listed(title, in: app).exists)
        let handled = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label MATCHES %@", "^(Handled|Erledigt)\\W*1$")).firstMatch
        XCTAssertFalse(handled.exists, "seed should start with nothing handled")
        QA.checkpoint(app, "core-home")

        localized(app.buttons, "Add reminder", "Erinnerung hinzufügen").tap()
        let field = localized(app.textFields, "Title", "Titel")
        XCTAssertTrue(field.waitForExistence(timeout: 15), "editor never opened")
        field.tap()
        field.typeText(title)
        if let typed = field.value as? String, title.hasPrefix(typed), typed != title {
            field.typeText(String(title.dropFirst(typed.count)))
        }
        XCTAssertEqual(field.value as? String, title, "title was not entered completely")
        // The keyboard covers the schedule rows, and the oracles would measure
        // them through its blur; judge the form with the keyboard away.
        closeKeyboard(with: "\n", on: field, in: app)
        // A loaded host can also lose the last key as the keyboard closes, so check
        // again: the row is looked for by this exact title.
        if let kept = field.value as? String, title.hasPrefix(kept), kept != title {
            field.tap()
            closeKeyboard(with: String(title.dropFirst(kept.count)) + "\n", on: field, in: app)
        }
        XCTAssertEqual(field.value as? String, title, "title did not stay as typed")
        QA.checkpoint(app, "core-editor")

        let save = localized(app.buttons, "Save", "Speichern")
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        save.tap()
        // The first reminder asks for notification permission; answer it as a
        // person would so it does not sit over every later step.
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if alert.waitForExistence(timeout: 8) { localized(alert.buttons, "Allow", "Erlauben").tap() }
        XCTAssertTrue(listed(title, in: app).waitForExistence(timeout: 20) || scrollTo(listed(title, in: app), in: app),
                      "saved reminder is not listed")
        // The editor's dismissal animation would otherwise be captured mid-slide.
        let add = localized(app.buttons, "Add reminder", "Erinnerung hinzufügen")
        let closed = Date().addingTimeInterval(10)
        while !(add.exists && add.isHittable) && Date() < closed {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        // Saving lands on the top of the list; finding the lazily rendered row
        // above scrolled it, so return to what the person is looking at.
        scrollToTop(app)
        QA.checkpoint(app, "core-added")

        QA.relaunch(app)
        XCTAssertTrue(listed(title, in: app).waitForExistence(timeout: 25) || scrollTo(listed(title, in: app), in: app),
                      "reminder gone after relaunch")
        scrollToTop(app)
        QA.checkpoint(app, "core-added-after-relaunch")

        // Large text and the Duo's narrow pane scroll the new row out of the
        // lazy list; bring it back before reaching for its check circle.
        let cell = app.cells.containing(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        let done = localized(cell.buttons, "Mark as done", "Als erledigt markieren")
        // The title can stay in the tree after its row is recycled, so scroll
        // until the row's own button exists, not just its text.
        for _ in 0..<24 where !done.exists { QA.swipe(visibleList(app), .up) }
        tap(done, in: app)
        scrollTo(handled, in: app)
        XCTAssertTrue(handled.exists, "done reminder never reached Handled")
        XCTAssertFalse(listed(title, in: app).exists, "done reminder still listed as open")
        restAtListEnd(app)
        QA.checkpoint(app, "core-done")

        QA.relaunch(app)
        XCTAssertTrue(tab("Reminders", in: app).waitForExistence(timeout: 25))
        scrollTo(handled, in: app)
        XCTAssertTrue(handled.exists, "Handled lost after relaunch")
        XCTAssertFalse(listed(title, in: app).exists, "done reminder reopened after relaunch")
        restAtListEnd(app)
        QA.checkpoint(app, "core-done-after-relaunch")
    }

    /// Whatever shows this title: a plain text, or the row's combined label
    /// when large text or the Duo's pane merges it into the row.
    private func closeKeyboard(with text: String, on field: XCUIElement, in app: XCUIApplication) {
        field.typeText(text)
        let gone = Date().addingTimeInterval(10)
        while app.keyboards.count > 0 && Date() < gone {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
    }

    private func listed(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    /// Lists render lazily, so a row off screen is not in the tree until
    /// scrolled to. Returns whether the element exists afterwards.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, up: Bool = true) -> Bool {
        for _ in 0..<24 where !element.exists {
            QA.swipe(visibleList(app), up ? .up : .down)
        }
        // A row above the current position (large text, a list left mid-scroll
        // after the editor closes) is reached by going back the other way.
        for _ in 0..<24 where !element.exists {
            QA.swipe(visibleList(app), up ? .down : .up)
        }
        return element.exists
    }

    /// The list on screen. A TabView keeps every tab's list in the tree, so
    /// the first collection view is not always the one the person sees (on
    /// the unfolded Duo it is another tab's); screens without a list scroll
    /// as a plain scroll view.
    private func visibleList(_ app: XCUIApplication) -> XCUIElement {
        // The Reminders list is the one holding reminder rows; on the unfolded
        // Duo the first collection view is the Insights pane's.
        let reminders = app.collectionViews["reminders-list"]
        if reminders.exists { return reminders }
        return app.collectionViews.allElementsBoundByIndex.first { $0.exists && $0.isHittable }
            ?? (app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.scrollViews.firstMatch)
    }

    /// Rest at the end of the list, where the last rows clear the tab bar and
    /// the scroll indicator has faded, not mid-scroll with a row under the bar.
    private func restAtListEnd(_ app: XCUIApplication) {
        for _ in 0..<3 { QA.swipe(visibleList(app), .up) }
        sleep(3)
    }

    private func scrollToTop(_ app: XCUIApplication) {
        for _ in 0..<8 { QA.swipe(visibleList(app), .down) }
    }

    /// A tab bar button. The unfolded Duo's floating bar is not always a
    /// `tabBars` element, so fall back to the button by label.
    private func tab(_ name: String, in app: XCUIApplication) -> XCUIElement {
        let german = ["Reminders": "Erinnerungen", "Check-In": "Check-in", "Milestones": "Meilensteine", "Insights": "Einblicke", "Settings": "Einstellungen"][name] ?? name
        let bar = localized(app.tabBars.buttons, name, german)
        return bar.exists ? bar : localized(app.buttons, name, german)
    }

    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: Self.bundle)
        QA.launch(app, arguments: Self.seeded)
        XCTAssertTrue(tab("Reminders", in: app).waitForExistence(timeout: 25), "seeded home never rendered")
        return app
    }

    /// The hittable button with this label. A step change cross-fades, so the
    /// outgoing step's button can still be in the tree for a moment.
    /// The element by either language's text. A text field's label is empty: its
    /// words are the placeholder.
    private func localized(_ query: XCUIElementQuery, _ english: String, _ german: String) -> XCUIElement {
        let names = [english, german]
        return query.matching(NSPredicate(format: "label IN %@ OR placeholderValue IN %@ OR identifier IN %@", names, names, names)).firstMatch
    }

    private func onScreenButton(_ label: String, _ german: String, in app: XCUIApplication) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", label, german))
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if let hit = matches.allElementsBoundByIndex.first(where: { $0.isHittable }) { return hit }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        return matches.firstMatch
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 15))
        // Scroll the list itself: a swipe on the whole app lands on the fold
        // of the unfolded Duo, between its two panes, and moves neither.
        let scroller = visibleList(app)
        for _ in 0..<6 where !element.isHittable { QA.swipe(scroller, .up) }
        for _ in 0..<12 where !element.isHittable { QA.swipe(scroller, .down) }
        element.tap()
    }
}
