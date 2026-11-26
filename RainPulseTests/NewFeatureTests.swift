import XCTest
import CoreLocation
import UIKit
import CloudKit
@testable import RainPulse

/// Tests for Rain Truth (crowd reports), the Leave-now window, the one-line summary and NASA map styles.
final class CrowdReportTests: XCTestCase {
    let chennai = CLLocationCoordinate2D(latitude: 13.0827, longitude: 80.2707)
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testGeohashKnownValue() {
        // Reference value from the geohash spec (Jutland, Denmark).
        let c = CLLocationCoordinate2D(latitude: 57.64911, longitude: 10.40744)
        XCTAssertEqual(Geohash.encode(c, precision: 11), "u4pruydqqvj")
        XCTAssertEqual(Geohash.encode(c, precision: 5), "u4pru")
    }

    func testBoundsContainPointAndNeighbourhoodHasNineCells() {
        let hash = Geohash.encode(chennai, precision: 5)
        let (a, b, c, d) = Geohash.bounds(hash)
        XCTAssertTrue(a <= chennai.latitude && chennai.latitude <= b)
        XCTAssertTrue(c <= chennai.longitude && chennai.longitude <= d)
        let cells = Geohash.neighbourhood(hash)
        XCTAssertEqual(cells.count, 9)
        XCTAssertTrue(cells.contains(hash))
        XCTAssertEqual(Set(cells).count, 9)
    }

    func testNeighbourhoodWrapsDateLine() {
        let fiji = CLLocationCoordinate2D(latitude: -17.0, longitude: 179.99)
        let cells = Geohash.neighbourhood(Geohash.encode(fiji, precision: 5))
        XCTAssertEqual(cells.count, 9)
        XCTAssertTrue(cells.contains { $0.hasPrefix("r") }, "east side")
        XCTAssertTrue(cells.contains { $0.hasPrefix("2") }, "west side across the date line")
    }

    func testRecordNamesAreFindable() {
        let cell = Geohash.encode(chennai, precision: ReportKeys.precision)
        let rain = ReportKeys.recordName(cell: cell, condition: .rain, time: now, slot: 3)
        let flood = ReportKeys.recordName(cell: cell, condition: .waterlogging, time: now.addingTimeInterval(-3000), slot: 7)
        let names = Set(ReportKeys.namesNear(chennai, now: now))
        XCTAssertTrue(rain.hasPrefix("r-\(cell)-"))
        XCTAssertTrue(names.contains(rain))
        XCTAssertTrue(names.contains(flood), "waterlogging stays findable for 2 hours")
        let old = ReportKeys.recordName(cell: cell, condition: .rain, time: now.addingTimeInterval(-3600), slot: 0)
        XCTAssertFalse(names.contains(old), "rain reports older than 30 minutes are not fetched")
        XCTAssertEqual(names.count, 9 * (ReportKeys.rainLookback * ReportKeys.rainSlots + ReportKeys.floodLookback * ReportKeys.floodSlots))
        XCTAssertLessThanOrEqual(names.count, 800)
    }

    func testApproximateLocationIsAbout100m() {
        XCTAssertEqual(ReportKeys.approximate(13.082749), 13.083, accuracy: 1e-9)
        XCTAssertEqual(ReportKeys.approximate(-46.633349), -46.633, accuracy: 1e-9)
    }

    private func report(_ c: ReportCondition, dLat: Double = 0.005, minsAgo: Double, id: String = UUID().uuidString,
                        area: String? = nil) -> CrowdReport {
        CrowdReport(id: id, condition: c, latitude: chennai.latitude + dLat, longitude: chennai.longitude,
                    time: now.addingTimeInterval(-minsAgo * 60), area: area)
    }

    func testSummaryCountsRecentNearbyReports() {
        let reports = [report(.rain, minsAgo: 3), report(.heavyRain, minsAgo: 8), report(.dry, minsAgo: 10),
                       report(.rain, minsAgo: 45),                 // too old
                       report(.rain, dLat: 0.2, minsAgo: 2),        // ~22 km away
                       report(.waterlogging, dLat: 0.02, minsAgo: 70, area: "Anna Salai"),
                       report(.waterlogging, dLat: 0.001, minsAgo: 20, area: "Mount Road"),
                       report(.waterlogging, minsAgo: 150)]         // older than 2 h
        let s = CrowdLogic.summary(reports, near: chennai, now: now)
        XCTAssertEqual(s.wet, 2)
        XCTAssertEqual(s.dry, 1)
        XCTAssertEqual(s.heavy, 1)
        XCTAssertTrue(s.mostlyWet)
        XCTAssertEqual(s.newest, now.addingTimeInterval(-180))
        XCTAssertEqual(s.floods.map(\.area), ["Mount Road", "Anna Salai"], "closest first")
        XCTAssertEqual(s.headline(now: now), "2 people report heavy rain nearby · 3 min ago")
    }

