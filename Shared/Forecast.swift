import Foundation

/// Forecast for one location, built from the Open-Meteo forecast API.
struct Forecast: Codable {
    struct Current: Codable {
        let time: Date
        let temperature: Double
        let weatherCode: Int
        let precipitation: Double
    }

    /// One 15-minute precipitation step (mm per 15 min).
    struct Step: Codable, Identifiable {
        var id: Date { time }
        let time: Date
        let precipitation: Double
    }

    struct Hour: Codable, Identifiable {
        var id: Date { time }
        let time: Date
        let temperature: Double
        let precipitationProbability: Int?
        let precipitation: Double
        let weatherCode: Int
    }

    struct Day: Codable, Identifiable {
        var id: Date { time }
        let time: Date
        let weatherCode: Int
        let maxTemperature: Double
        let minTemperature: Double
        let precipitationSum: Double
        let precipitationProbabilityMax: Int?
    }

    let current: Current
    let nowcast: [Step]
    let hourly: [Hour]
    let daily: [Day]
    let utcOffsetSeconds: Int
    let fetchedAt: Date

    var timeZone: TimeZone { TimeZone(secondsFromGMT: utcOffsetSeconds) ?? .current }

    /// Upcoming 15-minute steps, starting with the current one.
    func upcomingSteps(hours: Double = 2, from now: Date = Date()) -> [Step] {
        let end = now.addingTimeInterval(hours * 3600)
        return nowcast.filter { $0.time.addingTimeInterval(15 * 60) > now && $0.time <= end }
    }

    /// First time rain (≥ threshold mm / 15 min) is expected within `minutes`.
    func rainStart(within minutes: Int, threshold: Double = 0.1, from now: Date = Date()) -> Date? {
        upcomingSteps(hours: Double(minutes) / 60, from: now)
            .first { $0.precipitation >= threshold }?
            .time
    }

    var isRainingNow: Bool {
        if current.precipitation >= 0.1 { return true }
        return upcomingSteps(hours: 0.25).first.map { $0.precipitation >= 0.1 } ?? false
    }

    /// Short human summary such as "Rain in 25 min" or "No rain for 2 hours".
    func nowcastSummary(from now: Date = Date()) -> String {
        let steps = upcomingSteps(hours: 2, from: now)
        if isRainingNow {
            if let stop = steps.first(where: { $0.precipitation < 0.1 && $0.time > now }) {
                let mins = max(5, Int(stop.time.timeIntervalSince(now) / 60))
                return String(localized: "Rain stopping in about \(mins) min")
            }
            return String(localized: "Rain for at least 2 hours")
        }
        if let start = steps.first(where: { $0.precipitation >= 0.1 }) {
            let mins = max(5, Int(start.time.timeIntervalSince(now) / 60))
            return String(localized: "Rain in about \(mins) min")
        }
        return String(localized: "No rain for 2 hours")
    }
}

// MARK: - Service

enum ForecastError: Error { case badResponse, decoding }

actor ForecastService {
    static let shared = ForecastService()

    private var cache: [String: Forecast] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    func forecast(latitude: Double, longitude: Double, days: Int, maxAge: TimeInterval = 600) async throws -> Forecast {
        let key = String(format: "%.3f,%.3f,%d", latitude, longitude, days)
        if let cached = cache[key], Date().timeIntervalSince(cached.fetchedAt) < maxAge {
            return cached
        }

        let commercialKey = AppConfig.openMeteoAPIKey
        var components = URLComponents()
        components.scheme = "https"
        components.host = commercialKey.isEmpty ? "api.open-meteo.com" : "customer-api.open-meteo.com"
        components.path = "/v1/forecast"
        var items: [URLQueryItem] = [
            .init(name: "latitude", value: String(format: "%.4f", latitude)),
            .init(name: "longitude", value: String(format: "%.4f", longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,precipitation"),
            .init(name: "minutely_15", value: "precipitation"),
            .init(name: "forecast_minutely_15", value: "12"),
            .init(name: "hourly", value: "temperature_2m,precipitation_probability,precipitation,weather_code"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max"),
            .init(name: "forecast_days", value: String(max(1, min(days, 16)))),
            .init(name: "timezone", value: "auto"),
            .init(name: "timeformat", value: "unixtime")
        ]
        if !commercialKey.isEmpty { items.append(.init(name: "apikey", value: commercialKey)) }
        components.queryItems = items
        guard let url = components.url else { throw ForecastError.badResponse }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ForecastError.badResponse
        }
        let forecast = try Self.decode(data)
        cache[key] = forecast
        return forecast
    }

    // MARK: Decoding

    private struct Raw: Decodable {
        struct RawCurrent: Decodable {
            let time: Int
            let temperature_2m: Double?
            let weather_code: Int?
            let precipitation: Double?
        }
        struct RawMinutely: Decodable {
            let time: [Int]
            let precipitation: [Double?]
        }
        struct RawHourly: Decodable {
            let time: [Int]
            let temperature_2m: [Double?]
            let precipitation_probability: [Int?]?
            let precipitation: [Double?]
            let weather_code: [Int?]
        }
        struct RawDaily: Decodable {
            let time: [Int]
            let weather_code: [Int?]
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
            let precipitation_sum: [Double?]
            let precipitation_probability_max: [Int?]?
        }
        let utc_offset_seconds: Int?
        let current: RawCurrent?
        let minutely_15: RawMinutely?
        let hourly: RawHourly?
        let daily: RawDaily?
    }

    static func decode(_ data: Data) throws -> Forecast {
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else { throw ForecastError.decoding }
        func date(_ t: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(t)) }

        let current = Forecast.Current(
            time: raw.current.map { date($0.time) } ?? Date(),
            temperature: raw.current?.temperature_2m ?? 0,
            weatherCode: raw.current?.weather_code ?? 0,
            precipitation: raw.current?.precipitation ?? 0
        )

        var steps: [Forecast.Step] = []
        if let m = raw.minutely_15 {
            for (i, t) in m.time.enumerated() where i < m.precipitation.count {
                steps.append(.init(time: date(t), precipitation: m.precipitation[i] ?? 0))
            }
        }

        var hours: [Forecast.Hour] = []
        if let h = raw.hourly {
            for (i, t) in h.time.enumerated() {
                hours.append(.init(
                    time: date(t),
                    temperature: h.temperature_2m[safe: i].flatMap { $0 } ?? 0,
                    precipitationProbability: h.precipitation_probability?[safe: i].flatMap { $0 },
                    precipitation: h.precipitation[safe: i].flatMap { $0 } ?? 0,
                    weatherCode: h.weather_code[safe: i].flatMap { $0 } ?? 0
                ))
            }
        }

        var days: [Forecast.Day] = []
        if let d = raw.daily {
            for (i, t) in d.time.enumerated() {
                days.append(.init(
                    time: date(t),
                    weatherCode: d.weather_code[safe: i].flatMap { $0 } ?? 0,
                    maxTemperature: d.temperature_2m_max[safe: i].flatMap { $0 } ?? 0,
                    minTemperature: d.temperature_2m_min[safe: i].flatMap { $0 } ?? 0,
                    precipitationSum: d.precipitation_sum[safe: i].flatMap { $0 } ?? 0,
                    precipitationProbabilityMax: d.precipitation_probability_max?[safe: i].flatMap { $0 }
                ))
            }
        }

        return Forecast(current: current, nowcast: steps, hourly: hours, daily: days,
                        utcOffsetSeconds: raw.utc_offset_seconds ?? 0, fetchedAt: Date())
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
