import SwiftUI
import CoreLocation

// MARK: - Report sheet ("Is it raining where you are?")

struct ReportSheet: View {
    let coordinate: CLLocationCoordinate2D?
    var onSent: (CrowdReport) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var sending: ReportCondition?
    @State private var message: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("What's it like outside right now?")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(ReportCondition.allCases) { c in
                        Button { send(c) } label: {
                            VStack(spacing: 6) {
                                Text(c.emoji).font(.system(size: 38))
                                Text(c.label).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    .multilineTextAlignment(.center).minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity, minHeight: 96)
                            .background(c == .waterlogging ? Color.red.opacity(0.18) : Color.primary.opacity(0.07),
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay {
                                if sending == c { ProgressView() }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(sending != nil || sent || coordinate == nil)
                        .accessibilityIdentifier("report.\(c.rawValue)")
                    }
                }
                if let message {
                    Label(message, systemImage: sent ? "checkmark.circle.fill" : "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(sent ? .green : .secondary)
                        .multilineTextAlignment(.center)
                } else if coordinate == nil {
                    Label("Turn on location to send a report.", systemImage: "location.slash")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("Reports are anonymous and share only an approximate location (about 100 m). They help people nearby see where it's really raining.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("Report weather")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.accessibilityIdentifier("report.close")
                }
            }
        }
    }

    private func send(_ c: ReportCondition) {
        guard let coordinate else { return }
        sending = c
        Haptics.tap()
        Task {
            let area = c == .waterlogging ? await Self.streetName(coordinate) : nil
            do {
                let report = try await CrowdReportService.shared.submit(c, at: coordinate, area: area)
                sent = true
                message = String(localized: "Thanks! Your report is on the map.")
                onSent(report)
                try? await Task.sleep(for: .seconds(1.2))
                dismiss()
            } catch {
                message = error.localizedDescription
            }
            sending = nil
        }
    }

    /// Street (or neighbourhood) name for waterlogging reports.
    static func streetName(_ c: CLLocationCoordinate2D) async -> String? {
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: c.latitude, longitude: c.longitude)).first
        return placemark?.thoroughfare ?? placemark?.subLocality ?? placemark?.locality
    }
}

// MARK: - Crowd card (Forecast screen)

struct CrowdCard: View {
    let summary: CrowdSummary
    let canReport: Bool
    let onReport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Rain Truth", systemImage: "person.3.fill")
                    .font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
                Spacer()
                Text("Live reports").font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(summary.floods.prefix(2)) { flood in
                HStack(alignment: .top, spacing: 10) {
                    Text("🌊").font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(flood.area.map { String(localized: "Waterlogging near \($0)") } ?? String(localized: "Waterlogging reported nearby"))
                            .font(.subheadline.weight(.semibold))
                        Text("\(max(1, Int(Date().timeIntervalSince(flood.time) / 60))) min ago · consider another route")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if let headline = summary.headline(now: Date()) {
                Text(headline).font(.headline)
            } else if summary.floods.isEmpty {
                Text("No reports near you yet. Be the first — it takes one tap.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Button(action: onReport) {
                Label("Is it raining where you are?", systemImage: "hand.tap.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.white.opacity(0.18), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canReport)
            .accessibilityIdentifier("crowd.report")
        }
        .foregroundStyle(.white)
        .glassCard()
        .accessibilityIdentifier("crowd.card")
    }
}

// MARK: - Leave now card

struct LeaveNowCard: View {
    let forecast: Forecast
    let locked: Bool
    let onUnlock: () -> Void
    @AppStorage("leave.tripMinutes") private var trip = 30

    var body: some View {
        let advice = forecast.leaveAdvice(tripMinutes: trip)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Leave now?", systemImage: "figure.walk.departure")
                    .font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
                Spacer()
                Picker("Trip length", selection: $trip) {
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("1 h").tag(60)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 190)
            }
            ZStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(advice.title).font(.title3.weight(.semibold))
                    if !advice.detail.isEmpty {
                        Text(advice.detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .blur(radius: locked ? 7 : 0)
                if locked {
                    Button(action: onUnlock) {
                        Label("Unlock with Essential", systemImage: "lock.fill")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.white.opacity(0.2), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .foregroundStyle(.white)
        .glassCard()
        .accessibilityIdentifier("leave.card")
    }
}

// MARK: - Crowd chip (Radar screen)

struct CrowdChip: View {
    let summary: CrowdSummary
    let action: () -> Void

    var body: some View {
        if let text = chipText {
            Button(action: action) {
                Text(text)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(summary.floods.isEmpty ? Color.blue.opacity(0.85) : Color.red, in: Capsule())
                    .foregroundStyle(.white)
            }
            .accessibilityIdentifier("crowd.chip")
        }
    }

    private var chipText: String? {
        if let flood = summary.floods.first {
            return "🌊 " + (flood.area.map { String(localized: "Waterlogging near \($0)") } ?? String(localized: "Waterlogging reported nearby"))
        }
        return summary.headline(now: Date()).map { (summary.mostlyWet ? "🌧 " : "☀️ ") + $0 }
    }
}
