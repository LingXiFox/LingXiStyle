import Foundation
import SQLite3

/// Central, testable policy values. The daily allowance lives here so raising it later is one
/// edit rather than a hunt through UI copy.
public enum QuotaConfiguration {
    public static let freeDailyLimit = 10
    public static let appGroupIdentifier = "group.com.lingxifox.LingXiStyle"
    /// A reservation older than this is treated as abandoned. Conversions normally finish in
    /// seconds; the window only protects against a crash between reserve and commit.
    public static let reservationLifetime: TimeInterval = 30 * 60
}

public struct QuotaStatus: Sendable, Equatable {
    public let isPro: Bool
    public let limit: Int
    public let used: Int
    public let reserved: Int
    /// False when the local quota store could not be read. The UI must not pretend the user has
    /// a full allowance in that case.
    public let isAvailable: Bool

    public init(isPro: Bool,
                limit: Int,
                used: Int,
                reserved: Int,
                isAvailable: Bool = true) {
        self.isPro = isPro
        self.limit = limit
        self.used = max(0, used)
        self.reserved = max(0, reserved)
        self.isAvailable = isAvailable
    }

    public static func unlimited(limit: Int = QuotaConfiguration.freeDailyLimit) -> QuotaStatus {
        QuotaStatus(isPro: true, limit: limit, used: 0, reserved: 0)
    }

    public static func unavailable(limit: Int = QuotaConfiguration.freeDailyLimit) -> QuotaStatus {
        QuotaStatus(isPro: false, limit: limit, used: 0, reserved: 0, isAvailable: false)
    }

    /// Includes in-flight reservations so a second entry point cannot spend the same slot.
    public var remaining: Int {
        if isPro { return Int.max }
        guard isAvailable else { return 0 }
        return max(0, limit - used - reserved)
    }

    public var isExhausted: Bool {
        !isPro && isAvailable && remaining <= 0
    }

    /// A finite number for the home-screen "10 / 10" badge; Pro uses its own label.
    public var remainingForDisplay: Int {
        isPro ? limit : remaining
    }
}

public enum QuotaError: Error, LocalizedError, Sendable, Equatable {
    case exhausted(limit: Int)
    case unavailable
    case database(String)

    public var errorDescription: String? {
        switch self {
        case .exhausted:
            return "今日免费额度已用完。明天会按本地时间重置，也可以永久解锁无限转换。"
        case .unavailable:
            return "暂时无法读取今日免费额度，请稍后重试。"
        case .database:
            return "额度存储出现异常，请稍后重试。"
        }
    }

    public var diagnosticCode: String {
        switch self {
        case .exhausted: return "E_QUOTA_EXHAUSTED"
        case .unavailable: return "E_QUOTA_UNAVAILABLE"
        case .database: return "E_QUOTA_STORE"
        }
    }
}

public struct QuotaReservation: Sendable, Equatable {
    public let id: String
    public let day: String
    /// Keychain storage uses a stable slot index; SQLite storage leaves this nil.
    public let slot: Int?

    public init(id: String, day: String, slot: Int? = nil) {
        self.id = id
        self.day = day
        self.slot = slot
    }
}

public protocol QuotaManaging: Sendable {
    func status(isPro: Bool) throws -> QuotaStatus
    func reserve(isPro: Bool) throws -> QuotaReservation?
    func commit(_ reservation: QuotaReservation?) throws
    func release(_ reservation: QuotaReservation?) throws
}

public enum QuotaStorageKind: String, Sendable {
    case appGroupDatabase
    case localDatabase
    case keychain
}

/// Daily allowance shared by the app, Share Extension and App Shortcuts.
///
/// When an App Group container is available (paid developer team with the entitlement), the
/// shared SQLite store is used: every mutation runs in its own connection with BEGIN IMMEDIATE,
/// so check-and-reserve is atomic across processes. On a free Personal Team the App Group
/// entitlement is not available, so the default falls back to a Keychain slot ledger. Both
/// backends enforce the same limit and use atomic creation; UserDefaults is deliberately not
/// used because read-modify-write there cannot enforce a cross-process limit.
public final class QuotaManager: QuotaManaging, @unchecked Sendable {
    public static let shared = QuotaManager()

    public let databaseURL: URL?
    public let usesAppGroupContainer: Bool
    public let storageKind: QuotaStorageKind
    public let limit: Int
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let keychainStore: KeychainQuotaStore?
    private let lock = NSLock()
    private var initializationError: QuotaError?

