import Foundation
import CoreLocation

/// An active tropical cyclone (any ocean basin) from GDACS — the UN / European
/// Commission Global Disaster Alert and Coordination System, which republishes
/// JTWC / NHC advisories. Free to reuse with credit.
struct Cyclone: Identifiable, Codable {
    struct Segment: Codable {
        let points: [Coordinate]
        let isForecast: Bool
        let category: String    // "TD", "TS", "Cat1"... "Cat5"
    }
    struct Coordinate: Codable {
        let lat: Double, lon: Double
        var cl: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    }

    let id: Int
    let name: String                 // e.g. "AKVAN"
    let alertLevel: String           // Green / Orange / Red
    let maxWindKmh: Double
    let strengthText: String
    let position: Coordinate
    let updated: Date?
    let segments: [Segment]
    let cone: [[Coordinate]]
    let reportURL: URL?
    let source: String

    /// Last point of the forecast track, for "heading towards".
    var forecastEnd: Coordinate? { segments.filter(\.isForecast).flatMap(\.points).last }

    func distanceKm(to c: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: position.lat, longitude: position.lon)
            .distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)) / 1000
    }

    /// Closest the forecast track gets to a point.
    func closestApproachKm(to c: CLLocationCoordinate2D) -> Double {
        let target = CLLocation(latitude: c.latitude, longitude: c.longitude)
        let all = [position] + segments.filter(\.isForecast).flatMap(\.points)
        return all.map { CLLocation(latitude: $0.lat, longitude: $0.lon).distance(from: target) / 1000 }.min()
            ?? distanceKm(to: c)
    }

    var categoryLabel: String {
        switch maxWindKmh {
        case ..<63: return String(localized: "Tropical depression")
        case ..<119: return String(localized: "Tropical storm")
        case ..<154: return String(localized: "Category 1 cyclone")
        case ..<178: return String(localized: "Category 2 cyclone")
        case ..<209: return String(localized: "Category 3 cyclone")
        case ..<252: return String(localized: "Category 4 cyclone")
        default: return String(localized: "Category 5 cyclone")
        }
    }

    /// Sample storm ~450 km south-east of a point, used only by UI tests.
    static func sample(near c: CLLocationCoordinate2D) -> Cyclone {
        let p = Coordinate(lat: c.latitude - 3, lon: c.longitude + 3)
        func pt(_ dLat: Double, _ dLon: Double) -> Coordinate { Coordinate(lat: p.lat + dLat, lon: p.lon + dLon) }
        return Cyclone(
            id: 1, name: "ARIA", alertLevel: "Orange", maxWindKmh: 120,
            strengthText: "Tropical Storm (maximum wind speed of 120 km/h)", position: p, updated: Date(),
            segments: [
                Segment(points: [pt(-3, 2), pt(-1.5, 1)], isForecast: false, category: "TS"),
                Segment(points: [pt(-1.5, 1), pt(0, 0)], isForecast: false, category: "TS"),
                Segment(points: [pt(0, 0), pt(1.5, -1.2)], isForecast: true, category: "Cat1"),
                Segment(points: [pt(1.5, -1.2), pt(3, -2.5)], isForecast: true, category: "TS")
            ],
            cone: [[pt(0, -0.5), pt(1.6, -2), pt(3.5, -3.8), pt(3.2, -1), pt(1.3, -0.3), pt(0, 0.5)]],
            reportURL: URL(string: "https://www.gdacs.org"), source: "JTWC")
    }
}

