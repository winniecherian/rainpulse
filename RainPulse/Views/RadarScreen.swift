import SwiftUI
import MapKit

/// Playback ranges a user can pick, gated by plan.
enum PastRange: Int, CaseIterable, Identifiable {
    case m30 = 1800, h1 = 3600, h2 = 7200, h6 = 21600, h24 = 86400, h48 = 172800
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .m30: return "30m"
        case .h1: return "1h"
        case .h2: return "2h"
        case .h6: return "6h"
        case .h24: return "24h"
        case .h48: return "48h"
        }
    }
    func allowed(for tier: Tier) -> Bool { TimeInterval(rawValue) <= tier.radarPast }
}

struct RadarScreen: View {
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var places: PlacesModel
    @EnvironmentObject private var location: LocationManager

    @AppStorage("radar.source") private var sourceRaw = RadarSource.owmGlobalPrecip.rawValue
    @AppStorage("radar.opacity") private var opacity = 0.75
    @AppStorage("radar.speed") private var speed = 1.0
    @AppStorage("radar.past") private var pastRaw = PastRange.m30.rawValue
    @AppStorage("radar.showFuture") private var showFuture = true
    @AppStorage("map.style") private var mapStyle = 0
    @AppStorage("map.windFlow") private var windFlow = false
    @AppStorage("map.cyclones") private var showCyclones = true
    @State private var cyclones: [Cyclone] = []
    @State private var focus: CLLocationCoordinate2D?
    @State private var focusToken = 0

    @State private var layer: MapLayer = .radar
    @State private var frames: [RadarFrame] = []
    @State private var index = 0
    @State private var isPlaying = false
    @State private var tick = 0
    @State private var showPaywall = false
    @State private var showLegend = false
    @State private var fellBackToCurrent = false
    @State private var recenterToken = 0
    @State private var controlsExpanded = true

    private let playTimer = Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()
    private let refreshTimer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

    private var source: RadarSource {
        let chosen = RadarSource(rawValue: sourceRaw) ?? .owmGlobalPrecip
        return (fellBackToCurrent && chosen == .owmGlobalPrecip) ? .owmCurrent : chosen
    }
    private var provider: RadarProvider { RadarProvider(source: source) }