    public init(databaseURL: URL? = nil,
                limit: Int = QuotaConfiguration.freeDailyLimit,
                calendar: Calendar = .current,
                now: @escaping @Sendable () -> Date = { Date() }) {
        let resolved: (url: URL?, usesAppGroup: Bool, kind: QuotaStorageKind)
        if let databaseURL {
            resolved = (databaseURL, false, .localDatabase)
        } else if let appGroupURL = Self.appGroupDatabaseURL() {
            resolved = (appGroupURL, true, .appGroupDatabase)
        } else {
            resolved = (nil, false, .keychain)
        }
        self.databaseURL = resolved.url
        self.usesAppGroupContainer = resolved.usesAppGroup
        self.storageKind = resolved.kind
        self.limit = max(1, limit)
        self.calendar = calendar
        self.now = now
        if resolved.kind == .keychain {
            self.keychainStore = KeychainQuotaStore(limit: self.limit, calendar: calendar, now: now)
        } else {
            self.keychainStore = nil
            if let url = resolved.url {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
            }
            initializeStore()
        }
    }

    // MARK: Public API

    public func status(isPro: Bool) throws -> QuotaStatus {
        if isPro { return .unlimited(limit: limit) }
        if let keychainStore {
            return try keychainStore.status(isPro: false)
        }
        if let initializationError { throw initializationError }
        lock.lock()
        defer { lock.unlock() }
        do {
            let db = try openDatabase()
            defer { sqlite3_close(db) }
            try cleanupExpiredReservations(on: db)
            let day = dayKey(for: now())
            let used = try scalarInt(on: db, sql: "SELECT COALESCE(used, 0) FROM quota_usage WHERE day = ?;", arguments: [day])
            let reserved = try scalarInt(on: db, sql: "SELECT COUNT(*) FROM quota_reservations WHERE day = ?;", arguments: [day])
            return QuotaStatus(isPro: false, limit: limit, used: used, reserved: reserved)
        } catch let error as QuotaError {
            throw error
        } catch {
            throw QuotaError.database(error.localizedDescription)
        }
    }

    /// Reserves one slot, or returns nil for Pro. Throws .exhausted without inserting anything
    /// when the current day is already full. The returned reservation must be committed on a
    /// successful conversion or released on every failure path.
    public func reserve(isPro: Bool) throws -> QuotaReservation? {
        if isPro { return nil }
        if let keychainStore {
            return try keychainStore.reserve(isPro: false)
        }
        if let initializationError { throw initializationError }
        lock.lock()
        defer { lock.unlock() }
        do {
            let db = try openDatabase()
            defer { sqlite3_close(db) }
            try execute(db, "BEGIN IMMEDIATE;")
            do {
                try cleanupExpiredReservations(on: db)
                let day = dayKey(for: now())
                let used = try scalarInt(on: db, sql: "SELECT COALESCE(used, 0) FROM quota_usage WHERE day = ?;", arguments: [day])
                let reserved = try scalarInt(on: db, sql: "SELECT COUNT(*) FROM quota_reservations WHERE day = ?;", arguments: [day])
                guard used + reserved < limit else {
                    try execute(db, "ROLLBACK;")
                    throw QuotaError.exhausted(limit: limit)
                }
                let reservation = QuotaReservation(id: UUID().uuidString, day: day)
                try execute(db,
                            "INSERT INTO quota_reservations (id, day, created_at) VALUES (?, ?, ?);",
                            arguments: [reservation.id, reservation.day, String(now().timeIntervalSince1970)])
                try execute(db, "COMMIT;")
                return reservation
            } catch {
                try? execute(db, "ROLLBACK;")
                throw error
            }
        } catch let error as QuotaError {
            throw error
        } catch {
            throw QuotaError.database(error.localizedDescription)
        }
    }

    /// Idempotent: committing an already-committed or expired reservation does nothing. That is
    /// important if a save succeeded and the process died just before the commit call.
    public func commit(_ reservation: QuotaReservation?) throws {
        guard let reservation else { return }
        if let keychainStore {
            try keychainStore.commit(reservation)
            return
        }
        if let initializationError { throw initializationError }
        lock.lock()
        defer { lock.unlock() }
        do {
            let db = try openDatabase()
            defer { sqlite3_close(db) }
            try execute(db, "BEGIN IMMEDIATE;")
            do {
                guard try reservationDay(on: db, id: reservation.id) != nil else {
                    try execute(db, "ROLLBACK;")
                    return
                }
                try execute(db,
                            "INSERT INTO quota_usage (day, used) VALUES (?, 1) ON CONFLICT(day) DO UPDATE SET used = used + 1;",
                            arguments: [reservation.day])
                try execute(db, "DELETE FROM quota_reservations WHERE id = ?;", arguments: [reservation.id])
                try execute(db, "COMMIT;")
            } catch {
                try? execute(db, "ROLLBACK;")
                throw error
            }
        } catch let error as QuotaError {
            throw error
        } catch {
            throw QuotaError.database(error.localizedDescription)
        }
    }

    public func release(_ reservation: QuotaReservation?) throws {
        guard let reservation else { return }
        if let keychainStore {
            try keychainStore.release(reservation)
            return
        }
        if let initializationError { throw initializationError }
        lock.lock()
        defer { lock.unlock() }
        do {
            let db = try openDatabase()
            defer { sqlite3_close(db) }
            try execute(db, "DELETE FROM quota_reservations WHERE id = ?;", arguments: [reservation.id])
        } catch let error as QuotaError {
            throw error
        } catch {
            throw QuotaError.database(error.localizedDescription)
        }
    }

