import SwiftUI

@main
struct RainPulseApp: App {
    @StateObject private var store = StoreManager()
    @StateObject private var places = PlacesModel()
    @StateObject private var location = LocationManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        if AppConfig.isUITest { TestData.seed() }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(places)
                .environmentObject(location)
                .tint(Color("AccentColor"))
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: if !AppConfig.isUITest { location.request() }
            case .background: RainAlertService.schedule()
            default: break
            }
        }
        .backgroundTask(.appRefresh(RainAlertService.taskID)) {
            RainAlertService.schedule()
            await RainAlertService.checkAll()
        }
    }
}

struct RootView: View {
    @AppStorage("onboarded") private var onboarded = false

    var body: some View {
        TabView {
            RadarScreen()
                .tabItem { Label("Radar", systemImage: "dot.radiowaves.left.and.right") }
            ForecastScreen()
                .tabItem { Label("Forecast", systemImage: "cloud.sun.rain") }
            PlacesScreen()
                .tabItem { Label("Places", systemImage: "star") }
            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .fullScreenCover(isPresented: Binding(get: { !onboarded }, set: { onboarded = !$0 })) {
            OnboardingView { onboarded = true }
        }
    }
}

/// Sample data for UI tests and App Store screenshots (Debug builds only).
enum TestData {
    static func seed() {
        UserDefaults.standard.set(true, forKey: "onboarded")
        SharedStore.lastLocation = Place(name: "London", latitude: 51.5072, longitude: -0.1276, isCurrentLocation: true)
        SharedStore.savePlaces([
            Place(name: "Chennai", latitude: 13.0827, longitude: 80.2707),
            Place(name: "Tokyo", latitude: 35.6762, longitude: 139.6503),
            Place(name: "New York", latitude: 40.7128, longitude: -74.0060),
            Place(name: "São Paulo", latitude: -23.5505, longitude: -46.6333)
        ])
        if let tier = AppConfig.uiTestTier { SharedStore.tier = tier }
    }
}
