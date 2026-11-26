import Foundation
import CoreLocation
import WeatherKit

/// Fetches official government warnings for a place.
/// India: NDMA SACHET (the national feed is fetched whole, so the user's location never leaves the
/// phone). Other countries: Apple Weather's official alerts, where Apple provides them.
actor OfficialAlertService {
    static let shared = OfficialAlertService()

    private struct CachedCAP: Codable {
        let message: CAPMessage
        let author: String
        let pubDate: Date
    }

    private var caps: [String: CachedCAP] = [:]          // by feed guid
    private var feed: (at: Date, items: [SachetFeedItem])?
    private var areas: [String: AdminArea] = [:]
    private var results: [String: (at: Date, alerts: [OfficialAlert])] = [:]
    private var loadedDisk = false

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        c.httpAdditionalHeaders = ["User-Agent": "RainPulse/1.0 (iOS)"]
        return URLSession(configuration: c)
    }()

    /// Active warnings for a place, most severe first. Cached for 10 minutes.
    func alerts(latitude: Double, longitude: Double, maxAge: TimeInterval = 600) async -> [OfficialAlert] {
        if AppConfig.isUITest {
            return CommandLine.arguments.contains("-UITestOfficialAlert") ? [Self.sample] : []
        }
        let key = String(format: "%.2f,%.2f", latitude, longitude)
        if let r = results[key], Date().timeIntervalSince(r.at) < maxAge { return r.alerts }
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let area = await adminArea(for: location)
        var found: [OfficialAlert]
        if area.country == "IN" || (area.country == nil && Self.inIndia(latitude, longitude)) {
            found = await sachetAlerts(for: area)
        } else {
            found = await appleAlerts(for: location)
        }
        found.sort { ($0.severity, $0.sent) > ($1.severity, $1.sent) }
        results[key] = (Date(), found)
        return found
    }

    static func inIndia(_ lat: Double, _ lon: Double) -> Bool { (6...36).contains(lat) && (68...98).contains(lon) }

    // MARK: Where is this place, in English names?

    private func adminArea(for location: CLLocation) async -> AdminArea {
        let key = String(format: "%.2f,%.2f", location.coordinate.latitude, location.coordinate.longitude)
        if let a = areas[key] { return a }
        let found = try? await withTimeout(seconds: 6) { () -> AdminArea? in
            guard let m = try await CLGeocoder().reverseGeocodeLocation(
                location, preferredLocale: Locale(identifier: "en_IN")).first else { return nil }
            return AdminArea(country: m.isoCountryCode, state: m.administrativeArea,
                             district: m.subAdministrativeArea, locality: m.locality)
        }
        guard let area = found ?? nil else { return AdminArea() }
        areas[key] = area
        return area
    }

    // MARK: India — NDMA SACHET

    private func sachetAlerts(for area: AdminArea) async -> [OfficialAlert] {
        loadDiskCache()
        if feed == nil || Date().timeIntervalSince(feed!.at) > 600,
           let (data, resp) = try? await session.data(from: SachetFeed.url),
           (resp as? HTTPURLResponse)?.statusCode == 200 {
            let items = SachetFeed.parse(data)
            if !items.isEmpty { feed = (Date(), items) }
        }
        guard let items = feed?.items else { return [] }

        // Fetch only new warnings from the last 36 hours (each file is a few KB).
        let recent = items.filter { Date().timeIntervalSince($0.pubDate) < 36 * 3600 && caps[$0.guid] == nil }
        for batch in stride(from: 0, to: recent.count, by: 6).map({ Array(recent[$0..<min($0 + 6, recent.count)]) }) {
            let fetched = await withTaskGroup(of: (SachetFeedItem, CAPMessage?).self) { group in
                for item in batch {
                    group.addTask { [session] in
                        guard let (data, resp) = try? await session.data(from: item.link),
                              (resp as? HTTPURLResponse)?.statusCode == 200 else { return (item, nil) }
                        return (item, CAPMessage.parse(data))
                    }
                }
                var out: [(SachetFeedItem, CAPMessage?)] = []
                for await r in group { out.append(r) }
                return out
            }
            for (item, msg) in fetched {
                if let msg { caps[item.guid] = CachedCAP(message: msg, author: item.author, pubDate: item.pubDate) }
            }
        }
        // Keep three days.
        caps = caps.filter { Date().timeIntervalSince($0.value.pubDate) < 72 * 3600 }
        saveDiskCache()

        let messages = caps.values.map(\.message)
        let authors = Dictionary(caps.values.map { ($0.message.identifier, $0.author) }, uniquingKeysWith: { a, _ in a })
        let languages = Locale.preferredLanguages.compactMap { $0.split(separator: "-").first.map(String.init) }
        return OfficialAlertLogic.alerts(from: messages, authorByID: authors, place: area,
                                         languages: languages, now: Date())
    }

    private var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("official-cap.json")
    }

    private func loadDiskCache() {
        guard !loadedDisk else { return }
        loadedDisk = true
        if let url = cacheURL, let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([String: CachedCAP].self, from: data) {
            caps = saved
        }
    }

    private func saveDiskCache() {
        if let url = cacheURL, let data = try? JSONEncoder().encode(caps) { try? data.write(to: url, options: .atomic) }
    }

    // MARK: Elsewhere — Apple Weather official alerts

    private func appleAlerts(for location: CLLocation) async -> [OfficialAlert] {
        let converted = try? await withTimeout(seconds: 10) { () -> [OfficialAlert] in
            let list = try await WeatherService.shared.weather(for: location, including: .alerts) ?? []
            return Self.convert(list)
        }
        return converted ?? []
    }

    private static func convert(_ alerts: [WeatherAlert]) -> [OfficialAlert] {
        alerts.compactMap { a in
            let sev: OfficialAlert.Severity
            switch a.severity {
            case .extreme: sev = .extreme
            case .severe: sev = .severe
            case .moderate: sev = .moderate
            case .minor: sev = .minor
            default: sev = .unknown
            }
            guard (a.metadata.expirationDate) > Date() else { return nil }
            return OfficialAlert(id: a.detailsURL.absoluteString, event: a.summary, headline: a.summary,
                                 severity: sev, agency: a.source, areaDesc: a.region ?? "",
                                 onset: nil, expires: a.metadata.expirationDate, sent: a.metadata.date,
                                 detailsURL: a.detailsURL, source: .appleWeather)
        }
    }

    static let sample = OfficialAlert(
        id: "sample-official", event: "Heavy Rain",
        headline: "Heavy rain likely at isolated places over Chennai, Chengalpattu and Tiruvallur districts in the next 3 hours.",
        severity: .severe, agency: "IMD Chennai", areaDesc: "Chennai, Chengalpattu, Tiruvallur districts of Tamil Nadu",
        onset: Date(), expires: Date().addingTimeInterval(3 * 3600), sent: Date().addingTimeInterval(-600),
        detailsURL: SachetFeed.portal, source: .sachet)
}
