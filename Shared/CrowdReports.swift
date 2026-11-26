import Foundation
import CoreLocation

// MARK: - "Rain Truth": what people on the ground report

/// What a person sees outside right now.
enum ReportCondition: Int, CaseIterable, Codable, Identifiable {
    case dry = 0, drizzle = 1, rain = 2, heavyRain = 3, waterlogging = 4

    var id: Int { rawValue }

    var emoji: String {
        switch self {
        case .dry: return "☀️"
        case .drizzle: return "🌦"
        case .rain: return "🌧"
        case .heavyRain: return "⛈"
        case .waterlogging: return "🌊"
        }
    }

    var label: String {
        switch self {
        case .dry: return String(localized: "Dry")
        case .drizzle: return String(localized: "Drizzle")
        case .rain: return String(localized: "Raining")
        case .heavyRain: return String(localized: "Heavy rain")
        case .waterlogging: return String(localized: "Waterlogged street")
        }
    }

    var isWet: Bool { self != .dry }
}

struct CrowdReport: Identifiable, Codable, Hashable {
    var id: String
    let condition: ReportCondition
    /// Approximate position (rounded to about 100 m before it leaves the phone).
    let latitude: Double
    let longitude: Double
    let time: Date
    /// Street or neighbourhood name, when known (waterlogging reports only).
    var area: String?

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    func distanceKm(to c: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)) / 1000
    }
}

// MARK: - Geohash cells and record names

/// Records are addressed by name — cell + time bucket + slot — so the app can fetch
/// everything near a point without server-side queries or indexes.
enum ReportKeys {
    static let rainBucket: TimeInterval = 600        // 10 minutes
    static let rainLookback = 3                      // buckets → last 30 minutes
    static let rainSlots = 12
    static let floodBucket: TimeInterval = 1800      // 30 minutes
    static let floodLookback = 4                     // buckets → last 2 hours
    static let floodSlots = 8
    static let precision = 5                         // ≈ 4.9 × 4.9 km cells

    static func bucket(_ date: Date, size: TimeInterval) -> Int { Int(floor(date.timeIntervalSince1970 / size)) }

    static func isFlood(_ c: ReportCondition) -> Bool { c == .waterlogging }

    static func recordName(cell: String, condition: ReportCondition, time: Date, slot: Int) -> String {
        isFlood(condition)
            ? "f-\(cell)-\(bucket(time, size: floodBucket))-\(slot)"
            : "r-\(cell)-\(bucket(time, size: rainBucket))-\(slot)"
    }

    /// Every record name that could hold a report near `c` (this cell and its 8 neighbours).
    static func namesNear(_ c: CLLocationCoordinate2D, now: Date) -> [String] {
        let cells = Geohash.neighbourhood(Geohash.encode(c, precision: precision))
        let rb = bucket(now, size: rainBucket), fb = bucket(now, size: floodBucket)
        var names: [String] = []
        for cell in cells {
            for b in (rb - rainLookback + 1)...rb { for s in 0..<rainSlots { names.append("r-\(cell)-\(b)-\(s)") } }
            for b in (fb - floodLookback + 1)...fb { for s in 0..<floodSlots { names.append("f-\(cell)-\(b)-\(s)") } }
        }
        return names
    }

    /// Rounds a coordinate to 3 decimals (about 100 m) so reports never reveal an exact spot.
    static func approximate(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
}

enum Geohash {
    private static let chars = Array("0123456789bcdefghjkmnpqrstuvwxyz")

    static func encode(_ c: CLLocationCoordinate2D, precision: Int) -> String {
        var lat = (-90.0, 90.0), lon = (-180.0, 180.0)
        var out = "", bit = 0, ch = 0, even = true
        while out.count < precision {
            if even {
                let mid = (lon.0 + lon.1) / 2
                if c.longitude >= mid { ch = ch << 1 | 1; lon.0 = mid } else { ch <<= 1; lon.1 = mid }
            } else {
                let mid = (lat.0 + lat.1) / 2
                if c.latitude >= mid { ch = ch << 1 | 1; lat.0 = mid } else { ch <<= 1; lat.1 = mid }
            }
            even.toggle()
            bit += 1
            if bit == 5 { out.append(chars[ch]); bit = 0; ch = 0 }
        }
        return out
    }

    /// Bounding box of a cell: (minLat, maxLat, minLon, maxLon).
    static func bounds(_ hash: String) -> (Double, Double, Double, Double) {
        var lat = (-90.0, 90.0), lon = (-180.0, 180.0), even = true
        for c in hash {
            guard let v = chars.firstIndex(of: c) else { break }
            for i in stride(from: 4, through: 0, by: -1) {
                let on = (v >> i) & 1 == 1
                if even {
                    let mid = (lon.0 + lon.1) / 2
                    if on { lon.0 = mid } else { lon.1 = mid }
                } else {
                    let mid = (lat.0 + lat.1) / 2
                    if on { lat.0 = mid } else { lat.1 = mid }
                }
                even.toggle()
            }
        }
        return (lat.0, lat.1, lon.0, lon.1)
    }

