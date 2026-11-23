import Foundation
import CoreLocation
import WeatherKit

/// Apple Weather (WeatherKit) — the main forecast source.
/// 500,000 calls a month are included with the Apple Developer Program membership.
enum WeatherKitSource {

    static func fetch(latitude: Double, longitude: Double) async throws -> Forecast {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let (current, hourly, daily, minute) = try await WeatherService.shared.weather(
            for: location, including: .current, .hourly, .daily, .minute)
        let zone = await TimeZoneLookup.shared.zone(for: location)

        let cur = Forecast.Current(
            time: current.date,
            temperature: current.temperature.converted(to: .celsius).value,
            weatherCode: wmoCode(current.condition),
            precipitation: mmPerHour(current.precipitationIntensity) / 4,
            feelsLike: current.apparentTemperature.converted(to: .celsius).value,
            humidity: current.humidity * 100,
            uvIndex: current.uvIndex.value,
            windSpeed: current.wind.speed.converted(to: .kilometersPerHour).value,
            windGust: current.wind.gust?.converted(to: .kilometersPerHour).value,
            windDirection: current.wind.direction.converted(to: .degrees).value,
            pressure: current.pressure.converted(to: .hectopascals).value,
            visibility: current.visibility.converted(to: .kilometers).value,
            dewPoint: current.dewPoint.converted(to: .celsius).value
        )

        let hours = hourly.forecast.map { h in
            Forecast.Hour(
                time: h.date,
                temperature: h.temperature.converted(to: .celsius).value,
                precipitationProbability: Int((h.precipitationChance * 100).rounded()),
                precipitation: h.precipitationAmount.converted(to: .millimeters).value,
                weatherCode: wmoCode(h.condition)
            )
        }

        let days = daily.forecast.map { d in
            Forecast.Day(
                time: d.date,
                weatherCode: wmoCode(d.condition),
                maxTemperature: d.highTemperature.converted(to: .celsius).value,
                minTemperature: d.lowTemperature.converted(to: .celsius).value,
                precipitationSum: d.precipitationAmount.converted(to: .millimeters).value,
                precipitationProbabilityMax: Int((d.precipitationChance * 100).rounded())
            )
        }

        // 15-minute rain steps: real minute data for the next hour where Apple has it,
        // then hourly totals spread over 15-minute steps.
        var steps: [Forecast.Step] = []
        let minutes = minute?.forecast ?? []
        let hasMinute = !minutes.isEmpty
        if hasMinute {
            var buckets: [TimeInterval: Double] = [:]
            for m in minutes {
                let start = floor(m.date.timeIntervalSince1970 / 900) * 900
                buckets[start, default: 0] += mmPerHour(m.precipitationIntensity) / 60
            }
            steps = buckets.keys.sorted().map {
                Forecast.Step(time: Date(timeIntervalSince1970: $0), precipitation: buckets[$0] ?? 0)
            }
        }
        let coveredUntil = steps.last.map { $0.time.addingTimeInterval(900) } ?? Date()
        for h in hours where h.time.addingTimeInterval(3600) > coveredUntil && h.time < Date().addingTimeInterval(3 * 3600) {
            for q in 0..<4 {
                let t = h.time.addingTimeInterval(Double(q) * 900)
                guard t >= coveredUntil else { continue }
                steps.append(Forecast.Step(time: t, precipitation: h.precipitation / 4))
            }
        }

        var forecast = Forecast(current: cur, nowcast: steps, hourly: hours, daily: days,
                                utcOffsetSeconds: zone.secondsFromGMT(), fetchedAt: Date())
        forecast.timeZoneID = zone.identifier
        forecast.usesAppleWeather = true
        forecast.usesOpenMeteo = false
        forecast.hasMinuteData = hasMinute
        return forecast
    }

    /// Precipitation intensity (WeatherKit reports it as a speed) in mm per hour.
    private static func mmPerHour(_ intensity: Measurement<UnitSpeed>) -> Double {
        max(0, intensity.converted(to: .metersPerSecond).value * 3_600_000)
    }

    /// Maps Apple's conditions onto the WMO codes the UI already understands.
    static func wmoCode(_ condition: WeatherCondition) -> Int {
        switch condition {
        case .clear, .hot, .frigid: return 0
        case .mostlyClear: return 1
        case .partlyCloudy, .breezy, .windy: return 2
        case .mostlyCloudy, .cloudy: return 3
        case .foggy, .haze, .smoky, .blowingDust: return 45
        case .drizzle: return 53
        case .freezingDrizzle: return 56
        case .rain: return 63
        case .sunShowers: return 80
        case .heavyRain: return 65
        case .freezingRain, .sleet, .wintryMix: return 66
        case .flurries, .sunFlurries, .snow, .blowingSnow: return 73
        case .heavySnow, .blizzard: return 75
        case .isolatedThunderstorms, .scatteredThunderstorms, .thunderstorms: return 95
        case .strongStorms, .hurricane, .tropicalStorm, .hail: return 99
        @unknown default: return 3
        }
    }
}

/// Finds a place's time zone (for showing local times), cached per area.
actor TimeZoneLookup {
    static let shared = TimeZoneLookup()
    private var cache: [String: TimeZone] = [:]

    func zone(for location: CLLocation) async -> TimeZone {
        let key = String(format: "%.1f,%.1f", location.coordinate.latitude, location.coordinate.longitude)
        if let tz = cache[key] { return tz }
        let found = try? await withTimeout(seconds: 4) {
            try await CLGeocoder().reverseGeocodeLocation(location).first?.timeZone
        }
        let tz = (found ?? nil) ?? .current
        cache[key] = tz
        return tz
    }
}
