import MapKit
import UIKit

/// One animation frame of the radar. Tiles are cached on disk, and zoom levels
/// above the provider's maximum are filled by upscaling the parent tile, so the
/// overlay never disappears when the user zooms into street level.
final class RadarTileOverlay: MKTileOverlay {
    let provider: RadarProvider
    let layer: MapLayer
    let frame: RadarFrame?
    var onAuthFailure: (() -> Void)?

    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 32 * 1024 * 1024,
                                   diskCapacity: 256 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()

    init(provider: RadarProvider, layer: MapLayer, frame: RadarFrame?) {
        self.provider = provider
        self.layer = layer
        self.frame = frame
        super.init(urlTemplate: nil)
        canReplaceMapContent = false
        tileSize = CGSize(width: 256, height: 256)
        minimumZ = 1
        maximumZ = 19
    }

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let native = provider.source.nativeMaxZoom
        guard path.z > native else {
            fetch(z: path.z, x: path.x, y: path.y) { result($0, nil) }
            return
        }

        // Overzoom: crop and upscale the matching part of the parent tile.
        let dz = path.z - native
        let scale = 1 << dz
        let parentX = path.x / scale
        let parentY = path.y / scale
        let offsetX = path.x % scale
        let offsetY = path.y % scale
        let outputSide = 256 * max(1, path.contentScaleFactor)

        fetch(z: native, x: parentX, y: parentY) { data in
            guard let data, let image = UIImage(data: data), let cg = image.cgImage else {
                result(nil, nil)
                return
            }
            let side = CGFloat(cg.width) / CGFloat(scale)
            let crop = CGRect(x: CGFloat(offsetX) * side, y: CGFloat(offsetY) * side,
                              width: side, height: side).integral
            guard let cropped = cg.cropping(to: crop) else { result(nil, nil); return }

            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSide, height: outputSide), format: format)
            let png = renderer.pngData { ctx in
                ctx.cgContext.interpolationQuality = .medium
                UIImage(cgImage: cropped).draw(in: CGRect(x: 0, y: 0, width: outputSide, height: outputSide))
            }
            result(png, nil)
        }
    }

    private func fetch(z: Int, x: Int, y: Int, completion: @escaping (Data?) -> Void) {
        guard let url = provider.tileURL(layer: layer, frame: frame, z: z, x: x, y: y) else {
            completion(nil)
            return
        }
        let task = Self.session.dataTask(with: url) { [weak self] data, response, _ in
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 401 || http.statusCode == 403 {
                    self?.onAuthFailure?()
                    completion(nil)
                    return
                }
                guard (200..<300).contains(http.statusCode) else { completion(nil); return }
            }
            guard let data else { completion(nil); return }
            // OpenWeather 1.0 rain tiles are nearly transparent; make them readable.
            if self?.layer == .radar, url.host == "tile.openweathermap.org" {
                completion(RadarRecolor.recolor(data) ?? data)
            } else {
                completion(data)
            }
        }
        task.resume()
    }
}