    /// The cell plus its 8 neighbours (wrapping across the date line).
    static func neighbourhood(_ hash: String) -> [String] {
        let (a, b, c, d) = bounds(hash)
        let dLat = b - a, dLon = d - c
        let midLat = (a + b) / 2, midLon = (c + d) / 2
        var out: [String] = []
        for dy in -1...1 {
            for dx in -1...1 {
                let la = max(-89.9999, min(89.9999, midLat + Double(dy) * dLat))
                var lo = midLon + Double(dx) * dLon
                if lo > 180 { lo -= 360 }
                if lo < -180 { lo += 360 }
                let h = encode(CLLocationCoordinate2D(latitude: la, longitude: lo), precision: hash.count)
                if !out.contains(h) { out.append(h) }
            }
        }
        return out
    }
}

// MARK: - Summaries (pure, unit-tested)

struct CrowdSummary: Equatable {
    var wet = 0
    var dry = 0
    var heavy = 0
    var newest: Date?
    /// Most recent waterlogging reports, closest first.
    var floods: [CrowdReport] = []

    var total: Int { wet + dry }
    var mostlyWet: Bool { wet > dry }

    /// One-line status such as "4 people report rain nearby · 6 min ago".
    func headline(now: Date) -> String? {
        guard total > 0 else { return nil }
        let mins = newest.map { max(1, Int(now.timeIntervalSince($0) / 60)) } ?? 1
        if heavy > 0 && mostlyWet {
            return String(localized: "\(wet) people report heavy rain nearby · \(mins) min ago")
        }
        if mostlyWet {
            return wet == 1 ? String(localized: "1 person reports rain nearby · \(mins) min ago")
                            : String(localized: "\(wet) people report rain nearby · \(mins) min ago")
        }
        return dry == 1 ? String(localized: "1 person reports it's dry nearby · \(mins) min ago")
                        : String(localized: "\(dry) people report it's dry nearby · \(mins) min ago")
    }
}

enum CrowdLogic {
    /// Rain reports count for 30 minutes, waterlogging for 2 hours, within `radiusKm`.
    static func summary(_ reports: [CrowdReport], near c: CLLocationCoordinate2D, now: Date,
                        radiusKm: Double = 5) -> CrowdSummary {
        var s = CrowdSummary()
        var floods: [(CrowdReport, Double)] = []
        for r in reports {
            let age = now.timeIntervalSince(r.time)
            guard age >= -120 else { continue }        // ignore clocks far in the future
            let d = r.distanceKm(to: c)
            guard d <= radiusKm else { continue }
            if r.condition == .waterlogging {
                if age <= 2 * 3600 { floods.append((r, d)) }
                continue
            }
            guard age <= 30 * 60 else { continue }
            if r.condition.isWet { s.wet += 1 } else { s.dry += 1 }
            if r.condition == .heavyRain { s.heavy += 1 }
            if s.newest == nil || r.time > s.newest! { s.newest = r.time }
        }
        s.floods = floods.sorted { $0.1 < $1.1 }.map(\.0)
        return s
    }

    /// Waterlogging alert text, or nil when nothing new is worth a notification.
    static func floodAlert(_ summary: CrowdSummary, place: String, now: Date,
                           alreadyNotified: Set<String>) -> (id: String, title: String, body: String)? {
        guard let first = summary.floods.first(where: { !alreadyNotified.contains($0.id) }) else { return nil }
        let mins = max(1, Int(now.timeIntervalSince(first.time) / 60))
        let whereText = first.area ?? place
        let count = summary.floods.count
        let body = count > 1
            ? String(localized: "\(count) reports of waterlogging near \(whereText). Latest \(mins) min ago — consider another route.")
            : String(localized: "Waterlogging reported near \(whereText) \(mins) min ago — consider another route.")
        return (first.id, String(localized: "Flooded streets near \(place)"), body)
    }
}

// MARK: - Sample reports (UI tests and screenshots)

extension CrowdReport {
    static func samples(around c: CLLocationCoordinate2D, now: Date = Date()) -> [CrowdReport] {
        let offsets: [(Double, Double, ReportCondition, Double)] = [
            (0.010, 0.006, .rain, 4), (-0.008, 0.012, .heavyRain, 7), (0.004, -0.015, .rain, 12),
            (0.018, -0.004, .drizzle, 15), (-0.012, -0.010, .dry, 22), (0.006, 0.020, .waterlogging, 18)]
        let chennai = CLLocation(latitude: 13.08, longitude: 80.27)
        let street = CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: chennai) < 80_000
            ? "Anna Salai" : "High Street"
        return offsets.enumerated().map { i, o in
            CrowdReport(id: "sample-\(i)", condition: o.2,
                        latitude: ReportKeys.approximate(c.latitude + o.0),
                        longitude: ReportKeys.approximate(c.longitude + o.1),
                        time: now.addingTimeInterval(-o.3 * 60),
                        area: o.2 == .waterlogging ? street : nil)
        }
    }
}
