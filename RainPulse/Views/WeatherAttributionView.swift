import SwiftUI
import WeatherKit

/// Required data-source credits. Apple requires the Apple Weather mark and a link
/// to its legal page wherever WeatherKit data is shown.
struct WeatherAttributionView: View {
    var showsAppleWeather: Bool = true
    var showsOpenMeteo: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @State private var attribution: WeatherAttribution?

    var body: some View {
        VStack(spacing: 6) {
            if showsAppleWeather, let attribution {
                Link(destination: attribution.legalPageURL) {
                    AsyncImage(url: colorScheme == .dark ? attribution.combinedMarkDarkURL
                                                         : attribution.combinedMarkLightURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Text(attribution.serviceName).font(.caption2)
                    }
                    .frame(height: 12)
                }
                Link("Other data sources", destination: attribution.legalPageURL)
                    .font(.caption2)
            } else if showsAppleWeather {
                Link("\u{F8FF} Weather · Other data sources",
                     destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!)
                    .font(.caption2)
            }
            if showsOpenMeteo {
                Link("Weather data by Open-Meteo.com", destination: URL(string: "https://open-meteo.com/")!)
                    .font(.caption2)
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .task {
            guard showsAppleWeather, attribution == nil else { return }
            attribution = try? await WeatherService.shared.attribution
        }
    }
}
