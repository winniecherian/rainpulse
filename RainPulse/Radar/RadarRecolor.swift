import CoreGraphics
import UIKit

/// OpenWeather's free precipitation tiles draw rain almost transparent (max ~43% opacity),
/// so it vanishes on the map. Their alpha channel tracks intensity, so we re-map it to a
/// bold RainViewer-style scale: cyan → blue → green → yellow → orange → red → purple.
enum RadarRecolor {
    static let low: Int = 12, high: Int = 110

    /// RGBA (premultiplied) lookup indexed by source alpha.
    static let lut: [UInt32] = {
        let stops: [(Double, (Double, Double, Double))] = [
            (0.0, (0, 200, 255)), (0.25, (0, 90, 255)), (0.45, (0, 200, 60)), (0.65, (255, 230, 0)),
            (0.8, (255, 140, 0)), (0.9, (230, 0, 0)), (1.0, (170, 0, 200))]
        return (0..<256).map { a -> UInt32 in
            guard a >= low else { return 0 }
            let t = min(1, Double(a - low) / Double(high - low))
            var rgb = stops.last!.1
            for i in 0..<(stops.count - 1) where t <= stops[i + 1].0 {
                let (t0, c0) = stops[i], (t1, c1) = stops[i + 1]
                let f = (t - t0) / (t1 - t0)
                rgb = (c0.0 + (c1.0 - c0.0) * f, c0.1 + (c1.1 - c0.1) * f, c0.2 + (c1.2 - c0.2) * f)
                break
            }
            let alpha = 150 + 100 * t
            let k = alpha / 255
            let r = UInt32(rgb.0 * k), g = UInt32(rgb.1 * k), b = UInt32(rgb.2 * k)
            // Byte order R, G, B, A in memory (little-endian UInt32).
            return r | (g << 8) | (b << 16) | (UInt32(alpha) << 24)
        }
    }()

    static func recolor(_ data: Data) -> Data? {
        guard let cg = UIImage(data: data)?.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var pixels = [UInt32](repeating: 0, count: w * h)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let ok: Bool = pixels.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: space, bitmapInfo: info) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        // byteOrder32Big + premultipliedLast => memory bytes R,G,B,A; alpha is the 4th byte.
        for i in 0..<pixels.count {
            let alpha = Int((pixels[i] >> 24) & 0xFF)
            pixels[i] = lut[alpha]
        }
        let out: CGImage? = pixels.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                      bytesPerRow: w * 4, space: space, bitmapInfo: info)?.makeImage()
        }
        guard let out else { return nil }
        return UIImage(cgImage: out).pngData()
    }
}
