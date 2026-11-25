import Foundation
import CoreLocation

// MARK: - Place

struct Place: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var isCurrentLocation: Bool = false
    var alertsEnabled: Bool = true

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Subscription tier

/// Mirrors the competitor's Free / Essential / Pro structure.
enum Tier: Int, Codable, Comparable, CaseIterable {
    case free = 0
    case essential = 1
    case pro = 2

    static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }

    var displayName: String {
        switch self {
        case .free: return String(localized: "Free")
        case .essential: return String(localized: "Essential")
        case .pro: return String(localized: "Pro")
        }
    }

    /// How far back the radar animation goes.
    var radarPast: TimeInterval {
        switch self {
        case .free: return 30 * 60
        case .essential: return 2 * 3600
        case .pro: return 48 * 3600
        }
    }

    /// How far ahead the radar forecast animation goes.
    var radarFuture: TimeInterval {
        switch self {
        case .free: return 30 * 60
        case .essential, .pro: return 2 * 3600
        }
    }

    var forecastDays: Int { self == .free ? 2 : 14 }
    var maxSavedPlaces: Int { self == .free ? 3 : 20 }
    /// Number of places (including current location) that can trigger rain alerts.
    var alertPlacesLimit: Int { self == .free ? 1 : 20 }
    var hasMinuteChart: Bool { self >= .essential }
    var hasExtraLayers: Bool { self == .pro }
}

// MARK: - Shared storage (app + widget via App Group)

enum SharedStore {
    private static let placesKey = "places.v1"
    private static let tierKey = "tier.v1"
    private static let lastLocationKey = "lastLocation.v1"

    static var defaults: UserDefaults { AppConfig.sharedDefaults }

    static func loadPlaces() -> [Place] {
        guard let data = defaults.data(forKey: placesKey),
              let places = try? JSONDecoder().decode([Place].self, from: data) else { return [] }
        return places
    }

    static func savePlaces(_ places: [Place]) {
        if let data = try? JSONEncoder().encode(places) {
            defaults.set(data, forKey: placesKey)
        }
    }

    static var tier: Tier {
        get { Tier(rawValue: defaults.integer(forKey: tierKey)) ?? .free }
        set { defaults.set(newValue.rawValue, forKey: tierKey) }
    }

    /// Latest air quality per place (lets the widget avoid extra API calls).
    static func saveAirQuality(_ aqi: AirQuality, for place: Place) {
        if let data = try? JSONEncoder().encode(aqi) { defaults.set(data, forKey: aqiKey(place)) }
    }

    static func airQuality(for place: Place, maxAge: TimeInterval = 3 * 3600) -> AirQuality? {
        guard let data = defaults.data(forKey: aqiKey(place)),
              let aqi = try? JSONDecoder().decode(AirQuality.self, from: data),
              Date().timeIntervalSince(aqi.fetchedAt) < maxAge else { return nil }
        return aqi
    }

    private static func aqiKey(_ p: Place) -> String { String(format: "aqi.%.2f,%.2f", p.latitude, p.longitude) }

    /// Last known device location, saved by the app so the widget and
    /// background rain checks can use it without asking for "Always" location.
    static var lastLocation: Place? {
        get {
            guard let data = defaults.data(forKey: lastLocationKey) else { return nil }
            return try? JSONDecoder().decode(Place.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: lastLocationKey)
            } else {
                defaults.removeObject(forKey: lastLocationKey)
            }
        }
    }
}

// MARK: - Alert settings (shared so background task can read them)

enum AlertSettings {
    static let enabledKey = "alerts.enabled"
    static let leadMinutesKey = "alerts.leadMinutes"
    static let thresholdKey = "alerts.threshold"

    static var enabled: Bool { SharedStore.defaults.bool(forKey: enabledKey) }

    static var leadMinutes: Int {
        let v = SharedStore.defaults.integer(forKey: leadMinutesKey)
        return v == 0 ? 30 : v
    }

    /// Precipitation in mm per 15 minutes that counts as "rain".
    static var thresholdMM: Double {
        let v = SharedStore.defaults.double(forKey: thresholdKey)
        return v == 0 ? 0.1 : v
    }
}
