import XCTest
import StoreKit
import StoreKitTest
import LingXiKit
import LingXiServices

/// These tests run inside LingXiPurchaseHost, a deliberately StoreKit-free iOS app. A
/// production app would start its own StoreKit client before SKTestSession can install the
/// local configuration, which makes Product.products return an empty list.
@MainActor
final class StoreKitPurchaseTests: XCTestCase {
    private static let productID = ProProduct.identifier
    private var session: SKTestSession!
    private var temporaryFiles: [URL] = []

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle(for: StoreKitPurchaseTests.self)
            .url(forResource: "Configuration", withExtension: "storekit"))
        session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.askToBuyEnabled = false
        session.clearTransactions()
        session.storefront = "USA"
        session.locale = Locale(identifier: "en_US")
    }

    override func tearDownWithError() throws {
        session.resetToDefaultState()
        session = nil
        for url in temporaryFiles {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(atPath: url.path + "-wal")
            try? FileManager.default.removeItem(atPath: url.path + "-shm")
        }
        temporaryFiles = []
    }

    // MARK: Product loading and localization

    func testProductLoadsFromLocalConfiguration() async throws {
        let product = try await loadProduct()
        XCTAssertEqual(product.id, Self.productID)
        XCTAssertEqual(product.type, .nonConsumable)
        XCTAssertEqual(product.displayName, "Texel Pro")
        XCTAssertFalse(product.displayPrice.isEmpty)
        print("USA displayPrice=\(product.displayPrice) currency=\(product.priceFormatStyle.currencyCode)")
    }

    func testRegionalStorefrontPricesComeFromStoreKit() async throws {
        let storefronts = [
            ("USA", "en_US", "USD", "$"),
            ("CHN", "zh_CN", "CNY", "¥"),
            ("JPN", "ja_JP", "JPY", "¥"),
            ("DEU", "de_DE", "EUR", "€")
        ]
        var prices = Set<String>()
        for (storefront, locale, currency, symbol) in storefronts {
            session.storefront = storefront
            session.locale = Locale(identifier: locale)
            let product = try await loadProduct()
            XCTAssertEqual(product.priceFormatStyle.currencyCode, currency,
                           "Expected \(storefront) to use \(currency)")
            XCTAssertTrue(product.displayPrice.contains(symbol),
                          "\(storefront) price should use \(symbol): \(product.displayPrice)")
            XCTAssertFalse(product.displayPrice.isEmpty)
            if storefront == "USA" {
                XCTAssertEqual(product.displayPrice, "$2.99")
            }
            prices.insert(product.displayPrice)
            print("\(storefront) locale=\(locale) price=\(product.displayPrice) currency=\(product.priceFormatStyle.currencyCode)")
        }
        XCTAssertGreaterThan(prices.count, 1, "Prices must be localized by StoreKit, not hardcoded")
    }

    // MARK: Purchasing

    func testSuccessfulPurchaseGrantsVerifiedPro() async throws {
        let manager = PurchaseManager()
        await manager.start()
        await manager.loadProduct()
        XCTAssertNotNil(manager.product)

        await manager.purchase()

        XCTAssertEqual(manager.purchaseState, .success)
        XCTAssertTrue(manager.isPro)
        let verified = await StoreKitEntitlementProvider().isPro()
        XCTAssertTrue(verified)
        XCTAssertEqual(session.allTransactions().filter { $0.productIdentifier == Self.productID }.count, 1)
    }

    func testCancelledPurchaseDoesNotGrantPro() async throws {
        try await session.setSimulatedError(SKTestFailures.Purchase.generic(.userCancelled), forAPI: .purchase)
        let manager = PurchaseManager()
        await manager.start()
        await manager.loadProduct()

        await manager.purchase()

        XCTAssertEqual(manager.purchaseState, .cancelled)
        XCTAssertFalse(manager.isPro)
        XCTAssertTrue(session.allTransactions().isEmpty)
    }

    func testFailedPurchaseDoesNotGrantPro() async throws {
        try await session.setSimulatedError(
            SKTestFailures.Purchase.generic(.networkError(URLError(.notConnectedToInternet))),
            forAPI: .purchase
        )
        let manager = PurchaseManager()
        await manager.start()
        await manager.loadProduct()

        await manager.purchase()

        guard case .failed(let message) = manager.purchaseState else {
            return XCTFail("Expected a friendly failure, got \(manager.purchaseState)")
        }
        XCTAssertEqual(message, "网络连接失败，请检查网络后重试。")
        XCTAssertFalse(manager.isPro)
        XCTAssertTrue(session.allTransactions().isEmpty)
    }

    func testPendingPurchaseUnlocksAfterApproval() async throws {
        let manager = PurchaseManager()
        await manager.start()
        await manager.loadProduct()
        session.askToBuyEnabled = true

        await manager.purchase()
        XCTAssertEqual(manager.purchaseState, .awaitingApproval)
        XCTAssertFalse(manager.isPro)

        let pending = try XCTUnwrap(session.allTransactions().first { $0.pendingAskToBuyConfirmation })
        try session.approveAskToBuyTransaction(identifier: pending.identifier)

        let unlocked = await waitUntil { manager.isPro }
        XCTAssertTrue(unlocked)
        XCTAssertEqual(manager.purchaseState, .success)
        let verified = await StoreKitEntitlementProvider().isPro()
        XCTAssertTrue(verified)
    }

    func testRestorePurchasesRestoresPro() async throws {
        let first = PurchaseManager()
        await first.start()
        await first.loadProduct()
        await first.purchase()
        XCTAssertTrue(first.isPro)

        let second = PurchaseManager()
        await second.start()
        XCTAssertTrue(second.isPro)
        await second.restore()

        XCTAssertTrue(second.isPro)
        XCTAssertEqual(second.restoreMessage, "已恢复 纹粒 Pro 权益。")
    }

    func testProSurvivesAppRelaunch() async throws {
        let first = PurchaseManager()
        await first.start()
        await first.loadProduct()
        await first.purchase()
        XCTAssertTrue(first.isPro)

        let relaunched = PurchaseManager()
        await relaunched.start()
        await relaunched.loadProduct()

        XCTAssertTrue(relaunched.isPro)
        XCTAssertEqual(relaunched.product?.id, Self.productID)
    }

    func testRefundRevokesProAndRestoresFreeAllowance() async throws {
        let manager = PurchaseManager()
        await manager.start()
        await manager.loadProduct()
        await manager.purchase()
        XCTAssertTrue(manager.isPro)

        let transaction = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == Self.productID })
        try session.refundTransaction(identifier: transaction.identifier)

        let revoked = await waitUntil {
            await manager.refreshEntitlement()
            return !manager.isPro
        }
        XCTAssertTrue(revoked)
        let stillPro = await StoreKitEntitlementProvider().isPro()
        XCTAssertFalse(stillPro)

        let quota = QuotaManager(databaseURL: makeDatabaseURL())
        let status = try quota.status(isPro: manager.isPro)
        XCTAssertEqual(status.remaining, QuotaConfiguration.freeDailyLimit)
        XCTAssertFalse(status.isExhausted)
    }

    func testRepeatedCallbacksDoNotDuplicateEntitlement() async throws {
        let manager = PurchaseManager()
        await manager.start()
        await manager.loadProduct()
        await manager.purchase()
        XCTAssertTrue(manager.isPro)

        for _ in 0..<5 {
            await manager.start()
            await manager.refreshEntitlement()
        }

        var activeTransactions = 0
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.productID,
                  transaction.revocationDate == nil,
                  transaction.expirationDate == nil else { continue }
            activeTransactions += 1
        }

        XCTAssertEqual(activeTransactions, 1)
        XCTAssertEqual(session.allTransactions().filter { $0.productIdentifier == Self.productID }.count, 1)
        XCTAssertTrue(manager.isPro)

        let quota = QuotaManager(databaseURL: makeDatabaseURL())
        XCTAssertEqual(try quota.status(isPro: manager.isPro).remaining, Int.max)
    }

    // MARK: Product load failure and retry

    func testProductLoadFailureOffersFriendlyRetry() async throws {
        try await session.setSimulatedError(
            SKTestFailures.LoadProducts.generic(.networkError(URLError(.notConnectedToInternet))),
            forAPI: .loadProducts
        )
        let manager = PurchaseManager()

        await manager.loadProduct()

        XCTAssertNil(manager.product, "A failed load must not fall back to a fake price")
        let message = try XCTUnwrap(manager.productLoadError)
        XCTAssertFalse(message.isEmpty)
        XCTAssertFalse(message.contains("$"), "The error UI must not invent a price")
        XCTAssertFalse(message.contains("4.99"), "The error UI must not invent a price")

        try await session.setSimulatedError(nil, forAPI: .loadProducts)
        await manager.loadProduct()

        XCTAssertNotNil(manager.product)
        XCTAssertNil(manager.productLoadError)
    }

    func testQuotaLedgerSharedByAllServiceEntryPoints() async throws {
        let databaseURL = makeDatabaseURL()
        let appQuota = QuotaManager(databaseURL: databaseURL)
        let shareQuota = QuotaManager(databaseURL: databaseURL)
        let shortcutQuota = QuotaManager(databaseURL: databaseURL)

        let app = ConversionService(entitlementProvider: FreeEntitlementProvider(), quotaManager: appQuota)
        let share = ConversionService(entitlementProvider: FreeEntitlementProvider(), quotaManager: shareQuota)
        let shortcut = ConversionService(entitlementProvider: FreeEntitlementProvider(), quotaManager: shortcutQuota)

        let first = try XCTUnwrap(appQuota.reserve(isPro: false))
        try appQuota.commit(first)

        let appStatus = await app.quotaStatus()
        let shareStatus = await share.quotaStatus()
        let shortcutStatus = await shortcut.quotaStatus()
        XCTAssertEqual(appStatus.used, 1)
        XCTAssertEqual(shareStatus.used, 1)
        XCTAssertEqual(shortcutStatus.used, 1)
        XCTAssertEqual(shareStatus.remaining, QuotaConfiguration.freeDailyLimit - 1)
        XCTAssertEqual(shortcutStatus.remaining, QuotaConfiguration.freeDailyLimit - 1)

        let second = try XCTUnwrap(shareQuota.reserve(isPro: false))
        try shareQuota.commit(second)

        let appSecond = await app.quotaStatus()
        let shortcutSecond = await shortcut.quotaStatus()
        XCTAssertEqual(appSecond.used, 2)
        XCTAssertEqual(shortcutSecond.remaining, QuotaConfiguration.freeDailyLimit - 2)
        XCTAssertEqual(try appQuota.status(isPro: true).remaining, Int.max)
    }

    func testFailedConversionReleasesReservationWithoutChargingQuota() async throws {
        let recorder = RecordingQuotaManager()
        let service = ConversionService(entitlementProvider: FreeEntitlementProvider(),
                                        quotaManager: recorder)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingXiBroken-\(UUID().uuidString).heic")
        try Data("not a heic file".utf8).write(to: url)
        temporaryFiles.append(url)

        do {
            _ = try await service.convert(.init(fileURL: url,
                                                traits: AssetTraits(),
                                                preferredName: "broken_TextureGrain.heic",
                                                saveToLibrary: false)) { _ in }
            XCTFail("A broken file must not convert")
        } catch {
            // Expected: incompatible input is reported, not charged.
        }

        XCTAssertEqual(recorder.reserveCount, 1)
        XCTAssertEqual(recorder.releaseCount, 1)
        XCTAssertEqual(recorder.commitCount, 0)
        XCTAssertEqual(try recorder.status(isPro: false).remaining, QuotaConfiguration.freeDailyLimit)
    }

    // MARK: Helpers

    private func loadProduct() async throws -> Product {
        let products = try await Product.products(for: [Self.productID])
        return try XCTUnwrap(products.first)
    }

    private func makeDatabaseURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingXiPurchaseQuota-\(UUID().uuidString).sqlite")
        temporaryFiles.append(url)
        return url
    }

    private func waitUntil(timeout: TimeInterval = 8, _ condition: @escaping @MainActor () async -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return await condition()
    }
}

/// A quota manager that only records calls, so the conversion path can be tested without a
/// real database or StoreKit transaction.
private final class RecordingQuotaManager: QuotaManaging, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var reserveCount = 0
    private(set) var commitCount = 0
    private(set) var releaseCount = 0

    func status(isPro: Bool) throws -> QuotaStatus {
        isPro ? .unlimited() : QuotaStatus(isPro: false, limit: QuotaConfiguration.freeDailyLimit, used: 0, reserved: 0)
    }

    func reserve(isPro: Bool) throws -> QuotaReservation? {
        guard !isPro else { return nil }
        lock.lock(); defer { lock.unlock() }
        reserveCount += 1
        return QuotaReservation(id: UUID().uuidString, day: "test")
    }

    func commit(_ reservation: QuotaReservation?) throws {
        guard reservation != nil else { return }
        lock.lock(); defer { lock.unlock() }
        commitCount += 1
    }

    func release(_ reservation: QuotaReservation?) throws {
        guard reservation != nil else { return }
        lock.lock(); defer { lock.unlock() }
        releaseCount += 1
    }
}

private struct FreeEntitlementProvider: ProEntitlementProviding {
    func isPro() async -> Bool { false }
}