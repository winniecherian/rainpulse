import Foundation

/// Where radar tiles come from. Swap providers here when you upgrade data plans.
enum RadarSource: String, CaseIterable, Identifiable {
    /// OpenWeather Global Precipitation Maps (history + 2 h forecast, 10-minute step).
    /// Needs an OpenWeather plan with access to this product.
    case owmGlobalPrecip
    /// OpenWeather Weather Maps 1.0 — free, worldwide, current frame only.
    case owmCurrent
    /// Tomorrow.io map tiles. Free plan is ~25 requests/hour: testing only.
    case tomorrow

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .owmGlobalPrecip: return "OpenWeather – animated rain map"
        case .owmCurrent: return "OpenWeather – current only (free)"
        case .tomorrow: return "Tomorrow.io"
        }
    }

    var supportsTime: Bool { self != .owmCurrent }

    /// Highest zoom the provider serves; above this the overlay upscales tiles.
    var nativeMaxZoom: Int {
        switch self {
        case .owmGlobalPrecip, .owmCurrent: return 9
        case .tomorrow: return 12
        }
    }

    var attribution: String {
        switch self {
        case .owmGlobalPrecip, .owmCurrent: return "Rain map © OpenWeather"
        case .tomorrow: return "Rain map © Tomorrow.io"
        }
    }
}

/// Map layers. Radar is for everyone; the others are Pro.
enum MapLayer: String, CaseIterable, Identifiable {
    case radar, clouds, wind, temperature, pressure
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .radar: return String(localized: "Rain map")
        case .clouds: return String(localized: "Clouds")
        case .wind: return String(localized: "Wind")
        case .temperature: return String(localized: "Temperature")
        case .pressure: return String(localized: "Pressure")
        }
    }

    var symbol: String {
        switch self {
        case .radar: return "cloud.rain"
        case .clouds: return "cloud"
        case .wind: return "wind"
        case .temperature: return "thermometer.medium"
        case .pressure: return "gauge.with.dots.needle.67percent"
        }
    }

    /// OpenWeather Weather Maps 1.0 layer name.
    var owmLayerName: String {
        switch self {
        case .radar: return "precipitation_new"
        case .clouds: return "clouds_new"
        case .wind: return "wind_new"
        case .temperature: return "temp_new"
        case .pressure: return "pressure_new"
        }
    }

    var tomorrowField: String {
        switch self {
        case .radar: return "precipitationIntensity"
        case .clouds: return "cloudCover"
        case .wind: return "windSpeed"
        case .temperature: return "temperature"
        case .pressure: return "pressureSurfaceLevel"
        }
    }
}

struct RadarFrame: Hashable {
    let date: Date
    let isForecast: Bool
}

struct RadarProvider {
    let source: RadarSource

    /// Builds the animation frames a tier is entitled to.
    /// Frame count is capped (~18) to keep tile usage — and your data bill — predictable.
    func frames(for tier: Tier, layer: MapLayer, now: Date = Date()) -> [RadarFrame] {
        frames(past: tier.radarPast, future: tier.radarFuture, layer: layer, now: now)
    }

    func frames(past: TimeInterval, future: TimeInterval, layer: MapLayer, now: Date = Date()) -> [RadarFrame] {
        guard source.supportsTime, layer == .radar else {
            return [RadarFrame(date: now, isForecast: false)]
        }
        // Newest radar image is usually ~10 minutes old.
        let anchor = (floor((now.timeIntervalSince1970 - 600) / 600) * 600)
        let total = past + future
        let niceSteps: [TimeInterval] = [600, 1200, 1800, 3600, 7200, 10800]
        let step = niceSteps.first { total / $0 <= 18 } ?? 10800

        var frames: [RadarFrame] = []
        var t = anchor - floor(past / step) * step
        while t <= anchor + future + 1 {
            frames.append(RadarFrame(date: Date(timeIntervalSince1970: t), isForecast: t > anchor))
            t += step
        }
        return frames
    }

    /// Index of the "now" frame in a frame list.
    static func nowIndex(in frames: [RadarFrame]) -> Int {
        (frames.lastIndex { !$0.isForecast }) ?? 0
    }

    func tileURL(layer: MapLayer, frame: RadarFrame?, z: Int, x: Int, y: Int) -> URL? {
        switch source {
        case .owmGlobalPrecip:
            let key = AppConfig.owmAPIKey
            guard !key.isEmpty else { return nil }
            if layer == .radar, let frame {
                let tm = Int(frame.date.timeIntervalSince1970)
                return URL(string: "https://maps.openweathermap.org/maps/2.0/radar/forecast/\(z)/\(x)/\(y)?appid=\(key)&tm=\(tm)")
            }
            return URL(string: "https://tile.openweathermap.org/map/\(layer.owmLayerName)/\(z)/\(x)/\(y).png?appid=\(key)")

        case .owmCurrent:
            let key = AppConfig.owmAPIKey
            guard !key.isEmpty else { return nil }
            return URL(string: "https://tile.openweathermap.org/map/\(layer.owmLayerName)/\(z)/\(x)/\(y).png?appid=\(key)")

        case .tomorrow:
            let key = AppConfig.tomorrowAPIKey
            guard !key.isEmpty else { return nil }
            let time: String
            if let frame {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime]
                time = f.string(from: frame.date)
            } else {
                time = "now"
            }
            return URL(string: "https://api.tomorrow.io/v4/map/tile/\(z)/\(x)/\(y)/\(layer.tomorrowField)/\(time).png?apikey=\(key)")
        }
    }
}