    private var pastRange: PastRange {
        let chosen = PastRange(rawValue: pastRaw) ?? .m30
        return chosen.allowed(for: store.tier) ? chosen : .m30
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            RadarMapView(provider: provider,
                         layer: layer,
                         frames: frames,
                         currentIndex: index,
                         opacity: opacity,
                         center: location.location?.coordinate,
                         places: places.places,
                         recenterToken: recenterToken,
                         onAuthFailure: { if source == .owmGlobalPrecip { fellBackToCurrent = true } },
                         mapStyle: mapStyle,
                         showWindFlow: windFlow && store.tier.hasExtraLayers,
                         cyclones: showCyclones ? cyclones : [],
                         focus: focus,
                         focusToken: focusToken)
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                topBar
                Spacer()
                if showCyclones, let storm = nearestStorm {
                    cycloneChip(storm).padding(.bottom, 8)
                }
                if store.tier == .free && layer == .radar {
                    upgradeChip.padding(.bottom, 8)
                }
                timeline
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showLegend) { LegendSheet().presentationDetents([.height(320)]) }
        .onAppear(perform: rebuildFrames)
        .onChange(of: store.tier) { _, _ in rebuildFrames() }
        .onChange(of: sourceRaw) { _, _ in fellBackToCurrent = false; rebuildFrames() }
        .onChange(of: fellBackToCurrent) { _, _ in rebuildFrames() }
        .onChange(of: layer) { _, _ in rebuildFrames() }
        .onChange(of: pastRaw) { _, _ in rebuildFrames() }
        .onChange(of: showFuture) { _, _ in rebuildFrames() }
        .onReceive(playTimer) { _ in
            guard isPlaying, frames.count > 1 else { return }
            tick += 1
            let every = speed >= 2 ? 1 : (speed >= 1 ? 2 : 4)
            if tick % every == 0 { index = (index + 1) % frames.count }
        }
        .onReceive(refreshTimer) { _ in rebuildFrames(); Task { await loadCyclones() } }
        .task { await loadCyclones() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .top) {
            Button { showLegend = true } label: {
                LinearGradient(colors: [.cyan, .blue, .green, .yellow, .orange, .red, .purple],
                               startPoint: .top, endPoint: .bottom)
                    .frame(width: 10, height: 30)
                    .clipShape(Capsule())
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel("Radar legend")

            if AppConfig.owmAPIKey.isEmpty && source != .tomorrow {
                Label("Radar key missing", systemImage: "key.fill")
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            Spacer()
            VStack(spacing: 8) {
                ShareLink(item: shareText) {
                    mapButton(systemImage: "square.and.arrow.up")
                }
                Menu {
                    ForEach(MapLayer.allCases) { item in
                        Button {
                            if item != .radar && !store.tier.hasExtraLayers { showPaywall = true } else { layer = item }
                        } label: {
                            Label(item.displayName + (item != .radar && !store.tier.hasExtraLayers ? " (Pro)" : ""),
                                  systemImage: item.symbol)
                        }
                    }
                    Divider()
                    Button {
                        if store.tier.hasExtraLayers { windFlow.toggle() } else { showPaywall = true }
                    } label: {
                        Label(String(localized: "Wind flow") + (store.tier.hasExtraLayers ? "" : " (Pro)"),
                              systemImage: windFlow && store.tier.hasExtraLayers ? "checkmark" : "wind.circle")
                    }
                    Button { showCyclones.toggle() } label: {
                        Label("Cyclones", systemImage: showCyclones ? "checkmark" : "hurricane")
                    }
                } label: {
                    mapButton(systemImage: "square.3.layers.3d")
                }
                .accessibilityLabel("Map layers")
                Button {
                    location.request()
                    recenterToken += 1
                } label: {
                    mapButton(systemImage: "location.fill")
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// Closest active storm within 2,000 km of the user (or the first saved place).
    private var nearestStorm: Cyclone? {
        guard let here = location.location?.coordinate ?? places.places.first?.coordinate else { return cyclones.first }
        return cyclones.map { ($0, $0.distanceKm(to: here)) }
            .filter { $0.1 < 2000 }
            .min { $0.1 < $1.1 }?.0
    }

    private func cycloneChip(_ storm: Cyclone) -> some View {
        Button {
            focus = storm.position.cl
            focusToken += 1
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "hurricane")
                if let here = location.location?.coordinate {
                    Text("\(storm.name) · \(Int(storm.maxWindKmh.rounded())) km/h · \(Int(storm.distanceKm(to: here).rounded())) km away")
                } else {
                    Text("\(storm.name) · \(Int(storm.maxWindKmh.rounded())) km/h")
                }
            }
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(storm.alertLevel == "Red" ? Color.red : (storm.alertLevel == "Orange" ? Color.orange : Color.teal), in: Capsule())
            .foregroundStyle(.white)
        }
        .accessibilityLabel("Cyclone \(storm.name)")
    }

    private func loadCyclones() async {
        cyclones = await CycloneService.shared.activeCyclones(sampleNear: location.location?.coordinate ?? places.places.first?.coordinate)
    }

    private var attributionText: String {
        var parts = [provider.source.attribution]
        if windFlow && store.tier.hasExtraLayers { parts.append("Wind © NOAA GFS") }
        if showCyclones && !cyclones.isEmpty { parts.append("Cyclones © GDACS") }
        return parts.joined(separator: " · ")
    }

    private var shareText: String {
        let place = location.placeName ?? String(localized: "my area")
        return String(localized: "Live rain radar for \(place) — RainPulse: Live Rain Radar")
    }

    private func mapButton(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 44, height: 44)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var upgradeChip: some View {
        Button { showPaywall = true } label: {
            Label("Unlock 2-hour rain forecast animation", systemImage: "sparkles")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.accentColor, in: Capsule())
                .foregroundStyle(.white)
        }
    }

    // MARK: - Timeline & playback controls

    private var timeline: some View {
        VStack(spacing: 10) {
            if controlsExpanded && frames.count > 1 {
                HStack(spacing: 8) {
                    controlChip(systemImage: "gauge.with.dots.needle.33percent",
                                text: speed == 0.5 ? "0.5x" : (speed >= 2 ? "2x" : "1x")) {
                        speed = speed == 0.5 ? 1 : (speed == 1 ? 2 : 0.5)
                    }
                    Menu {
                        ForEach(PastRange.allCases) { range in
                            Button {
                                if range.allowed(for: store.tier) { pastRaw = range.rawValue } else { showPaywall = true }
                            } label: {
                                Text(range.label + (range.allowed(for: store.tier) ? "" : " 🔒"))
                            }
                        }
                    } label: {
                        chipLabel(systemImage: "clock.arrow.circlepath", text: pastRange.label)
                    }
                    controlChip(systemImage: "clock.badge.checkmark",
                                text: showFuture ? "+" + futureLabel : "Off") {
                        showFuture.toggle()
                    }
                }
            }

            HStack {
                Button { isPlaying.toggle() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .disabled(frames.count < 2)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(frameLabel).font(.headline.monospacedDigit())
                        if isAtNow {
                            Text("LIVE")
                                .font(.caption2.bold())
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.red, in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(.white)
                        }
                    }
                    Text(frameSubLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { withAnimation { controlsExpanded.toggle() } } label: {
                    Image(systemName: controlsExpanded ? "chevron.down" : "chevron.up")
                        .frame(width: 32, height: 32)
                }
                .opacity(frames.count > 1 ? 1 : 0)
            }

            if frames.count > 1 {
                Slider(value: Binding(get: { Double(index) },
                                      set: { index = Int($0.rounded()); isPlaying = false }),
                       in: 0...Double(frames.count - 1), step: 1)
                HStack {
                    Text("−" + pastRange.label).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    if showFuture {
                        Text("+" + futureLabel).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Image(systemName: freshnessIsStale ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(freshnessIsStale ? .orange : .green)
                    .font(.caption2)
                Text(freshnessText).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(attributionText).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func chipLabel(systemImage: String, text: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.08), in: Capsule())
    }

    private func controlChip(systemImage: String, text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(systemImage: systemImage, text: text) }
            .buttonStyle(.plain)
    }

    private var futureLabel: String {
        let mins = Int(store.tier.radarFuture / 60)
        return mins >= 60 ? "\(mins / 60)h" : "\(mins)m"
    }

    private var currentFrame: RadarFrame? { frames.indices.contains(index) ? frames[index] : nil }
    private var isAtNow: Bool { frames.count <= 1 || index == RadarProvider.nowIndex(in: frames) }

    private var frameLabel: String {
        guard let frame = currentFrame, frames.count > 1 else { return String(localized: "Live") }
        return Fmt.time(frame.date)
    }

    private var frameSubLabel: String {
        guard let frame = currentFrame, frames.count > 1 else {
            return fellBackToCurrent ? String(localized: "Current radar only") : layer.displayName
        }
        let mins = Int((frame.date.timeIntervalSince(frames[RadarProvider.nowIndex(in: frames)].date)) / 60)
        if mins == 0 { return String(localized: "Now") }
        let rel = mins > 0 ? "+\(Self.duration(mins))" : "−\(Self.duration(-mins))"
        return frame.isForecast ? String(localized: "Forecast \(rel)") : String(localized: "Past \(rel)")
    }

    /// How old the newest radar image is.
    private var radarAgeMinutes: Int {
        guard source.supportsTime, frames.count > 1 else { return 0 }
        let newest = frames[RadarProvider.nowIndex(in: frames)].date
        return max(0, Int(Date().timeIntervalSince(newest) / 60))
    }
    private var freshnessIsStale: Bool { radarAgeMinutes > 30 }
    private var freshnessText: String {
        if fellBackToCurrent { return String(localized: "Current radar · animation unavailable") }
        let age = radarAgeMinutes
        if age <= 1 { return String(localized: "Radar updated just now") }
        return freshnessIsStale ? String(localized: "Radar updated \(age) min ago · delayed")
                                : String(localized: "Radar updated \(age) min ago")
    }

    private static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : (minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min")
    }

    private func rebuildFrames() {
        let future = showFuture ? store.tier.radarFuture : 0
        let newFrames = provider.frames(past: TimeInterval(pastRange.rawValue), future: future, layer: layer)
        let wasPlaying = isPlaying
        frames = newFrames
        index = RadarProvider.nowIndex(in: newFrames)
        isPlaying = wasPlaying && newFrames.count > 1
    }
}

/// Rain intensity scale.
struct LegendSheet: View {
    private let rows: [(Color, String, String)] = [
        (.cyan, "Light", "< 2.5 mm/h"),
        (.blue, "Moderate", "2.5 – 7.6 mm/h"),
        (.green, "Heavy", "7.6 – 16 mm/h"),
        (.yellow, "Very heavy", "16 – 50 mm/h"),
        (.red, "Extreme", "> 50 mm/h"),
        (.purple, "Hail / storm core", "")
    ]

    var body: some View {
        NavigationStack {
            List(rows, id: \.1) { row in
                HStack {
                    RoundedRectangle(cornerRadius: 4).fill(row.0).frame(width: 28, height: 16)
                    Text(row.1)
                    Spacer()
                    Text(row.2).foregroundStyle(.secondary).font(.footnote)
                }
            }
            .navigationTitle("Rain intensity")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct RainLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Light").font(.caption2).foregroundStyle(.secondary)
            LinearGradient(colors: [.cyan.opacity(0.6), .blue, .green, .yellow, .orange, .red, .purple],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 90, height: 6)
                .clipShape(Capsule())
            Text("Heavy").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
