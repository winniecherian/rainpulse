import XCTest
import CoreLocation
import MapKit
@testable import RainPulse

/// Builds a forecast whose 15-minute steps start at `now` (rounded down to 15 min).
private func forecast(rain: [Double], now: Date, code: Int = 2, currentRain: Double? = nil,
                      tz: String = "Asia/Kolkata", days: Int = 3) -> Forecast {
    let base = floor(now.timeIntervalSince1970 / 900) * 900
    var steps: [Forecast.Step] = []
    for (i, mm) in rain.enumerated() {
        steps.append(Forecast.Step(time: Date(timeIntervalSince1970: base + Double(i) * 900), precipitation: mm))
    }
    let hourStart: Double = floor(now.timeIntervalSince1970 / 3600) * 3600
    var hours: [Forecast.Hour] = []
    for i in 0..<48 {
        let t = Date(timeIntervalSince1970: hourStart + Double(i) * 3600)
        let wet = (i == 5)
        let hourCode = (i == 30) ? 71 : 2
        hours.append(Forecast.Hour(time: t, temperature: 28, precipitationProbability: wet ? 70 : 10,
                                   precipitation: wet ? 1.2 : 0, weatherCode: hourCode))
    }
    let dayStart: Double = floor(now.timeIntervalSince1970 / 86400) * 86400
    var daily: [Forecast.Day] = []
    for i in 0..<days {
        let t = Date(timeIntervalSince1970: dayStart + Double(i) * 86400)
        daily.append(Forecast.Day(time: t, weatherCode: 2, maxTemperature: 31, minTemperature: 24,
                                  precipitationSum: 1, precipitationProbabilityMax: 40))
    }
    let currentPrecip: Double = currentRain ?? rain.first ?? 0
    let current = Forecast.Current(time: now, temperature: 28, weatherCode: code, precipitation: currentPrecip)
    var f = Forecast(current: current, nowcast: steps, hourly: hours, daily: daily, utcOffsetSeconds: 19800, fetchedAt: now)
    f.timeZoneID = tz
    return f
}

