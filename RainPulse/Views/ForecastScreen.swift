import SwiftUI
import Charts
import MapKit

struct ForecastScreen: View {
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var places: PlacesModel
    @EnvironmentObject private var location: LocationManager

    @AppStorage("map.style") private var mapStyle = 0

    @State private var selectedID: UUID?          // nil = current location
    @State private var forecast: Forecast?
    @State private var errorText: String?
    @State private var showPaywall = false
    @State private var dayIndex = 0
    @State private var insight: String?
    @State private var loadingInsight = false

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
                        titleBlock(place)
                        if store.tier == .free { trialBanner }
                        rainCard(forecast, place: place)
                        insightCard(forecast, place: place)
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
            .toolbar { toolbarContent }
            .refreshable { await load(force: true) }
            .task(id: taskKey) { await load(force: false) }
            .sheet(isPresented: $showPaywall) { PaywallView() }
        }
    }

    private var taskKey: String {
        guard let p = selectedPlace else { return "none-\(store.tier.rawValue)" }
        return String(format: "%.2f,%.2f,%d", p.latitude, p.longitude, store.tier.rawValue)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
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
            .accessibilityLabel("Choose place")
        }
        if let id = selectedID {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    places.places.removeAll { $0.id == id }
                    selectedID = nil
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Remove place")
            }
        }
    }

    private func load(force: Bool) async {
        guard let place = selectedPlace else { return }
        do {
            let f = try await ForecastService.shared.forecast(
                latitude: place.latitude, longitude: place.longitude,
                days: store.tier.forecastDays, maxAge: force ? 0 : 900)
            forecast = f
            errorText = nil
            dayIndex = 0
            insight = nil
            if store.tier == .pro { await loadInsight(f, place: place) }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func loadInsight(_ f: Forecast, place: Place) async {
        loadingInsight = true
        insight = await InsightService.insight(for: f, place: place.name)
        loadingInsight = false
    }

    // MARK: - Title & banner

    private func titleBlock(_ place: Place) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if place.isCurrentLocation {
                Image(systemName: "location.fill").font(.title3).foregroundStyle(Color.accentColor)
            }
            Text(place.name).font(.largeTitle.bold()).lineLimit(1).minimumScaleFactor(0.6)
            Spacer()
        }
    }

    private var trialBanner: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "drop.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Try Essential free for 14 days").font(.headline).foregroundStyle(.white)
                    Text("2-hour rain forecast, alerts for 20 places").font(.caption).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.white)
            }
            .padding()
            .background(LinearGradient(colors: [Color.accentColor, .indigo], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rain card (headline + chart + radar preview)

    private func rainCard(_ f: Forecast, place: Place) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(f.rainHeadline()).font(.title3.bold())
                    Text(f.rainDetail()).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: WeatherCode.symbol(f.current.weatherCode))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 34))
                    Text(Fmt.temperature(f.current.temperature))
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                }
            }

            Text("Next 2 hours").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            let steps = f.upcomingSteps(hours: 2)
            ZStack {
                Chart(steps) { step in
                    BarMark(x: .value("Time", step.time, unit: .minute),
                            y: .value("mm/h", step.precipitation * 4))
                        .foregroundStyle(Color.blue.gradient)
                        .cornerRadius(3)
                }
                .chartYScale(domain: 0...max(5, (steps.map(\.precipitation).max() ?? 0) * 4))
                .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .minute, count: 30)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .frame(height: 130)
                .blur(radius: store.tier.hasMinuteChart ? 0 : 8)

                if !store.tier.hasMinuteChart {
                    Button { showPaywall = true } label: {
                        Label("Unlock with Essential", systemImage: "lock.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Text("Precipitation (mm/h)").font(.caption2).foregroundStyle(.secondary)

            RadarMapView(provider: RadarProvider(source: .owmCurrent),
                         layer: .radar,
                         frames: [RadarFrame(date: Date(), isForecast: false)],
                         currentIndex: 0,
                         opacity: 0.8,
                         center: place.coordinate,
                         places: [place],
                         interactive: false,
                         span: 1.2,
                         mapStyle: mapStyle)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .allowsHitTesting(false)

            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
                Text("Updated \(f.fetchedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(f.hasMinuteData ? "Minute-level rain data" : "Model-based rain data")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - AI insights

    private func insightCard(_ f: Forecast, place: Place) -> some View {
        Group {
            if store.tier == .pro {
                VStack(alignment: .leading, spacing: 8) {
                    Label("AI insights", systemImage: "sparkles")
                        .font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
                    if let insight {
                        Text(insight).font(.body)
                    } else if loadingInsight {
                        ProgressView()
                    } else {
                        Button("Get insight") { Task { await loadInsight(f, place: place) } }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                Button { showPaywall = true } label: {
                    Label("Unlock AI insights", systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(LinearGradient(colors: [.teal.opacity(0.5), .purple.opacity(0.5)],
                                                   startPoint: .leading, endPoint: .trailing),
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Hourly with day tabs

    private func dayStarts(_ f: Forecast) -> [Date] {
        var cal = Calendar.current
        cal.timeZone = f.timeZone
        let now = Date().addingTimeInterval(-3600)
        let days = Set(f.hourly.filter { $0.time > now }.map { cal.startOfDay(for: $0.time) })
        return Array(days.sorted().prefix(store.tier == .free ? 2 : 3))
    }

    private func hourlyCard(_ f: Forecast) -> some View {
        let starts = dayStarts(f)
        let selected = starts.indices.contains(dayIndex) ? starts[dayIndex] : starts.first
        var cal = Calendar.current
        cal.timeZone = f.timeZone
        let now = Date().addingTimeInterval(-3600)
        let hours = f.hourly.filter { h in
            guard let selected else { return false }
            return h.time > now && cal.isDate(h.time, inSameDayAs: selected)
        }
        return Card(title: String(localized: "Hourly"), systemImage: "clock") {
            if starts.count > 1 {
                Picker("Day", selection: $dayIndex) {
                    ForEach(Array(starts.enumerated()), id: \.offset) { i, day in
                        Text(i == 0 ? String(localized: "Today") : Fmt.weekday(day, in: f.timeZone)).tag(i)
                    }
                }
                .pickerStyle(.segmented)
            }
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

    // MARK: - Daily

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
