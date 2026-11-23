import SwiftUI
import MapKit

struct RadarScreen: View {
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var places: PlacesModel
    @EnvironmentObject private var location: LocationManager

    @AppStorage("radar.source") private var sourceRaw = RadarSource.owmGlobalPrecip.rawValue
    @AppStorage("radar.opacity") private var opacity = 0.75

    @State private var layer: MapLayer = .radar
    @State private var frames: [RadarFrame] = []
    @State private var index = 0
    @State private var isPlaying = false
    @State private var showPaywall = false
    @State private var fellBackToCurrent = false
    @State private var recenterToken = 0

    private let playTimer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()
    private let refreshTimer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

    private var source: RadarSource {
        let chosen = RadarSource(rawValue: sourceRaw) ?? .owmGlobalPrecip
        return (fellBackToCurrent && chosen == .owmGlobalPrecip) ? .owmCurrent : chosen
    }
    private var provider: RadarProvider { RadarProvider(source: source) }

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
                         onAuthFailure: { if source == .owmGlobalPrecip { fellBackToCurrent = true } })
                .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                topBar
                Spacer()
                if store.tier == .free && layer == .radar {
                    upgradeChip.padding(.bottom, 8)
                }
                timeline
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .onAppear(perform: rebuildFrames)
        .onChange(of: store.tier) { _, _ in rebuildFrames() }
        .onChange(of: sourceRaw) { _, _ in fellBackToCurrent = false; rebuildFrames() }
        .onChange(of: fellBackToCurrent) { _, _ in rebuildFrames() }
        .onChange(of: layer) { _, _ in rebuildFrames() }
        .onReceive(playTimer) { _ in
            guard isPlaying, frames.count > 1 else { return }
            index = (index + 1) % frames.count
        }
        .onReceive(refreshTimer) { _ in rebuildFrames() }
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack(alignment: .top) {
            if AppConfig.owmAPIKey.isEmpty && source != .tomorrow {
                Label("Add your OpenWeather API key to show radar", systemImage: "key.fill")
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            Spacer()
            VStack(spacing: 8) {
                Menu {
                    ForEach(MapLayer.allCases) { item in
                        Button {
                            if item != .radar && !store.tier.hasExtraLayers {
                                showPaywall = true
                            } else {
                                layer = item
                            }
                        } label: {
                            Label(item.displayName + (item != .radar && !store.tier.hasExtraLayers ? " (Pro)" : ""),
                                  systemImage: item.symbol)
                        }
                    }
                } label: {
                    mapButton(systemImage: "square.3.layers.3d")
                }
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

    private var timeline: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .disabled(frames.count < 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(frameLabel).font(.headline.monospacedDigit())
                    Text(frameSubLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if fellBackToCurrent {
                    Text("Live only").font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.orange.opacity(0.2), in: Capsule())
                }
            }

            if frames.count > 1 {
                Slider(value: Binding(get: { Double(index) },
                                      set: { index = Int($0.rounded()); isPlaying = false }),
                       in: 0...Double(frames.count - 1), step: 1)
            }

            HStack {
                RainLegend()
                Spacer()
                Text(provider.source.attribution).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var currentFrame: RadarFrame? { frames.indices.contains(index) ? frames[index] : nil }

    private var frameLabel: String {
        guard let frame = currentFrame, frames.count > 1 else { return String(localized: "Live") }
        return Fmt.time(frame.date)
    }

    private var frameSubLabel: String {
        guard let frame = currentFrame, frames.count > 1 else { return layer.displayName }
        let mins = Int((frame.date.timeIntervalSince(frames[RadarProvider.nowIndex(in: frames)].date)) / 60)
        if mins == 0 { return String(localized: "Now") }
        let rel = mins > 0 ? "+\(Self.duration(mins))" : "−\(Self.duration(-mins))"
        return frame.isForecast ? String(localized: "Forecast \(rel)") : String(localized: "Past \(rel)")
    }

    private static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : (minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min")
    }

    private func rebuildFrames() {
        let newFrames = provider.frames(for: store.tier, layer: layer)
        let wasPlaying = isPlaying
        frames = newFrames
        index = RadarProvider.nowIndex(in: newFrames)
        isPlaying = wasPlaying && newFrames.count > 1
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
