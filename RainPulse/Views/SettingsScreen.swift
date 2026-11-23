import SwiftUI
import UIKit

struct SettingsScreen: View {
    @EnvironmentObject private var store: StoreManager

    @AppStorage(AlertSettings.enabledKey, store: AppConfig.sharedDefaults) private var alertsEnabled = false
    @AppStorage(AlertSettings.leadMinutesKey, store: AppConfig.sharedDefaults) private var leadMinutes = 30
    @AppStorage(AlertSettings.thresholdKey, store: AppConfig.sharedDefaults) private var threshold = 0.1
    @AppStorage("radar.opacity") private var opacity = 0.75
    @AppStorage("radar.source") private var sourceRaw = RadarSource.owmGlobalPrecip.rawValue

    @State private var showPaywall = false
    @State private var showManage = false
    @State private var notificationsDenied = false

    var body: some View {
        NavigationStack {
            Form {
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
                    Picker("Radar data", selection: $sourceRaw) {
                        ForEach(RadarSource.allCases) { Text($0.displayName).tag($0.rawValue) }
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
