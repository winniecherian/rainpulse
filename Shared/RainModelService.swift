import Foundation
import MapKit
import UIKit

/// Forecast rain frames from NOAA's GFS model (rainfall rate, 0.5°, public domain),
/// served by PacIOOS ERDDAP (University of Hawaiʻi). Used to animate future rain for
/// free when no paid animated-radar source is available.
struct RainModelFrames {
    let dates: [Date]
    let lats: [Double]          // ascending
    let lons: [Double]          // ascending (unwrapped)
    let values: [[Float]]       // per frame, row-major [lat][lon], mm/h

    var boundingMapRect: MKMapRect {
        let tl = MKMapPoint(CLLocationCoordinate2D(latitude: lats.last!, longitude: lons.first!))
        let br = MKMapPoint(CLLocationCoordinate2D(latitude: lats.first!, longitude: lons.last!))
        return MKMapRect(x: tl.x, y: tl.y, width: max(1, br.x - tl.x), height: max(1, br.y - tl.y))
    }

    /// Colour for a rain rate, matching the radar legend (cyan → purple).
    static func rgba(mmPerHour v: Float) -> (UInt8, UInt8, UInt8, UInt8) {
        guard v >= 0.1 else { return (0, 0, 0, 0) }
        // log scale: 0.1 mm/h → 0, 50 mm/h → 1
        let t = Double(min(1, max(0, log10(Double(v) / 0.1) / log10(500))))
        let stops: [(Double, (Double, Double, Double))] = [
            (0.0, (0, 200, 255)), (0.25, (0, 90, 255)), (0.45, (0, 200, 60)), (0.65, (255, 230, 0)),
            (0.8, (255, 140, 0)), (0.9, (230, 0, 0)), (1.0, (170, 0, 200))]
        var rgb = stops.last!.1
        for i in 0..<(stops.count - 1) where t <= stops[i + 1].0 {
            let (t0, c0) = stops[i], (t1, c1) = stops[i + 1]
            let f = (t - t0) / (t1 - t0)
            rgb = (c0.0 + (c1.0 - c0.0) * f, c0.1 + (c1.1 - c0.1) * f, c0.2 + (c1.2 - c0.2) * f)
            break
        }
        let a = 150 + 100 * t
        let k = a / 255
        return (UInt8(rgb.0 * k), UInt8(rgb.1 * k), UInt8(rgb.2 * k), UInt8(a))
    }