final class ForecastLogicTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_795_000_500)   // fixed instant, 15-min aligned + 5 min

    func testDryForecast() {
        let f = forecast(rain: Array(repeating: 0, count: 12), now: now)
        XCTAssertFalse(f.isRaining(at: now))
        XCTAssertNil(f.rainStart(within: 120, from: now))
        XCTAssertEqual(f.rainHeadline(from: now), "No rain nearby")
        XCTAssertEqual(f.rainDetail(from: now), "No rain expected in the next 3 hours.")
        XCTAssertEqual(f.nowcastSummary(from: now), "No rain for 2 hours")
    }

    func testRainArrivingIn30Minutes() {
        let f = forecast(rain: [0, 0, 0.4, 1.2, 0.8, 0, 0, 0, 0, 0, 0, 0], now: now)
        XCTAssertFalse(f.isRaining(at: now))
        let start = f.rainStart(within: 120, from: now)
        XCTAssertNotNil(start)
        XCTAssertEqual(f.rainHeadline(from: now), "Rain on the way")
        XCTAssertTrue(f.rainDetail(from: now).contains("rain expected from"), f.rainDetail(from: now))
        XCTAssertTrue(f.nowcastSummary(from: now).hasPrefix("Rain in about"))
    }

    func testRainingNowAndStopping() {
        let f = forecast(rain: [1.0, 0.8, 0.3, 0, 0, 0, 0, 0, 0, 0, 0, 0], now: now, code: 63)
        XCTAssertTrue(f.isRaining(at: now))
        XCTAssertEqual(f.rainHeadline(from: now), WeatherCode.description(63))
        XCTAssertTrue(f.rainDetail(from: now).hasPrefix("Expected to end at"), f.rainDetail(from: now))
        XCTAssertTrue(f.nowcastSummary(from: now).hasPrefix("Rain stopping in about"))
    }

    func testRainingWithNonRainCodeUsesGenericTitle() {
        let f = forecast(rain: [1.0, 1.0, 1.0, 1.0], now: now, code: 3)
        XCTAssertEqual(f.rainHeadline(from: now), "Rain")
    }

    func testLongRain() {
        let f = forecast(rain: Array(repeating: 1.0, count: 14), now: now, code: 61)
        XCTAssertEqual(f.rainDetail(from: now), "Will last more than 3 hours.")
        XCTAssertEqual(f.nowcastSummary(from: now), "Rain for at least 2 hours")
    }

    func testUpcomingStepsWindow() {
        let f = forecast(rain: Array(repeating: 0, count: 20), now: now)
        let steps = f.upcomingSteps(hours: 2, from: now)
        XCTAssertGreaterThanOrEqual(steps.count, 8)
        XCTAssertLessThanOrEqual(steps.count, 9)
        XCTAssertTrue(steps.first!.time <= now)
    }

    func testOldCacheWithoutDetailFieldsStillDecodes() throws {
        // A forecast saved by an older build had no wind/humidity/etc. fields.
        let f = forecast(rain: [0, 0], now: now)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(f)) as! [String: Any]
        var cur = json["current"] as! [String: Any]
        for k in ["feelsLike", "humidity", "uvIndex", "windSpeed", "windGust", "windDirection", "pressure", "visibility", "dewPoint"] {
            cur.removeValue(forKey: k)
        }
        json["current"] = cur
        json.removeValue(forKey: "timeZoneID")
        let back = try JSONDecoder().decode(Forecast.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(back.current.humidity)
        XCTAssertEqual(back.nowcast.count, 2)
    }

    func testMergeUsesOpenMeteoNowcastAndExtraDays() {
        var apple = forecast(rain: [0, 0], now: now, days: 10)
        apple.hasMinuteData = false
        apple.usesAppleWeather = true
        let extra = forecast(rain: [0, 0.5, 1, 0], now: now, days: 14)
        let merged = Forecast.merge(apple, with: extra, useNowcast: true)
        XCTAssertEqual(merged.nowcast.count, 4)
        XCTAssertEqual(merged.daily.count, 14)
        XCTAssertTrue(merged.usesAppleWeather && merged.usesOpenMeteo)
        XCTAssertEqual(merged.timeZoneID, "Asia/Kolkata")
    }

    func testTimeZoneFallsBackToOffset() {
        var f = forecast(rain: [0], now: now)
        f.timeZoneID = "Not/AZone"
        XCTAssertEqual(f.timeZone.secondsFromGMT(), 19800)
    }

    func testSampleForecastIsSane() {
        let s = Forecast.sample(latitude: 13)
        XCTAssertFalse(s.nowcast.isEmpty)
        XCTAssertGreaterThanOrEqual(s.daily.count, 2)
        XCTAssertNotNil(s.rainStart(within: 60))
    }
}

final class AlertDecisionTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_795_000_500)

    func testAlertsWhenRainWithinLead() {
        let f = forecast(rain: [0, 0, 0.5, 1, 0, 0, 0, 0], now: now)
        let d = RainAlertService.alertDecision(f, now: now, lead: 60, threshold: 0.1, lastNotified: nil)
        XCTAssertNotNil(d)
        XCTAssertGreaterThanOrEqual(d!.minutes, 5)
    }

    func testNoAlertWhenRainBeyondLead() {
        let f = forecast(rain: [0, 0, 0, 0, 0, 0, 1, 1], now: now)
        XCTAssertNil(RainAlertService.alertDecision(f, now: now, lead: 30, threshold: 0.1, lastNotified: nil))
    }

    func testNoAlertWhileAlreadyRaining() {
        let f = forecast(rain: [1, 1, 1, 1], now: now)
        XCTAssertNil(RainAlertService.alertDecision(f, now: now, lead: 60, threshold: 0.1, lastNotified: nil))
    }

    func testNoRepeatWithinTwoHours() {
        let f = forecast(rain: [0, 0, 0.5, 1], now: now)
        XCTAssertNil(RainAlertService.alertDecision(f, now: now, lead: 60, threshold: 0.1,
                                                    lastNotified: now.addingTimeInterval(-3600)))
        XCTAssertNotNil(RainAlertService.alertDecision(f, now: now, lead: 60, threshold: 0.1,
                                                       lastNotified: now.addingTimeInterval(-3 * 3600)))
    }

    func testHeavyOnlyThresholdIgnoresDrizzle() {
        let f = forecast(rain: [0, 0.2, 0.3, 0.2], now: now)
        XCTAssertNil(RainAlertService.alertDecision(f, now: now, lead: 60, threshold: 1.9, lastNotified: nil))
    }
}

