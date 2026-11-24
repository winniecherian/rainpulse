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

    /// A verified purchase the user currently holds.
    struct Owned { let productID: String; let revoked: Bool; let expires: Date? }

    /// Pure plan decision (unit-tested). Input is Apple's current entitlements, which already
    /// drop expired subscriptions but KEEP ones in a billing grace period, so we must not
    /// second-guess expiry dates here. Refunded/revoked items never unlock anything.
    nonisolated static func tier(for owned: [Owned], now: Date = Date()) -> Tier {
        var best: Tier = .free
        for item in owned where !item.revoked {
            switch item.productID {
            case ID.proMonthly, ID.proYearly: best = .pro
            case ID.essentialMonthly, ID.essentialYearly: if best < .essential { best = .essential }
            default: break
            }
        }
        return best
    }

    func refreshEntitlements() async {
        if let forced = AppConfig.uiTestTier {
            tier = forced
            SharedStore.tier = forced
            return
        }
        var owned: [Owned] = []
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }   // unverified = ignored
            owned.append(Owned(productID: transaction.productID, revoked: transaction.revocationDate != nil,
                               expires: transaction.expirationDate))
        }
        let best = Self.tier(for: owned)
        if best != tier || SharedStore.tier != best {
            tier = best
            SharedStore.tier = best
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
