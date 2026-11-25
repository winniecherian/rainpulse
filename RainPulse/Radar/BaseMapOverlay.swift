import MapKit
import UIKit

/// Extra map styles built from NASA GIBS imagery (free, public domain, no key needed).
/// Style numbers continue the existing ones (0–4 are Apple Maps styles).
enum NASAStyle: Int, CaseIterable {
    case earth = 5        // Blue Marble imagery with Apple's labels on top
    case liveClouds = 6   // Blue Marble + live infrared clouds (10-minute updates)
    case cityLights = 7   // Black Marble night lights — dark and minimal

    static func from(_ style: Int) -> NASAStyle? { NASAStyle(rawValue: style) }

    var attribution: String {
        switch self {
        case .earth: return "Imagery © NASA Blue Marble"
        case .liveClouds: return "Clouds © NASA GIBS, JMA/NOAA"
        case .cityLights: return "Imagery © NASA Black Marble"
        }
    }

    /// Overlays to put under the radar, bottom first.
    func overlays(now: Date = Date()) -> [BaseTileOverlay] {
        switch self {
        case .earth:
            return [BaseTileOverlay(kind: .blueMarble(dim: 1.0))]
        case .liveClouds:
            return [BaseTileOverlay(kind: .blueMarble(dim: 0.72)), BaseTileOverlay(kind: .clouds(time: Self.cloudTime(now)))]
        case .cityLights:
            return [BaseTileOverlay(kind: .blackMarble)]
        }
    }

    /// Satellite time to request: 30 minutes back (processing delay), on a 10-minute step.
    static func cloudTime(_ now: Date) -> String {
        let t = floor((now.timeIntervalSince1970 - 1800) / 600) * 600
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date(timeIntervalSince1970: t))
    }
}

/// A NASA GIBS base layer. Tiles above the layer's native zoom are upscaled, so the map
/// never goes blank when zooming in.
final class BaseTileOverlay: MKTileOverlay {
    enum Kind: Equatable {
        case blueMarble(dim: Double)
        case blackMarble
        case clouds(time: String)
    }

    let kind: Kind
    static let gibs = "https://gibs.earthdata.nasa.gov/wmts/epsg3857/best"
    /// Geostationary satellites stitched together for global live clouds.
    static let cloudLayers = ["GOES-West_ABI_Band13_Clean_Infrared", "GOES-East_ABI_Band13_Clean_Infrared",
                              "Himawari_AHI_Band13_Clean_Infrared"]

    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 24 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()

    init(kind: Kind) {
        self.kind = kind
        super.init(urlTemplate: nil)
        tileSize = CGSize(width: 256, height: 256)
        minimumZ = 1
        maximumZ = 19
        canReplaceMapContent = false
    }

    var nativeMaxZoom: Int {
        switch kind {
        case .blueMarble: return 8
        case .blackMarble: return 8
        case .clouds: return 6
        }
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let native = nativeMaxZoom
        guard path.z > native else {
            tile(z: path.z, x: path.x, y: path.y) { result($0, nil) }
            return
        }
        let scale = 1 << (path.z - native)
        let outputSide = 256 * max(1, path.contentScaleFactor)
        tile(z: native, x: path.x / scale, y: path.y / scale) { data in
            guard let data, let cg = UIImage(data: data)?.cgImage else { result(nil, nil); return }
            let side = CGFloat(cg.width) / CGFloat(scale)
            let crop = CGRect(x: CGFloat(path.x % scale) * side, y: CGFloat(path.y % scale) * side,
                              width: side, height: side).integral
            guard let cropped = cg.cropping(to: crop) else { result(nil, nil); return }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            let png = UIGraphicsImageRenderer(size: CGSize(width: outputSide, height: outputSide), format: format).pngData { ctx in
                ctx.cgContext.interpolationQuality = .high
                UIImage(cgImage: cropped).draw(in: CGRect(x: 0, y: 0, width: outputSide, height: outputSide))
            }
            result(png, nil)
        }
    }

