import SwiftUI

@main
struct RainPulseApp: App {
    @StateObject private var store = StoreManager()
    @StateObject private var places = PlacesModel()
    @StateObject private var location = LocationManager()
    @Environment(\.scenePhase) private var scenePhase

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
            case .active: location.request()
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