actor CycloneService {
    static let shared = CycloneService()
    private var cache: (date: Date, storms: [Cyclone])?

    /// Active storms worldwide. Cached for 30 minutes.
    func activeCyclones(sampleNear: CLLocationCoordinate2D? = nil) async -> [Cyclone] {
        if AppConfig.isUITest {
            return [Cyclone.sample(near: sampleNear ?? CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1))]
        }
        if let cache, Date().timeIntervalSince(cache.date) < 1800 { return cache.storms }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        let from = iso.string(from: Date().addingTimeInterval(-10 * 86400))
        let to = iso.string(from: Date().addingTimeInterval(86400))
        guard let url = URL(string: "https://www.gdacs.org/gdacsapi/api/events/geteventlist/SEARCH?eventlist=TC&fromdate=\(from)&todate=\(to)&alertlevel=green;orange;red"),
              let data = await get(url) else { return cache?.storms ?? [] }

        struct EventList: Decodable {
            struct Feature: Decodable {
                struct Geometry: Decodable { let coordinates: [Double] }
                struct Props: Decodable {
                    struct Sev: Decodable { let severity: Double?; let severitytext: String? }
                    struct URLs: Decodable { let geometry: String?; let report: String? }
                    let eventid: Int
                    let episodeid: Int?
                    let eventname: String?
                    let alertlevel: String?
                    let iscurrent: String?
                    let todate: String?
                    let source: String?
                    let severitydata: Sev?
                    let url: URLs?
                }
                let geometry: Geometry
                let properties: Props
            }
            let features: [Feature]
        }
        guard let list = try? JSONDecoder().decode(EventList.self, from: data) else { return cache?.storms ?? [] }

        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = TimeZone(identifier: "UTC")
        local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        // "Active" = latest advisory within the last 36 hours.
        let active = list.features.filter { f in
            guard f.properties.iscurrent == "true" else { return false }
            guard let t = f.properties.todate.flatMap(local.date(from:)) else { return true }
            return Date().timeIntervalSince(t) < 36 * 3600
        }

        var storms: [Cyclone] = []
        for f in active {
            let p = f.properties
            let coords = f.geometry.coordinates
            guard coords.count >= 2 else { continue }
            var segments: [Cyclone.Segment] = []
            var cone: [[Cyclone.Coordinate]] = []
            if let g = p.url?.geometry, let gURL = URL(string: g), let gData = await get(gURL) {
                (segments, cone) = Self.parseGeometry(gData)
            }
            storms.append(Cyclone(
                id: p.eventid,
                name: (p.eventname ?? "Cyclone").replacingOccurrences(of: #"-\d+$"#, with: "", options: .regularExpression),
                alertLevel: p.alertlevel ?? "Green",
                maxWindKmh: p.severitydata?.severity ?? 0,
                strengthText: p.severitydata?.severitytext ?? "",
                position: .init(lat: coords[1], lon: coords[0]),
                updated: p.todate.flatMap(local.date(from:)),
                segments: segments, cone: cone,
                reportURL: p.url?.report.flatMap(URL.init(string:)),
                source: p.source ?? "GDACS"))
        }
        cache = (Date(), storms)
        return storms
    }

    private func get(_ url: URL) async -> Data? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 25
        guard let (data, response) = try? await Net.session.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    /// Track lines ("Line_*", with forecast flag and category label) and the uncertainty cone ("Poly_Cones").
    static func parseGeometry(_ data: Data) -> ([Cyclone.Segment], [[Cyclone.Coordinate]]) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = root["features"] as? [[String: Any]] else { return ([], []) }
        var segments: [Cyclone.Segment] = []
        var cone: [[Cyclone.Coordinate]] = []
        for f in features {
            guard let props = f["properties"] as? [String: Any],
                  let geom = f["geometry"] as? [String: Any],
                  let type = geom["type"] as? String else { continue }
            let cls = props["Class"] as? String ?? ""
            if type == "LineString", cls.hasPrefix("Line"), let raw = geom["coordinates"] as? [[Double]] {
                let pts = raw.compactMap { $0.count >= 2 ? Cyclone.Coordinate(lat: $0[1], lon: $0[0]) : nil }
                let forecast = (props["forecast"] as? Bool) ?? ((props["forecast"] as? String) == "true")
                segments.append(.init(points: pts, isForecast: forecast, category: props["polygonlabel"] as? String ?? ""))
            } else if cls == "Poly_Cones" {
                let rings: [[[Double]]]
                if type == "Polygon" { rings = (geom["coordinates"] as? [[[Double]]]).map { [$0.first ?? []] } ?? [] }
                else if type == "MultiPolygon" { rings = (geom["coordinates"] as? [[[[Double]]]])?.compactMap(\.first) ?? [] }
                else { rings = [] }
                for ring in rings {
                    cone.append(ring.compactMap { $0.count >= 2 ? Cyclone.Coordinate(lat: $0[1], lon: $0[0]) : nil })
                }
            }
        }
        return (segments, cone)
    }
}
