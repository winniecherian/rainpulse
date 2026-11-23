import Foundation

/// WMO weather interpretation codes used by Open-Meteo.
enum WeatherCode {
    static func symbol(_ code: Int, isNight: Bool = false) -> String {
        switch code {
        case 0: return isNight ? "moon.stars.fill" : "sun.max.fill"
        case 1, 2: return isNight ? "cloud.moon.fill" : "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 80, 81: return "cloud.rain.fill"
        case 65, 82: return "cloud.heavyrain.fill"
        case 66, 67: return "cloud.sleet.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95: return "cloud.bolt.rain.fill"
        case 96, 99: return "cloud.bolt.fill"
        default: return "cloud.fill"
        }
    }

    static func description(_ code: Int) -> String {
        switch code {
        case 0: return String(localized: "Clear")
        case 1: return String(localized: "Mostly clear")
        case 2: return String(localized: "Partly cloudy")
        case 3: return String(localized: "Overcast")
        case 45, 48: return String(localized: "Fog")
        case 51, 53, 55: return String(localized: "Drizzle")
        case 56, 57: return String(localized: "Freezing drizzle")
        case 61: return String(localized: "Light rain")
        case 63: return String(localized: "Rain")
        case 65: return String(localized: "Heavy rain")
        case 66, 67: return String(localized: "Freezing rain")
        case 71, 73, 75, 77: return String(localized: "Snow")
        case 80, 81: return String(localized: "Rain showers")
        case 82: return String(localized: "Violent showers")
        case 85, 86: return String(localized: "Snow showers")
        case 95: return String(localized: "Thunderstorm")
        case 96, 99: return String(localized: "Thunderstorm with hail")
        default: return String(localized: "Cloudy")
        }
    }
}

/// Locale-aware formatting so the app reads naturally worldwide
/// (°C / °F and mm / in follow the user's region automatically).
enum Fmt {
    static func temperature(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, usage: .weather,
                                    numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    static func rainfall(_ mm: Double) -> String {
        Measurement(value: mm, unit: UnitLength.millimeters)
            .formatted(.measurement(width: .abbreviated, usage: .rainfall,
                                    numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }

    static func hour(_ date: Date, in tz: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.hour()
        style.timeZone = tz
        return date.formatted(style)
    }

    static func time(_ date: Date, in tz: TimeZone = .current) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = tz
        return date.formatted(style)
    }

    static func weekday(_ date: Date, in tz: TimeZone) -> String {
        var cal = Calendar.current
        cal.timeZone = tz
        if cal.isDateInToday(date) { return String(localized: "Today") }
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated)
        style.timeZone = tz
        return date.formatted(style)
    }

    /// Intensity label for mm per 15 minutes.
    static func intensity(_ mmPer15: Double) -> String {
        let perHour = mmPer15 * 4
        switch perHour {
        case ..<2.5: return String(localized: "Light")
        case ..<7.6: return String(localized: "Moderate")
        case ..<50: return String(localized: "Heavy")
        default: return String(localized: "Violent")
        }
    }
}
