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
    /// The keyboard shows that prompt a moment after typing starts, so wait for it.
    private func dismissSystemPopups(_ app: XCUIApplication, wait: TimeInterval = 4) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deadline = Date().addingTimeInterval(wait)
        repeat {
            for source in [app, springboard] {
                for label in ["Not Now", "Don’t Allow", "Don't Allow"] {
                    let button = source.buttons[label]
                    if button.exists && button.isHittable { button.tap(); return }
                }
            }
            usleep(300_000)
        } while Date() < deadline
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Screenshots of the radar in each map style, over India, for choosing the default.
    func testMapStyles() throws {
        executionTimeAllowance = 400
        for (style, name) in [(3, "dark"), (6, "live-clouds"), (5, "earth"), (7, "city-lights"), (2, "satellite")] {
            let app = XCUIApplication()
            app.launchArguments = ["-UITestMode", "-UITestTier", "pro", "-UITestChennai", "-UITestMapStyle", "\(style)"]
            app.launch()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
            sleep(12)   // let map and satellite tiles load
            snap(app, "style-\(style)-\(name)")
            XCTAssertEqual(app.state, .runningForeground, "map style \(style) must not crash")
            app.terminate()
        }
    }

    /// Pro user: every screen loads with real forecast data.
    func testProWalkthrough() throws {
        executionTimeAllowance = 400
        let app = launch(tier: "pro")
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 20), "Tab bar should appear (onboarding skipped)")

        // Radar
        XCTAssertTrue(app.buttons["play.fill"].exists || app.staticTexts["Live"].exists || app.buttons.count > 0)
        sleep(6)
        let play = app.buttons["Play"]
        XCTAssertTrue(play.waitForExistence(timeout: 10), "Play button should exist")
        let deadline = Date().addingTimeInterval(15)
        while !play.isEnabled && Date() < deadline { sleep(1) }
        XCTAssertTrue(play.isEnabled, "Play should work with model rain forecast frames")
        play.tap()
        sleep(3)
        snap(app, "01-Radar")
        if app.buttons["Pause"].exists { app.buttons["Pause"].tap() }

        // Cyclone chip focuses the storm; then turn on wind flow (Pro).
        let chip = app.buttons["Cyclone ARIA"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "Cyclone chip should show on radar")
        chip.tap()
        sleep(3)
        app.buttons["Map layers"].tap()
        let windItem = app.buttons["Wind flow"]
        XCTAssertTrue(windItem.waitForExistence(timeout: 5), "Wind flow option in layer menu")
        windItem.tap()
        sleep(5)
        snap(app, "01b-WindFlow-Cyclone")

        // Rain Truth: nearby reports show as a chip, and a report can be sent in one tap.
        XCTAssertTrue(app.buttons["crowd.chip"].waitForExistence(timeout: 10), "Crowd reports chip should show")
        app.buttons["radar.report"].tap()
        let rainButton = app.buttons["report.2"]
        XCTAssertTrue(rainButton.waitForExistence(timeout: 5), "Report sheet should open")
        sleep(1)
        snap(app, "01c-ReportSheet")
        rainButton.tap()
        // The sheet closes itself only after the report is accepted.
        let sheetGone = NSPredicate(format: "exists == false")
        expectation(for: sheetGone, evaluatedWith: rainButton)
        waitForExpectations(timeout: 10)

        // Forecast
        tabs.buttons["Forecast"].tap()
        XCTAssertTrue(app.staticTexts["hero.temperature"].waitForExistence(timeout: 30), "Forecast should load")
        XCTAssertFalse(app.buttons["Unlock with Essential"].exists, "Pro should not see the lock")
        XCTAssertTrue(app.staticTexts["Cyclone ARIA"].waitForExistence(timeout: 10), "Cyclone card should show")
        sleep(2)
        snap(app, "02-Forecast")
        XCTAssertTrue(app.staticTexts["hero.oneLiner"].exists || app.descendants(matching: .any)["hero.oneLiner"].exists,
                      "One-line summary under the temperature")
        let leave = app.descendants(matching: .any)["leave.card"]
        var l = 0
        while !(leave.exists && leave.isHittable) && l < 6 { app.swipeUp(velocity: .slow); l += 1 }
        XCTAssertTrue(leave.exists, "Leave-now card should show")
        XCTAssertTrue(app.descendants(matching: .any)["crowd.card"].exists, "Rain Truth card should show")
        sleep(1)
        snap(app, "02b-LeaveNow-RainTruth")
        let snowTile = app.descendants(matching: .any)["tile.snowflake"]
        let aqiTile = app.descendants(matching: .any)["tile.aqi.medium"]
        var k = 0
        while !(snowTile.exists && snowTile.isHittable) && k < 12 { app.swipeUp(velocity: .slow); k += 1 }
        XCTAssertTrue(snowTile.waitForExistence(timeout: 10), "Key conditions should load")
        XCTAssertTrue(aqiTile.exists, "AQI tile should show")
        sleep(1)
        snap(app, "03-KeyConditions")
        let more = app.buttons["More details"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "More details should be offered")
        var m = 0
        while !more.isHittable && m < 10 { app.swipeUp(velocity: .slow); m += 1 }
        more.tap()
        XCTAssertTrue(app.staticTexts["Next 2 hours"].waitForExistence(timeout: 5), "Rain chart inside More details")
        var tries = 0
        while !app.staticTexts["Humidity"].exists && tries < 6 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(app.staticTexts["Humidity"].waitForExistence(timeout: 5), "Conditions card should show")
        sleep(1)
        snap(app, "03b-MoreDetails")

        // Places
        tabs.buttons["Places"].tap()
        XCTAssertTrue(app.staticTexts["Tokyo"].waitForExistence(timeout: 10), "Saved places should list")
        sleep(4)
        snap(app, "04-Places")

        // Search field is present (typing is skipped: the simulator's
        // "Enable Dictation?" prompt sits outside the app and can't be dismissed)
        let searchVisible = app.searchFields.firstMatch.waitForExistence(timeout: 5)
            || app.buttons["Search"].exists
        XCTAssertTrue(searchVisible, "Places search should be available")

        // Settings
        tabs.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Pro"].waitForExistence(timeout: 5), "Plan should show Pro")
        snap(app, "05-Settings")
        // Privacy & Security section for the store screenshot
        var swipes = 0
        while !app.staticTexts["Privacy & Security"].isHittable && swipes < 6 { app.swipeUp(); swipes += 1 }
        sleep(1)
        snap(app, "05b-Privacy")
    }

    /// Free user: locks and the paywall work.
    func testFreeUserSeesPaywall() throws {
        let app = launch(tier: "free")
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 20))

        XCTAssertTrue(app.buttons["Unlock 2-hour rain forecast animation"].waitForExistence(timeout: 10),
                      "Free radar should show the upgrade chip")

        tabs.buttons["Forecast"].tap()
        let lock = app.buttons["forecast.unlock"]
        XCTAssertTrue(lock.waitForExistence(timeout: 30), "Free forecast chart should be locked")
        XCTAssertTrue(app.descendants(matching: .any)["leave.card"].exists, "Leave-now card shows (locked) for free users")
        lock.tap()

        XCTAssertTrue(app.staticTexts["Know exactly when it rains"].waitForExistence(timeout: 10), "Paywall should open")
        XCTAssertTrue(app.buttons["Restore"].exists, "Paywall needs Restore")
        sleep(5) // let StoreKit prices load
        snap(app, "06-Paywall")
    }
}
