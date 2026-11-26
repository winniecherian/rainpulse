import Foundation
import CoreLocation

/// Keeps the "forecast vs reality" record: saves forecasts, then checks finished blocks against
/// Rain Truth reports, or Open-Meteo's recorded rainfall when nobody reported.
actor LedgerService {
    static let shared = LedgerService()
    private var lastVerify: [String: Date] = [:]

    func record(_ forecast: Forecast, place: Place) {
        guard !AppConfig.isUITest else { return }
        let cell = LedgerLogic.cell(for: place.coordinate)
        let updated = LedgerLogic.record(forecast, cell: cell, placeName: place.name, now: Date(), into: LedgerStore.load())
        LedgerStore.save(updated)
    }

    /// Checks finished blocks for this place (at most every 20 minutes).
    func verify(place: Place) async {
        guard !AppConfig.isUITest else { return }
        let cell = LedgerLogic.cell(for: place.coordinate)
        if let last = lastVerify[cell], Date().timeIntervalSince(last) < 1200 { return }
        lastVerify[cell] = Date()
        var entries = LedgerStore.load()
        let now = Date()
        let pending = entries.indices.filter {
            entries[$0].cell == cell && entries[$0].verdict == nil && entries[$0].blockEnd <= now
                && now.timeIntervalSince(entries[$0].blockEnd) < 3 * 86400
        }
        guard !pending.isEmpty else { return }
        let recorded = await recordedRain(latitude: place.latitude, longitude: place.longitude)
        for i in pending.prefix(8) {
            let e = entries[i]
            let reports = await CrowdReportService.shared.reports(inCell: cell, from: e.blockStart, to: e.blockEnd)
            let mm = recorded.map { series in
                series.filter { $0.0 >= e.blockStart && $0.0 < e.blockEnd }.map(\.1).reduce(0, +)
            }
            // Recorded rainfall needs the whole block to be in the data.
            let covered = recorded.map { s in s.filter { $0.0 >= e.blockStart && $0.0 < e.blockEnd }.count >= LedgerEntry.blockHours } ?? false
            entries[i].verdict = LedgerLogic.verdict(for: e, reports: reports, recordedMM: covered ? mm : nil)
        }
        LedgerStore.save(entries)
    }

    func summary(for place: Place) -> (score: LedgerScore, recent: [LedgerEntry]) {
        let cell = LedgerLogic.cell(for: place.coordinate)
        if AppConfig.isUITest { return Self.sample(place: place, cell: cell) }
        let entries = LedgerStore.load()
        return (LedgerLogic.score(entries, cell: cell, now: Date()), LedgerLogic.recent(entries, cell: cell))
    }

    /// Hourly recorded rainfall for the past 3 days (Open-Meteo; a model analysis, not a gauge).
    private func recordedRain(latitude: Double, longitude: Double) async -> [(Date, Double)]? {
        let key = AppConfig.openMeteoAPIKey
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = key.isEmpty ? "api.open-meteo.com" : "customer-api.open-meteo.com"
        comps.path = "/v1/forecast"
        comps.queryItems = [
            .init(name: "latitude", value: Net.approx(latitude)),
            .init(name: "longitude", value: Net.approx(longitude)),
            .init(name: "hourly", value: "precipitation"),
            .init(name: "past_days", value: "3"),
            .init(name: "forecast_days", value: "1"),
            .init(name: "timeformat", value: "unixtime")
        ] + (key.isEmpty ? [] : [.init(name: "apikey", value: key)])
        guard let url = comps.url,
              let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hourly = json["hourly"] as? [String: Any],
              let times = hourly["time"] as? [Double],
              let values = hourly["precipitation"] as? [Any] else { return nil }
        let now = Date()
        return zip(times, values).compactMap { t, v in
            let date = Date(timeIntervalSince1970: t)
            guard date.addingTimeInterval(3600) <= now, let mm = (v as? Double) ?? (v as? Int).map(Double.init) else { return nil }
            return (date, mm)
        }
    }

    static func sample(place: Place, cell: String) -> (LedgerScore, [LedgerEntry]) {
        let tz = TimeZone.current
        let base = LedgerLogic.blockStart(Date(), in: tz)
        func entry(_ hoursAgo: Double, chance: Int, mm: Double, verdict: LedgerEntry.Verdict) -> LedgerEntry {
            LedgerEntry(cell: cell, placeName: place.name, blockStart: base.addingTimeInterval(-hoursAgo * 3600),
                        timeZoneID: tz.identifier, issuedAt: Date(), chance: chance, amountMM: mm, verdict: verdict)
        }
        let list = [
            entry(6, chance: 70, mm: 4, verdict: .init(rained: true, evidence: .people(wet: 9, dry: 1), outcome: .hit)),
            entry(24, chance: 20, mm: 0, verdict: .init(rained: false, evidence: .recorded(mm: 0), outcome: .correctDry)),
            entry(30, chance: 60, mm: 2, verdict: .init(rained: false, evidence: .people(wet: 1, dry: 4), outcome: .falseAlarm))]
        return (LedgerScore(verified: 41, correct: 34, peopleChecked: 12), list)
    }
}
