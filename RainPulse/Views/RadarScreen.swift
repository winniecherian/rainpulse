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
    @AppStorage("map.style.v2") private var mapStyle = 3
    @AppStorage("map.windFlow") private var windFlow = false
    @AppStorage("map.cyclones") private var showCyclones = true
    @State private var cyclones: [Cyclone] = []
    @State private var focus: CLLocationCoordinate2D?
    @State private var focusToken = 0
    @State private var modelFrames: RainModelFrames?
    @State private var lastRegion: MKCoordinateRegion?
    @State private var modelTask: Task<Void, Never>?
    @State private var nowForecast: Forecast?
    @State private var reports: [CrowdReport] = []
    @State private var showReport = false
    @State private var reportsTask: Task<Void, Never>?

    @State private var layer: MapLayer = .radar
    @State private var frames: [RadarFrame] = []
    @State private var index = 0
    @State private var isPlaying = false
    @State private var tick = 0
    @State private var showPaywall = false
    @State private var showLegend = false
    @State private var fellBackToCurrent = Date().timeIntervalSince1970 - UserDefaults.standard.double(forKey: "radar.animatedRefusedAt") < 86400

    @State private var recenterToken = 0
    @State private var controlsExpanded = false

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
                         currentIndex: min(index, max(0, frames.count - 1)),
                         opacity: opacity,
                         center: location.location?.coordinate,
                         places: places.places,
                         recenterToken: recenterToken,
                         onAuthFailure: {
                             if source == .owmGlobalPrecip {
                                 fellBackToCurrent = true
                                 UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "radar.animatedRefusedAt")
                             }
                         },
                         mapStyle: mapStyle,
                         showWindFlow: windFlow && store.tier.hasExtraLayers,
                         cyclones: showCyclones ? cyclones : [],
                         focus: focus,
                         focusToken: focusToken,
                         modelFrames: modelFrames,
                         modelIndex: modelIndex,
                         onRegionChange: handleRegion,
                         reports: reports)
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                topBar
                Spacer()
                if AppConfig.crowdFeaturesVisible {
                    CrowdChip(summary: crowdSummary) { recenterToken += 1 }
                        .padding(.bottom, 8)
                }
                if showCyclones, let storm = nearestStorm {
                    cycloneChip(storm).padding(.bottom, 8)
                }
                if store.tier == .free && layer == .radar {
                    upgradeChip.padding(.bottom, 8)
                }
                timeline
            }
            // Controls float over the map, so cap their text size: at the largest accessibility
            // sizes they would otherwise overflow the screen and hide the top buttons.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showLegend) { LegendSheet().presentationDetents([.height(320)]) }
        .sheet(isPresented: $showReport) {
            ReportSheet(coordinate: location.location?.coordinate) { report in
                reports.append(report)
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear(perform: rebuildFrames)
        .onChange(of: store.tier) { _, _ in rebuildFrames() }
        .onChange(of: sourceRaw) { _, _ in
            fellBackToCurrent = false
            UserDefaults.standard.removeObject(forKey: "radar.animatedRefusedAt")
            rebuildFrames()
        }
        .onChange(of: fellBackToCurrent) { _, _ in rebuildFrames() }
        .onChange(of: layer) { _, _ in rebuildFrames(); reloadModel() }
        .onChange(of: pastRaw) { _, _ in rebuildFrames() }
        .onChange(of: showFuture) { _, _ in rebuildFrames(); reloadModel() }
        .onChange(of: store.tier) { _, _ in reloadModel() }
        .onReceive(playTimer) { _ in
            guard isPlaying, allFrames.count > 1 else { return }
            tick += 1
            let every = speed >= 2 ? 1 : (speed >= 1 ? 2 : 4)
            if tick % every == 0 { index = (index + 1) % allFrames.count }
        }
        .onReceive(refreshTimer) { _ in rebuildFrames(); Task { await loadCyclones() }; loadReports() }
        .task(id: location.location?.coordinate.latitude) { loadReports() }
        .task { await loadCyclones() }
        .task(id: location.location?.coordinate.latitude) { await loadNow() }
        .onChange(of: index) { _, _ in if !isPlaying { Haptics.tick() } }
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
            .accessibilityLabel("Rain map legend")

            Spacer(minLength: 8)
            if let f = nowForecast { nowPill(f) }
            if AppConfig.owmAPIKey.isEmpty && source != .tomorrow {
                Label("Rain map key missing", systemImage: "key.fill")
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            Spacer()
            VStack(spacing: 8) {
                if AppConfig.crowdFeaturesVisible {
                    Button { showReport = true } label: {
                        mapButton(systemImage: "hand.tap.fill")
                    }
                    .accessibilityLabel("Report weather")
                    .accessibilityIdentifier("radar.report")
                }
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

    /// Compact "right now" status floating over the map.
    private func nowPill(_ f: Forecast) -> some View {
        HStack(spacing: 8) {
            Image(systemName: WeatherCode.symbol(f.current.weatherCode))
                .symbolRenderingMode(.multicolor)
            Text(Fmt.temperature(f.current.temperature)).font(.subheadline.weight(.semibold).monospacedDigit())
            Text(f.rainHeadline()).font(.subheadline).lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }

    private func loadNow() async {
        guard let c = location.location?.coordinate ?? places.places.first?.coordinate else { return }
        nowForecast = try? await ForecastService.shared.forecast(latitude: c.latitude, longitude: c.longitude,
                                                                 days: store.tier.forecastDays)
    }

    private func loadCyclones() async {
        cyclones = await CycloneService.shared.activeCyclones(sampleNear: location.location?.coordinate ?? places.places.first?.coordinate)
    }

    private var attributionText: String {
        var parts = [provider.source.attribution]
        if let nasa = NASAStyle.from(mapStyle) { parts.append(nasa.attribution) }
        if !reports.isEmpty { parts.append(String(localized: "Reports by RainPulse users")) }
        if windFlow && store.tier.hasExtraLayers { parts.append("Wind © NOAA GFS") }
        if modelFrames != nil && layer == .radar { parts.append("Rain forecast © NOAA GFS") }
        if showCyclones && !cyclones.isEmpty { parts.append("Cyclones © GDACS") }
        return parts.joined(separator: " · ")
    }

    private var shareText: String {
        let place = location.placeName ?? String(localized: "my area")
        return String(localized: "Live rain map for \(place) — RainPulse: Rain Map & Alerts")
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
            if controlsExpanded && allFrames.count > 1 {
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
                Button { isPlaying.toggle(); Haptics.tap() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
                .accessibilityIdentifier("radar.play")
                .disabled(allFrames.count < 2)

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
                .opacity(allFrames.count > 1 ? 1 : 0)
            }

            if allFrames.count > 1 {
                Slider(value: Binding(get: { Double(index) },
                                      set: { index = Int($0.rounded()); isPlaying = false }),
                       in: 0...Double(allFrames.count - 1), step: 1)
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
        .glassCard(padding: 14)
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
        let mins = max(Int(store.tier.radarFuture / 60), modelFrames == nil ? 0 : modelHours * 60)
        return mins >= 60 ? "\(mins / 60)h" : "\(mins)m"
    }

    private var currentFrame: RadarFrame? { allFrames.indices.contains(index) ? allFrames[index] : nil }
    private var isAtNow: Bool { allFrames.count <= 1 || index == RadarProvider.nowIndex(in: allFrames) }

    private var frameLabel: String {
        guard let frame = currentFrame, allFrames.count > 1 else { return String(localized: "Live") }
        return Fmt.time(frame.date)
    }

    private var frameSubLabel: String {
        guard let frame = currentFrame, allFrames.count > 1 else {
            return fellBackToCurrent ? String(localized: "Current rain map only") : layer.displayName
        }
        let mins = Int((frame.date.timeIntervalSince(allFrames[RadarProvider.nowIndex(in: allFrames)].date)) / 60)
        if mins == 0 { return String(localized: "Now") }
        let rel = mins > 0 ? "+\(Self.duration(mins))" : "−\(Self.duration(-mins))"
        if index >= frames.count { return String(localized: "Rain forecast (model) \(rel)") }
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
        if modelFrames != nil && (fellBackToCurrent || frames.count <= 1) {
            return String(localized: "Rain map now · future rain from forecast model")
        }
        if fellBackToCurrent { return String(localized: "Current rain map · animation unavailable") }
        let age = radarAgeMinutes
        if age <= 1 { return String(localized: "Rain map updated just now") }
        return freshnessIsStale ? String(localized: "Rain map updated \(age) min ago · delayed")
                                : String(localized: "Rain map updated \(age) min ago")
    }

    private static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : (minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min")
    }

    /// GFS forecast window by plan (free gets a short taste so playback always works).
    private var modelHours: Int {
        guard layer == .radar, showFuture else { return 0 }
        switch store.tier {
        case .free: return 6
        case .essential: return 24
        case .pro: return 48
        }
    }

    /// Model frames that come after the last radar frame.
    private var modelStart: Int {
        guard let m = modelFrames else { return 0 }
        let last = frames.last?.date ?? Date()
        return m.dates.firstIndex(where: { $0 > last.addingTimeInterval(60) }) ?? m.dates.count
    }

    /// Radar frames followed by model forecast frames.
    private var allFrames: [RadarFrame] {
        guard let m = modelFrames, modelStart < m.dates.count else { return frames }
        return frames + m.dates[modelStart...].map { RadarFrame(date: $0, isForecast: true) }
    }

    private var modelIndex: Int? {
        guard modelFrames != nil, index >= frames.count else { return nil }
        return modelStart + (index - frames.count)
    }

    private func handleRegion(_ region: MKCoordinateRegion) {
        lastRegion = region
        reloadModel(delay: 0.6)
        loadReports(delay: 0.8)
    }

    /// Reports near the map centre when zoomed in to city level, otherwise near the user.
    private var reportCenter: CLLocationCoordinate2D? {
        if let r = lastRegion, r.span.latitudeDelta < 1.5 { return r.center }
        return location.location?.coordinate ?? places.places.first?.coordinate
    }

    private var crowdSummary: CrowdSummary {
        guard let here = location.location?.coordinate ?? places.places.first?.coordinate else { return CrowdSummary() }
        return CrowdLogic.summary(reports, near: here, now: Date())
    }

    private func loadReports(delay: Double = 0) {
        reportsTask?.cancel()
        guard let c = reportCenter else { return }
        reportsTask = Task {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            let found = await CrowdReportService.shared.reports(near: c)
            guard !Task.isCancelled else { return }
            await MainActor.run { reports = found }
        }
    }

    private func reloadModel(delay: Double = 0) {
        modelTask?.cancel()
        let hours = modelHours
        guard hours > 0, let region = lastRegion ?? location.location.map({
            MKCoordinateRegion(center: $0.coordinate, span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 6))
        }) else {
            modelFrames = nil
            if index >= frames.count { index = RadarProvider.nowIndex(in: frames) }
            return
        }
        modelTask = Task {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            let result = await RainModelService.shared.frames(for: region, hours: hours)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if result != nil || modelFrames == nil {
                    modelFrames = result
                }
                if index >= allFrames.count { index = RadarProvider.nowIndex(in: allFrames) }
            }
        }
    }

    private func rebuildFrames() {
        let future = showFuture ? store.tier.radarFuture : 0
        let newFrames = provider.frames(past: TimeInterval(pastRange.rawValue), future: future, layer: layer)
        let wasPlaying = isPlaying
        frames = newFrames
        index = RadarProvider.nowIndex(in: newFrames)
        isPlaying = wasPlaying && allFrames.count > 1
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
