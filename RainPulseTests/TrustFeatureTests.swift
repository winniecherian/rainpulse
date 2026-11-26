import XCTest
import CoreLocation
@testable import RainPulse

/// Official warnings (SACHET / CAP), forecast confidence and forecast-vs-reality.
final class OfficialAlertTests: XCTestCase {
    let now = CAPMessage.isoDate("2026-11-26T17:00:00+05:30")!

    static let rss = """
    <?xml version="1.0" encoding="UTF-8" standalone="no"?>
    <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom"><channel>
    <title>All India: CAP Disaster Alert Feeds</title>
    <item>
      <title>Lt to Mod Rain with light TSL is likely to occur at isolated places over CGLP, DRM in next 3 hours.</title>
      <description/>
      <category>Met</category>
      <link>https://sachet.ndma.gov.in/cap_public_website/FetchXMLFile?identifier=1795690010993007</link>
      <author>controlroom@ndma.gov.in (IMD Chennai)</author>
      <guid isPermaLink="false">1795690010993007</guid>
      <pubDate>Thu, 26 Nov 2026 10:46:55 GMT</pubDate>
    </item>
    <item>
      <title>Broken item without a link</title>
      <guid isPermaLink="false">1</guid>
    </item>
    </channel></rss>
    """

    static func cap(id: String = "IN-1795690010993007_43", sender: String = "IMD-Chennai", msgType: String = "Alert",
                    references: String = "", sent: String = "2026-11-26T16:16:06+05:30",
                    expires: String = "2026-11-26T19:00:00+05:30", severity: String = "Moderate",
                    area: String = "Chengalpattu, Dharmapuri, Kancheepuram, Madurai districts of Tamil Nadu",
                    tamil: Bool = false) -> String {
        let taInfo = tamil ? """
        <cap:info><cap:language>TA</cap:language><cap:category>Met</cap:category><cap:event>மிதமான மழை</cap:event>
        <cap:severity>\(severity)</cap:severity><cap:expires>\(expires)</cap:expires>
        <cap:headline>அடுத்த 3 மணி நேரத்தில் மிதமான மழை</cap:headline>
        <cap:area><cap:areaDesc>\(area)</cap:areaDesc></cap:area></cap:info>
        """ : ""
        return """
        <cap:alert xmlns:cap="urn:oasis:names:tc:emergency:cap:1.2">
        <cap:identifier>\(id)</cap:identifier>
        <cap:sender>\(sender)</cap:sender>
        <cap:sent>\(sent)</cap:sent>
        <cap:status>Actual</cap:status>
        <cap:msgType>\(msgType)</cap:msgType>
        <cap:references>\(references)</cap:references>
        \(taInfo)
        <cap:info>
        <cap:language>en-IN</cap:language>
        <cap:category>Met</cap:category>
        <cap:event>Moderate Rain</cap:event>
        <cap:urgency>Expected</cap:urgency>
        <cap:severity>\(severity)</cap:severity>
        <cap:certainty>Likely</cap:certainty>
        <cap:onset>2026-11-26T16:16:06+05:30</cap:onset>
        <cap:expires>\(expires)</cap:expires>
        <cap:headline>Lt to Mod Rain with light TSL is likely to occur at isolated places over CGLP, DRM in next 3 hours.</cap:headline>
        <cap:description/>
        <cap:parameter><cap:valueName>Polygon URL</cap:valueName><cap:value>https://example.invalid/p</cap:value></cap:parameter>
        <cap:area>
        <cap:areaDesc>\(area)</cap:areaDesc>
        <cap:geocode><cap:valueName>LGD District Code</cap:valueName><cap:value>555</cap:value></cap:geocode>
        </cap:area>
        </cap:info>
        </cap:alert>
        """
    }

