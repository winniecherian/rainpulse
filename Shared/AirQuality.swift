import Foundation

/// Current air quality (US AQI scale) from Open-Meteo's air-quality API (CAMS data).
struct AirQuality: Codable {
    let usAQI: Int
    let pm25: Double?
    let pm10: Double?
    let fetchedAt: Date

    var category: String {
        switch usAQI {
        case ..<51: return String(localized: "Good")
        case ..<101: return String(localized: "Moderate")
        case ..<151: return String(localized: "Unhealthy for sensitive groups")
        case ..<201: return String(localized: "Unhealthy")
        case ..<301: return String(localized: "Very unhealthy")
        default: return String(localized: "Hazardous")
        }
    }

    static let sample = AirQuality(usAQI: 62, pm25: 18.4, pm10: 41, fetchedAt: Date())
}

actor AirQualityService {
    static let shared = AirQualityService()
    private var cache: [String: AirQuality] = [:]

    func airQuality(latitude: Double, longitude: Double) async -> AirQuality? {
        if AppConfig.isUITest { return .sample }
        let key = String(format: "%.2f,%.2f", latitude, longitude)
        if let hit = cache[key], Date().timeIntervalSince(hit.fetchedAt) < 3600 { return hit }

        let commercialKey = AppConfig.openMeteoAPIKey
        var c = URLComponents()
        c.scheme = "https"
        c.host = commercialKey.isEmpty ? "air-quality-api.open-meteo.com" : "customer-air-quality-api.open-meteo.com"
        c.path = "/v1/air-quality"
        c.queryItems = [
            .init(name: "latitude", value: Net.approx(latitude)),
            .init(name: "longitude", value: Net.approx(longitude)),
            .init(name: "current", value: "us_aqi,pm2_5,pm10")
        ]
        if !commercialKey.isEmpty { c.queryItems?.append(.init(name: "apikey", value: commercialKey)) }
        guard let url = c.url else { return nil }

        struct Raw: Decodable {
            struct Cur: Decodable { let us_aqi: Double?; let pm2_5: Double?; let pm10: Double? }
            let current: Cur?
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        guard let (data, _) = try? await Net.session.data(for: request),
              let raw = try? JSONDecoder().decode(Raw.self, from: data),
              let aqi = raw.current?.us_aqi else { return nil }
        let result = AirQuality(usAQI: Int(aqi.rounded()), pm25: raw.current?.pm2_5, pm10: raw.current?.pm10, fetchedAt: Date())
        cache[key] = result
        return result
    }
}