    /// Smooth image for one frame, laid out in Web-Mercator rows so it lines up with the map.
    func image(frame i: Int, scale: Int = 6) -> CGImage? {
        guard values.indices.contains(i), lats.count > 1, lons.count > 1 else { return nil }
        let grid = values[i]
        let w = (lons.count - 1) * scale + 1, h = (lats.count - 1) * scale + 1
        let rect = boundingMapRect
        let n = lons.count
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for row in 0..<h {
            // map-point y for this row → latitude
            let mp = MKMapPoint(x: rect.minX, y: rect.minY + rect.height * Double(row) / Double(h - 1))
            let lat = mp.coordinate.latitude
            let fi = (lat - lats[0]) / (lats[1] - lats[0])
            let i0 = max(0, min(lats.count - 2, Int(fi)))
            let ti = Float(max(0, min(1, fi - Double(i0))))
            for col in 0..<w {
                let fj = Double(col) / Double(scale)
                let j0 = min(n - 2, Int(fj))
                let tj = Float(fj - Double(j0))
                let a = grid[i0 * n + j0], b = grid[i0 * n + j0 + 1]
                let c = grid[(i0 + 1) * n + j0], d = grid[(i0 + 1) * n + j0 + 1]
                let top = a + (b - a) * tj, bottom = c + (d - c) * tj
                let v = top + (bottom - top) * ti
                let (r, g, bl, al) = Self.rgba(mmPerHour: v)
                let p = (row * w + col) * 4
                pixels[p] = r; pixels[p + 1] = g; pixels[p + 2] = bl; pixels[p + 3] = al
            }
        }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    static func sample(around c: CLLocationCoordinate2D, hours: Int) -> RainModelFrames {
        let lats = stride(from: c.latitude - 8, through: c.latitude + 8, by: 1.0).map { $0 }
        let lons = stride(from: c.longitude - 10, through: c.longitude + 10, by: 1.0).map { $0 }
        var values: [[Float]] = []
        var dates: [Date] = []
        let steps = max(2, hours / 3)
        for s in 1...steps {
            dates.append(Date().addingTimeInterval(Double(s) * 3 * 3600))
            var g: [Float] = []
            for la in lats {
                for lo in lons {
                    let dx = lo - (c.longitude - 6 + Double(s) * 1.5), dy = la - (c.latitude - 2)
                    g.append(Float(max(0, 12 * exp(-(dx * dx + dy * dy) / 6))))
                }
            }
            values.append(g)
        }
        return RainModelFrames(dates: dates, lats: lats, lons: lons, values: values)
    }
}

actor RainModelService {
    static let shared = RainModelService()
    private var cache: [String: (Date, RainModelFrames)] = [:]
    private let base = "https://pae-paha.pacioos.hawaii.edu/erddap/griddap/ncep_global"

    /// Frames from now to `hours` ahead (≈3-hour steps; hourly for short windows).
    func frames(for region: MKCoordinateRegion, hours: Int) async -> RainModelFrames? {
        guard hours > 0 else { return nil }
        if AppConfig.isUITest { return .sample(around: region.center, hours: hours) }

        let latMin = max(-85, floor(region.center.latitude - region.span.latitudeDelta * 0.7))
        let latMax = min(85, ceil(region.center.latitude + region.span.latitudeDelta * 0.7))
        let lonHalf = min(170, region.span.longitudeDelta * 0.7)
        let lonMin = floor(region.center.longitude - lonHalf)
        let lonMax = ceil(region.center.longitude + lonHalf)
        let span = max(latMax - latMin, lonMax - lonMin)
        let stride = max(1, Int(ceil(span / 0.5 / 28)))
        let key = "\(Int(latMin)),\(Int(latMax)),\(Int(lonMin)),\(Int(lonMax)),\(stride),\(hours)"
        if let (date, f) = cache[key], Date().timeIntervalSince(date) < 3600 { return f }

        let iso = ISO8601DateFormatter()
        let start = Date(timeIntervalSince1970: ceil(Date().timeIntervalSince1970 / 3600) * 3600)
        let end = start.addingTimeInterval(Double(hours) * 3600)
        let t0 = iso.string(from: start), t1 = iso.string(from: end)

        // 1) Find the dataset's time step with a one-point request.
        guard let probe = await rows(query: "pratesfc[(\(t0)):1:(\(t1))][(0)][(0)]"), probe.count > 1 else { return nil }
        let times = probe.compactMap { $0.first as? String }.compactMap(iso.date(from:))
        guard times.count > 1 else { return nil }
        let step = times[1].timeIntervalSince(times[0])
        let wanted: TimeInterval = hours <= 6 ? 3600 : 3 * 3600
        let tStride = max(1, Int((wanted / max(step, 1)).rounded()))

        // 2) The grid. Longitudes are 0…359.5 in this dataset.
        var boxes: [(Double, Double)] = []
        let a = lonMin < 0 ? lonMin + 360 : lonMin, b = lonMax < 0 ? lonMax + 360 : lonMax
        boxes = a <= b ? [(a, b)] : [(a, 359.5), (0, b)]
        var byTime: [String: [(Double, Double, Float)]] = [:]
        for (l0, l1) in boxes {
            let q = "pratesfc[(\(t0)):\(tStride):(\(t1))][(\(latMin)):\(stride):(\(latMax))][(\(l0)):\(stride):(\(l1))]"
            guard let rs = await rows(query: q) else { return nil }
            for r in rs where r.count >= 4 {
                guard let t = r[0] as? String,
                      let la = (r[1] as? NSNumber)?.doubleValue,
                      var lo = (r[2] as? NSNumber)?.doubleValue else { continue }
                var v = (r[3] as? NSNumber)?.floatValue ?? 0
                if v < 0 || v > 1 { v = 0 }      // fill values
                if lo > 180 { lo -= 360 }
                if lo < lonMin { lo += 360 }
                byTime[t, default: []].append((la, lo, v * 3600))   // kg m-2 s-1 → mm/h
            }
        }
        let keys = byTime.keys.sorted()
        guard let first = keys.first, let rows0 = byTime[first] else { return nil }
        let lats = Array(Set(rows0.map(\.0))).sorted()
        let lons = Array(Set(rows0.map(\.1))).sorted()
        guard lats.count > 1, lons.count > 1 else { return nil }
        let li = Dictionary(uniqueKeysWithValues: lats.enumerated().map { ($1, $0) })
        let lj = Dictionary(uniqueKeysWithValues: lons.enumerated().map { ($1, $0) })
        var values: [[Float]] = []
        var dates: [Date] = []
        for k in keys {
            guard let d = iso.date(from: k), d > Date() else { continue }
            var g = [Float](repeating: 0, count: lats.count * lons.count)
            for r in byTime[k] ?? [] {
                if let i = li[r.0], let j = lj[r.1] { g[i * lons.count + j] = r.2 }
            }
            values.append(g)
            dates.append(d)
        }
        guard !dates.isEmpty else { return nil }
        let result = RainModelFrames(dates: dates, lats: lats, lons: lons, values: values)
        if cache.count > 8 { cache.removeAll() }
        cache[key] = (Date(), result)
        return result
    }

    private func rows(query: String) async -> [[Any]]? {
        guard let enc = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: ".-:,_"))),
              let url = URL(string: "\(base).json?\(enc)") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let table = root["table"] as? [String: Any] else { return nil }
        return table["rows"] as? [[Any]]
    }
}
