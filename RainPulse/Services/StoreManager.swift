import Foundation
import StoreKit
import WidgetKit

/// StoreKit 2 subscriptions. All four products live in ONE subscription group
/// ("RainPulse Premium") so users can upgrade/downgrade between Essential and Pro.
@MainActor
final class StoreManager: ObservableObject {
    enum ID {
        static let essentialMonthly = "rainpulse.essential.monthly"
        static let essentialYearly = "rainpulse.essential.yearly"
        static let proMonthly = "rainpulse.pro.monthly"
        static let proYearly = "rainpulse.pro.yearly"
        static let all = [essentialMonthly, essentialYearly, proMonthly, proYearly]
    }

    @Published private(set) var products: [Product] = []
    @Published private(set) var tier: Tier = SharedStore.tier
    @Published private(set) var isEligibleForTrial = true
    @Published var lastError: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit { updatesTask?.cancel() }

    func product(_ id: String) -> Product? { products.first { $0.id == id } }

    func loadProducts() async {
        do {
            products = try await Product.products(for: ID.all).sorted { $0.price < $1.price }
            if let subscription = products.first?.subscription {
                isEligibleForTrial = await subscription.isEligibleForIntroOffer
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { return false }
                await transaction.finish()
                await refreshEntitlements()
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func restore() async {
        do { try await AppStore.sync() } catch { lastError = error.localizedDescription }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var best: Tier = .free
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  transaction.revocationDate == nil else { continue }
            if transaction.productID == ID.proMonthly || transaction.productID == ID.proYearly {
                best = .pro
            } else if transaction.productID == ID.essentialMonthly || transaction.productID == ID.essentialYearly,
                      best < .essential {
                best = .essential
            }
        }
        if best != tier || SharedStore.tier != best {
            tier = best
            SharedStore.tier = best
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
