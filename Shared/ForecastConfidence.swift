import Foundation

// MARK: - "How sure is the rain forecast?"
//
// Four independent global weather models (Europe's ECMWF, the US GFS, Germany's ICON and
// Canada's GEM) are asked the same question: will it rain here in the next 12 hours, and when?
// Agreement → high confidence; disagreement → we say so, in plain words. Nothing is invented:
// the sentence is built directly from the models' numbers.

struct ForecastConfidence: Equatable {
    enum Level: Int, Comparable {
        case low = 0, medium, high
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }

        var label: String {
            switch self {
            case .high: return String(localized: "High confidence")
            case .medium: return String(localized: "Medium confidence")
            case .low: return String(localized: "Low confidence")
            }
        }
    }

    struct ModelView: Equatable, Identifiable {
        var id: String
        let name: String
        let firstRain: Date?       // nil = no rain in the window
        let totalMM: Double
    }

    let level: Level
    let sentence: String
    let models: [ModelView]
    let windowHours: Int
    let computedAt: Date
}

enum ConfidenceModel: String, CaseIterable {
    case ecmwf = "ecmwf_ifs025", gfs = "gfs_seamless", icon = "icon_seamless", gem = "gem_seamless"

    var displayName: String {
        switch self {
        case .ecmwf: return String(localized: "ECMWF (Europe)")
        case .gfs: return String(localized: "GFS (USA)")
        case .icon: return String(localized: "ICON (Germany)")
        case .gem: return String(localized: "GEM (Canada)")
        }
    }
}

enum ConfidenceLogic {
    static let rainMM = 0.3          // an hour with at least this much counts as rain
    static let windowHours = 12

    /// `series`: hourly precipitation per model (hour start, mm). Needs at least 3 models.
    static func compute(series: [ConfidenceModel: [(Date, Double)]], now: Date, timeZone: TimeZone) -> ForecastConfidence? {
        let end = now.addingTimeInterval(Double(windowHours) * 3600)
        var views: [ForecastConfidence.ModelView] = []
        for model in ConfidenceModel.allCases {
            guard let s = series[model] else { continue }
            let window = s.filter { $0.0.addingTimeInterval(3600) > now && $0.0 < end }
            guard window.count >= windowHours - 1 else { continue }
            let first = window.first { $0.1 >= rainMM }.map { max($0.0, now) }
            views.append(.init(id: model.rawValue, name: model.displayName, firstRain: first,
                               totalMM: window.map(\.1).reduce(0, +)))
        }
        let n = views.count
        guard n >= 3 else { return nil }
        let wet = views.filter { $0.firstRain != nil }
        let dryCount = n - wet.count
        let level: ForecastConfidence.Level
        let sentence: String
        let time = { (d: Date) in Fmt.time(d, in: timeZone) }

        if wet.count * 2 == n {
            level = .low
            sentence = String(localized: "Weather models disagree: \(wet.count) of \(n) show rain in the next 12 hours.")
        } else if wet.count * 2 < n {
            // Mostly dry.
            if dryCount == n {
                level = .high
                sentence = String(localized: "All \(n) weather models agree: no rain in the next 12 hours.")
            } else {
                level = dryCount >= n - 1 ? .medium : .low
                sentence = String(localized: "\(dryCount) of \(n) weather models show no rain in the next 12 hours; \(wet.count) show some.")
            }
        } else {
            // Mostly wet: also check whether they agree on when.
            let starts = wet.compactMap(\.firstRain).sorted()
            let spread = (starts.last!.timeIntervalSince(starts.first!)) / 3600
            let median = starts[starts.count / 2]
            if spread <= 2 {
                level = wet.count == n ? .high : .medium
                sentence = wet.count == n
                    ? String(localized: "All \(n) weather models show rain, starting around \(time(median)).")
                    : String(localized: "\(wet.count) of \(n) weather models show rain, starting around \(time(median)).")
            } else {
                level = (wet.count >= n - 1 && spread <= 4) ? .medium : .low
                sentence = String(localized: "\(wet.count) of \(n) weather models show rain, but disagree on timing: between \(time(starts.first!)) and \(time(starts.last!)).")
            }
        }
        return ForecastConfidence(level: level, sentence: sentence, models: views,
                                  windowHours: windowHours, computedAt: now)
    }

    /// Reads Open-Meteo's multi-model response (timeformat=unixtime).
    static func decode(_ data: Data) -> [ConfidenceModel: [(Date, Double)]] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hourly = json["hourly"] as? [String: Any],
              let times = hourly["time"] as? [Double] else { return [:] }
        var out: [ConfidenceModel: [(Date, Double)]] = [:]
        for model in ConfidenceModel.allCases {
            guard let values = hourly["precipitation_\(model.rawValue)"] as? [Any] else { continue }
            var series: [(Date, Double)] = []
            for (t, v) in zip(times, values) {
                if let mm = v as? Double { series.append((Date(timeIntervalSince1970: t), mm)) }
                else if let mm = v as? Int { series.append((Date(timeIntervalSince1970: t), Double(mm))) }
            }
            if !series.isEmpty { out[model] = series }
        }
        return out
    }
}

actor ConfidenceService {
    static let shared = ConfidenceService()
    private var cache: [String: (at: Date, value: ForecastConfidence?)] = [:]

    func confidence(latitude: Double, longitude: Double, timeZone: TimeZone, maxAge: TimeInterval = 1800) async -> ForecastConfidence? {
        if AppConfig.isUITest { return Self.sample(timeZone: timeZone) }
        let key = String(format: "%.2f,%.2f", latitude, longitude)
        if let c = cache[key], Date().timeIntervalSince(c.at) < maxAge { return c.value }
        let commercialKey = AppConfig.openMeteoAPIKey
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = commercialKey.isEmpty ? "api.open-meteo.com" : "customer-api.open-meteo.com"
        comps.path = "/v1/forecast"
        comps.queryItems = [
            .init(name: "latitude", value: Net.approx(latitude)),
            .init(name: "longitude", value: Net.approx(longitude)),
            .init(name: "hourly", value: "precipitation"),
            .init(name: "models", value: ConfidenceModel.allCases.map(\.rawValue).joined(separator: ",")),
            .init(name: "forecast_days", value: "2"),
            .init(name: "timeformat", value: "unixtime")
        ] + (commercialKey.isEmpty ? [] : [.init(name: "apikey", value: commercialKey)])
        guard let url = comps.url,
              let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return cache[key]?.value }
        let value = ConfidenceLogic.compute(series: ConfidenceLogic.decode(data), now: Date(), timeZone: timeZone)
        cache[key] = (Date(), value)
        return value
    }

    static func sample(timeZone: TimeZone) -> ForecastConfidence {
        let start = Date().addingTimeInterval(3 * 3600)
        let wet = 3, n = 4, at = Fmt.time(start, in: timeZone)
        return ForecastConfidence(
            level: .medium,
            sentence: String(localized: "\(wet) of \(n) weather models show rain, starting around \(at)."),
            models: [
                .init(id: "ecmwf", name: ConfidenceModel.ecmwf.displayName, firstRain: start, totalMM: 6.2),
                .init(id: "gfs", name: ConfidenceModel.gfs.displayName, firstRain: start.addingTimeInterval(3600), totalMM: 4.1),
                .init(id: "icon", name: ConfidenceModel.icon.displayName, firstRain: start, totalMM: 7.5),
                .init(id: "gem", name: ConfidenceModel.gem.displayName, firstRain: nil, totalMM: 0.1)],
            windowHours: 12, computedAt: Date())
    }
}
