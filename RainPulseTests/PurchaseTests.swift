import XCTest
import StoreKit
import StoreKitTest
@testable import RainPulse

/// Plan logic: which purchases unlock which plan.
final class PlanDecisionTests: XCTestCase {
    typealias O = StoreManager.Owned
    let now = Date()

    func testNothingOwnedIsFree() {
        XCTAssertEqual(StoreManager.tier(for: [], now: now), .free)
    }

    func testEssentialPlans() {
        XCTAssertEqual(StoreManager.tier(for: [O(productID: StoreManager.ID.essentialMonthly, revoked: false, expires: now + 3600)], now: now), .essential)
        XCTAssertEqual(StoreManager.tier(for: [O(productID: StoreManager.ID.essentialYearly, revoked: false, expires: nil)], now: now), .essential)
    }

    func testProBeatsEssentialInAnyOrder() {
        let e = O(productID: StoreManager.ID.essentialYearly, revoked: false, expires: now + 3600)
        let p = O(productID: StoreManager.ID.proMonthly, revoked: false, expires: now + 3600)
        XCTAssertEqual(StoreManager.tier(for: [e, p], now: now), .pro)
        XCTAssertEqual(StoreManager.tier(for: [p, e], now: now), .pro)
    }

    func testRefundedPurchaseUnlocksNothing() {
        XCTAssertEqual(StoreManager.tier(for: [O(productID: StoreManager.ID.proYearly, revoked: true, expires: now + 3600)], now: now), .free)
    }

    func testBillingGracePeriodKeepsAccess() {
        // Apple still lists a subscription in grace period (date passed, payment being retried).
        XCTAssertEqual(StoreManager.tier(for: [O(productID: StoreManager.ID.proYearly, revoked: false, expires: now - 3600)], now: now), .pro)
    }

    func testDowngradeWhenOnlyEssentialRemains() {
        // After Pro lapses, Apple's list only contains the remaining Essential plan.
        XCTAssertEqual(StoreManager.tier(for: [O(productID: StoreManager.ID.essentialMonthly, revoked: false, expires: now + 600)], now: now), .essential)
    }

    func testUnknownProductIgnored() {
        XCTAssertEqual(StoreManager.tier(for: [O(productID: "com.other.thing", revoked: false, expires: nil)], now: now), .free)
    }

    func testProductIDsMatchAppStoreConnect() {
        XCTAssertEqual(Set(StoreManager.ID.all), ["rainpulse.essential.monthly", "rainpulse.essential.yearly",
                                                  "rainpulse.pro.monthly", "rainpulse.pro.yearly"])
    }
}

/// Smoke test against the local StoreKit configuration: all four plans load with the right prices.
@MainActor
final class StoreCatalogTests: XCTestCase {
    func testAllFourPlansLoadWithExpectedPrices() async throws {
        let session = try SKTestSession(configurationFileNamed: "Products")
        session.resetToDefaultState()
        session.disableDialogs = true
        let products = try await Product.products(for: StoreManager.ID.all)
        XCTAssertEqual(Set(products.map(\.id)), Set(StoreManager.ID.all))
        let price = { (id: String) in products.first { $0.id == id }?.price }
        XCTAssertEqual(price(StoreManager.ID.essentialMonthly), Decimal(string: "2.99"))
        XCTAssertEqual(price(StoreManager.ID.essentialYearly), Decimal(string: "19.99"))
        XCTAssertEqual(price(StoreManager.ID.proMonthly), Decimal(string: "5.99"))
        XCTAssertEqual(price(StoreManager.ID.proYearly), Decimal(string: "34.99"))
        let intro = { (id: String) in products.first { $0.id == id }?.subscription?.introductoryOffer }
        XCTAssertNil(intro(StoreManager.ID.essentialMonthly), "no trial on monthly")
        XCTAssertNil(intro(StoreManager.ID.proMonthly), "no trial on monthly")
        XCTAssertEqual(intro(StoreManager.ID.essentialYearly)?.paymentMode, .freeTrial)
        XCTAssertEqual(intro(StoreManager.ID.proYearly)?.paymentMode, .freeTrial)
        XCTAssertTrue(products.allSatisfy { $0.subscription?.subscriptionGroupID == products[0].subscription?.subscriptionGroupID },
                      "all plans must share one group so upgrades and downgrades work")
    }
}