    // MARK: Storage

    public static func defaultDatabaseURL(fileManager: FileManager = .default) -> (url: URL, usesAppGroup: Bool) {
        if let appGroupURL = appGroupDatabaseURL(fileManager: fileManager) {
            return (appGroupURL, true)
        }
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = support.appendingPathComponent("LingXiStyle", isDirectory: true)
        return (directory.appendingPathComponent("quota.sqlite"), false)
    }

    private static func appGroupDatabaseURL(fileManager: FileManager = .default) -> URL? {
        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: QuotaConfiguration.appGroupIdentifier) else {
            return nil
        }
        return container
            .appendingPathComponent("Quota", isDirectory: true)
            .appendingPathComponent("quota.sqlite")
    }

    // MARK: SQLite

    private func initializeStore() {
        guard databaseURL != nil else { return }
        do {
            let db = try openRawDatabase()
            defer { sqlite3_close(db) }
            // WAL is a database-level setting. Writing it on every connection would make
            // simultaneous app/extension opens contend for a write lock for no benefit.
            try execute(db, "PRAGMA journal_mode = WAL;")
            try prepareSchema(on: db)
        } catch let error as QuotaError {
            initializationError = error
        } catch {
            initializationError = .database(error.localizedDescription)
        }
    }

    private func openDatabase() throws -> OpaquePointer {
        try openRawDatabase()
    }

    private func openRawDatabase() throws -> OpaquePointer {
        guard let databaseURL else {
            throw QuotaError.database("Quota database is not configured")
        }
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开额度数据库"
            if let handle { sqlite3_close(handle) }
            throw QuotaError.database(message)
        }
        sqlite3_busy_timeout(handle, 5_000)
        do {
            try execute(handle, "PRAGMA synchronous = NORMAL;")
            return handle
        } catch {
            sqlite3_close(handle)
            throw error
        }
    }

    private func prepareSchema(on db: OpaquePointer) throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS quota_usage (
            day TEXT PRIMARY KEY NOT NULL,
            used INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS quota_reservations (
            id TEXT PRIMARY KEY NOT NULL,
            day TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS quota_reservations_day ON quota_reservations(day);
        """
        var message: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &message)
        if result != SQLITE_OK {
            let detail = message.map { String(cString: $0) } ?? sqliteMessage(db)
            sqlite3_free(message)
            throw QuotaError.database(detail)
        }
    }

    private func cleanupExpiredReservations(on db: OpaquePointer) throws {
        let cutoff = now().addingTimeInterval(-QuotaConfiguration.reservationLifetime).timeIntervalSince1970
        try execute(db, "DELETE FROM quota_reservations WHERE created_at < ?;", arguments: [String(cutoff)])
    }

    private func reservationDay(on db: OpaquePointer, id: String) throws -> String? {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT day FROM quota_reservations WHERE id = ?;", -1, &statement, nil) == SQLITE_OK else {
            throw QuotaError.database(sqliteMessage(db))
        }
        bind(statement, index: 1, value: id)
        let result = sqlite3_step(statement)
        if result == SQLITE_ROW { return columnString(statement, index: 0) }
        if result == SQLITE_DONE { return nil }
        throw QuotaError.database(sqliteMessage(db))
    }

    private func scalarInt(on db: OpaquePointer, sql: String, arguments: [String]) throws -> Int {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw QuotaError.database(sqliteMessage(db))
        }
        for (offset, value) in arguments.enumerated() {
            bind(statement, index: Int32(offset + 1), value: value)
        }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return 0 }
        guard result == SQLITE_ROW else {
            throw QuotaError.database(sqliteMessage(db))
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func execute(_ db: OpaquePointer, _ sql: String, arguments: [String] = []) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw QuotaError.database(sqliteMessage(db))
        }
        for (offset, value) in arguments.enumerated() {
            bind(statement, index: Int32(offset + 1), value: value)
        }
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW { result = sqlite3_step(statement) }
        guard result == SQLITE_DONE else {
            throw QuotaError.database(sqliteMessage(db))
        }
    }

    private func bind(_ statement: OpaquePointer?, index: Int32, value: String) {
        guard let statement else { return }
        _ = value.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, Self.sqliteTransient)
        }
    }

    private func columnString(_ statement: OpaquePointer?, index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: pointer)
    }

    private func sqliteMessage(_ db: OpaquePointer) -> String {
        String(cString: sqlite3_errmsg(db))
    }

    private func dayKey(for date: Date) -> String {
        var calendar = calendar
        calendar.timeZone = calendar.timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      components.year ?? 0,
                      components.month ?? 0,
                      components.day ?? 0)
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