final class PlanAndRadarTests: XCTestCase {
    func testTierLimits() {
        XCTAssertEqual(Tier.free.forecastDays, 2)
        XCTAssertEqual(Tier.essential.forecastDays, 14)
        XCTAssertEqual(Tier.free.maxSavedPlaces, 3)
        XCTAssertEqual(Tier.pro.maxSavedPlaces, 20)
        XCTAssertFalse(Tier.free.hasMinuteChart)
        XCTAssertTrue(Tier.essential.hasMinuteChart)
        XCTAssertFalse(Tier.essential.hasExtraLayers)
        XCTAssertTrue(Tier.pro.hasExtraLayers)
        XCTAssertTrue(Tier.free < Tier.essential && Tier.essential < Tier.pro)
    }

    func testPastRangeGating() {
        XCTAssertTrue(PastRange.m30.allowed(for: .free))
        XCTAssertFalse(PastRange.h1.allowed(for: .free))
        XCTAssertTrue(PastRange.h2.allowed(for: .essential))
        XCTAssertFalse(PastRange.h6.allowed(for: .essential))
        XCTAssertTrue(PastRange.h48.allowed(for: .pro))
    }

    func testAnimatedFramesAreCappedOrderedAndHaveNow() {
        let p = RadarProvider(source: .owmGlobalPrecip)
        for tier in Tier.allCases {
            let frames = p.frames(for: tier, layer: .radar)
            XCTAssertLessThanOrEqual(frames.count, 20, "\(tier)")
            XCTAssertEqual(frames.map(\.date), frames.map(\.date).sorted())
            let i = RadarProvider.nowIndex(in: frames)
            XCTAssertFalse(frames[i].isForecast)
            if i + 1 < frames.count { XCTAssertTrue(frames[i + 1].isForecast) }
        }
        let long = p.frames(past: 48 * 3600, future: 7200, layer: .radar)
        XCTAssertLessThanOrEqual(long.count, 20)
    }

    func testLiveOnlySourceHasSingleFrame() {
        let p = RadarProvider(source: .owmCurrent)
        XCTAssertEqual(p.frames(for: .pro, layer: .radar).count, 1)
        XCTAssertEqual(RadarProvider(source: .owmGlobalPrecip).frames(for: .pro, layer: .clouds).count, 1)
    }

    func testRecolorLookupTable() {
        XCTAssertEqual(RadarRecolor.lut[0], 0)
        XCTAssertEqual(RadarRecolor.lut[RadarRecolor.low - 1], 0)
        let alpha: (UInt32) -> UInt32 = { ($0 >> 24) & 0xFF }
        XCTAssertGreaterThanOrEqual(alpha(RadarRecolor.lut[RadarRecolor.low]), 150)
        XCTAssertGreaterThanOrEqual(alpha(RadarRecolor.lut[200]), 240)
    }

    func testRecolorMakesFaintRainVisible() throws {
        // A 4x4 tile with one faint rain pixel (alpha 40), like OpenWeather's free layer.
        let size = 4
        var px = [UInt8](repeating: 0, count: size * size * 4)
        px[0] = 40; px[1] = 40; px[2] = 60; px[3] = 40
        let provider = CGDataProvider(data: Data(px) as CFData)!
        let cg = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                         space: CGColorSpaceCreateDeviceRGB(),
                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let png = try XCTUnwrap(UIImage(cgImage: cg).pngData())
        let out = try XCTUnwrap(RadarRecolor.recolor(png))
        let img = try XCTUnwrap(UIImage(data: out)?.cgImage)
        XCTAssertEqual(img.width, size)
        // Read back alpha of pixel 0.
        var back = [UInt8](repeating: 0, count: size * size * 4)
        let ctx = CGContext(data: &back, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: size, height: size))
        let alphas = stride(from: 3, to: back.count, by: 4).map { back[$0] }
        XCTAssertGreaterThanOrEqual(alphas.max() ?? 0, 150, "faint rain should become clearly visible")
        XCTAssertEqual(alphas.filter { $0 > 0 }.count, 1, "empty pixels stay empty")
    }

    func testTileURLsNeedKeyAndAreHTTPS() {
        let url = RadarProvider(source: .owmCurrent).tileURL(layer: .radar, frame: nil, z: 5, x: 22, y: 14)
        if AppConfig.owmAPIKey.isEmpty {
            XCTAssertNil(url)
        } else {
            XCTAssertEqual(url?.scheme, "https")
            XCTAssertTrue(url!.absoluteString.contains("/5/22/14"))
        }
    }
}

