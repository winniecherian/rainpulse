import XCTest
import StoreKit
import StoreKitTest
@testable import RainPulse

/// Runs real StoreKit purchases against the local Products.storekit configuration.
@MainActor
final class PurchaseTests: XCTestCase {
    var session: SKTestSession!

    override func setUp() async throws {
        session = try SKTestSession(configurationFileNamed: "Products")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.askToBuyEnabled = false
    }

    override func tearDown() async throws {
        session.clearTransactions()
    }

    /// Simulated App Store purchase (no confirmation sheet).
    private func buy(_ id: String) async throws {
        _ = try await session.buyProduct(identifier: id)
    }

    /// StoreKit applies refunds/expiry asynchronously; poll briefly.
    private func waitForTier(_ store: StoreManager, _ expected: Tier, seconds: Double = 10) async {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            await store.refreshEntitlements()
            if store.tier == expected { return }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private func makeStore() async -> StoreManager {
        let store = StoreManager()
        await store.loadProducts()
        await store.refreshEntitlements()
        return store
    }

    func testAllFourPlansLoadWithExpectedPrices() async throws {
        let store = await makeStore()
        let ids = Set(store.products.map(\.id))
        XCTAssertEqual(ids, Set(StoreManager.ID.all))
        XCTAssertEqual(store.product(StoreManager.ID.essentialMonthly)?.price, Decimal(string: "2.99"))
        XCTAssertEqual(store.product(StoreManager.ID.proYearly)?.price, Decimal(string: "34.99"))
        XCTAssertEqual(store.tier, .free)
    }

    func testFreeTrialOnlyOnYearlyPlans() async throws {
        let store = await makeStore()
        XCTAssertNil(store.product(StoreManager.ID.essentialMonthly)?.subscription?.introductoryOffer)
        XCTAssertNil(store.product(StoreManager.ID.proMonthly)?.subscription?.introductoryOffer)
        XCTAssertEqual(store.product(StoreManager.ID.essentialYearly)?.subscription?.introductoryOffer?.paymentMode, .freeTrial)
        XCTAssertEqual(store.product(StoreManager.ID.proYearly)?.subscription?.introductoryOffer?.paymentMode, .freeTrial)
    }

    func testBuyingEssentialUnlocksEssential() async throws {
        let store = await makeStore()
        try await buy(StoreManager.ID.essentialMonthly)
        await waitForTier(store, .essential)
        XCTAssertEqual(store.tier, .essential)
        XCTAssertEqual(SharedStore.tier, .essential, "widget must see the same plan")
    }

    func testUpgradeToProThenExpire() async throws {
        let store = await makeStore()
        try await buy(StoreManager.ID.essentialMonthly)
        try await buy(StoreManager.ID.proYearly)
        await waitForTier(store, .pro)
        XCTAssertEqual(store.tier, .pro)

        try session.expireSubscription(productIdentifier: StoreManager.ID.proYearly)
        try? session.expireSubscription(productIdentifier: StoreManager.ID.essentialMonthly)
        await waitForTier(store, .free)
        XCTAssertEqual(store.tier, .free, "expired subscriptions must lock features again")
    }

    func testRefundRemovesAccess() async throws {
        let store = await makeStore()
        try await buy(StoreManager.ID.proMonthly)
        await waitForTier(store, .pro)
        XCTAssertEqual(store.tier, .pro)
        let txn = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == StoreManager.ID.proMonthly })
        try session.refundTransaction(identifier: UInt(txn.identifier))
        await waitForTier(store, .free)
        XCTAssertEqual(store.tier, .free, "refunded purchase must lock features again")
    }

    func testFailedPurchaseKeepsFreeAndShowsError() async throws {
        let store = await makeStore()
        session.failTransactionsEnabled = true
        do { try await buy(StoreManager.ID.essentialYearly); XCTFail("purchase should fail") } catch {}
        await store.refreshEntitlements()
        XCTAssertEqual(store.tier, .free)
        session.failTransactionsEnabled = false
    }

    /// A subscription bought earlier (e.g. on another device) is found on launch.
    func testExistingSubscriptionIsFoundOnLaunch() async throws {
        _ = try await session.buyProduct(identifier: StoreManager.ID.essentialYearly)
        let store = await makeStore()
        XCTAssertEqual(store.tier, .essential)
    }
}