    func testParsesSachetFeed() {
        let items = SachetFeed.parse(Data(Self.rss.utf8))
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].guid, "1795690010993007")
        XCTAssertEqual(items[0].author, "IMD Chennai")
        XCTAssertEqual(items[0].link.absoluteString, "https://sachet.ndma.gov.in/cap_public_website/FetchXMLFile?identifier=1795690010993007")
        XCTAssertEqual(items[0].pubDate, CAPMessage.isoDate("2026-11-26T10:46:55Z"))
    }

    func testParsesCAPMessage() throws {
        let m = try XCTUnwrap(CAPMessage.parse(Data(Self.cap(tamil: true).utf8)))
        XCTAssertEqual(m.identifier, "IN-1795690010993007_43")
        XCTAssertEqual(m.sender, "IMD-Chennai")
        XCTAssertEqual(m.infos.count, 2)
        XCTAssertEqual(m.infos[1].event, "Moderate Rain")
        XCTAssertEqual(m.infos[1].expires, CAPMessage.isoDate("2026-11-26T19:00:00+05:30"))
        XCTAssertTrue(m.infos[1].areaDesc.hasPrefix("Chengalpattu"))
        // Picks the user's language when the agency published it, else English.
        XCTAssertEqual(m.bestInfo(preferred: ["ta"])?.language, "TA")
        XCTAssertEqual(m.bestInfo(preferred: ["fr"])?.language, "en-IN")
        XCTAssertEqual(CAPMessage.baseID(m.identifier), "IN-1795690010993007")
    }

    func testReferencesAreParsed() throws {
        let m = try XCTUnwrap(CAPMessage.parse(Data(Self.cap(id: "IN-9_41", msgType: "Update",
            references: "IMD-Chennai,IN-9_43,2026-11-26T16:16:06+05:30").utf8)))
        XCTAssertEqual(m.references, ["IN-9_43"])
    }

    func testAreaKeysTolerateSpellings() {
        XCTAssertEqual(AreaMatch.key("Kancheepuram"), AreaMatch.key("Kanchipuram"))
        XCTAssertEqual(AreaMatch.key("Thoothukkudi"), AreaMatch.key("Thoothukudi"))
        XCTAssertEqual(AreaMatch.key("Thiruvallur"), AreaMatch.key("Tiruvallur"))
        XCTAssertNotEqual(AreaMatch.key("Chennai"), AreaMatch.key("Chengalpattu"))
    }

    func testAreaMatching() {
        let area = "Chengalpattu, Dharmapuri, Kancheepuram districts of Tamil Nadu"
        let split = AreaMatch.split(area)
        XCTAssertEqual(split.districts, ["Chengalpattu", "Dharmapuri", "Kancheepuram"])
        XCTAssertEqual(split.state, "Tamil Nadu")

        let kanchi = AdminArea(country: "IN", state: "Tamil Nadu", district: "Kanchipuram", locality: "Kanchipuram")
        let chennai = AdminArea(country: "IN", state: "Tamil Nadu", district: "Chennai", locality: "Chennai")
        let kerala = AdminArea(country: "IN", state: "Kerala", district: "Ernakulam", locality: "Kochi")
        XCTAssertTrue(AreaMatch.covers(area, place: kanchi))
        XCTAssertFalse(AreaMatch.covers(area, place: chennai))
        XCTAssertFalse(AreaMatch.covers(area, place: kerala))
        XCTAssertTrue(AreaMatch.covers("Ernakulam,Pathanamthitta,Thrissur districts of Kerala", place: kerala))
        // Whole-state warning.
        XCTAssertTrue(AreaMatch.covers("Tamil Nadu", place: chennai))
        XCTAssertFalse(AreaMatch.covers("Tamil Nadu", place: kerala))
        // Unknown place: never matches.
        XCTAssertFalse(AreaMatch.covers(area, place: AdminArea()))
    }

    private func messages(_ xmls: [String]) -> [CAPMessage] { xmls.compactMap { CAPMessage.parse(Data($0.utf8)) } }
    private let kanchi = AdminArea(country: "IN", state: "Tamil Nadu", district: "Kanchipuram", locality: nil)

    func testDuplicateCopiesShownOnce() {
        // IMD's original and a state authority's re-send of the same warning.
        let list = messages([Self.cap(), Self.cap(id: "IN-555_41", sender: "Puducherry-SDMA", msgType: "Update",
                                                   references: "IMD-Chennai,IN-1795690010993007_43,x")])
        let alerts = OfficialAlertLogic.alerts(from: list, authorByID: ["IN-1795690010993007_43": "IMD Chennai"],
                                               place: kanchi, languages: ["en"], now: now)
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts[0].event, "Moderate Rain")
        XCTAssertEqual(alerts[0].source, .sachet)
    }

    func testExpiredAndCancelledWarningsAreHidden() {
        let expired = messages([Self.cap(expires: "2026-11-26T16:30:00+05:30")])
        XCTAssertTrue(OfficialAlertLogic.alerts(from: expired, authorByID: [:], place: kanchi, languages: ["en"], now: now).isEmpty)

        let cancelled = messages([Self.cap(), Self.cap(id: "IN-777_1", msgType: "Cancel",
                                                        references: "IMD-Chennai,IN-1795690010993007_43,x")])
        XCTAssertTrue(OfficialAlertLogic.alerts(from: cancelled, authorByID: [:], place: kanchi, languages: ["en"], now: now).isEmpty)
    }

    func testMostSevereFirstAndNotifyRule() {
        let list = messages([Self.cap(id: "IN-1_1", severity: "Moderate"),
                             Self.cap(id: "IN-2_1", expires: "2026-11-26T21:00:00+05:30", severity: "Severe")])
        let alerts = OfficialAlertLogic.alerts(from: list, authorByID: [:], place: kanchi, languages: ["en"], now: now)
        XCTAssertEqual(alerts.map(\.severity), [.severe, .moderate])
        XCTAssertEqual(alerts[0].agency, "IMD Chennai")       // from the sender when the feed author is unknown
        XCTAssertTrue(OfficialAlertLogic.shouldNotify(alerts[0], alreadyNotified: []))
        XCTAssertFalse(OfficialAlertLogic.shouldNotify(alerts[0], alreadyNotified: [alerts[0].id]))
        XCTAssertFalse(OfficialAlertLogic.shouldNotify(alerts[1], alreadyNotified: []))
    }

    func testIndiaBoundingBox() {
        XCTAssertTrue(OfficialAlertService.inIndia(13.08, 80.27))
        XCTAssertFalse(OfficialAlertService.inIndia(51.5, -0.12))
    }
}