    func testHeadlines() {
        XCTAssertNil(CrowdSummary().headline(now: now))
        let one = CrowdLogic.summary([report(.rain, minsAgo: 5)], near: chennai, now: now)
        XCTAssertEqual(one.headline(now: now), "1 person reports rain nearby · 5 min ago")
        let dry = CrowdLogic.summary([report(.dry, minsAgo: 1), report(.dry, minsAgo: 2)], near: chennai, now: now)
        XCTAssertEqual(dry.headline(now: now), "2 people report it's dry nearby · 1 min ago")
    }

    func testFloodAlertOnlyOncePerReport() {
        let s = CrowdLogic.summary([report(.waterlogging, minsAgo: 12, id: "f1", area: "Anna Salai")], near: chennai, now: now)
        let alert = CrowdLogic.floodAlert(s, place: "Chennai", now: now, alreadyNotified: [])
        XCTAssertEqual(alert?.id, "f1")
        XCTAssertEqual(alert?.title, "Flooded streets near Chennai")
        XCTAssertTrue(alert?.body.contains("Anna Salai") == true)
        XCTAssertTrue(alert?.body.contains("12 min ago") == true)
        XCTAssertNil(CrowdLogic.floodAlert(s, place: "Chennai", now: now, alreadyNotified: ["f1"]))
        XCTAssertNil(CrowdLogic.floodAlert(CrowdSummary(), place: "Chennai", now: now, alreadyNotified: []))
    }

    func testSampleReportsAreValid() {
        let samples = CrowdReport.samples(around: chennai, now: now)
        XCTAssertEqual(samples.count, 6)
        let s = CrowdLogic.summary(samples, near: chennai, now: now)
        XCTAssertGreaterThan(s.wet, 0)
        XCTAssertEqual(s.floods.count, 1)
    }
}

