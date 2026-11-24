import SwiftUI
import Charts
import MapKit

struct ForecastScreen: View {
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var places: PlacesModel
    @EnvironmentObject private var location: LocationManager

    @AppStorage("map.style.v2") private var mapStyle = 3

    @State private var selectedID: UUID?          // nil = current location
    @State private var forecast: Forecast?
    @State private var errorText: String?
    @State private var showPaywall = false
    @State private var dayIndex = 0
    @State private var insight: String?
    @State private var loadingInsight = false
    @State private var airQuality: AirQuality?
    @State private var nearbyStorms: [Cyclone] = []

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
                        hero(forecast, place: place)
                        if store.tier == .free { trialBanner }
                        ForEach(nearbyStorms) { storm in
                            CycloneCard(storm: storm, place: place)
                        }
                        rainCard(forecast, place: place)
                        insightCard(forecast, place: place)
                        DetailsCard(current: forecast.current, airQuality: airQuality)
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
            .background(SkyBackground(colors: skyColors))
            .environment(\.colorScheme, .dark)
            .toolbarBackground(.hidden, for: .navigationBar)
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
            airQuality = await AirQualityService.shared.airQuality(latitude: place.latitude, longitude: place.longitude)
            nearbyStorms = await CycloneService.shared.activeCyclones(sampleNear: place.coordinate)
                .filter { $0.closestApproachKm(to: place.coordinate) < 1500 }
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

    private var skyColors: [Color] {
        guard let f = forecast else { return Theme.sky(code: 0, isNight: false) }
        return Theme.sky(code: f.current.weatherCode, isNight: Theme.isNight(in: f.timeZone))
    }

    /// Hero: place, temperature and the Rain Clock.
    private func hero(_ f: Forecast, place: Place) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    if place.isCurrentLocation {
                        Image(systemName: "location.fill").font(.subheadline)
                    }
                    Text(place.name).font(.title2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .foregroundStyle(.white)
                Text(Fmt.temperature(f.current.temperature))
                    .font(.system(size: 84, weight: .thin, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                HStack(spacing: 10) {
                    Text(WeatherCode.description(f.current.weatherCode))
                    if let today = f.daily.first {
                        Text("H \(Fmt.temperature(today.maxTemperature))  L \(Fmt.temperature(today.minTemperature))")
                    }
                }
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
            }
            Button {
                if !store.tier.hasMinuteChart { showPaywall = true }
            } label: {
                RainClock(steps: f.upcomingSteps(hours: 2),
                          headline: f.rainHeadline(),
                          detail: f.rainDetail(),
                          size: 250,
                          locked: !store.tier.hasMinuteChart)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var trialBanner: some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "drop.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Try Essential yearly free for 14 days").font(.headline).foregroundStyle(.white)
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
        .glassCard()
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
                .glassCard()
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
        .glassCard()
    }
}


/// Windy-style "conditions now" grid.
struct DetailsCard: View {
    let current: Forecast.Current
    let airQuality: AirQuality?

    private struct Item: Identifiable {
        let id = UUID()
        let title: String, value: String, symbol: String, note: String?
    }

    private static func measure<U: Dimension>(_ v: Double, _ unit: U, digits: Int = 0) -> String {
        Measurement(value: v, unit: unit).formatted(.measurement(width: .abbreviated, usage: .general,
                                                                 numberFormatStyle: .number.precision(.fractionLength(digits))))
    }

    private static func compass(_ deg: Double) -> String {
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return dirs[Int(((deg.truncatingRemainder(dividingBy: 360)) + 22.5) / 45) % 8]
    }

    private static func uvLabel(_ uv: Int) -> String {
        switch uv {
        case ..<3: return String(localized: "Low")
        case ..<6: return String(localized: "Moderate")
        case ..<8: return String(localized: "High")
        case ..<11: return String(localized: "Very high")
        default: return String(localized: "Extreme")
        }
    }

    private var items: [Item] {
        var list: [Item] = []
        if let v = current.feelsLike {
            list.append(.init(title: String(localized: "Feels like"), value: Fmt.temperature(v), symbol: "thermometer.sun", note: nil))
        }
        if let v = current.humidity {
            list.append(.init(title: String(localized: "Humidity"), value: "\(Int(v.rounded()))%", symbol: "humidity", note: nil))
        }
        if let v = current.uvIndex {
            list.append(.init(title: String(localized: "UV index"), value: "\(v)", symbol: "sun.max", note: Self.uvLabel(v)))
        }
        if let v = current.windSpeed {
            let dir = current.windDirection.map { " " + Self.compass($0) } ?? ""
            list.append(.init(title: String(localized: "Wind"), value: Self.measure(v, UnitSpeed.kilometersPerHour) + dir, symbol: "wind",
                              note: current.windGust.map { String(localized: "Gusts \(Self.measure($0, UnitSpeed.kilometersPerHour))") }))
        }
        if let v = current.pressure {
            list.append(.init(title: String(localized: "Pressure"), value: "\(Int(v.rounded())) hPa", symbol: "gauge.with.dots.needle.67percent", note: nil))
        }
        if let v = current.visibility {
            list.append(.init(title: String(localized: "Visibility"), value: Self.measure(v, UnitLength.kilometers, digits: v < 10 ? 1 : 0), symbol: "eye", note: nil))
        }
        if let v = current.dewPoint {
            list.append(.init(title: String(localized: "Dew point"), value: Fmt.temperature(v), symbol: "drop.degreesign", note: nil))
        }
        if let aq = airQuality {
            list.append(.init(title: String(localized: "Air quality"), value: "\(aq.usAQI) AQI", symbol: "aqi.medium", note: aq.category))
        }
        return list
    }

    var body: some View {
        if !items.isEmpty {
            Card(title: String(localized: "Conditions now"), systemImage: "gauge.with.needle") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(item.title, systemImage: item.symbol)
                                .font(.caption).foregroundStyle(.secondary)
                            Text(item.value).font(.title3.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                            if let note = item.note {
                                Text(note).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
    }
}


/// Shown on the forecast when an active cyclone's track passes within 1,500 km.
struct CycloneCard: View {
    let storm: Cyclone
    let place: Place

    private var tint: Color {
        storm.alertLevel == "Red" ? .red : (storm.alertLevel == "Orange" ? .orange : .teal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "hurricane").font(.title2).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cyclone \(storm.name)").font(.headline)
                    Text("\(storm.categoryLabel) · winds up to \(Int(storm.maxWindKmh.rounded())) km/h")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            let now = Int(storm.distanceKm(to: place.coordinate).rounded())
            let closest = Int(storm.closestApproachKm(to: place.coordinate).rounded())
            Text(closest < now - 50
                 ? "\(now) km from \(place.name) now; forecast track passes about \(closest) km away."
                 : "\(now) km from \(place.name).")
                .font(.subheadline)
            Text("Always follow official warnings from your national weather service.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if let url = storm.reportURL {
                    Link("Details", destination: url).font(.footnote.weight(.semibold))
                }
                Spacer()
                Text("Source: GDACS / \(storm.source)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(tint.opacity(0.5), lineWidth: 1))
    }
}