final class ConfidenceTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let tz = TimeZone(identifier: "Asia/Kolkata")!

    /// Hourly series starting at the current hour; `rainAt` = hour offsets with 1 mm.
    private func series(rainAt: [Int]) -> [(Date, Double)] {
        let start = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 3600) * 3600)
        return (0..<24).map { h in (start.addingTimeInterval(Double(h) * 3600), rainAt.contains(h) ? 1.0 : 0) }
    }

    func testAllDryIsHigh() throws {
        let s = Dictionary(uniqueKeysWithValues: ConfidenceModel.allCases.map { ($0, series(rainAt: [])) })
        let c = try XCTUnwrap(ConfidenceLogic.compute(series: s, now: now, timeZone: tz))
        XCTAssertEqual(c.level, .high)
        XCTAssertTrue(c.sentence.contains("4"))
        XCTAssertEqual(c.models.count, 4)
    }

    func testAgreeOnRainAndTiming() throws {
        let s: [ConfidenceModel: [(Date, Double)]] = [
            .ecmwf: series(rainAt: [5, 6]), .gfs: series(rainAt: [6]), .icon: series(rainAt: [5]), .gem: series(rainAt: [6, 7])]
        XCTAssertEqual(ConfidenceLogic.compute(series: s, now: now, timeZone: tz)?.level, .high)
        var three = s; three[.gem] = series(rainAt: [])
        XCTAssertEqual(ConfidenceLogic.compute(series: three, now: now, timeZone: tz)?.level, .medium)
    }

    func testSplitAndTimingDisagreementIsLow() throws {
        let split: [ConfidenceModel: [(Date, Double)]] = [
            .ecmwf: series(rainAt: [3]), .gfs: series(rainAt: [4]), .icon: series(rainAt: []), .gem: series(rainAt: [])]
        XCTAssertEqual(ConfidenceLogic.compute(series: split, now: now, timeZone: tz)?.level, .low)
        let timing: [ConfidenceModel: [(Date, Double)]] = [
            .ecmwf: series(rainAt: [1]), .gfs: series(rainAt: [9]), .icon: series(rainAt: [5]), .gem: series(rainAt: [10])]
        let c = try XCTUnwrap(ConfidenceLogic.compute(series: timing, now: now, timeZone: tz))
        XCTAssertEqual(c.level, .low)
    }

    func testNeedsThreeModels() {
        let s: [ConfidenceModel: [(Date, Double)]] = [.ecmwf: series(rainAt: []), .gfs: series(rainAt: [])]
        XCTAssertNil(ConfidenceLogic.compute(series: s, now: now, timeZone: tz))
    }

    func testDecodesOpenMeteoMultiModel() {
        let json = """
        {"hourly":{"time":[1800000000,1800003600],"precipitation_ecmwf_ifs025":[0.0,1.2],
        "precipitation_gfs_seamless":[0,null],"precipitation_icon_seamless":[0.1,0.4]}}
        """
        let d = ConfidenceLogic.decode(Data(json.utf8))
        XCTAssertEqual(d[.ecmwf]?.map(\.1), [0.0, 1.2])
        XCTAssertEqual(d[.gfs]?.count, 1)
        XCTAssertNil(d[.gem])
    }
}