final class DayPlannerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// 15-minute rain values from now, then hourly values after.
    private func forecast(steps: [Double], hourly: [(mm: Double, prob: Int?)] = [], uv: Int? = nil,
                          maxTemp: Double = 30, current: Double = 0) -> Forecast {
        var nowcast: [Forecast.Step] = []
        for (i, mm) in steps.enumerated() {
            nowcast.append(Forecast.Step(time: now.addingTimeInterval(Double(i) * 900), precipitation: mm))
        }
        var hours: [Forecast.Hour] = []
        for (i, h) in hourly.enumerated() {
            hours.append(Forecast.Hour(time: now.addingTimeInterval(Double(i) * 3600), temperature: 28,
                                       precipitationProbability: h.prob, precipitation: h.mm, weatherCode: 3))
        }
        let cur = Forecast.Current(time: now, temperature: 28, weatherCode: current > 0 ? 61 : 2, precipitation: current,
                                   uvIndex: uv)
        let day = Forecast.Day(time: now, weatherCode: 2, maxTemperature: maxTemp, minTemperature: 24,
                               precipitationSum: 0, precipitationProbabilityMax: nil)
        var f = Forecast(current: cur, nowcast: nowcast, hourly: hours, daily: [day], utcOffsetSeconds: 0, fetchedAt: now)
        f.timeZoneID = "UTC"
        return f
    }

    func testGoNowWhenDry() {
        let f = forecast(steps: Array(repeating: 0, count: 12))
        let w = f.dryWindow(tripMinutes: 30, from: now)
        XCTAssertEqual(w?.kind, .goNow)
        XCTAssertEqual(w?.start, now)
        XCTAssertEqual(f.dryMinutes(from: now), 180)
        XCTAssertEqual(f.leaveAdvice(tripMinutes: 30, from: now).title, "Go now — it's dry")
    }

    func testWaitWhenRainingNow() {
        let f = forecast(steps: [1.2, 0.8, 0.3, 0, 0, 0, 0, 0, 0, 0, 0, 0], current: 1.2)
        let w = f.dryWindow(tripMinutes: 30, from: now)
        XCTAssertEqual(w?.kind, .waitUntil)
        XCTAssertEqual(w?.start, now.addingTimeInterval(45 * 60))
        XCTAssertTrue(f.leaveAdvice(tripMinutes: 30, from: now).title.hasPrefix("Leave at"))
    }

    func testShortTripFitsGapLongTripDoesNot() {
        // Dry gap of 30 minutes between showers.
        let f = forecast(steps: [0.5, 0, 0, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6])
        XCTAssertEqual(f.dryWindow(tripMinutes: 30, from: now)?.start, now.addingTimeInterval(15 * 60))
        XCTAssertEqual(f.dryWindow(tripMinutes: 60, from: now)?.kind, .noDryWindow)
    }

    func testNoDryWindowPicksLeastWet() {
        let f = forecast(steps: [2, 2, 2, 2, 0.3, 0.3, 0.3, 0.3, 2, 2, 2, 2])
        let w = f.dryWindow(tripMinutes: 60, from: now)
        XCTAssertEqual(w?.kind, .noDryWindow)
        XCTAssertEqual(w?.start, now.addingTimeInterval(60 * 60))
        XCTAssertEqual(f.leaveAdvice(tripMinutes: 60, from: now).title, "Take an umbrella")
    }

    func testHourlyFillsBeyondNowcastAndHighChanceCountsAsWet() {
        // Only 1 hour of 15-minute data; hour 2 has a 70% chance with no amount.
        let f = forecast(steps: [0, 0, 0, 0], hourly: [(0, 10), (0, 70), (0, 10)])
        let slots = f.slotRain(hours: 3, from: now)
        XCTAssertEqual(slots.count, 12)
        XCTAssertEqual(slots[4].mm, 0.1, accuracy: 1e-9)
        XCTAssertEqual(slots[8].mm, 0, accuracy: 1e-9)
        XCTAssertEqual(f.dryMinutes(from: now), 60)
    }

    func testOneLinerRainAndAirQuality() {
        let later = forecast(steps: Array(repeating: 0, count: 12),
                             hourly: [(0, 0), (0, 0), (0, 10), (0, 20), (1.5, 80), (0, 10)])
        let bad = AirQuality(usAQI: 172, pm25: 90, pm10: 120, fetchedAt: now)
        let line = later.oneLiner(airQuality: bad, now: now)
        XCTAssertTrue(line.hasPrefix("Umbrella after"), line)
        XCTAssertTrue(line.contains("AQI 172, wear a mask"), line)

        let dry = forecast(steps: Array(repeating: 0, count: 12), hourly: [(0, 0), (0, 0)], uv: 9)
        XCTAssertEqual(dry.oneLiner(airQuality: AirQuality(usAQI: 40, pm25: nil, pm10: nil, fetchedAt: now), now: now),
                       "No rain today · Strong sun, UV 9")

        let soon = forecast(steps: [0, 0, 0.4, 0.8, 0.2, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertTrue(soon.oneLiner(airQuality: nil, now: now).hasPrefix("Umbrella from"))

        let raining = forecast(steps: [1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], current: 1)
        XCTAssertTrue(raining.oneLiner(airQuality: nil, now: now).hasPrefix("Rain until"))

        let hot = forecast(steps: Array(repeating: 0, count: 12), maxTemp: 41)
        XCTAssertTrue(hot.oneLiner(airQuality: nil, now: now).contains("Very hot"))
    }
}

final class MapStyleTests: XCTestCase {
    func testCloudPixelMapping() {
        XCTAssertNil(TileImage.cloudPixel(r: 110, g: 110, b: 110), "warm ground or sea = clear")
        let thick = TileImage.cloudPixel(r: 190, g: 190, b: 190)!
        XCTAssertEqual(Int(thick >> 24), 235, "cold cloud top is nearly opaque")
        XCTAssertEqual(Int(thick & 0xFF), 235, "premultiplied white")
        let thin = TileImage.cloudPixel(r: 150, g: 150, b: 150)!
        XCTAssertLessThan(Int(thin >> 24), 235)
        let storm = TileImage.cloudPixel(r: 255, g: 0, b: 0)!
        XCTAssertEqual(Int(storm & 0xFF), 235, "storm colours kept")
        XCTAssertEqual(Int((storm >> 8) & 0xFF), 0)
    }

    func testCloudTimeIsRecentTenMinuteStep() {
        let now = Date(timeIntervalSince1970: 1_800_000_123)
        let s = NASAStyle.cloudTime(now)
        XCTAssertTrue(s.hasSuffix("Z"))
        let d = ISO8601DateFormatter().date(from: s)!
        XCTAssertEqual(Int(d.timeIntervalSince1970) % 600, 0)
        XCTAssertTrue((1800...2400).contains(Int(now.timeIntervalSince(d))))
    }

    func testStylesProduceLayers() {
        XCTAssertEqual(NASAStyle.earth.overlays().count, 1)
        XCTAssertEqual(NASAStyle.liveClouds.overlays().count, 2)
        XCTAssertEqual(NASAStyle.cityLights.overlays().count, 1)
        XCTAssertNil(NASAStyle.from(3))
        XCTAssertEqual(RadarMapView.Coordinator.interfaceStyle(for: 6), .dark)
    }
}

final class ReportErrorTests: XCTestCase {
    func testCloudKitErrorsBecomeFriendlyMessages() {
        XCTAssertEqual(CrowdReportService.describe(CKError(.networkUnavailable)).message,
                       "No internet connection. Try again in a moment.")
        XCTAssertEqual(CrowdReportService.describe(CKError(.notAuthenticated)).message,
                       "Sign in to iCloud in Settings to send reports.")
        XCTAssertEqual(CrowdReportService.describe(CKError(.requestRateLimited)).message,
                       "Reports are busy right now. Try again in a minute.")
        let rejected = CrowdReportService.describe(CKError(.serverRejectedRequest))
        XCTAssertEqual(rejected.message, "Reports aren't available right now.")
        XCTAssertFalse(rejected.message.contains("CKRecordID"), "never show raw CloudKit text")
    }
}
