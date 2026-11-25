import WidgetKit
import SwiftUI
import Charts

@main
struct RainPulseWidgetBundle: WidgetBundle {
    var body: some Widget {
        RainNowWidget()
        TodayLineWidget()
    }
}

struct RainEntry: TimelineEntry {
    let date: Date
    let placeName: String
    let forecast: Forecast?
    let tier: Tier
    var airQuality: AirQuality? = nil
}

struct RainProvider: TimelineProvider {
    func placeholder(in context: Context) -> RainEntry {
        RainEntry(date: Date(), placeName: String(localized: "My Location"), forecast: nil, tier: .essential)
    }

    func getSnapshot(in context: Context, completion: @escaping (RainEntry) -> Void) {
        Task { completion(await makeEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RainEntry>) -> Void) {
        Task {
            let entry = await makeEntry()
            // Paid users refresh every 20 min, free users every 45 min, to keep API costs low.
            let minutes: Double = entry.tier >= .essential ? 20 : 45
            let next = Date().addingTimeInterval(minutes * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func makeEntry() async -> RainEntry {
        let tier = SharedStore.tier
        guard let place = SharedStore.lastLocation ?? SharedStore.loadPlaces().first else {
            return RainEntry(date: Date(), placeName: String(localized: "Open RainPulse"), forecast: nil, tier: tier)
        }
        let forecast = try? await ForecastService.shared.forecast(latitude: place.latitude,
                                                                   longitude: place.longitude,
                                                                   days: 1, maxAge: 900)
        var aqi = SharedStore.airQuality(for: place)
        if aqi == nil { aqi = await AirQualityService.shared.airQuality(latitude: place.latitude, longitude: place.longitude) }
        return RainEntry(date: Date(), placeName: place.name, forecast: forecast, tier: tier, airQuality: aqi)
    }
}

struct RainNowWidget: Widget {
    let kind = "RainPulseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RainProvider()) { entry in
            RainWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(.systemBackground), .blue.opacity(0.18)],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("Rain Now")
        .description("Current weather and rain for the next 2 hours.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct RainWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RainEntry

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    private var summary: String {
        entry.forecast?.nowcastSummary(from: entry.date) ?? String(localized: "Open the app to load")
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.placeName).font(.caption.weight(.semibold)).lineLimit(1)
            if let f = entry.forecast {
                HStack(alignment: .firstTextBaseline) {
                    Text(Fmt.temperature(f.current.temperature))
                        .font(.system(size: 38, weight: .light, design: .rounded))
                    Image(systemName: WeatherCode.symbol(f.current.weatherCode))
                        .symbolRenderingMode(.multicolor)
                        .font(.title3)
                }
            }
            Spacer(minLength: 0)
            Text(summary)
                .font(.caption2.weight(.medium))
                .foregroundStyle(entry.forecast?.isRainingNow == true ? Color.blue : Color.secondary)
                .lineLimit(2)
            if entry.forecast?.usesAppleWeather == true {
                Text("\u{F8FF} Weather").font(.system(size: 8)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(spacing: 14) {
            small.frame(maxWidth: 120)
            if entry.tier >= .essential, let f = entry.forecast {
                RainBars(steps: f.upcomingSteps(hours: 2, from: entry.date))
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    Text("2-hour rain chart with Essential")
                        .font(.caption2).multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: "drop.fill")
                Text(entry.placeName).lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            Text(summary).font(.caption).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        Label(summary, systemImage: "drop.fill")
    }
}

struct RainBars: View {
    let steps: [Forecast.Step]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Next 2 hours").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Chart(steps) { step in
                BarMark(x: .value("Time", step.time, unit: .minute),
                        y: .value("Rain", step.precipitation * 4))
                    .foregroundStyle(Color.blue.gradient)
                    .cornerRadius(2)
            }
            .chartYScale(domain: 0...max(2.5, (steps.map(\.precipitation).max() ?? 0) * 4))
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .minute, count: 60)) { _ in
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
        }
    }
}

// MARK: - Today in one line (lock screen)

struct TodayLineWidget: Widget {
    let kind = "RainPulseTodayLine"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: RainProvider()) { entry in
            TodayLineView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Today in one line")
        .description("Umbrella, heat and air quality advice at a glance.")
        .supportedFamilies([.accessoryInline, .accessoryRectangular])
    }
}

struct TodayLineView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RainEntry

    private var line: String {
        entry.forecast?.oneLiner(airQuality: entry.airQuality, now: entry.date) ?? String(localized: "Open the app to load")
    }

    var body: some View {
        if family == .accessoryInline {
            Label(line, systemImage: "umbrella.fill")
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "umbrella.fill")
                    Text(entry.placeName).lineLimit(1)
                    if let f = entry.forecast {
                        Spacer(minLength: 0)
                        Text(Fmt.temperature(f.current.temperature))
                    }
                }
                .font(.caption.weight(.semibold))
                Text(line).font(.caption).lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
