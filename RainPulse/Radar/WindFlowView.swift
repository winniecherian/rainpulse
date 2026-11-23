import UIKit
import MapKit

/// Windy-style animated wind streaks drawn over an MKMapView.
/// Particles live in screen space; each frame they move along the wind at their
/// map position, leaving fading trails. Paused and cleared while the map moves.
final class WindFlowView: UIView {
    weak var mapView: MKMapView?
    var field: WindField? { didSet { resetParticles() } }

    private struct Particle { var x: CGFloat; var y: CGFloat; var age: Int; var maxAge: Int }
    private var particles: [Particle] = []
    private var link: CADisplayLink?
    private var context: CGContext?
    private var pixelScale: CGFloat = 2
    private var paused = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
    required init?(coder: NSCoder) { fatalError() }

    var isRunning: Bool { link != nil }

    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(step))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
        l.add(to: .main, forMode: .common)
        link = l
        isHidden = false
    }

    func stop() {
        link?.invalidate()
        link = nil
        clear()
        isHidden = true
    }

    /// Call when the map starts moving / stops moving.
    func setPaused(_ value: Bool) {
        paused = value
        if value { clear() } else { resetParticles() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        context = nil
        resetParticles()
    }

    private var particleCount: Int {
        // Density scales with screen area (~1 particle per 300 pt²), capped for battery.
        min(1800, max(300, Int(bounds.width * bounds.height / 300)))
    }

    private func resetParticles() {
        guard bounds.width > 0 else { return }
        particles = (0..<particleCount).map { _ in randomParticle(staggered: true) }
        clear()
    }

    private func randomParticle(staggered: Bool) -> Particle {
        let maxAge = Int.random(in: 40...110)
        return Particle(x: .random(in: 0...bounds.width), y: .random(in: 0...bounds.height),
                        age: staggered ? Int.random(in: 0..<maxAge) : 0, maxAge: maxAge)
    }

    private func makeContext() -> CGContext? {
        pixelScale = window?.screen.scale ?? 2
        let w = Int(bounds.width * pixelScale), h = Int(bounds.height * pixelScale)
        guard w > 0, h > 0 else { return nil }
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.scaleBy(x: pixelScale, y: pixelScale)
        // UIKit-style coordinates (origin top-left).
        ctx?.translateBy(x: 0, y: bounds.height)
        ctx?.scaleBy(x: 1, y: -1)
        ctx?.setLineCap(.round)
        return ctx
    }

    private func clear() {
        context?.clear(CGRect(origin: .zero, size: bounds.size))
        layer.contents = nil
    }

    private static func color(forSpeed s: Double) -> CGColor {
        // calm: soft white → breezy: pale cyan → strong: yellow → gale: orange/red
        switch s {
        case ..<4: return UIColor(white: 1, alpha: 0.55).cgColor
        case ..<9: return UIColor(red: 0.8, green: 0.95, blue: 1, alpha: 0.8).cgColor
        case ..<15: return UIColor(red: 1, green: 0.95, blue: 0.55, alpha: 0.9).cgColor
        case ..<22: return UIColor(red: 1, green: 0.7, blue: 0.3, alpha: 0.95).cgColor
        default: return UIColor(red: 1, green: 0.35, blue: 0.35, alpha: 1).cgColor
        }
    }

    @objc private func step() {
        guard !paused, let field, let map = mapView, bounds.width > 0 else { return }
        if context == nil { context = makeContext() }
        guard let ctx = context else { return }

        // Fade the previous frame so streaks leave short trails.
        ctx.saveGState()
        ctx.setBlendMode(.destinationIn)
        ctx.setFillColor(UIColor(white: 0, alpha: 0.9).cgColor)
        ctx.fill(CGRect(origin: .zero, size: bounds.size))
        ctx.restoreGState()

        // Fast screen → coordinate conversion via the visible map rect (Web Mercator).
        let rect = map.visibleMapRect
        let w = bounds.width, h = bounds.height
        let pixelsPerSpeed: CGFloat = 0.28   // screen points per frame per m/s

        ctx.setLineWidth(1.4)
        for i in particles.indices {
            var p = particles[i]
            if p.age >= p.maxAge || p.x < 0 || p.y < 0 || p.x > w || p.y > h {
                particles[i] = randomParticle(staggered: false)
                continue
            }
            let mp = MKMapPoint(x: rect.minX + Double(p.x / w) * rect.width,
                                y: rect.minY + Double(p.y / h) * rect.height)
            let c = mp.coordinate
            guard let wind = field.vector(lat: c.latitude, lon: c.longitude) else {
                p.age = p.maxAge
                particles[i] = p
                continue
            }
            let speed = (wind.u * wind.u + wind.v * wind.v).squareRoot()
            let nx = p.x + CGFloat(wind.u) * pixelsPerSpeed
            let ny = p.y - CGFloat(wind.v) * pixelsPerSpeed
            // Thin dark outline keeps light streaks readable on light map styles.
            ctx.setStrokeColor(UIColor(white: 0, alpha: 0.28).cgColor)
            ctx.setLineWidth(2.6)
            ctx.move(to: CGPoint(x: p.x, y: p.y))
            ctx.addLine(to: CGPoint(x: nx, y: ny))
            ctx.strokePath()
            ctx.setStrokeColor(Self.color(forSpeed: speed))
            ctx.setLineWidth(1.4)
            ctx.move(to: CGPoint(x: p.x, y: p.y))
            ctx.addLine(to: CGPoint(x: nx, y: ny))
            ctx.strokePath()
            p.x = nx; p.y = ny; p.age += 1
            particles[i] = p
        }
        layer.contents = ctx.makeImage()
    }
}
