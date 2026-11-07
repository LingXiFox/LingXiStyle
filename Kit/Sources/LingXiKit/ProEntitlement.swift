import Foundation
import Combine
import StoreKit

public enum ProProduct {
    public static let identifier = "com.lingxifox.LingXiStyle.pro"
    public static var displayName: String { Brand.proName }
    public static var description: String { String(localized: "一次购买，永久不限张数。") }
}

/// The only source of truth for Pro. A local bool, a button callback, or an unverified JWS can
/// never turn this into true.
public protocol ProEntitlementProviding: Sendable {
    func isPro() async -> Bool
}

public struct StoreKitEntitlementProvider: ProEntitlementProviding {
    public init() {}

    public func isPro() async -> Bool {
        if #available(iOS 18.4, macOS 15.4, *) {
            for await result in Transaction.currentEntitlements(for: ProProduct.identifier) {
                if Self.isActiveEntitlement(result) { return true }
            }
            return false
        } else {
            for await result in Transaction.currentEntitlements {
                if Self.isActiveEntitlement(result) { return true }
            }
            return false
        }
    }

    private static func isActiveEntitlement(_ result: VerificationResult<Transaction>) -> Bool {
        guard case .verified(let transaction) = result else { return false }
        guard transaction.productID == ProProduct.identifier else { return false }
        return transaction.revocationDate == nil && transaction.expirationDate == nil
    }
}

@MainActor
public final class PurchaseManager: ObservableObject {
    public enum PurchaseState: Equatable {
        case idle
        case purchasing
        case awaitingApproval
        case success
        case cancelled
        case failed(String)
    }

    @Published public private(set) var product: Product?
    @Published public private(set) var isPro = false
    @Published public private(set) var isLoadingProduct = false
    @Published public private(set) var productLoadError: String?
    @Published public private(set) var purchaseState: PurchaseState = .idle
    @Published public private(set) var isRestoring = false
    @Published public private(set) var restoreMessage: String?

    public let productID: String
    private let entitlementProvider: any ProEntitlementProviding
    private var updatesTask: Task<Void, Never>?
    private var hasStarted = false

    public init(productID: String = ProProduct.identifier,
                entitlementProvider: any ProEntitlementProviding = StoreKitEntitlementProvider()) {
        self.productID = productID
        self.entitlementProvider = entitlementProvider
    }

    deinit {
        updatesTask?.cancel()
    }

    /// Starts the transaction listener and refreshes the verified entitlement. Safe to call on
    /// every foreground transition; it does not present a paywall or a purchase dialog.
    public func start() async {
        if !hasStarted {
            hasStarted = true
            updatesTask = Task { [weak self] in
                guard let self else { return }
                for await update in Transaction.updates {
                    await self.handle(update)
                }
            }
        }
        await refreshEntitlement()
    }

    public func refreshEntitlement() async {
        isPro = await entitlementProvider.isPro()
        // Ask to Buy approval can arrive while the app is backgrounded. iOS 18 does not always
        // replay that approval through Transaction.updates in a test host, so recover the visible
        // state from the verified entitlement instead of leaving the sheet on "awaiting approval".
        if isPro, purchaseState == .awaitingApproval {
            purchaseState = .success
        }
    }

    public func loadProduct() async {
        guard !isLoadingProduct else { return }
        isLoadingProduct = true
        productLoadError = nil
        defer { isLoadingProduct = false }
        do {
            let products = try await Product.products(for: [productID])
            guard let match = products.first(where: { $0.id == productID }) else {
                product = nil
                productLoadError = String(localized: "App Store 暂时没有返回这个商品，请稍后重试。")
                return
            }
            product = match
        } catch {
            product = nil
            productLoadError = Self.message(for: error, fallback: String(localized: "无法连接 App Store，请检查网络后重试。"))
        }
    }

    public func purchase() async {
        guard let product else {
            purchaseState = .failed(String(localized: "商品信息尚未加载，请稍后重试。"))
            return
        }
        guard purchaseState != .purchasing else { return }
        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification,
                      transaction.productID == productID,
                      transaction.revocationDate == nil else {
                    purchaseState = .failed(String(localized: "购买凭证未通过验证，未授予 Pro 权益。"))
                    return
                }
                await transaction.finish()
                await refreshEntitlement()
                purchaseState = isPro ? .success : .failed(String(localized: "交易已验证，但权益尚未生效，请稍后重试。"))
            case .pending:
                purchaseState = .awaitingApproval
            case .userCancelled:
                purchaseState = .cancelled
            @unknown default:
                purchaseState = .failed(String(localized: "购买返回了未知状态，请稍后重试。"))
            }
        } catch {
            if let storeError = error as? StoreKitError, case .userCancelled = storeError {
                purchaseState = .cancelled
            } else {
                purchaseState = .failed(Self.message(for: error, fallback: String(localized: "购买未完成，请稍后重试。")))
            }
        }
    }

    public func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        restoreMessage = nil
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            restoreMessage = isPro
                ? String(localized: "restore.success", defaultValue: "已恢复 \(Brand.proName) 权益。")
                : String(localized: "没有找到可恢复的购买记录。")
        } catch {
            restoreMessage = Self.message(for: error, fallback: String(localized: "恢复购买失败，请稍后重试。"))
        }
    }

    public func clearPurchaseMessage() {
        purchaseState = .idle
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        guard transaction.productID == productID else { return }
        // A refund or family-sharing revocation arrives as an update for the same transaction.
        // Never finish or celebrate it as a purchase; re-read StoreKit's current entitlement.
        if transaction.revocationDate != nil {
            await refreshEntitlement()
            if !isPro { purchaseState = .idle }
            return
        }
        await transaction.finish()
        await refreshEntitlement()
        if isPro { purchaseState = .success }
    }

    private static func message(for error: Error, fallback: String) -> String {
        if let storeError = error as? StoreKitError {
            // Pattern matching instead of a switch keeps this file buildable with both the
            // iOS 18.5 SDK (Xcode 16.4) and newer SDKs that add StoreKitError cases such as
            // invalidPresentationContext. Unknown future cases fall through to the caller copy.
            if case .networkError = storeError {
                return String(localized: "网络连接失败，请检查网络后重试。")
            }
            if case .notAvailableInStorefront = storeError {
                return String(localized: "当前 App Store 地区暂不支持这个商品。")
            }
            if case .userCancelled = storeError {
                return String(localized: "购买已取消。")
            }
            if case .systemError = storeError {
                return String(localized: "App Store 暂时不可用，请稍后重试。")
            }
            return fallback
        }
        if let purchaseError = error as? Product.PurchaseError {
            switch purchaseError {
            case .productUnavailable:
                return String(localized: "这个商品当前不可购买，请稍后重试。")
            case .purchaseNotAllowed:
                return String(localized: "当前设备不允许购买，请检查屏幕使用时间或家长控制。")
            default:
                return String(localized: "购买未完成，请稍后重试。")
            }
        }
        return fallback
    }
}