import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var store: StoreManager
    @Environment(\.dismiss) private var dismiss

    @State private var yearly = false   // open on monthly
    @State private var selectedTier: Tier = .essential
    @State private var purchasing = false

    private var selectedProductID: String {
        switch (selectedTier, yearly) {
        case (.pro, true): return StoreManager.ID.proYearly
        case (.pro, false): return StoreManager.ID.proMonthly
        case (_, true): return StoreManager.ID.essentialYearly
        default: return StoreManager.ID.essentialMonthly
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Image(systemName: "cloud.rain.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.accentColor.gradient)
                        Text("Know exactly when it rains")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text("Live radar, a 2-hour rain forecast and alerts before it starts.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    Picker("Billing", selection: $yearly) {
                        Text("Monthly").tag(false)
                        Text("Yearly").tag(true)
                    }
                    .pickerStyle(.segmented)

                    PlanCard(tier: .essential,
                             product: store.product(yearly ? StoreManager.ID.essentialYearly : StoreManager.ID.essentialMonthly),
                             yearly: yearly,
                             isSelected: selectedTier == .essential,
                             features: [
                                String(localized: "2-hour radar forecast animation"),
                                String(localized: "2-hour radar history"),
                                String(localized: "Minute-by-minute rain chart"),
                                String(localized: "14-day forecast"),
                                String(localized: "Rain alerts for up to 20 places"),
                                String(localized: "All widget sizes")
                             ])
                        .onTapGesture { selectedTier = .essential }

                    PlanCard(tier: .pro,
                             product: store.product(yearly ? StoreManager.ID.proYearly : StoreManager.ID.proMonthly),
                             yearly: yearly,
                             isSelected: selectedTier == .pro,
                             features: [
                                String(localized: "Everything in Essential"),
                                String(localized: "48-hour radar playback"),
                                String(localized: "Clouds, wind and temperature map layers")
                             ])
                        .onTapGesture { selectedTier = .pro }

                    Button {
                        guard let product = store.product(selectedProductID) else { return }
                        purchasing = true
                        Task {
                            let ok = await store.purchase(product)
                            purchasing = false
                            if ok { dismiss() }
                        }
                    } label: {
                        Group {
                            if purchasing { ProgressView().tint(.white) }
                            else { Text(ctaTitle).font(.headline) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.product(selectedProductID) == nil || purchasing)

                    Text(legalText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 18) {
                        Button("Restore") { Task { await store.restore(); if store.tier > .free { dismiss() } } }
                            .accessibilityIdentifier("paywall.restore")
                        Link("Terms", destination: AppConfig.termsURL)
                        Link("Privacy", destination: AppConfig.privacyURL)
                    }
                    .font(.footnote)

                    if store.products.isEmpty {
                        Text("Loading prices…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .accessibilityLabel("Close")
                }
            }
            .task { if store.products.isEmpty { await store.loadProducts() } }
        }
    }

    private var trialText: String? {
        guard store.isEligibleForTrial,
              let offer = store.product(selectedProductID)?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        let p = offer.period
        let unit: String
        switch p.unit {
        case .day: unit = p.value == 1 ? String(localized: "day") : String(localized: "days")
        case .week: unit = p.value == 1 ? String(localized: "week") : String(localized: "weeks")
        case .month: unit = p.value == 1 ? String(localized: "month") : String(localized: "months")
        case .year: unit = p.value == 1 ? String(localized: "year") : String(localized: "years")
        @unknown default: unit = ""
        }
        return "\(p.value) \(unit)"
    }

    private var ctaTitle: String {
        if let trial = trialText { return String(localized: "Start \(trial) free trial") }
        return String(localized: "Continue")
    }

    private var legalText: String {
        guard let product = store.product(selectedProductID) else { return "" }
        let period = yearly ? String(localized: "year") : String(localized: "month")
        var text = ""
        if let trial = trialText {
            text = String(localized: "Free for \(trial), then \(product.displayPrice) per \(period). ")
        } else {
            text = String(localized: "\(product.displayPrice) per \(period). ")
        }
        text += String(localized: "Renews automatically until cancelled. Cancel anytime in Settings > Apple Account > Subscriptions at least 24 hours before renewal.")
        return text
    }
}

private struct PlanCard: View {
    let tier: Tier
    let product: Product?
    let yearly: Bool
    let isSelected: Bool
    let features: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tier.displayName).font(.title3.bold())
                if tier == .pro {
                    Text("BEST").font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange, in: Capsule()).foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(product?.displayPrice ?? "—").font(.headline)
                    Text(yearly ? "per year" : "per month").font(.caption2).foregroundStyle(.secondary)
                }
            }
            ForEach(features, id: \.self) { feature in
                Label(feature, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
        )
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
