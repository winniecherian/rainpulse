import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var location: LocationManager
    @AppStorage(AlertSettings.enabledKey, store: AppConfig.sharedDefaults) private var alertsEnabled = false
    let onFinish: () -> Void

    @State private var page = 0

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $page) {
                pageView(symbol: "dot.radiowaves.left.and.right",
                         title: String(localized: "Live rain radar"),
                         text: String(localized: "See where it's raining right now, anywhere in the world, and where the rain is heading."))
                    .tag(0)
                pageView(symbol: "location.fill",
                         title: String(localized: "Rain where you are"),
                         text: String(localized: "Allow location so RainPulse can show the radar and forecast around you."))
                    .tag(1)
                pageView(symbol: "bell.badge.fill",
                         title: String(localized: "Alerts before it rains"),
                         text: String(localized: "Get a heads-up before rain reaches you, so you can leave early or wait it out."))
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button {
                switch page {
                case 0: withAnimation { page = 1 }
                case 1:
                    location.request()
                    withAnimation { page = 2 }
                default:
                    Task {
                        alertsEnabled = await RainAlertService.requestPermission()
                        if alertsEnabled { RainAlertService.schedule() }
                        onFinish()
                    }
                }
            } label: {
                Text(page == 0 ? "Get started" : page == 1 ? "Allow location" : "Turn on alerts")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)

            Button("Not now") {
                if page < 2 { withAnimation { page += 1 } } else { onFinish() }
            }
            .font(.subheadline)
            .padding(.bottom)
        }
        .background(
            LinearGradient(colors: [Color.accentColor.opacity(0.25), Color(.systemBackground)],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
        )
    }

    private func pageView(symbol: String, title: String, text: String) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(Color.accentColor.gradient)
            Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(text).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}
