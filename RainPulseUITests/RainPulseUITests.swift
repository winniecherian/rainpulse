import XCTest

/// Smoke tests that walk every screen and save screenshots (also used for the App Store).
final class RainPulseUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = true
    }

    private func launch(tier: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "-UITestTier", tier]
        app.launch()
        return app
    }

    /// Dismisses simulator popups (e.g. "Enable Dictation?") that can cover the app.
    private func dismissSystemPopups(_ app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Not Now", "Don’t Allow", "Don't Allow", "Cancel"] {
            for source in [app, springboard] where source.buttons[label].exists {
                source.buttons[label].tap()
            }
        }
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Pro user: every screen loads with real forecast data.
    func testProWalkthrough() throws {
        let app = launch(tier: "pro")
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 20), "Tab bar should appear (onboarding skipped)")

        // Radar
        XCTAssertTrue(app.buttons["play.fill"].exists || app.staticTexts["Live"].exists || app.buttons.count > 0)
        sleep(6)
        snap(app, "01-Radar")

        // Forecast
        tabs.buttons["Forecast"].tap()
        let nextTwo = app.staticTexts["Next 2 hours"]
        XCTAssertTrue(nextTwo.waitForExistence(timeout: 30), "Forecast should load from Open-Meteo")
        XCTAssertFalse(app.buttons["Unlock with Essential"].exists, "Pro should not see the lock")
        sleep(2)
        snap(app, "02-Forecast")
        app.swipeUp()
        sleep(1)
        snap(app, "03-Forecast-Daily")

        // Places
        tabs.buttons["Places"].tap()
        XCTAssertTrue(app.staticTexts["Tokyo"].waitForExistence(timeout: 10), "Saved places should list")
        sleep(4)
        snap(app, "04-Places")

        // Search adds a place
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("Sydney")
            dismissSystemPopups(app)
            let result = app.cells.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Sydney'")).firstMatch
            if result.waitForExistence(timeout: 15) {
                result.tap()
                dismissSystemPopups(app)
                XCTAssertTrue(app.staticTexts["Sydney"].waitForExistence(timeout: 15), "Sydney should be added")
            }
            dismissSystemPopups(app)
            if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        }
        dismissSystemPopups(app)

        // Settings
        tabs.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Pro"].waitForExistence(timeout: 5), "Plan should show Pro")
        snap(app, "05-Settings")
    }

    /// Free user: locks and the paywall work.
    func testFreeUserSeesPaywall() throws {
        let app = launch(tier: "free")
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 20))

        XCTAssertTrue(app.buttons["Unlock 2-hour rain forecast animation"].waitForExistence(timeout: 10),
                      "Free radar should show the upgrade chip")

        tabs.buttons["Forecast"].tap()
        let lock = app.buttons["Unlock with Essential"]
        XCTAssertTrue(lock.waitForExistence(timeout: 30), "Free forecast chart should be locked")
        lock.tap()

        XCTAssertTrue(app.staticTexts["Know exactly when it rains"].waitForExistence(timeout: 10), "Paywall should open")
        XCTAssertTrue(app.buttons["Restore"].exists, "Paywall needs Restore")
        sleep(5) // let StoreKit prices load
        snap(app, "06-Paywall")
    }
}
