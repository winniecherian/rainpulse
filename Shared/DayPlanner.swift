import Foundation

// MARK: - "Leave now" window

/// The best time to head out and stay dry, for a trip of a given length.
struct DryWindow: Equatable {
    enum Kind: Equatable {
        case goNow          // dry now for the whole trip
        case waitUntil      // raining (or about to), dry window later
        case noDryWindow    // wet the whole look-ahead: least-wet option given
    }
    let kind: Kind
    let start: Date
    let end: Date
    /// Expected rain during the window (mm).
    let rain: Double
}

extension Forecast {
    /// Rain (mm) expected in each 15-minute slot from `now`, for `hours` ahead.
    /// Uses 15-minute steps where available, otherwise spreads hourly rain over its quarters.
    /// Hours with a high rain chance but no amount count as light rain.
    func slotRain(hours: Double = 3, from now: Date = Date()) -> [(start: Date, mm: Double)] {
        let count = Int(hours * 4)
        return (0..<count).map { i in
            let start = now.addingTimeInterval(Double(i) * 900)
            let mid = start.addingTimeInterval(450)
            if let step = nowcast.first(where: { $0.time <= mid && mid < $0.time.addingTimeInterval(900) }) {
                return (start, step.precipitation)
            }
            if let hour = hourly.first(where: { $0.time <= mid && mid < $0.time.addingTimeInterval(3600) }) {
                var mm = hour.precipitation / 4
                if mm < 0.1, let p = hour.precipitationProbability, p >= 60 { mm = 0.1 }
                return (start, mm)
            }
            return (start, 0)
        }
    }

    /// Earliest dry window of `tripMinutes` within the next `hours`.
    func dryWindow(tripMinutes: Int, hours: Double = 3, from now: Date = Date(), threshold: Double = 0.1) -> DryWindow? {
        let slots = slotRain(hours: hours, from: now)
        let need = max(1, Int(ceil(Double(tripMinutes) / 15)))
        guard slots.count >= need else { return nil }
        var best: (i: Int, mm: Double)?
        for i in 0...(slots.count - need) {
            let window = slots[i..<(i + need)]
            let mm = window.reduce(0) { $0 + $1.mm }
            if window.allSatisfy({ $0.mm < threshold }) {
                let start = slots[i].start
                return DryWindow(kind: i == 0 ? .goNow : .waitUntil, start: start,
                                 end: start.addingTimeInterval(Double(tripMinutes) * 60), rain: mm)
            }
            if best == nil || mm < best!.mm - 0.05 { best = (i, mm) }
        }
        guard let best else { return nil }
        let start = slots[best.i].start
        return DryWindow(kind: .noDryWindow, start: start, end: start.addingTimeInterval(Double(tripMinutes) * 60),
                         rain: best.mm)
    }

    /// Headline and detail for the "Leave now" card.
    func leaveAdvice(tripMinutes: Int, from now: Date = Date()) -> (title: String, detail: String) {
        guard let w = dryWindow(tripMinutes: tripMinutes, from: now) else {
            return (String(localized: "No forecast yet"), "")
        }
        let at = Fmt.time(w.start, in: timeZone)
        let until = Fmt.time(w.end, in: timeZone)
        switch w.kind {
        case .goNow:
            let dryFor = dryMinutes(from: now)
            return (String(localized: "Go now — it's dry"),
                    dryFor >= 180 ? String(localized: "No rain expected for the next 3 hours.")
                                  : String(localized: "Dry for about \(dryFor) min. Back before \(until) to stay dry."))
        case .waitUntil:
            let mins = max(5, Int(w.start.timeIntervalSince(now) / 60))
            return (String(localized: "Leave at \(at) to stay dry"),
                    String(localized: "Wait about \(mins) min — then dry until \(until)."))
        case .noDryWindow:
            return (String(localized: "Take an umbrella"),
                    String(localized: "Rain likely for the next 3 hours. Least wet: \(at)–\(until)."))
        }
    }

    /// Minutes of dry weather from `now` (up to 180).
    func dryMinutes(from now: Date = Date()) -> Int {
        let slots = slotRain(hours: 3, from: now)
        let wet = slots.firstIndex { $0.mm >= 0.1 } ?? slots.count
        return wet * 15
    }
}

// MARK: - Today in one line (lock screen)

extension Forecast {
    /// e.g. "Umbrella after 4 PM · AQI 160, wear a mask". Rain first, then the most important extra.
    func oneLiner(airQuality: AirQuality?, now: Date = Date()) -> String {
        var parts: [String] = [rainPart(now: now)]
        if let aqi = airQuality?.usAQI, aqi > 150 {
            parts.append(String(localized: "AQI \(aqi), wear a mask"))
        } else if let today = daily.first, today.maxTemperature >= 38 {
            parts.append(String(localized: "Very hot, \(Fmt.temperature(today.maxTemperature))"))
        } else if let aqi = airQuality?.usAQI, aqi > 100 {
            parts.append(String(localized: "AQI \(aqi), sensitive groups take care"))
        } else if let uv = current.uvIndex, uv >= 8 {
            parts.append(String(localized: "Strong sun, UV \(uv)"))
        }
        return parts.joined(separator: " · ")
    }

    private func rainPart(now: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let endOfDay = cal.startOfDay(for: now).addingTimeInterval(86400)
        if isRaining(at: now) {
            let slots = slotRain(hours: 6, from: now)
            if let stop = slots.first(where: { $0.mm < 0.1 }) {
                return String(localized: "Rain until \(Fmt.time(stop.start, in: timeZone))")
            }
            return String(localized: "Rain for hours — umbrella")
        }
        if let soon = rainStart(within: 120, from: now) {
            return String(localized: "Umbrella from \(Fmt.time(soon, in: timeZone))")
        }
        let later = hourly.first { h in
            h.time > now && h.time < endOfDay && (h.precipitation >= 0.3 || (h.precipitationProbability ?? 0) >= 60)
        }
        if let later {
            return String(localized: "Umbrella after \(Fmt.hour(later.time, in: timeZone))")
        }
        return String(localized: "No rain today")
    }
}
