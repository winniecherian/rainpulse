import SwiftUI
import UIKit
import StoreKit

struct SettingsScreen: View {
    @EnvironmentObject private var store: StoreManager

    @AppStorage(AlertSettings.enabledKey, store: AppConfig.sharedDefaults) private var alertsEnabled = false
    @AppStorage(AlertSettings.leadMinutesKey, store: AppConfig.sharedDefaults) private var leadMinutes = 30
    @AppStorage(AlertSettings.thresholdKey, store: AppConfig.sharedDefaults) private var threshold = 0.1
    @AppStorage("radar.opacity") private var opacity = 0.75
    @AppStorage("radar.source") private var sourceRaw = RadarSource.owmGlobalPrecip.rawValue
    @AppStorage("map.style") private var mapStyle = 0
    @AppStorage("radar.speed") private var speed = 1.0
    @AppStorage("radar.showFuture") private var showFuture = true
    @Environment(\.requestReview) private var requestReview

    @State private var showPaywall = false
    @State private var showManage = false
    @State private var notificationsDenied = false

    var body: some View {
        NavigationStack {
            Form {
                Section { CurrentPlanCard(tier: store.tier) { showPaywall = true } }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                Section("Subscription") {
                    HStack {
                        Text("Plan")
                        Spacer()
                        Text(store.tier.displayName).foregroundStyle(.secondary)
                    }
                    if store.tier < .pro {
                        Button(store.tier == .free ? "Upgrade to Essential or Pro" : "Upgrade to Pro") {
                            showPaywall = true
                        }
                    }
                    if store.tier > .free {
                        Button("Manage subscription") { showManage = true }
                    }
                    Button("Restore purchases") { Task { await store.restore() } }
                }

                Section {
                    Toggle("Rain alerts", isOn: $alertsEnabled)
                        .onChange(of: alertsEnabled) { _, on in
                            guard on else { return }
                            Task {
                                let granted = await RainAlertService.requestPermission()
                                if !granted { alertsEnabled = false; notificationsDenied = true }
                                else { RainAlertService.schedule() }
                            }
                        }
                    Picker("Warn me", selection: $leadMinutes) {
                        Text("30 min before").tag(30)
                        Text("1 hour before").tag(60)
                    }
                    .disabled(!alertsEnabled)
                    Picker("Sensitivity", selection: $threshold) {
                        Text("Any drizzle").tag(0.1)
                        Text("Moderate rain").tag(0.5)
                        Text("Heavy rain only").tag(2.0)
                    }
                    .disabled(!alertsEnabled)
                } header: {
                    Text("Alerts")
                } footer: {
                    Text(store.tier == .free
                         ? "Free: alerts for your current location. Essential and Pro: alerts for all saved places."
                         : "Alerts cover your current location and every saved place with the bell on. iOS decides exactly when background checks run.")
                }

                Section("Map") {
                    VStack(alignment: .leading) {
                        Text("Radar opacity")
                        Slider(value: $opacity, in: 0.3...1)
                    }
                    Picker("Map style", selection: $mapStyle) {
                        Text("Standard").tag(0)
                        Text("Hybrid").tag(1)
                        Text("Satellite").tag(2)
                    }
                    Picker("Playback speed", selection: $speed) {
                        Text("0.5x").tag(0.5)
                        Text("1x").tag(1.0)
                        Text("2x").tag(2.0)
                    }
                    Toggle("Show rain forecast in animation", isOn: $showFuture)
                    Picker("Radar data", selection: $sourceRaw) {
                        ForEach(RadarSource.allCases) { Text($0.displayName).tag($0.rawValue) }
                    }
                }

                Section("Help & Feedback") {
                    Button {
                        requestReview()
                    } label: {
                        Label("Rate RainPulse", systemImage: "star")
                    }
                    Link(destination: URL(string: "mailto:support@neuralorbitx.com?subject=RainPulse%20feedback")!) {
                        Label("Send feedback", systemImage: "envelope")
                    }
                }

                Section("Data status") {
                    LabeledContent("Apple Weather", value: DataSourceStatus.text(.appleWeather))
                    LabeledContent("Open-Meteo", value: DataSourceStatus.text(.openMeteo))
                }
                .font(.footnote)

                Section("About") {
                    Link("Privacy Policy", destination: AppConfig.privacyURL)
                    Link("Terms of Use", destination: AppConfig.termsURL)
                    Link("Map data © OpenWeather", destination: URL(string: "https://openweathermap.org/")!)
                    WeatherAttributionView()
                        .listRowBackground(Color.clear)
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .manageSubscriptionsSheet(isPresented: $showManage)
            .alert("Notifications are off", isPresented: $notificationsDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Turn on notifications for RainPulse in Settings to get rain alerts.")
            }
        }
    }
}


/// RainViewer-style plan card at the top of Settings.
struct CurrentPlanCard: View {
    let tier: Tier
    let upgrade: () -> Void

    private var bullets: [String] {
        switch tier {
        case .free: return [String(localized: "2-hour rain forecast animation"),
                            String(localized: "Minute-by-minute rain chart"),
                            String(localized: "14-day forecast and alerts for 20 places")]
        case .essential: return [String(localized: "6-hour radar history"),
                                 String(localized: "Clouds, wind and temperature layers"),
                                 String(localized: "AI insights")]
        case .pro: return [String(localized: "Everything in RainPulse is unlocked")]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your plan").font(.subheadline).foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(tier.displayName)
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.white.opacity(0.25), in: Capsule())
                    .foregroundStyle(.white)
            }
            Text(tier == .pro ? String(localized: "You have Pro") :
                 (tier == .free ? String(localized: "Get Essential") : String(localized: "Try Pro")))
                .font(.title2.bold()).foregroundStyle(.white)
            ForEach(bullets, id: \.self) { b in
                Label(b, systemImage: "checkmark").font(.subheadline).foregroundStyle(.white)
            }
            if tier != .pro {
                Button(action: upgrade) {
                    Text("Upgrade").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding()
        .background(LinearGradient(colors: [Color.accentColor, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