    private func tile(z: Int, x: Int, y: Int, completion: @escaping (Data?) -> Void) {
        switch kind {
        case .blueMarble(let dim):
            let url = URL(string: "\(Self.gibs)/BlueMarble_ShadedRelief_Bathymetry/default/GoogleMapsCompatible_Level8/\(z)/\(y)/\(x).jpeg")!
            Self.get(url) { data in
                guard let data, dim < 1 else { completion(data); return }
                completion(TileImage.dim(data, factor: dim) ?? data)
            }
        case .blackMarble:
            let url = URL(string: "\(Self.gibs)/VIIRS_Black_Marble/default/2016-01-01/GoogleMapsCompatible_Level8/\(z)/\(y)/\(x).png")!
            Self.get(url, completion: completion)
        case .clouds(let time):
            let group = DispatchGroup()
            var parts = [Data?](repeating: nil, count: Self.cloudLayers.count)
            let lock = NSLock()
            for (i, layer) in Self.cloudLayers.enumerated() {
                let url = URL(string: "\(Self.gibs)/\(layer)/default/\(time)/GoogleMapsCompatible_Level6/\(z)/\(y)/\(x).png")!
                group.enter()
                Self.get(url) { data in
                    lock.lock(); parts[i] = data; lock.unlock()
                    group.leave()
                }
            }
            group.notify(queue: .global(qos: .userInitiated)) {
                completion(TileImage.clouds(parts.compactMap { $0 }))
            }
        }
    }

    private static func get(_ url: URL, completion: @escaping (Data?) -> Void) {
        session.dataTask(with: url) { data, response, _ in
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let data, !data.isEmpty else { completion(nil); return }
            completion(data)
        }.resume()
    }
}

/// Pixel work for base tiles.
enum TileImage {
    private static let space = CGColorSpaceCreateDeviceRGB()
    private static let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    private static func pixels(_ data: Data, size: Int = 256) -> [UInt32]? {
        guard let cg = UIImage(data: data)?.cgImage else { return nil }
        var px = [UInt32](repeating: 0, count: size * size)
        let ok: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: size * 4, space: space, bitmapInfo: info) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        return ok ? px : nil
    }

    private static func png(_ px: inout [UInt32], size: Int = 256) -> Data? {
        let image: CGImage? = px.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: size, height: size, bitsPerComponent: 8,
                      bytesPerRow: size * 4, space: space, bitmapInfo: info)?.makeImage()
        }
        return image.flatMap { UIImage(cgImage: $0).pngData() }
    }

    /// Darkens a tile so white clouds and radar colours stand out.
    static func dim(_ data: Data, factor: Double) -> Data? {
        guard var px = pixels(data) else { return nil }
        let k = UInt32(max(0, min(1, factor)) * 256)
        for i in px.indices {
            let p = px[i]
            let r = ((p & 0xFF) * k) >> 8, g = (((p >> 8) & 0xFF) * k) >> 8, b = (((p >> 16) & 0xFF) * k) >> 8
            px[i] = r | (g << 8) | (b << 16) | (p & 0xFF00_0000)
        }
        return png(&px)
    }

    /// Infrared satellite tiles → white clouds on a transparent background.
    /// Grey = cloud-top temperature (brighter is colder, i.e. higher cloud); NASA colours the
    /// coldest tops (thunderstorms), and those colours are kept so storms stand out.
    static func clouds(_ tiles: [Data]) -> Data? {
        var out = [UInt32](repeating: 0, count: 256 * 256)
        for data in tiles {
            guard let px = pixels(data) else { continue }
            for i in px.indices {
                let p = px[i]
                let a = (p >> 24) & 0xFF
                guard a > 0 else { continue }
                let r = Int(p & 0xFF), g = Int((p >> 8) & 0xFF), b = Int((p >> 16) & 0xFF)
                if let v = cloudPixel(r: r, g: g, b: b) { out[i] = v }
            }
        }
        return png(&out)
    }

    /// One infrared pixel → premultiplied RGBA (R,G,B,A byte order), or nil for clear sky.
    static func cloudPixel(r: Int, g: Int, b: Int) -> UInt32? {
        if max(r, g, b) - min(r, g, b) > 40 {
            let a = 235
            return UInt32(r * a / 255) | UInt32(g * a / 255) << 8 | UInt32(b * a / 255) << 16 | UInt32(a) << 24
        }
        let v = Double(r + g + b) / 3
        let t = max(0, min(1, (v - 135) / 45))
        guard t > 0.02 else { return nil }
        let a = UInt32(pow(t, 0.8) * 235)
        return a | a << 8 | a << 16 | a << 24      // premultiplied white
    }
}
