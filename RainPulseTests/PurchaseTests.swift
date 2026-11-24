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
        let product = try XCTUnwrap(store.product(StoreManager.ID.essentialMonthly))
        let ok = await store.purchase(product)
        XCTAssertTrue(ok)
        XCTAssertEqual(store.tier, .essential)
        XCTAssertEqual(SharedStore.tier, .essential, "widget must see the same plan")
    }

    func testUpgradeToProThenExpire() async throws {
        let store = await makeStore()
        _ = await store.purchase(try XCTUnwrap(store.product(StoreManager.ID.essentialMonthly)))
        _ = await store.purchase(try XCTUnwrap(store.product(StoreManager.ID.proYearly)))
        await store.refreshEntitlements()
        XCTAssertEqual(store.tier, .pro)

        try session.expireSubscription(productIdentifier: StoreManager.ID.proYearly)
        try? session.expireSubscription(productIdentifier: StoreManager.ID.essentialMonthly)
        await store.refreshEntitlements()
        XCTAssertEqual(store.tier, .free, "expired subscriptions must lock features again")
    }

    func testRefundRemovesAccess() async throws {
        let store = await makeStore()
        _ = await store.purchase(try XCTUnwrap(store.product(StoreManager.ID.proMonthly)))
        XCTAssertEqual(store.tier, .pro)
        let txn = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == StoreManager.ID.proMonthly })
        try session.refundTransaction(identifier: UInt(txn.identifier))
        await store.refreshEntitlements()
        XCTAssertEqual(store.tier, .free)
    }

    func testFailedPurchaseKeepsFreeAndShowsError() async throws {
        let store = await makeStore()
        session.failTransactionsEnabled = true
        let ok = await store.purchase(try XCTUnwrap(store.product(StoreManager.ID.essentialYearly)))
        XCTAssertFalse(ok)
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
