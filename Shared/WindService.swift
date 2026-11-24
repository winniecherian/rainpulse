import Foundation
import MapKit

/// A regular grid of surface wind (m/s, u = eastward, v = northward).
struct WindField {
    let lats: [Double]      // ascending
    let lons: [Double]      // ascending, may run past 180 (unwrapped)
    let u: [Float]          // row-major [lat][lon]
    let v: [Float]
    let validTime: Date?

    /// Bilinear wind at a coordinate, or nil outside the grid.
    func vector(lat: Double, lon: Double) -> (u: Double, v: Double)? {
        guard lats.count > 1, lons.count > 1 else { return nil }
        var x = lon
        if x < lons[0] { x += 360 }
        if x > lons[lons.count - 1] { x -= 360 }
        guard lat >= lats[0], lat <= lats[lats.count - 1], x >= lons[0], x <= lons[lons.count - 1] else { return nil }
        let dLat = lats[1] - lats[0], dLon = lons[1] - lons[0]
        let fi = (lat - lats[0]) / dLat, fj = (x - lons[0]) / dLon
        let i0 = min(Int(fi), lats.count - 2), j0 = min(Int(fj), lons.count - 2)
        let ti = Float(fi - Double(i0)), tj = Float(fj - Double(j0))
        let n = lons.count
        func lerp(_ a: [Float]) -> Double {
            let a00 = a[i0 * n + j0], a01 = a[i0 * n + j0 + 1]
            let a10 = a[(i0 + 1) * n + j0], a11 = a[(i0 + 1) * n + j0 + 1]
            let top = a00 + (a01 - a00) * tj, bottom = a10 + (a11 - a10) * tj
            return Double(top + (bottom - top) * ti)
        }
        return (lerp(u), lerp(v))
    }

    /// Gentle swirling sample field for UI tests.
    static func sample(around c: CLLocationCoordinate2D) -> WindField {
        let lats = stride(from: c.latitude - 20, through: c.latitude + 20, by: 2.0).map { $0 }
        let lons = stride(from: c.longitude - 30, through: c.longitude + 30, by: 2.0).map { $0 }
        var u: [Float] = [], v: [Float] = []
        for la in lats {
            for lo in lons {
                u.append(Float(6 + 4 * sin((la - c.latitude) / 6)))
                v.append(Float(3 * cos((lo - c.longitude) / 8)))
            }
        }
        return WindField(lats: lats, lons: lons, u: u, v: v, validTime: Date())
    }
}