final class MapDataTests: XCTestCase {
    func testWindFieldBilinearAndWrap() {
        // 2x2 grid: u = 0 at west, 10 at east; v = 0 south, 4 north.
        let f = WindField(lats: [10, 12], lons: [170, 172], u: [0, 10, 0, 10], v: [0, 0, 4, 4], validTime: nil)
        let mid = f.vector(lat: 11, lon: 171)!
        XCTAssertEqual(mid.u, 5, accuracy: 0.001)
        XCTAssertEqual(mid.v, 2, accuracy: 0.001)
        XCTAssertNil(f.vector(lat: 20, lon: 171))
        // Grid stored with unwrapped longitudes past 180 still answers for -188 ≡ 172.
        let g = WindField(lats: [0, 1], lons: [179, 181], u: [1, 1, 1, 1], v: [0, 0, 0, 0], validTime: nil)
        XCTAssertNotNil(g.vector(lat: 0.5, lon: -179.5))
    }

    func testWindGridBuilder() {
        let rows: [(Double, Double, Float, Float)] = [(0, 0, 1, 2), (0, 1, 3, 4), (1, 0, 5, 6), (1, 1, 7, 8)]
        let f = WindService.grid(rows, validTime: nil)!
        XCTAssertEqual(f.lats, [0, 1]); XCTAssertEqual(f.lons, [0, 1])
        XCTAssertEqual(f.u, [1, 3, 5, 7]); XCTAssertEqual(f.v, [2, 4, 6, 8])
        XCTAssertNil(WindService.grid([(0, 0, 1, 1)], validTime: nil))
    }

    func testRainModelColours() {
        XCTAssertEqual(RainModelFrames.rgba(mmPerHour: 0).3, 0)
        XCTAssertEqual(RainModelFrames.rgba(mmPerHour: 0.02).3, 0)
        let soft = RainModelFrames.rgba(mmPerHour: 0.06).3
        XCTAssertTrue(soft > 0 && soft < 150)
        XCTAssertGreaterThanOrEqual(RainModelFrames.rgba(mmPerHour: 0.1).3, 150)
        XCTAssertGreaterThanOrEqual(RainModelFrames.rgba(mmPerHour: 60).3, 245)
    }

    func testRainModelImageAndBounds() throws {
        let frames = RainModelFrames.sample(around: CLLocationCoordinate2D(latitude: 13, longitude: 80), hours: 24)
        XCTAssertEqual(frames.dates.count, frames.values.count)
        XCTAssertEqual(frames.dates, frames.dates.sorted())
        let img = try XCTUnwrap(frames.image(frame: 0))
        XCTAssertGreaterThan(img.width, 100)
        XCTAssertLessThanOrEqual(img.width, 1300)
        XCTAssertNil(frames.image(frame: 999))
        let r = frames.boundingMapRect
        XCTAssertTrue(r.width > 0 && r.height > 0)
        XCTAssertTrue(r.contains(MKMapPoint(CLLocationCoordinate2D(latitude: 13, longitude: 80))))
    }

    func testAirQualityCategories() {
        func cat(_ v: Int) -> String { AirQuality(usAQI: v, pm25: nil, pm10: nil, fetchedAt: Date()).category }
        XCTAssertEqual(cat(10), "Good"); XCTAssertEqual(cat(51), "Moderate")
        XCTAssertEqual(cat(120), "Unhealthy for sensitive groups"); XCTAssertEqual(cat(180), "Unhealthy")
        XCTAssertEqual(cat(250), "Very unhealthy"); XCTAssertEqual(cat(400), "Hazardous")
    }

    func testLocationIsRoundedForThirdParties() {
        XCTAssertEqual(Net.approx(13.082681), "13.08")
        XCTAssertEqual(Net.approx(-0.1278), "-0.13")
    }
}

