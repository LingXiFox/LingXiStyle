import Foundation
import Security

/// Cross-process daily allowance ledger backed by the Keychain.
///
/// A daily limit is represented by stable slot accounts (slot.<day>.<index>). Adding a slot is
/// a single SecItemAdd, and the Keychain guarantees that only one process can create a given
/// account. That makes reserve atomic across the app, Share Extension and App Intents without a
/// shared writable database. Committed and in-flight reservations are separate states so the UI
/// can show the same numbers as the SQLite store.
///
/// The store deliberately keeps item values tiny (one short pipe-separated record). Keychain is
/// not a general-purpose database, but five slots per day is well within its intended use.
final class KeychainQuotaStore: @unchecked Sendable {
    static let defaultService = "com.lingxifox.LingXiStyle.quota"

    private enum SlotState: String {
        case reserved
        case committed
    }

    private struct Slot {
        let account: String
        let day: String
        let index: Int
        let id: String
        let state: SlotState
        let createdAt: Date
    }

    private let service: String
    private let accessGroup: String?
    private let limit: Int
    private let calendar: Calendar
    private let fixedTimeZone: TimeZone?
    private let now: @Sendable () -> Date
    private let lock = NSLock()

    init(service: String = KeychainQuotaStore.defaultService,
         accessGroup: String? = KeychainQuotaStore.defaultAccessGroup(),
         limit: Int = QuotaConfiguration.freeDailyLimit,
         calendar: Calendar = .current,
         timeZone: TimeZone? = nil,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.service = service
        self.accessGroup = accessGroup
        self.limit = max(1, limit)
        self.calendar = calendar
        self.fixedTimeZone = timeZone
        self.now = now
    }

    /// Reads the team-prefixed group from the target's Info.plist. The build setting expands to
    /// e.g. TEAMID.com.lingxifox.Texel.shared; unsigned test builds have no group and fall
    /// back to the process default Keychain group. Simulator builds signed by Xcode carry the
    /// same simulated entitlement as device builds, so the production path is exercised there.
    static func defaultAccessGroup(bundle: Bundle = .main) -> String? {
        accessGroup(from: bundle.object(forInfoDictionaryKey: "LingXiKeychainGroup") as? String)
    }

    /// An unexpanded build setting is not a usable access group. Returning nil is safer than
    /// asking the Keychain for a group the target cannot access.
    static func accessGroup(from raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("$(") else { return nil }
        // A real keychain group always starts with the 10-character team prefix. An unsigned
        // build expands $(AppIdentifierPrefix) to nothing, and asking for that bare group would
        // fail with errSecMissingEntitlement instead of falling back to the process keychain.
        guard let prefix = value.split(separator: ".", maxSplits: 1).first,
              prefix.count == 10,
              prefix.allSatisfy({ $0.isNumber || ("A"..."Z").contains($0) }) else { return nil }
        return value
    }

    // MARK: Public API

    func status(isPro: Bool) throws -> QuotaStatus {
        if isPro { return .unlimited(limit: limit) }
        lock.lock()
        defer { lock.unlock() }
        try cleanupExpiredSlots()
        let day = dayKey(for: now())
        var used = 0
        var reserved = 0
        for slot in try allSlots() where slot.day == day {
            switch slot.state {
            case .committed: used += 1
            case .reserved: reserved += 1
            }
        }
        return QuotaStatus(isPro: false, limit: limit, used: used, reserved: reserved)
    }

    /// Returns nil for Pro. Throws .exhausted only after every slot account is occupied.
    func reserve(isPro: Bool) throws -> QuotaReservation? {
        if isPro { return nil }
        lock.lock()
        defer { lock.unlock() }
        try cleanupExpiredSlots()
        let day = dayKey(for: now())
        for index in 0..<limit {
            let account = accountName(day: day, index: index)
            let id = UUID().uuidString
            let createdAt = now()
            var attributes = baseQuery(account: account)
            attributes[kSecValueData as String] = payload(id: id, state: .reserved, createdAt: createdAt)
            attributes[kSecAttrGeneric as String] = genericTag(id: id, state: .reserved)
            attributes[kSecAttrLabel as String] = "LingXiStyle daily quota"
            #if os(iOS)
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            #endif
            let result = SecItemAdd(attributes as CFDictionary, nil)
            if result == errSecSuccess {
                return QuotaReservation(id: id, day: day, slot: index)
            }
            if result == errSecDuplicateItem { continue }
            throw keychainError(result, operation: "reserve")
        }
        throw QuotaError.exhausted(limit: limit)
    }

