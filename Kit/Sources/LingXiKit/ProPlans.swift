import Foundation
import Security

/// The four ways a user can hold Pro. Prices are never stored here: the paywall must always
/// render `Product.displayPrice` for the storefront that is actually being used.
public enum ProPlan: String, CaseIterable, Codable, Sendable, Identifiable {
    case dayPass = "day"
    case weekly = "weekly"
    case monthly = "monthly"
    case lifetime = "lifetime"

    public var id: String { rawValue }

    /// The lifetime product keeps its 1.x identifier so existing owners are never asked to buy again.
    public var productID: String {
        switch self {
        case .lifetime: return ProProduct.identifier
        case .dayPass: return "com.lingxifox.LingXiStyle.pro.day"
        case .weekly: return "com.lingxifox.LingXiStyle.pro.weekly"
        case .monthly: return "com.lingxifox.LingXiStyle.pro.monthly"
        }
    }

    public var isSubscription: Bool {
        self == .weekly || self == .monthly
    }

    public var displayName: String {
        switch self {
        case .dayPass: return String(localized: "24 小时通行证", defaultValue: "24 小时通行证")
        case .weekly: return String(localized: "周订阅", defaultValue: "周订阅")
        case .monthly: return String(localized: "月订阅", defaultValue: "月订阅")
        case .lifetime: return String(localized: "永久版", defaultValue: "永久版")
        }
    }

    public var periodDescription: String {
        switch self {
        case .dayPass: return String(localized: "一次购买，24 小时内不限张数", defaultValue: "一次购买，24 小时内不限张数")
        case .weekly: return String(localized: "自动续订，按周计费", defaultValue: "自动续订，按周计费")
        case .monthly: return String(localized: "自动续订，按月计费", defaultValue: "自动续订，按月计费")
        case .lifetime: return String(localized: "一次购买，永久不限张数", defaultValue: "一次购买，永久不限张数")
        }
    }

    public var badge: String? {
        switch self {
        case .dayPass: return String(localized: "先试一天", defaultValue: "先试一天")
        case .monthly: return String(localized: "最灵活", defaultValue: "最灵活")
        case .lifetime: return String(localized: "一次到位", defaultValue: "一次到位")
        case .weekly: return nil
        }
    }

    public static func plan(forProductID id: String) -> ProPlan? {
        allCases.first { $0.productID == id }
    }
}

/// One verified StoreKit transaction reduced to the facts the access evaluator needs. Keeping
/// this away from `Transaction` makes the entitlement rules unit-testable without StoreKit.
public struct ProEntitlementRecord: Sendable, Equatable {
    public let productID: String
    public let purchaseDate: Date
    public let expirationDate: Date?
    public let revocationDate: Date?

    public init(productID: String, purchaseDate: Date, expirationDate: Date?, revocationDate: Date?) {
        self.productID = productID
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
        self.revocationDate = revocationDate
    }
}

/// What the app is allowed to unlock right now.
public struct ProAccessSnapshot: Sendable, Equatable {
    public enum Source: String, Codable, Sendable, Equatable {
        case none
        case lifetime
        case subscription
        case dayPass
        case trial
    }

    public let source: Source
    public let plan: ProPlan?
    /// `nil` for the lifetime purchase; always set for time-limited access.
    public let expiresAt: Date?

    public init(source: Source, plan: ProPlan?, expiresAt: Date?) {
        self.source = source
        self.plan = plan
        self.expiresAt = expiresAt
    }

    public static let free = ProAccessSnapshot(source: .none, plan: nil, expiresAt: nil)

    public var isActive: Bool { source != .none }
    public var isLifetime: Bool { source == .lifetime }
    public var isTrial: Bool { source == .trial }

    public func isActive(at date: Date) -> Bool {
        guard isActive else { return false }
        guard let expiresAt else { return true }
        return expiresAt > date
    }

    public func remainingLifetime(at date: Date) -> TimeInterval? {
        guard isActive, let expiresAt else { return nil }
        return max(0, expiresAt.timeIntervalSince(date))
    }
}

/// Pure entitlement rules. Any single active source is enough; a lifetime purchase always wins
/// so refunds of shorter products can never downgrade an owner.
public enum ProAccessEvaluator {
    public static let dayPassDuration: TimeInterval = 24 * 60 * 60
    public static let trialDuration: TimeInterval = 24 * 60 * 60

