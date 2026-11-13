import UIKit
import XCTest

/// Capture only: `gh-sim` cannot rotate the iPad, so this launches each
/// surface with its seed and turns the device sideways before the screenshot.
/// Skips itself everywhere except an iPad.
final class IPadLandscapeCaptureTests: XCTestCase {
    private let surfaces: [(name: String, args: [String])] = [
        ("reminders", ["-BondScreenshotSeed", "-DuoScreen", "reminders"]),
        ("checkin", ["-BondScreenshotSeed", "-DuoScreen", "checkin"]),
        ("milestones", ["-BondScreenshotSeed", "-DuoScreen", "milestones"]),
        ("insights", ["-BondScreenshotSeed", "-DuoScreen", "insights"]),
        ("settings", ["-BondScreenshotSeed", "-DuoScreen", "settings"]),
        ("editor", ["-BondScreenshotSeed", "-DuoScreen", "editor"]),
        ("onboarding", ["-BondOnboardingSeed"]),
        ("paywall-trial", ["-PaywallSnapshot", "trial"]),
        ("paywall-yearly", ["-PaywallSnapshot", "yearly"]),
    ]

    func testCaptureLandscape() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .landscapeLeft
        for surface in surfaces {
            let app = XCUIApplication(bundleIdentifier: "com.jackwallner.bond")
            app.launchArguments = surface.args
            app.launch()
            XCUIDevice.shared.orientation = .landscapeLeft
            sleep(6)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "landscape-\(surface.name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }
}
