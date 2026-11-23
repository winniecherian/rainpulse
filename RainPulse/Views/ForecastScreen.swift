import SwiftUI
import Charts

struct ForecastScreen: View {
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var places: PlacesModel
    @EnvironmentObject private var location: LocationManager

    @State private var selectedID: UUID?          // nil = current location
    @State private var forecast: Forecast?
    @State private var errorText: String?
    @State private var isLoading = false
    @State private var showPaywall = false

    private var selectedPlace: Place? {
        if let id = selectedID, let place = places.places.first(where: { $0.id == id }) { return place }
        if let loc = location.location {
            return Place(name: location.placeName ?? String(localized: "Current Location"),
                         latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude,
                         isCurrentLocation: true)
        }
        return places.places.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let forecast, let place = selectedPlace {
                        header(forecast, place: place)
                        nowcastCard(forecast)
                        hourlyCard(forecast)
                        dailyCard(forecast)
                        WeatherAttributionView(showsAppleWeather: forecast.usesAppleWeather,
                                               showsOpenMeteo: forecast.usesOpenMeteo)
                    } else if selectedPlace == nil {
                        ContentUnavailableView {
                            Label("No location yet", systemImage: "location.slash")
                        } description: {
                            Text("Allow location access or add a place to see the forecast.")
                        } actions: {
                            Button("Use my location") { location.request() }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 60)
                    } else if let errorText {
                        ContentUnavailableView("Couldn't load forecast", systemImage: "wifi.exclamationmark",
                                               description: Text(errorText))
                            .padding(.top, 60)
                    } else {
                        ProgressView().padding(.top, 80)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(selectedPlace?.name ?? String(localized: "Forecast"))
            .toolbar { placeMenu }
            .refreshable { await load(force: true) }
            .task(id: taskKey) { await load(force: false) }
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    private var taskKey: String {
        guard let p = selectedPlace else { return "none-\(store.tier.rawValue)" }
        return String(format: "%.2f,%.2f,%d", p.latitude, p.longitude, store.tier.rawValue)
    }

    private var placeMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { selectedID = nil } label: {
                    Label("Current Location", systemImage: "location.fill")
                }
                ForEach(places.places) { place in
                    Button(place.name) { selectedID = place.id }
                }
            } label: {
                Image(systemName: "list.bullet")
            }
        }
    }

    private func load(force: Bool) async {
        guard let place = selectedPlace else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            forecast = try await ForecastService.shared.forecast(
                latitude: place.latitude, longitude: place.longitude,
                days: store.tier.forecastDays, maxAge: force ? 0 : 600)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Cards

    private func header(_ f: Forecast, place: Place) -> some View {
        VStack(spacing: 6) {
            Image(systemName: WeatherCode.symbol(f.current.weatherCode))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 56))
            Text(Fmt.temperature(f.current.temperature))
                .font(.system(size: 64, weight: .thin, design: .rounded))
            Text(WeatherCode.description(f.current.weatherCode))
                .font(.title3)
            Text(f.nowcastSummary())
                .font(.headline)
                .foregroundStyle(f.isRainingNow ? Color.blue : Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func nowcastCard(_ f: Forecast) -> some View {
        Card(title: String(localized: "Next 2 hours"), systemImage: "drop.fill") {
            let steps = f.upcomingSteps(hours: 2)
            ZStack {
                Chart(steps) { step in
                    BarMark(x: .value("Time", step.time, unit: .minute),
                            y: .value("Rain", step.precipitation * 4))
                        .foregroundStyle(Color.blue.gradient)
                        .cornerRadius(3)
                }
                .chartYScale(domain: 0...max(2.5, (steps.map(\.precipitation).max() ?? 0) * 4))
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .minute, count: 30)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .frame(height: 140)
                .blur(radius: store.tier.hasMinuteChart ? 0 : 8)

                if !store.tier.hasMinuteChart {
                    Button { showPaywall = true } label: {
                        Label("Unlock with Essential", systemImage: "lock.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Text("Rain intensity (mm/h equivalent), 15-minute steps")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func hourlyCard(_ f: Forecast) -> some View {
        let now = Date().addingTimeInterval(-3600)
        let hours = Array(f.hourly.filter { $0.time > now }.prefix(store.tier == .free ? 24 : 48))
        return Card(title: String(localized: "Hourly"), systemImage: "clock") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(hours) { hour in
                        VStack(spacing: 6) {
                            Text(Fmt.hour(hour.time, in: f.timeZone)).font(.caption)
                            Image(systemName: WeatherCode.symbol(hour.weatherCode))
                                .symbolRenderingMode(.multicolor)
                                .frame(height: 24)
                            Text(Fmt.temperature(hour.temperature)).font(.subheadline.weight(.medium))
                            Text(hour.precipitationProbability.map { "\($0)%" } ?? " ")
                                .font(.caption2).foregroundStyle(.blue)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func dailyCard(_ f: Forecast) -> some View {
        let days = Array(f.daily.prefix(store.tier.forecastDays))
        let low = days.map(\.minTemperature).min() ?? 0
        let high = days.map(\.maxTemperature).max() ?? 1
        return Card(title: String(localized: "\(days.count)-day forecast"), systemImage: "calendar") {
            VStack(spacing: 10) {
                ForEach(days) { day in
                    HStack {
                        Text(Fmt.weekday(day.time, in: f.timeZone)).frame(width: 56, alignment: .leading)
                        Image(systemName: WeatherCode.symbol(day.weatherCode))
                            .symbolRenderingMode(.multicolor).frame(width: 30)
                        Text(day.precipitationProbabilityMax.map { "\($0)%" } ?? "")
                            .font(.caption).foregroundStyle(.blue).frame(width: 38)
                        Text(Fmt.temperature(day.minTemperature)).foregroundStyle(.secondary).frame(width: 40)
                        TemperatureBar(low: low, high: high, dayLow: day.minTemperature, dayHigh: day.maxTemperature)
                        Text(Fmt.temperature(day.maxTemperature)).frame(width: 40)
                    }
                    .font(.subheadline)
                }
                if store.tier == .free {
                    Button { showPaywall = true } label: {
                        Label("See 14 days with Essential", systemImage: "lock.fill").font(.footnote)
                    }
                }
            }
        }
    }
}

struct TemperatureBar: View {
    let low: Double, high: Double, dayLow: Double, dayHigh: Double
    var body: some View {
        GeometryReader { geo in
            let range = max(high - low, 1)
            let start = (dayLow - low) / range * geo.size.width
            let width = max((dayHigh - dayLow) / range * geo.size.width, 6)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(LinearGradient(colors: [.teal, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                    .frame(width: width)
                    .offset(x: start)
            }
        }
        .frame(height: 5)
    }
}

struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
