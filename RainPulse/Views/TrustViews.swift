import SwiftUI

// MARK: - Official warnings (government wording, never mixed with our forecasts)

struct OfficialAlertsCard: View {
    let alerts: [OfficialAlert]
    let timeZone: TimeZone
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(showAll ? alerts : Array(alerts.prefix(1))) { alert in
                OfficialAlertRow(alert: alert, timeZone: timeZone)
            }
            if alerts.count > 1 {
                Button(showAll ? String(localized: "Show fewer") : String(localized: "\(alerts.count - 1) more official warnings")) {
                    withAnimation { showAll.toggle() }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
            }
        }
        .accessibilityIdentifier("official.card")
    }
}

private struct OfficialAlertRow: View {
    let alert: OfficialAlert
    let timeZone: TimeZone

    private var tint: Color {
        switch alert.severity {
        case .extreme, .severe: return .red
        case .moderate: return .orange
        default: return .yellow
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "building.columns.fill")
                Text("Official warning").textCase(.uppercase)
                Spacer()
                if let expires = alert.expires {
                    Text("Until \(Fmt.time(expires, in: timeZone))")
                }
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.black.opacity(0.85))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(tint)

            VStack(alignment: .leading, spacing: 6) {
                Text(alert.event).font(.headline)
                Text(alert.headline).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline) {
                    Text(alert.source == .sachet
                         ? String(localized: "Issued by \(alert.agency) · via NDMA SACHET")
                         : String(localized: "Issued by \(alert.agency) · via Apple Weather"))
                        .font(.caption).foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    if let url = alert.detailsURL {
                        Link(String(localized: "Details"), destination: url).font(.caption.weight(.semibold))
                    }
                }
                Text("The agency's own wording. Follow local authorities' instructions.")
                    .font(.caption2).foregroundStyle(.white.opacity(0.6))
            }
            .foregroundStyle(.white)
            .padding(14)
        }
        .background(Color.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(tint, lineWidth: 2))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Forecast confidence

struct ConfidenceCard: View {
    let confidence: ForecastConfidence
    let timeZone: TimeZone
    @State private var expanded = false

    private var tint: Color {
        switch confidence.level {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Forecast confidence", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
                Spacer()
                Text(confidence.level.label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black.opacity(0.85))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(tint, in: Capsule())
                    .accessibilityIdentifier("confidence.level")
            }
            Text(confidence.sentence).font(.headline).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup(isExpanded: $expanded) {
                VStack(spacing: 6) {
                    ForEach(confidence.models) { m in
                        HStack {
                            Text(m.name).font(.subheadline)
                            Spacer()
                            Text(m.firstRain.map { String(localized: "Rain from \(Fmt.time($0, in: timeZone))") }
                                 ?? String(localized: "No rain"))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(m.firstRain == nil ? .white.opacity(0.7) : .white)
                        }
                    }
                    Text("Four independent weather models, next 12 hours. When they agree, the forecast is more reliable.")
                        .font(.caption2).foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .padding(.top, 6)
            } label: {
                Text("What each model says").font(.footnote.weight(.semibold))
            }
            .tint(.white)
        }
        .foregroundStyle(.white)
        .glassCard()
        .accessibilityIdentifier("confidence.card")
    }
}

// MARK: - Forecast vs reality

struct LedgerCard: View {
    let score: LedgerScore
    let recent: [LedgerEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Forecast vs reality", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
            if let pct = score.percent {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "\(pct)%").font(.system(size: 40, weight: .semibold, design: .rounded))
                    Text("of rain forecasts were right here in the last 7 days")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                }
                Text("\(score.verified) checks · \(score.peopleChecked) confirmed by Rain Truth reports")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            } else {
                Text("RainPulse is keeping score here. Each forecast is checked against what really happened — results appear within a day.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.85))
            }
            ForEach(recent) { e in
                LedgerRow(entry: e)
            }
            Text("Checked against Rain Truth reports; when nobody reported, against Open-Meteo's recorded rainfall (a model estimate, not a rain gauge).")
                .font(.caption2).foregroundStyle(.white.opacity(0.6))
        }
        .foregroundStyle(.white)
        .glassCard()
        .accessibilityIdentifier("ledger.card")
    }
}

private struct LedgerRow: View {
    let entry: LedgerEntry

    var body: some View {
        let v = entry.verdict!
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: v.outcome.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(v.outcome.isCorrect ? .green : .orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(LedgerLogic.blockLabel(entry, now: Date())).font(.subheadline.weight(.semibold))
                Text(said).font(.caption)
                Text(happened(v)).font(.caption).foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
        }
        .padding(10)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var said: String {
        if entry.predictedRain {
            if let c = entry.chance {
                let pct = "\(c)%"
                return String(localized: "Forecast: rain (\(pct) chance)")
            }
            return String(localized: "Forecast: rain")
        }
        return String(localized: "Forecast: dry")
    }

    private func happened(_ v: LedgerEntry.Verdict) -> String {
        switch v.evidence {
        case .people(let wet, let dry):
            return v.rained
                ? String(localized: "Reality: \(wet) of \(wet + dry) Rain Truth reports said rain")
                : String(localized: "Reality: \(dry) of \(wet + dry) Rain Truth reports said dry")
        case .recorded(let mm):
            return v.rained
                ? String(localized: "Reality: \(Fmt.rainfall(mm)) recorded")
                : String(localized: "Reality: no rain recorded")
        }
    }
}
