import XCTest

/// Language-independent walkthrough used by the "UI matrix" workflow (different languages,
/// device sizes, text sizes, plans, empty phone). Skipped unless RP_CONFIG is set.
/// RP_CONFIG example: "tier=free;empty=1;bigtext=1"
final class MatrixUITests: XCTestCase {
    private var config: [String: String] = [:]

    override func setUpWithError() throws {
        continueAfterFailure = true
        guard let raw = ProcessInfo.processInfo.environment["RP_CONFIG"], !raw.isEmpty else {
            throw XCTSkip("Matrix run only")
        }
        for pair in raw.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 { config[kv[0]] = kv[1] }
        }
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func tab(_ app: XCUIApplication, _ i: Int) {
        let buttons = app.tabBars.firstMatch.buttons
        XCTAssertGreaterThanOrEqual(buttons.count, 4, "tab bar should have 4 tabs")
        if buttons.count > i { buttons.element(boundBy: i).tap() }
        sleep(2)
    }

    func testWalkEveryScreen() throws {
        let app = XCUIApplication()
        var args = ["-UITestMode", "-UITestTier", config["tier"] ?? "pro"]
        if config["empty"] == "1" { args.append("-UITestEmpty") }
        if config["bigtext"] == "1" {
            args += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launchArguments = args
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 25), "app should start to the tab bar")

        // Radar
        tab(app, 0)
        XCTAssertTrue(app.buttons["radar.play"].waitForExistence(timeout: 15), "radar controls")
        sleep(3)
        snap(app, "m1-radar")

        // Forecast
        tab(app, 1)
        if config["empty"] == "1" {
            XCTAssertTrue(app.buttons["forecast.useLocation"].waitForExistence(timeout: 15), "empty state offers location")
            snap(app, "m2-forecast-empty")
        } else {
            XCTAssertTrue(app.staticTexts["hero.temperature"].waitForExistence(timeout: 30), "forecast hero")
            sleep(2)
            snap(app, "m2-forecast")
            for _ in 0..<2 { app.swipeUp() }
            XCTAssertTrue(app.descendants(matching: .any)["tile.cloud.rain.fill"].exists, "rain tile")
            XCTAssertTrue(app.descendants(matching: .any)["tile.aqi.medium"].exists, "air quality tile")
            snap(app, "m3-forecast-tiles")
            let more = app.buttons["forecast.more"]
            var n = 0
            while !more.isHittable && n < 5 { app.swipeUp(); n += 1 }
            if more.isHittable { more.tap(); sleep(1); app.swipeUp(); snap(app, "m4-more-details") }
            for _ in 0..<6 { app.swipeDown() }
            if config["tier"] == "free" {
                let unlock = app.buttons["forecast.unlock"]
                XCTAssertTrue(unlock.waitForExistence(timeout: 5), "free user sees unlock")
                unlock.tap()
                XCTAssertTrue(app.buttons["paywall.restore"].waitForExistence(timeout: 10), "paywall opens")
                sleep(1)
                snap(app, "m5-paywall")
                app.swipeDown(velocity: .fast)
                sleep(1)
                if app.buttons["paywall.restore"].exists {
                    app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'close' OR identifier CONTAINS[c] 'close'")).firstMatch.tap()
                }
            }
        }

        // Places
        tab(app, 2)
        snap(app, "m6-places")

        // Settings
        tab(app, 3)
        snap(app, "m7-settings")
        for _ in 0..<3 { app.swipeUp() }
        snap(app, "m8-settings-lower")
        XCTAssertEqual(app.state, .runningForeground, "app must not crash")
    }
}