final class LedgerTests: XCTestCase {
    let tz = TimeZone(identifier: "Asia/Kolkata")!
    // 2026-11-26 10:20 IST
    let now = CAPMessage.isoDate("2026-11-26T10:20:00+05:30")!

    private func forecast(rainHours: Set<Int> = [], chance: Int = 80) -> Forecast {
        let start = LedgerLogic.blockStart(now, in: tz)
        let hours = (0..<30).map { h -> Forecast.Hour in
            let t = start.addingTimeInterval(Double(h) * 3600)
            return Forecast.Hour(time: t, temperature: 28, precipitationProbability: rainHours.contains(h) ? chance : 10,
                                 precipitation: rainHours.contains(h) ? 2 : 0, weatherCode: 3)
        }
        var f = Forecast(current: .init(time: now, temperature: 28, weatherCode: 3, precipitation: 0),
                         nowcast: [], hourly: hours, daily: [], utcOffsetSeconds: 19800, fetchedAt: now)
        f.timeZoneID = tz.identifier
        return f
    }

    func testBlocksAreLocalThreeHourWindows() {
        let b = LedgerLogic.blockStart(now, in: tz)
        XCTAssertEqual(b, CAPMessage.isoDate("2026-11-26T09:00:00+05:30"))
    }

    func testRecordsOnlyBlocksAnHourAhead() {
        let entries = LedgerLogic.record(forecast(rainHours: [6, 7]), cell: "tf3bx", placeName: "Chennai", now: now, into: [])
        // 09–12 (started) is skipped; 12–15 starts in 1h40m → kept; up to 24h ahead.
        let starts = entries.map(\.blockStart).sorted()
        XCTAssertEqual(starts.first, CAPMessage.isoDate("2026-11-26T12:00:00+05:30"))
        XCTAssertEqual(entries.count, 8)
        let rainy = entries.first { $0.blockStart == CAPMessage.isoDate("2026-11-26T15:00:00+05:30") }
        XCTAssertEqual(rainy?.predictedRain, true)
        XCTAssertEqual(rainy?.chance, 80)
        // A later run within the hour before 12:00 no longer changes that block.
        let later = CAPMessage.isoDate("2026-11-26T11:30:00+05:30")!
        let again = LedgerLogic.record(forecast(rainHours: [3]), cell: "tf3bx", placeName: "Chennai", now: later, into: entries)
        let noon = again.first { $0.blockStart == CAPMessage.isoDate("2026-11-26T12:00:00+05:30") }
        XCTAssertEqual(noon?.issuedAt, now)
        XCTAssertEqual(noon?.predictedRain, false)
    }