    public static func snapshot(records: [ProEntitlementRecord],
                                trial: ProTrial?,
                                storedDayPassExpiry: Date? = nil,
                                now: Date) -> ProAccessSnapshot {
        let active = records.filter { record in
            record.revocationDate == nil &&
            (record.expirationDate == nil || record.expirationDate! > now)
        }

        if active.contains(where: { $0.productID == ProPlan.lifetime.productID }) {
            return ProAccessSnapshot(source: .lifetime, plan: .lifetime, expiresAt: nil)
        }

        let subscriptions = active.compactMap { record -> (ProPlan, Date, Date)? in
            guard let plan = ProPlan.plan(forProductID: record.productID),
                  plan.isSubscription,
                  let expiration = record.expirationDate else { return nil }
            return (plan, record.purchaseDate, expiration)
        }
        // If StoreKit briefly reports both the old and the new plan during a switch, the most
        // recent purchase is the plan the user chose; expiry only breaks ties.
        if let best = subscriptions.max(by: { ($0.1, $0.2) < ($1.1, $1.2) }) {
            return ProAccessSnapshot(source: .subscription, plan: best.0, expiresAt: best.2)
        }

        let purchasedDayPassExpiry = active
            .filter { $0.productID == ProPlan.dayPass.productID }
            .map { $0.purchaseDate.addingTimeInterval(dayPassDuration) }
            .max()
        // A refund removes the transaction from currentEntitlements but leaves the local
        // Keychain mirror behind. If the newest day-pass transaction was revoked, ignore the
        // mirror so a refunded pass cannot keep Pro alive until its old expiry.
        let latestDayPass = records
            .filter { $0.productID == ProPlan.dayPass.productID }
            .max { $0.purchaseDate < $1.purchaseDate }
        let usableStoredDayPassExpiry = latestDayPass?.revocationDate == nil ? storedDayPassExpiry : nil
        let dayPassExpiry = [purchasedDayPassExpiry, usableStoredDayPassExpiry]
            .compactMap { $0 }
            .filter { $0 > now }
            .max()
        if let dayPassExpiry {
            return ProAccessSnapshot(source: .dayPass, plan: .dayPass, expiresAt: dayPassExpiry)
        }

        if let trial, trial.expiresAt > now {
            return ProAccessSnapshot(source: .trial, plan: nil, expiresAt: trial.expiresAt)
        }

        return .free
    }
}

/// A one-time, per-device Pro trial. It is claimed explicitly by the user, starts when the
/// confirmation is accepted, and never turns into a subscription or a charge.
public struct ProTrial: Codable, Sendable, Equatable {
    public let claimedAt: Date
    public let expiresAt: Date
    /// Random, device-scoped token. It exists only to keep the record identifiable and is never
    /// derived from hardware identifiers.
    public let deviceSeed: String

    public init(claimedAt: Date, expiresAt: Date, deviceSeed: String) {
        self.claimedAt = claimedAt
        self.expiresAt = expiresAt
        self.deviceSeed = deviceSeed
    }
}

public enum ProTrialState: Sendable, Equatable {
    case eligible
    case active(ProTrial)
    case expired(ProTrial)

    public var trial: ProTrial? {
        switch self {
        case .eligible: return nil
        case .active(let trial), .expired(let trial): return trial
        }
    }

    public func isActive(at date: Date) -> Bool {
        switch self {
        case .active(let trial): return trial.expiresAt > date
        case .eligible, .expired: return false
        }
    }
}

public enum ProTrialError: LocalizedError, Equatable, Sendable {
    case alreadyClaimed
    case storage

    public var errorDescription: String? {
        switch self {
        case .alreadyClaimed:
            return String(localized: "这台设备已经领取过免费体验。", defaultValue: "这台设备已经领取过免费体验。")
        case .storage:
            return String(localized: "无法保存体验记录，请稍后重试。", defaultValue: "无法保存体验记录，请稍后重试。")
        }
    }
}

/// The trial ledger lives in the Keychain so deleting and reinstalling the app does not hand out
/// a second trial. Tests inject an in-memory store.
public protocol ProTrialStoring: Sendable {
    func load() -> ProTrial?
    func save(_ trial: ProTrial) throws
    func clear() throws
}

public struct ProTrialService: Sendable {
    private let store: any ProTrialStoring
    private let now: @Sendable () -> Date

    public init(store: any ProTrialStoring, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.now = now
    }

    /// Keychain-backed ledger, scoped to the host bundle so an app and its test host never share
    /// a trial record.
    public static func live(bundle: Bundle = .main) -> ProTrialService {
        ProTrialService(store: KeychainTrialStore(bundle: bundle))
    }

    public func state() -> ProTrialState {
        guard let trial = store.load() else { return .eligible }
        return trial.expiresAt > now() ? .active(trial) : .expired(trial)
    }

    public func claim() throws -> ProTrial {
        switch state() {
        case .eligible:
            break
        case .active, .expired:
            throw ProTrialError.alreadyClaimed
        }
        let claimedAt = now()
        let trial = ProTrial(claimedAt: claimedAt,
                             expiresAt: claimedAt.addingTimeInterval(ProAccessEvaluator.trialDuration),
                             deviceSeed: UUID().uuidString)
        try store.save(trial)
        return trial
    }
}

/// The app and its share extension have different bundle IDs but must read the same
/// per-device trial and day-pass ledger. Test hosts keep their own scope.
enum ProLedgerScope {
    static func ownerBundleID(for bundle: Bundle) -> String {
        ownerBundleID(for: bundle.bundleIdentifier ?? "unknown")
    }

    static func ownerBundleID(for identifier: String) -> String {
        if identifier.hasSuffix(".Share") {
            return String(identifier.dropLast(".Share".count))
        }
        return identifier
    }
}

final class KeychainTrialStore: ProTrialStoring, @unchecked Sendable {
    static let defaultService = "com.lingxifox.LingXiStyle.trial"