    /// Commits exactly the reservation that still owns the slot. A second commit, an expired
    /// reservation, or a reservation that was already released is a no-op.
    func commit(_ reservation: QuotaReservation?) throws {
        guard let reservation, let index = reservation.slot else { return }
        lock.lock()
        defer { lock.unlock() }
        let account = accountName(day: reservation.day, index: index)
        var query = baseQuery(account: account)
        query[kSecAttrGeneric as String] = genericTag(id: reservation.id, state: .reserved)
        let attributes: [String: Any] = [
            kSecValueData as String: payload(id: reservation.id, state: .committed, createdAt: now()),
            kSecAttrGeneric as String: genericTag(id: reservation.id, state: .committed)
        ]
        let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound { return }
        guard result == errSecSuccess else {
            throw keychainError(result, operation: "commit")
        }
    }

    /// Releases only a still-reserved slot. Once committed, the generic tag changes and a late
    /// release cannot erase the used slot.
    func release(_ reservation: QuotaReservation?) throws {
        guard let reservation, let index = reservation.slot else { return }
        lock.lock()
        defer { lock.unlock() }
        var query = baseQuery(account: accountName(day: reservation.day, index: index))
        query[kSecAttrGeneric as String] = genericTag(id: reservation.id, state: .reserved)
        let result = SecItemDelete(query as CFDictionary)
        if result == errSecItemNotFound { return }
        guard result == errSecSuccess else {
            throw keychainError(result, operation: "release")
        }
    }

    /// Testing hook. Removes every slot for this service; production cleanup is per-slot.
    func removeAllItems() {
        lock.lock()
        defer { lock.unlock() }
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        SecItemDelete(query as CFDictionary)
    }

    // MARK: Keychain

    private func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private func allSlots() throws -> [Slot] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let rows = result as? [[String: Any]] else {
            throw keychainError(status, operation: "read")
        }
        var slots: [Slot] = []
        for row in rows {
            guard let account = row[kSecAttrAccount as String] as? String,
                  let data = row[kSecValueData as String] as? Data,
                  let parsed = parse(account: account, data: data) else { continue }
            slots.append(parsed)
        }
        return slots
    }

    private func cleanupExpiredSlots() throws {
        let currentDay = dayKey(for: now())
        let reservationCutoff = now().addingTimeInterval(-QuotaConfiguration.reservationLifetime)
        let oldDayCutoff = now().addingTimeInterval(-24 * 60 * 60)
        for slot in try allSlots() {
            let expiredReservation = slot.day == currentDay
                && slot.state == .reserved
                && slot.createdAt < reservationCutoff
            let oldSlot = slot.day != currentDay && slot.createdAt < oldDayCutoff
            guard expiredReservation || oldSlot else { continue }
            var query = baseQuery(account: slot.account)
            query[kSecAttrGeneric as String] = genericTag(id: slot.id, state: slot.state)
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                throw keychainError(status, operation: "cleanup")
            }
        }
    }

    private func payload(id: String, state: SlotState, createdAt: Date) -> Data {
        Data("v1|\(id)|\(state.rawValue)|\(Int(createdAt.timeIntervalSince1970))".utf8)
    }

    private func genericTag(id: String, state: SlotState) -> Data {
        Data("\(id)|\(state.rawValue)".utf8)
    }

    private func parse(account: String, data: Data) -> Slot? {
        let components = account.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0] == "slot",
              let index = Int(components[2]) else { return nil }
        let day = String(components[1])
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let parts = text.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 4,
              parts[0] == "v1",
              let state = SlotState(rawValue: String(parts[2])),
              let seconds = TimeInterval(parts[3]) else { return nil }
        return Slot(account: account,
                    day: day,
                    index: index,
                    id: String(parts[1]),
                    state: state,
                    createdAt: Date(timeIntervalSince1970: seconds))
    }

    private func accountName(day: String, index: Int) -> String {
        "slot.\(day).\(index)"
    }

    private func dayKey(for date: Date) -> String {
        var calendar = calendar
        calendar.timeZone = fixedTimeZone ?? .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      components.year ?? 0,
                      components.month ?? 0,
                      components.day ?? 0)
    }

    private func keychainError(_ status: OSStatus, operation: String) -> QuotaError {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        return .database("Keychain \(operation) failed: \(detail)")
    }
}