    private func entry(predictRain: Bool) -> LedgerEntry {
        LedgerEntry(cell: "tf3bx", placeName: "Chennai", blockStart: CAPMessage.isoDate("2026-11-26T15:00:00+05:30")!,
                    timeZoneID: tz.identifier, issuedAt: now, chance: predictRain ? 70 : 10,
                    amountMM: predictRain ? 3 : 0, verdict: nil)
    }

    private func report(_ c: ReportCondition, minutesAfter: Double) -> CrowdReport {
        CrowdReport(id: UUID().uuidString, condition: c, latitude: 13.08, longitude: 80.27,
                    time: CAPMessage.isoDate("2026-11-26T15:00:00+05:30")!.addingTimeInterval(minutesAfter * 60))
    }

    func testVerdictPrefersPeople() {
        let e = entry(predictRain: true)
        let reports = [report(.rain, minutesAfter: 20), report(.heavyRain, minutesAfter: 40), report(.dry, minutesAfter: 50),
                       report(.dry, minutesAfter: 200)]   // outside the block: ignored
        let v = LedgerLogic.verdict(for: e, reports: reports, recordedMM: 0)
        XCTAssertEqual(v?.outcome, .hit)
        XCTAssertEqual(v?.evidence, .people(wet: 2, dry: 1))
    }

    func testVerdictFallsBackToRecordedRain() {
        XCTAssertEqual(LedgerLogic.verdict(for: entry(predictRain: true), reports: [], recordedMM: 0.1)?.outcome, .falseAlarm)
        XCTAssertEqual(LedgerLogic.verdict(for: entry(predictRain: false), reports: [], recordedMM: 4)?.outcome, .missed)
        XCTAssertEqual(LedgerLogic.verdict(for: entry(predictRain: false), reports: [], recordedMM: 0)?.outcome, .correctDry)
        XCTAssertNil(LedgerLogic.verdict(for: entry(predictRain: false), reports: [], recordedMM: nil))
    }

    func testScoreNeedsFourChecks() {
        var list: [LedgerEntry] = []
        for i in 0..<5 {
            var e = entry(predictRain: true)
            e = LedgerEntry(cell: e.cell, placeName: e.placeName, blockStart: e.blockStart.addingTimeInterval(Double(-i) * 10800),
                            timeZoneID: e.timeZoneID, issuedAt: now, chance: 70, amountMM: 3,
                            verdict: .init(rained: i != 4, evidence: i == 0 ? .people(wet: 3, dry: 0) : .recorded(mm: 2),
                                           outcome: i == 4 ? .falseAlarm : .hit))
            list.append(e)
        }
        let later = CAPMessage.isoDate("2026-11-27T00:00:00+05:30")!
        let score = LedgerLogic.score(list, cell: "tf3bx", now: later)
        XCTAssertEqual(score.verified, 5)
        XCTAssertEqual(score.correct, 4)
        XCTAssertEqual(score.peopleChecked, 1)
        XCTAssertEqual(score.percent, 80)
        XCTAssertNil(LedgerLogic.score(Array(list.prefix(3)), cell: "tf3bx", now: later).percent)
        XCTAssertEqual(LedgerLogic.recent(list, cell: "tf3bx").count, 3)
    }

    func testPastWindowRecordNames() {
        let start = Date(timeIntervalSince1970: 1_800_000_000 - 1_800_000_000.truncatingRemainder(dividingBy: 1800))
        let names = ReportKeys.namesIn(cell: "tf3bx", from: start, to: start.addingTimeInterval(3 * 3600))
        // 18 ten-minute rain buckets × 12 slots + 6 half-hour flood buckets × 8 slots.
        XCTAssertEqual(names.count, 18 * 12 + 6 * 8)
        XCTAssertTrue(names.allSatisfy { $0.contains("-tf3bx-") })
    }
}
