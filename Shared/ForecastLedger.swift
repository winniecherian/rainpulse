import Foundation
import CoreLocation

// MARK: - "Forecast vs reality"
//
// For every 3-hour block, RainPulse keeps what the forecast said at least an hour beforehand.
// After the block, it checks what happened: first with Rain Truth reports from people in the
// same ~5 km area, and if nobody reported, with Open-Meteo's recorded rainfall (a model
// analysis, labelled as such — not a rain gauge). The score is simply how often it was right.

struct LedgerEntry: Codable, Identifiable, Equatable {
    enum Outcome: String, Codable { case hit, correctDry, missed, falseAlarm
        var isCorrect: Bool { self == .hit || self == .correctDry }
    }

    enum Evidence: Codable, Equatable {
        case people(wet: Int, dry: Int)
        case recorded(mm: Double)
    }

    struct Verdict: Codable, Equatable {
        let rained: Bool
        let evidence: Evidence
        let outcome: Outcome
    }

    var id: String { "\(cell)-\(Int(blockStart.timeIntervalSince1970))" }
    let cell: String
    var placeName: String
    let blockStart: Date
    var timeZoneID: String
    var issuedAt: Date
    var chance: Int?           // highest hourly rain chance in the block (%)
    var amountMM: Double
    var verdict: Verdict?

    static let blockHours = 3
    var blockEnd: Date { blockStart.addingTimeInterval(Double(Self.blockHours) * 3600) }

    /// What counted as "the forecast said rain".
    var predictedRain: Bool { (chance ?? 0) >= 50 || amountMM >= 1.0 }

    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
}

struct LedgerScore: Equatable {
    let verified: Int
    let correct: Int
    let peopleChecked: Int
    var percent: Int? { verified >= 4 ? Int((Double(correct) / Double(verified) * 100).rounded()) : nil }
}

enum LedgerLogic {
    /// A forecast counts only if it was made at least this long before the block started.
    static let minLead: TimeInterval = 3600
    static let keepDays: Double = 8

    static func cell(for c: CLLocationCoordinate2D) -> String { Geohash.encode(c, precision: ReportKeys.precision) }

    /// Start of the local 3-hour block (00, 03, 06 … 21) containing `date`.
    static func blockStart(_ date: Date, in tz: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.year, .month, .day, .hour], from: date)
        var d = c
        d.hour = ((c.hour ?? 0) / LedgerEntry.blockHours) * LedgerEntry.blockHours
        d.minute = 0; d.second = 0
        return cal.date(from: d) ?? date
    }

    /// Updates the record with the latest forecast for blocks that start 1–24 hours from now.
    /// Blocks starting within the hour are frozen: their entry is what the forecast said beforehand.
    static func record(_ forecast: Forecast, cell: String, placeName: String, now: Date,
                       into entries: [LedgerEntry]) -> [LedgerEntry] {
        var byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let tz = forecast.timeZone
        var start = blockStart(now, in: tz)
        let limit = now.addingTimeInterval(24 * 3600)
        while start < limit {
            defer { start = start.addingTimeInterval(Double(LedgerEntry.blockHours) * 3600) }
            guard start.timeIntervalSince(now) >= minLead else { continue }
            let end = start.addingTimeInterval(Double(LedgerEntry.blockHours) * 3600)
            let hours = forecast.hourly.filter { $0.time >= start && $0.time < end }
            guard hours.count >= LedgerEntry.blockHours - 1 else { continue }
            let entry = LedgerEntry(cell: cell, placeName: placeName, blockStart: start,
                                    timeZoneID: tz.identifier, issuedAt: now,
                                    chance: hours.compactMap(\.precipitationProbability).max(),
                                    amountMM: hours.map(\.precipitation).reduce(0, +), verdict: nil)
            byID[entry.id] = entry
        }
        return trim(Array(byID.values), now: now)
    }

    /// Decides what happened in a finished block.
    static func verdict(for entry: LedgerEntry, reports: [CrowdReport], recordedMM: Double?) -> LedgerEntry.Verdict? {
        let inBlock = reports.filter { $0.time >= entry.blockStart && $0.time < entry.blockEnd }
        let wet = inBlock.filter { $0.condition.isWet }.count
        let dry = inBlock.count - wet
        let rained: Bool
        let evidence: LedgerEntry.Evidence
        if wet + dry > 0 {
            rained = wet >= dry
            evidence = .people(wet: wet, dry: dry)
        } else if let mm = recordedMM {
            rained = mm >= 0.5
            evidence = .recorded(mm: mm)
        } else {
            return nil
        }
        let outcome: LedgerEntry.Outcome
        switch (entry.predictedRain, rained) {
        case (true, true): outcome = .hit
        case (false, false): outcome = .correctDry
        case (false, true): outcome = .missed
        case (true, false): outcome = .falseAlarm
        }
        return .init(rained: rained, evidence: evidence, outcome: outcome)
    }

    static func score(_ entries: [LedgerEntry], cell: String, now: Date, days: Double = 7) -> LedgerScore {
        let recent = entries.filter { $0.cell == cell && $0.verdict != nil && now.timeIntervalSince($0.blockStart) < days * 86400 }
        let correct = recent.filter { $0.verdict!.outcome.isCorrect }.count
        let people = recent.filter { if case .people = $0.verdict!.evidence { return true } else { return false } }.count
        return LedgerScore(verified: recent.count, correct: correct, peopleChecked: people)
    }

    /// Most recent checked blocks, newest first. Prefers blocks with rain in the forecast or reality.
    static func recent(_ entries: [LedgerEntry], cell: String, limit: Int = 3) -> [LedgerEntry] {
        let done = entries.filter { $0.cell == cell && $0.verdict != nil }.sorted { $0.blockStart > $1.blockStart }
        let interesting = done.filter { $0.predictedRain || $0.verdict!.rained }
        return Array((interesting.isEmpty ? done : interesting).prefix(limit))
    }

    static func trim(_ entries: [LedgerEntry], now: Date) -> [LedgerEntry] {
        Array(entries.filter { now.timeIntervalSince($0.blockStart) < keepDays * 86400 }
            .sorted { $0.blockStart > $1.blockStart }.prefix(400))
    }

    /// "Yesterday 3–6 pm" / "Today 9 am–12 pm".
    static func blockLabel(_ e: LedgerEntry, now: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = e.timeZone
        let day: String
        if cal.isDate(e.blockStart, inSameDayAs: now) { day = String(localized: "Today") }
        else if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(e.blockStart, inSameDayAs: y) {
            day = String(localized: "Yesterday")
        } else { day = Fmt.weekday(e.blockStart, in: e.timeZone) }
        return "\(day) \(Fmt.hour(e.blockStart, in: e.timeZone))–\(Fmt.hour(e.blockEnd, in: e.timeZone))"
    }
}

/// The saved record (App Group, so background checks can add to it).
enum LedgerStore {
    private static let key = "ledger.v1"

    static func load() -> [LedgerEntry] {
        guard let data = SharedStore.defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([LedgerEntry].self, from: data) else { return [] }
        return list
    }

    static func save(_ entries: [LedgerEntry]) {
        if let data = try? JSONEncoder().encode(entries) { SharedStore.defaults.set(data, forKey: key) }
    }
}
