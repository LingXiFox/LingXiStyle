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

    func testEveryProPlanLoadsFromStoreKitConfiguration() async throws {
        let manager = PurchaseManager()
        await manager.loadPlans()

        XCTAssertNil(manager.productLoadError)
        XCTAssertEqual(Set(manager.planProducts.keys), Set(ProPlan.allCases))
        XCTAssertEqual(manager.planProducts[.lifetime]?.displayPrice, "$2.99")
        XCTAssertEqual(manager.planProducts[.dayPass]?.displayPrice, "$0.49")
        XCTAssertEqual(manager.planProducts[.dayPass]?.type, .nonRenewable)
        XCTAssertEqual(manager.planProducts[.weekly]?.type, .autoRenewable)
        XCTAssertEqual(manager.planProducts[.monthly]?.type, .autoRenewable)
        XCTAssertFalse(manager.planProducts[.weekly]?.displayPrice.isEmpty ?? true)
        XCTAssertFalse(manager.planProducts[.monthly]?.displayPrice.isEmpty ?? true)
    }

    func testLifetimeLoadKeepsTheSubscriptionsReachable() async throws {
        let manager = PurchaseManager()
        await manager.loadProduct()

        XCTAssertEqual(manager.loadedPlans, [.lifetime])
        XCTAssertFalse(manager.hasLoadedAllPlans)
        XCTAssertNil(manager.planProducts[.monthly])

        await manager.loadPlansIfNeeded()

        XCTAssertTrue(manager.hasLoadedAllPlans)
        XCTAssertNil(manager.productLoadError)
        XCTAssertEqual(Set(manager.planProducts.keys), Set(ProPlan.allCases))
        XCTAssertFalse(manager.planProducts[.monthly]?.displayPrice.isEmpty ?? true)
    }

    func testLoadedPlansAreNotRequestedTwiceOnThePaywall() async throws {
        let manager = PurchaseManager()
        await manager.loadPlansIfNeeded()
        XCTAssertTrue(manager.hasLoadedAllPlans)

        // A second paywall entry must not hit StoreKit again, so a simulated failure stays invisible.
        try await session.setSimulatedError(
            SKTestFailures.LoadProducts.generic(.networkError(URLError(.notConnectedToInternet))),
            forAPI: .loadProducts
        )
        await manager.loadPlansIfNeeded()
        XCTAssertNil(manager.productLoadError)
        try await session.setSimulatedError(nil, forAPI: .loadProducts)
    }

    func testDayPassPurchaseUnlocksProForTwentyFourHours() async throws {
        let trialStore = MemoryTrialStore()
        let dayPassStore = MemoryDayPassStore()
        let manager = PurchaseManager(
            entitlementProvider: StoreKitEntitlementProvider(
                trial: { ProTrialService(store: trialStore).state() },
                dayPass: { ProDayPassService(store: dayPassStore).expiresAt() }
            ),
            trialService: ProTrialService(store: trialStore),
            dayPassService: ProDayPassService(store: dayPassStore)
        )

        await manager.loadPlans()
        await manager.purchase(plan: .dayPass)

        XCTAssertEqual(manager.purchaseState, .success)
        XCTAssertTrue(manager.isPro)
        XCTAssertEqual(manager.access.source, .dayPass)
        XCTAssertEqual(manager.access.plan, .dayPass)
        let expiresAt = try XCTUnwrap(manager.access.expiresAt)
        let remaining = expiresAt.timeIntervalSinceNow
        XCTAssertGreaterThan(remaining, 23.5 * 3600)
        XCTAssertLessThanOrEqual(remaining, 24 * 3600)
    }

    /// A non-renewing day pass must be recoverable on another device signed in to the same
    /// Apple ID. StoreKit 2 keeps the latest non-renewing transaction in currentEntitlements,
    /// so a fresh device with empty local Keychain stores can still derive the 24-hour window
    /// from the verified purchase date.
    func testDayPassRestoresOnSecondDeviceFromStoreKitHistory() async throws {
        let firstTrial = MemoryTrialStore()
        let firstDayPass = MemoryDayPassStore()
        let first = PurchaseManager(
            entitlementProvider: StoreKitEntitlementProvider(
                trial: { ProTrialService(store: firstTrial).state() },
                dayPass: { ProDayPassService(store: firstDayPass).expiresAt() }
            ),
            trialService: ProTrialService(store: firstTrial),
            dayPassService: ProDayPassService(store: firstDayPass)
        )
        await first.loadPlans()
        await first.purchase(plan: .dayPass)
        XCTAssertTrue(first.isPro)

        let secondTrial = MemoryTrialStore()
        let secondDayPass = MemoryDayPassStore()
        let second = PurchaseManager(
            entitlementProvider: StoreKitEntitlementProvider(
                trial: { ProTrialService(store: secondTrial).state() },
                dayPass: { ProDayPassService(store: secondDayPass).expiresAt() }
            ),
            trialService: ProTrialService(store: secondTrial),
            dayPassService: ProDayPassService(store: secondDayPass)
        )
        await second.start()

        XCTAssertNil(secondDayPass.record, "the second device starts without a local day-pass mirror")
        XCTAssertTrue(second.isPro)
        XCTAssertEqual(second.access.source, .dayPass)
        XCTAssertEqual(second.access.plan, .dayPass)
        let remaining = try XCTUnwrap(second.access.expiresAt).timeIntervalSinceNow
        XCTAssertGreaterThan(remaining, 23.5 * 3600)
        XCTAssertLessThanOrEqual(remaining, 24 * 3600)
    }

    func testDayPassRefundRevokesAccessEvenWithTheLocalMirror() async throws {
        let trialStore = MemoryTrialStore()
        let dayPassStore = MemoryDayPassStore()
        let manager = PurchaseManager(
            entitlementProvider: StoreKitEntitlementProvider(
                trial: { ProTrialService(store: trialStore).state() },
                dayPass: { ProDayPassService(store: dayPassStore).expiresAt() }
            ),
            trialService: ProTrialService(store: trialStore),
            dayPassService: ProDayPassService(store: dayPassStore)
        )
        await manager.loadPlans()
        await manager.purchase(plan: .dayPass)
        XCTAssertTrue(manager.isPro)
        XCTAssertNotNil(dayPassStore.record)

        let transaction = try XCTUnwrap(session.allTransactions()
            .first { $0.productIdentifier == ProPlan.dayPass.productID })
        try session.refundTransaction(identifier: transaction.identifier)

        let revoked = await waitUntil {
            await manager.refreshEntitlement()
            return !manager.isPro
        }
        XCTAssertTrue(revoked, "a refunded day pass must not stay active through the Keychain mirror")
        // Transaction.updates may not replay in a test host, so the adapter deliberately keeps
        // the mirror. The verified revocation in Transaction.all must still win.
    }

    func testWeeklySubscriptionPurchaseReportsSubscriptionAccess() async throws {
        let manager = PurchaseManager()
        await manager.loadPlans()
        await manager.purchase(plan: .weekly)

        XCTAssertEqual(manager.purchaseState, .success)
        XCTAssertTrue(manager.isPro)
        XCTAssertEqual(manager.access.source, .subscription)
        XCTAssertEqual(manager.access.plan, .weekly)
        let expiresAt = try XCTUnwrap(manager.access.expiresAt)
        XCTAssertGreaterThan(expiresAt.timeIntervalSinceNow, 6 * 24 * 3600)
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

    // Offer-code purchase options ship with the newer StoreKitTest SDK. The Xcode 16.4 CI
    // compatibility job still compiles and runs the rest of the purchase suite; the current
    // SDK jobs run this zero-price entitlement test.
    #if compiler(>=6.2)
    func testFreeOfferCodeGrantsVerifiedPro() async throws {
        guard #available(iOS 27.0, *) else {
            throw XCTSkip("The iOS 18–26 StoreKitTest runtime ignores local offer codes and charges the list price. The same zero-price redemption is verified on iOS 27.3; production redemption is checked against App Store Connect.")
        }
        let transaction = try await session.buyProduct(
            identifier: Self.productID,
            options: [.codeOffer(referenceName: "DEVELOPER_FREE")]
        )
        XCTAssertEqual(transaction.productID, Self.productID)
        XCTAssertEqual(transaction.price, 0, "The offer code must be a 100% free redemption")
        XCTAssertNil(transaction.revocationDate)
        XCTAssertNil(transaction.expirationDate)

        // Off-device StoreKitTest purchases can return before the transaction cache updates.
        let verified = await waitUntil { await StoreKitEntitlementProvider().isPro() }
        XCTAssertTrue(verified, "A verified zero-price offer transaction must unlock Pro")

        let manager = PurchaseManager()
        await manager.start()
        XCTAssertTrue(manager.isPro)
    }
    #endif

    func testCancelledPurchaseDoesNotGrantPro() async throws {
        try await session.setSimulatedError(SKTestFailures.Purchase.generic(.userCancelled), forAPI: .purchase)
        let manager = PurchaseManager()
        await manager.start()
        await manager.loadProduct()

        await manager.purchase()

        XCTAssertEqual(manager.purchaseState, .cancelled)
        XCTAssertFalse(manager.isPro)
        // iOS 18/26 StoreKitTest keeps a non-success attempt in allTransactions(); it must never
        // leave a completed transaction. Only purchased/restored entries can grant an entitlement.
        XCTAssertTrue(completedTransactions().isEmpty, transactionDump())
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
        XCTAssertTrue(completedTransactions().isEmpty, transactionDump())
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
        if !unlocked {
            if #available(iOS 26.0, *) {
                XCTFail("Approved purchase did not unlock Pro through Transaction.updates")
            } else {
                // StoreKitTest on iOS 18.5 does not push an approved Ask to Buy purchase into
                // Transaction.updates for this host, but the verified entitlement is present.
                // Verify that recovery path explicitly instead of weakening newer runtimes.
                let verified = await waitUntil { await StoreKitEntitlementProvider().isPro() }
                XCTAssertTrue(verified, "The approved transaction must still be a verified entitlement")
                await manager.refreshEntitlement()
            }
        }
        XCTAssertTrue(manager.isPro)
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

    func testClearingPurchaseHistoryRestoresFreeAccess() async throws {
        let manager = PurchaseManager()
        await manager.start()
        await manager.loadProduct()
        await manager.purchase()
        XCTAssertTrue(manager.isPro)

        session.clearTransactions()

        let cleared = await waitUntil {
            await manager.refreshEntitlement()
            return !manager.isPro
        }
        XCTAssertTrue(cleared)
        XCTAssertEqual(manager.access.source, .none)
        let stillPro = await StoreKitEntitlementProvider().isPro()
        XCTAssertFalse(stillPro)
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

    private func completedTransactions() -> [SKTestTransaction] {
        session.allTransactions().filter { $0.state == .purchased || $0.state == .restored }
    }

    private func transactionDump() -> String {
        let rows = session.allTransactions().map {
            "\($0.productIdentifier):state=\($0.state.rawValue):pending=\($0.pendingAskToBuyConfirmation)"
        }
        return "Completed transactions must be empty; recorded: \(rows.joined(separator: ", "))"
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

/// In-memory ledgers so plan purchase tests never leave trial or day pass records in the
/// simulator Keychain.
private final class MemoryTrialStore: ProTrialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: ProTrial?

    func load() -> ProTrial? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func save(_ trial: ProTrial) throws {
        lock.lock(); defer { lock.unlock() }
        value = trial
    }

    func clear() throws {
        lock.lock(); defer { lock.unlock() }
        value = nil
    }
}

private final class MemoryDayPassStore: ProDayPassStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: ProDayPass?

    func load() -> ProDayPass? {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    var record: ProDayPass? { load() }

    func save(_ pass: ProDayPass) throws {
        lock.lock(); defer { lock.unlock() }
        value = pass
    }

    func clear() throws {
        lock.lock(); defer { lock.unlock() }
        value = nil
    }
}