/// Surface wind from NOAA's GFS model, served by NOAA's public ERDDAP data server
/// (public domain). Falls back to Open-Meteo for a coarse grid if ERDDAP is down.
actor WindService {
    static let shared = WindService()
    private var cache: [String: (Date, WindField)] = [:]

    func field(for region: MKCoordinateRegion) async -> WindField? {
        if AppConfig.isUITest { return .sample(around: region.center) }

        // Snap the request to whole degrees with some margin so panning reuses it.
        let latMin = max(-85, floor(region.center.latitude - region.span.latitudeDelta * 0.75))
        let latMax = min(85, ceil(region.center.latitude + region.span.latitudeDelta * 0.75))
        let lonHalf = min(180, region.span.longitudeDelta * 0.75)
        var lonMin = floor(region.center.longitude - lonHalf)
        var lonMax = ceil(region.center.longitude + lonHalf)
        if lonMax - lonMin >= 359 { lonMin = -180; lonMax = 179.5 }

        // 0.5° grid; keep the request to roughly 45 x 45 points.
        let span = max(latMax - latMin, lonMax - lonMin)
        let stride = max(1, Int(ceil(span / 0.5 / 45)))
        let key = "\(Int(latMin)),\(Int(latMax)),\(Int(lonMin)),\(Int(lonMax)),\(stride)"
        if let (date, field) = cache[key], Date().timeIntervalSince(date) < 3 * 3600 { return field }

        var field = await erddap(latMin: latMin, latMax: latMax, lonMin: lonMin, lonMax: lonMax, stride: stride)
        if field == nil {
            field = await openMeteo(latMin: latMin, latMax: latMax, lonMin: lonMin, lonMax: lonMax)
        }
        if let field {
            if cache.count > 12 { cache.removeAll() }
            cache[key] = (Date(), field)
        }
        return field
    }

    // MARK: ERDDAP (NOAA GFS 0.5°)

    private func erddap(latMin: Double, latMax: Double, lonMin: Double, lonMax: Double, stride: Int) async -> WindField? {
        // Nearest 3-hourly forecast step to now.
        let step = (Date().timeIntervalSince1970 / 10800).rounded() * 10800
        let iso = ISO8601DateFormatter()
        let time = iso.string(from: Date(timeIntervalSince1970: step))

        // Dataset longitudes run 0…359.5, so a box crossing 0° needs two requests.
        var boxes: [(Double, Double)] = []
        let a = lonMin < 0 ? lonMin + 360 : lonMin
        let b = lonMax < 0 ? lonMax + 360 : lonMax
        if a <= b { boxes = [(a, b)] } else { boxes = [(a, 359.5), (0, b)] }

        var rows: [(Double, Double, Float, Float)] = []
        for (l0, l1) in boxes {
            let sel = "[(\(time))][(\(latMin)):\(stride):(\(latMax))][(\(l0)):\(stride):(\(l1))]"
            let query = "ugrd10m\(sel),vgrd10m\(sel)"
            guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: ".-:,_"))) else { return nil }
            var payload: Data?
            for base in ["https://pae-paha.pacioos.hawaii.edu/erddap/griddap/ncep_global",
                         "https://coastwatch.pfeg.noaa.gov/erddap/griddap/NCEP_Global_Best"] {
                guard let url = URL(string: "\(base).json?\(encoded)") else { continue }
                var req = URLRequest(url: url)
                req.timeoutInterval = 20
                if let (d, resp) = try? await URLSession.shared.data(for: req),
                   (resp as? HTTPURLResponse)?.statusCode == 200 { payload = d; break }
            }
            guard let data = payload,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let table = root["table"] as? [String: Any],
                  let raw = table["rows"] as? [[Any]] else { return nil }
            for r in raw where r.count >= 5 {
                guard let la = (r[1] as? NSNumber)?.doubleValue, var lo = (r[2] as? NSNumber)?.doubleValue else { continue }
                var uu = (r[3] as? NSNumber)?.floatValue ?? 0
                var vv = (r[4] as? NSNumber)?.floatValue ?? 0
                if abs(uu) > 200 { uu = 0 }
                if abs(vv) > 200 { vv = 0 }
                // Unwrap so longitudes increase continuously from lonMin.
                if lo > 180 { lo -= 360 }
                if lo < lonMin { lo += 360 }
                rows.append((la, lo, uu, vv))
            }
        }
        return Self.grid(rows, validTime: Date(timeIntervalSince1970: step))
    }

    static func grid(_ rows: [(Double, Double, Float, Float)], validTime: Date?) -> WindField? {
        let lats = Array(Set(rows.map(\.0))).sorted()
        let lons = Array(Set(rows.map(\.1))).sorted()
        guard lats.count > 1, lons.count > 1 else { return nil }
        let latIndex = Dictionary(uniqueKeysWithValues: lats.enumerated().map { ($1, $0) })
        let lonIndex = Dictionary(uniqueKeysWithValues: lons.enumerated().map { ($1, $0) })
        var u = [Float](repeating: 0, count: lats.count * lons.count)
        var v = u
        for r in rows {
            guard let i = latIndex[r.0], let j = lonIndex[r.1] else { continue }
            u[i * lons.count + j] = r.2
            v[i * lons.count + j] = r.3
        }
        return WindField(lats: lats, lons: lons, u: u, v: v, validTime: validTime)
    }

    // MARK: Open-Meteo fallback (10 x 10 points)

    private func openMeteo(latMin: Double, latMax: Double, lonMin: Double, lonMax: Double) async -> WindField? {
        let n = 10
        var lats: [Double] = [], lons: [Double] = []
        for i in 0..<n {
            for j in 0..<n {
                lats.append(latMin + (latMax - latMin) * Double(i) / Double(n - 1))
                var lo = lonMin + (lonMax - lonMin) * Double(j) / Double(n - 1)
                if lo > 180 { lo -= 360 }
                lons.append(lo)
            }
        }
        let fmt: (Double) -> String = { String(format: "%.2f", $0) }
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: lats.map(fmt).joined(separator: ",")),
            .init(name: "longitude", value: lons.map(fmt).joined(separator: ",")),
            .init(name: "current", value: "wind_speed_10m,wind_direction_10m"),
            .init(name: "wind_speed_unit", value: "ms")
        ]
        guard let url = c.url, let (data, _) = try? await URLSession.shared.data(from: url),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], arr.count == n * n else { return nil }
        var rows: [(Double, Double, Float, Float)] = []
        for (k, item) in arr.enumerated() {
            guard let cur = item["current"] as? [String: Any],
                  let s = (cur["wind_speed_10m"] as? NSNumber)?.doubleValue,
                  let d = (cur["wind_direction_10m"] as? NSNumber)?.doubleValue else { continue }
            // Direction is where the wind comes FROM.
            let rad = d * .pi / 180
            let i = k / n, j = k % n
            let la = latMin + (latMax - latMin) * Double(i) / Double(n - 1)
            let lo = lonMin + (lonMax - lonMin) * Double(j) / Double(n - 1)
            rows.append((la, lo, Float(-s * sin(rad)), Float(-s * cos(rad))))
        }
        return Self.grid(rows, validTime: Date())
    }
}