final class CycloneTests: XCTestCase {
    let geometry = """
    {"type":"FeatureCollection","features":[
     {"type":"Feature","properties":{"Class":"Point_Centroid"},"geometry":{"type":"Point","coordinates":[84.7,17.2]}},
     {"type":"Feature","properties":{"Class":"Line_Line_0","forecast":false,"polygonlabel":"TS"},
      "geometry":{"type":"LineString","coordinates":[[86,14],[85.5,15.5],[84.7,17.2]]}},
     {"type":"Feature","properties":{"Class":"Line_Line_1","forecast":true,"polygonlabel":"Cat1"},
      "geometry":{"type":"LineString","coordinates":[[84.7,17.2],[84,18.5]]}},
     {"type":"Feature","properties":{"Class":"Poly_Cones"},
      "geometry":{"type":"Polygon","coordinates":[[[84.7,17.2],[83,19],[85,19.5],[84.7,17.2]]]}},
     {"type":"Feature","properties":{"Class":"Poly_Cones"},
      "geometry":{"type":"MultiPolygon","coordinates":[[[[84,18],[83.5,19],[84.5,19],[84,18]]]]}}
    ]}
    """

    func testParsesTracksAndCones() {
        let (segments, cones) = CycloneService.parseGeometry(Data(geometry.utf8))
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments.filter(\.isForecast).count, 1)
        XCTAssertEqual(segments.first { $0.isForecast }?.category, "Cat1")
        XCTAssertEqual(segments[0].points.first?.lat, 14)
        XCTAssertEqual(cones.count, 2)
        XCTAssertEqual(CycloneService.parseGeometry(Data("not json".utf8)).0.count, 0)
    }

    func testDistancesAndCategories() {
        let chennai = CLLocationCoordinate2D(latitude: 13.08, longitude: 80.27)
        let storm = Cyclone.sample(near: chennai)
        let d = storm.distanceKm(to: chennai)
        XCTAssertGreaterThan(d, 300); XCTAssertLessThan(d, 600)
        XCTAssertLessThanOrEqual(storm.closestApproachKm(to: chennai), d)
        func label(_ kmh: Double) -> String {
            Cyclone(id: 0, name: "X", alertLevel: "Green", maxWindKmh: kmh, strengthText: "", position: .init(lat: 0, lon: 0),
                    updated: nil, segments: [], cone: [], reportURL: nil, source: "").categoryLabel
        }
        XCTAssertEqual(label(50), "Tropical depression")
        XCTAssertEqual(label(100), "Tropical storm")
        XCTAssertEqual(label(130), "Category 1 cyclone")
        XCTAssertEqual(label(260), "Category 5 cyclone")
    }
}

final class LocalizationTests: XCTestCase {
    static let languages = ["es", "pt-BR", "hi", "id", "ja", "de", "fr", "ar", "ta", "vi"]

    private func bundle(_ lang: String) -> Bundle? {
        Bundle.main.path(forResource: lang, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    func testEveryLanguageIsBundled() {
        for lang in Self.languages {
            XCTAssertNotNil(bundle(lang), "\(lang).lproj missing from the app")
        }
    }

    func testKeyStringsAreTranslatedAndFormatSafely() {
        let samples: [(String, [CVarArg])] = [
            ("Rain in about %lld min", [25]),
            ("Radar updated %lld min ago", [4]),
            ("Cyclone %@ near %@", ["ARIA", "Chennai"]),
            ("%lld km from %@ now; forecast track passes about %lld km away.", [420, "Chennai", 180]),
            ("Free for %@, then %@ per %@. ", ["14 days", "₹999", "year"]),
            ("Saved places (%lld/%lld)", [3, 20]),
            ("%lld%% chance in 24 h", [70]),
        ]
        for lang in Self.languages {
            guard let b = bundle(lang) else { continue }
            for (key, args) in samples {
                let translated = b.localizedString(forKey: key, value: "⛔️", table: "Localizable")
                XCTAssertNotEqual(translated, "⛔️", "\(lang) missing: \(key)")
                XCTAssertNotEqual(translated, key, "\(lang) not translated: \(key)")
                let out = String(format: translated, locale: Locale(identifier: lang), arguments: args)
                XCTAssertFalse(out.contains("%@") || out.contains("%lld"), "\(lang) bad format: \(out)")
            }
            for plain in ["Rain", "Snow", "Wind", "Air quality", "More details", "Unlock with Essential", "Restore purchases"] {
                XCTAssertNotEqual(b.localizedString(forKey: plain, value: plain, table: "Localizable"), plain, "\(lang): \(plain)")
            }
        }
    }
}
