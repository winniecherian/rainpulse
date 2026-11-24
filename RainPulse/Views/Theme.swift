import SwiftUI

/// RainPulse design language: a living sky behind everything, frosted glass cards,
/// rounded type, and one signature element: the Rain Clock.
enum Theme {
    /// Sky gradient that follows the weather and the time of day at the place.
    static func sky(code: Int, isNight: Bool) -> [Color] {
        let rainy: Set<Int> = [51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82]
        let stormy: Set<Int> = [95, 96, 99]
        if stormy.contains(code) {
            return [Color(red: 0.12, green: 0.10, blue: 0.22), Color(red: 0.28, green: 0.20, blue: 0.40), Color(red: 0.10, green: 0.12, blue: 0.20)]
        }
        if rainy.contains(code) {
            return isNight
                ? [Color(red: 0.05, green: 0.10, blue: 0.20), Color(red: 0.10, green: 0.22, blue: 0.35)]
                : [Color(red: 0.25, green: 0.38, blue: 0.55), Color(red: 0.45, green: 0.58, blue: 0.70)]
        }
        if code >= 2 && code <= 48 {
            return isNight
                ? [Color(red: 0.08, green: 0.10, blue: 0.18), Color(red: 0.20, green: 0.24, blue: 0.34)]
                : [Color(red: 0.42, green: 0.56, blue: 0.75), Color(red: 0.70, green: 0.78, blue: 0.88)]
        }
        return isNight
            ? [Color(red: 0.03, green: 0.05, blue: 0.16), Color(red: 0.13, green: 0.16, blue: 0.38)]
            : [Color(red: 0.15, green: 0.50, blue: 0.95), Color(red: 0.50, green: 0.78, blue: 1.0)]
    }

    static func isNight(at date: Date = Date(), in tz: TimeZone) -> Bool {
        var cal = Calendar.current
        cal.timeZone = tz
        let h = cal.component(.hour, from: date)
        return h < 6 || h >= 19
    }
}

/// Animated sky background with slowly drifting light.
struct SkyBackground: View {
    let colors: [Color]
    @State private var drift = false

    var body: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [.white.opacity(0.22), .clear], center: drift ? .topTrailing : .topLeading,
                           startRadius: 10, endRadius: 420)
                .blendMode(.softLight)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

/// Frosted glass card used across the app.
struct GlassCard: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.05)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }
}

extension View {
    func glassCard(padding: CGFloat = 16) -> some View { modifier(GlassCard(padding: padding)) }
}

/// The Rain Clock: the next two hours as a dial. Twelve o'clock is now; the ring fills
/// clockwise with rain intensity, minute by minute. One glance answers
/// "when does it rain, and how hard?"
struct RainClock: View {
    let steps: [Forecast.Step]      // 15-minute steps, next 2 hours
    let headline: String
    let detail: String
    var size: CGFloat = 220
    var locked = false

    @State private var reveal: CGFloat = 0

    private var samples: [Double] {
        // 120 one-minute samples interpolated from the 15-minute steps (mm per 15 min → mm/h).
        let v = steps.prefix(9).map { $0.precipitation * 4 }
        guard v.count > 1 else { return Array(repeating: 0, count: 120) }
        return (0..<120).map { m in
            let f = Double(m) / 15
            let i = min(Int(f), v.count - 2)
            let t = f - Double(i)
            return v[i] + (v[i + 1] - v[i]) * t
        }
    }

    private static func color(_ mmh: Double) -> Color {
        switch mmh {
        case ..<0.1: return .white.opacity(0.12)
        case ..<1: return Color(red: 0.4, green: 0.85, blue: 1)
        case ..<2.5: return Color(red: 0.2, green: 0.55, blue: 1)
        case ..<7.6: return Color(red: 0.2, green: 0.8, blue: 0.45)
        case ..<16: return Color(red: 1, green: 0.85, blue: 0.2)
        case ..<50: return Color(red: 1, green: 0.45, blue: 0.2)
        default: return Color(red: 0.75, green: 0.2, blue: 0.9)
        }
    }

    var body: some View {
        let data = samples
        ZStack {
            // Minute ticks: length and colour follow rain intensity.
            ForEach(0..<120, id: \.self) { m in
                let mmh = data[m]
                let len = 10 + min(28, CGFloat(log10(max(mmh, 0.1) / 0.1) * 12))
                Capsule()
                    .fill(Self.color(mmh))
                    .frame(width: m % 15 == 0 ? 3 : 2, height: mmh < 0.1 ? 8 : len)
                    .offset(y: -(size / 2 - 22))
                    .rotationEffect(.degrees(Double(m) * 3))
                    .opacity(CGFloat(m) / 120 <= reveal ? 1 : 0)
            }
            // Quarter labels, placed around the inner edge of the ring.
            ForEach([0, 30, 60, 90], id: \.self) { m in
                let a = Double(m) * 3 * .pi / 180
                let r = size / 2 - 52
                Text(m == 0 ? String(localized: "Now") : "\(m)′")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .offset(x: sin(a) * r, y: -cos(a) * r)
            }
            VStack(spacing: 4) {
                Image(systemName: data.contains { $0 >= 0.1 } ? "cloud.rain.fill" : "sun.max.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: size * 0.12))
                Text(headline)
                    .font(.system(size: size * 0.08, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: size * 0.055, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(3)
            }
            .frame(width: size * 0.48)
            .blur(radius: locked ? 6 : 0)
            if locked {
                Label("Essential", systemImage: "lock.fill")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(headline). \(detail)")
        .onAppear { withAnimation(.easeOut(duration: 1.1)) { reveal = 1 } }
    }
}

/// Tactile feedback helpers.
enum Haptics {
    static func tick() { UISelectionFeedbackGenerator().selectionChanged() }
    static func tap() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
}