    private let service: String
    private let account: String
    private let accessGroup: String?
    private let lock = NSLock()

    init(service: String = KeychainTrialStore.defaultService,
         bundle: Bundle = .main) {
        self.service = service
        self.account = "trial." + ProLedgerScope.ownerBundleID(for: bundle)
        self.accessGroup = KeychainQuotaStore.defaultAccessGroup(bundle: bundle)
    }

    func load() -> ProTrial? {
        lock.lock()
        defer { lock.unlock() }
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(ProTrial.self, from: data)
    }

    func save(_ trial: ProTrial) throws {
        lock.lock()
        defer { lock.unlock() }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(trial)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw ProTrialError.storage }
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
            throw ProTrialError.storage
        }
    }

    func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProTrialError.storage
        }
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}
/// A day pass is a non-renewing purchase. StoreKit 2 keeps the latest transaction for a
/// non-renewing subscription in `Transaction.currentEntitlements`, even after it finishes, so
/// the verified purchase date restores the same 24-hour window on every device signed in to
/// the same Apple ID. The Keychain mirror is a local fallback for the moment between a
/// successful purchase and StoreKit publishing the transaction; it is not a cross-device store.
/// One activated day pass. The transaction identifier makes activation idempotent: a replayed
/// StoreKit update can never buy the same purchase twice.
public struct ProDayPass: Codable, Sendable, Equatable {
    public let expiresAt: Date
    public let activatedAt: Date
    public let transactionID: String?

    public init(expiresAt: Date, activatedAt: Date, transactionID: String?) {
        self.expiresAt = expiresAt
        self.activatedAt = activatedAt
        self.transactionID = transactionID
    }
}

public protocol ProDayPassStoring: Sendable {
    func load() -> ProDayPass?
    func save(_ pass: ProDayPass) throws
    func clear() throws
}

public enum ProDayPassError: LocalizedError, Equatable, Sendable {
    case storage

    public var errorDescription: String? {
        switch self {
        case .storage:
            return String(localized: "无法保存通行证记录，请稍后重试。", defaultValue: "无法保存通行证记录，请稍后重试。")
        }
    }
}

public struct ProDayPassService: Sendable {
    private let store: any ProDayPassStoring
    private let now: @Sendable () -> Date

    public init(store: any ProDayPassStoring, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.now = now
    }

    public static func live(bundle: Bundle = .main) -> ProDayPassService {
        ProDayPassService(store: KeychainDayPassStore(bundle: bundle))
    }

    /// The stored record, even after it expired. Used for diagnostics and for extending a window.
    public func record() -> ProDayPass? {
        store.load()
    }

    /// Active deadline, or nil when no pass has been activated or the pass already ran out.
    public func expiresAt() -> Date? {
        guard let expiry = store.load()?.expiresAt, expiry > now() else { return nil }
        return expiry
    }
    /// Clears the mirror only when it belongs to the revoked transaction, so a late update for
    /// an old pass cannot wipe a newer, active purchase.
    public func clear(ifTransactionID transactionID: String) throws {
        guard let existing = store.load(), existing.transactionID == transactionID else { return }
        try store.clear()
    }

    /// Buys 24 more hours on top of whatever is still left, so a second purchase never shortens
    /// an active window. Activating the same transaction twice is a no-op, which keeps replayed
    /// StoreKit updates from stacking free time.
    @discardableResult
    public func activate(transactionID: String? = nil, purchasedAt: Date? = nil) throws -> Date {
        let existing = store.load()
        if let transactionID,
           let existing,
           existing.transactionID == transactionID,
           existing.expiresAt > now() {
            return existing.expiresAt
        }
        let current = now()
        // StoreKit's purchase date is issued by Apple; using it for the fallback window keeps a
        // manually changed device clock from stretching the paid 24 hours.
        let start = purchasedAt ?? current
        let base = max(start, existing?.expiresAt ?? start)
        let pass = ProDayPass(expiresAt: base.addingTimeInterval(ProAccessEvaluator.dayPassDuration),
                              activatedAt: current,
                              transactionID: transactionID)
        try store.save(pass)
        return pass.expiresAt
    }
}

final class KeychainDayPassStore: ProDayPassStoring, @unchecked Sendable {
    static let defaultService = "com.lingxifox.LingXiStyle.daypass"

    private let service: String
    private let account: String
    private let accessGroup: String?
    private let lock = NSLock()

    init(service: String = KeychainDayPassStore.defaultService,
         bundle: Bundle = .main) {
        self.service = service
        self.account = "daypass." + ProLedgerScope.ownerBundleID(for: bundle)
        self.accessGroup = KeychainQuotaStore.defaultAccessGroup(bundle: bundle)
    }

    func load() -> ProDayPass? {
        lock.lock()
        defer { lock.unlock() }
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(ProDayPass.self, from: data)
    }

    func save(_ pass: ProDayPass) throws {
        lock.lock()
        defer { lock.unlock() }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(pass)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw ProDayPassError.storage }
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
            throw ProDayPassError.storage
        }
    }

    func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ProDayPassError.storage
        }
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

