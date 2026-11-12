import Foundation

public enum TaskOrigin: String, Codable, Sendable {
    case app
    case shortcut
    case share
    case mac
}

public enum ConversionTaskState: String, Codable, Sendable {
    case running
    /// Every convertible item produced a result, but the photos are not written back yet.
    case waitingToSave
    case completed
    case partiallyCompleted
    case failed
    case cancelled
    /// The app died while the task was running; the journal caught it on the next launch.
    case interrupted
}

public enum ConversionItemState: String, Codable, Sendable {
    case pending
    case converting
    case saving
    case saved
    case failed
    case cancelled
    case skipped
    case deferred
    case interrupted
}

/// Whether this item has spent a free slot. The journal records the intent, not just the result,
/// so a crash between the Photos write and the quota commit is never charged twice.
public enum QuotaSettlement: String, Codable, Sendable {
    case none
    case reserved
    case committed
    case released
}

public struct TaskItemRecord: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var displayName: String
    public var isLivePhoto: Bool
    public var livePhotoMode: String?
    public var state: ConversionItemState
    public var failureCode: String?
    public var failureMessage: String?
    public var vaultRecordID: UUID?
    public var savedAssetIdentifier: String?
    public var outputByteCount: Int?
    public var quotaReservationID: String?
    public var quotaDay: String?
    public var quotaSlot: Int?
    public var quotaState: QuotaSettlement

    public init(
        id: UUID = UUID(),
        displayName: String,
        isLivePhoto: Bool = false,
        livePhotoMode: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.isLivePhoto = isLivePhoto
        self.livePhotoMode = livePhotoMode
        self.state = .pending
        self.quotaState = .none
    }

    public var quotaReservation: QuotaReservation? {
        guard quotaState == .reserved,
              let quotaReservationID,
              let quotaDay else { return nil }
        return QuotaReservation(id: quotaReservationID, day: quotaDay, slot: quotaSlot)
    }

    public mutating func attachReservation(_ reservation: QuotaReservation) {
        quotaReservationID = reservation.id
        quotaDay = reservation.day
        quotaSlot = reservation.slot
        quotaState = .reserved
    }

    /// A result exists in the vault, so the item can be finished without converting again.
    public var hasRecoverableResult: Bool { vaultRecordID != nil }
}

public struct ConversionTaskRecord: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var origin: TaskOrigin
    public var isPro: Bool
    public var state: ConversionTaskState
    public var items: [TaskItemRecord]

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        origin: TaskOrigin = .app,
        isPro: Bool = false,
        items: [TaskItemRecord] = []
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.origin = origin
        self.isPro = isPro
        self.state = .running
        self.items = items
    }

    public var itemCount: Int { items.count }
    public var savedCount: Int { items.filter { $0.state == .saved }.count }
    public var failedCount: Int { items.filter { $0.state == .failed || $0.state == .interrupted }.count }
    public var cancelledCount: Int { items.filter { $0.state == .cancelled }.count }
    public var pendingCount: Int {
        items.filter { $0.state == .pending || $0.state == .converting || $0.state == .saving }.count
    }
    public var isActive: Bool { state == .running || state == .waitingToSave }
    public var totalByteCount: Int { items.reduce(0) { $0 + ($1.outputByteCount ?? 0) } }

    /// Items whose conversion survived, so a retry only needs to save them again.
    public var recoverableItems: [TaskItemRecord] {
        items.filter { $0.state == .interrupted && $0.hasRecoverableResult }
    }

    /// Derives the finished state from the item states. Callers pass isCancelled because a
    /// cancelled task keeps that label even when a few items had already saved.
    public func resolvedState(isCancelled: Bool, now: Date = Date()) -> ConversionTaskState {
        if pendingCount > 0 { return .running }
        if isCancelled { return .cancelled }
        let saved = savedCount
        let failed = failedCount
        if saved > 0, failed > 0 { return .partiallyCompleted }
        if saved > 0 { return .completed }
        if failed > 0 { return .failed }
        if items.contains(where: { $0.state == .cancelled }) { return .cancelled }
        return .completed
    }

    public mutating func applyResolvedState(isCancelled: Bool, now: Date = Date()) {
        state = resolvedState(isCancelled: isCancelled, now: now)
        updatedAt = now
    }
}

/// What the app must settle after a crash: reservations that were never attached to a result are
/// released, reservations for a saved item are committed, and results already in the vault are
/// reported so the UI can offer a one-tap save without converting or charging again.
public struct TaskRecovery: Sendable, Equatable {
    public let task: ConversionTaskRecord
    public let reservationsToRelease: [QuotaReservation]
    public let reservationsToCommit: [QuotaReservation]

    public init(
        task: ConversionTaskRecord,
        reservationsToRelease: [QuotaReservation],
        reservationsToCommit: [QuotaReservation]
    ) {
        self.task = task
        self.reservationsToRelease = reservationsToRelease
        self.reservationsToCommit = reservationsToCommit
    }
}

/// Append-only task ledger stored as one JSON file.
///
/// A single file keeps the write path small enough to be atomic on every platform: the journal
/// writes to a temporary file and replaces the old one, so a power loss leaves either the old
/// ledger or the new one, never a truncated mix.
public final class TaskJournal: @unchecked Sendable {
    public static let fileName = "tasks.json"

    public let storeURL: URL
    private let fileManager: FileManager
    private let maxRecords: Int
    private let lock = NSLock()

    public init(storeURL: URL, fileManager: FileManager = .default, maxRecords: Int = 200) {
        self.storeURL = storeURL
        self.fileManager = fileManager
        self.maxRecords = max(1, maxRecords)
    }

    public static func defaultStoreURL(fileManager: FileManager = .default) -> URL {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Texel", isDirectory: true)
            .appendingPathComponent("Tasks", isDirectory: true)
            .appendingPathComponent(Self.fileName)
    }

    // MARK: - Reading

    public func tasks() -> [ConversionTaskRecord] {
        lock.lock()
        defer { lock.unlock() }
        return loadLocked().sorted { $0.createdAt > $1.createdAt }
    }

    public func task(id: UUID) -> ConversionTaskRecord? {
        tasks().first { $0.id == id }
    }

    public func activeTasks() -> [ConversionTaskRecord] {
        tasks().filter { $0.isActive }
    }

    // MARK: - Writing

    @discardableResult
    public func upsert(_ task: ConversionTaskRecord) throws -> ConversionTaskRecord {
        lock.lock()
        defer { lock.unlock() }
        var all = loadLocked()
        var stored = task
        stored.updatedAt = Date()
        if let index = all.firstIndex(where: { $0.id == stored.id }) {
            all[index] = stored
        } else {
            all.append(stored)
        }
        all = Self.trimmed(all, keeping: maxRecords)
        try saveLocked(all)
        return stored
    }

    @discardableResult
    public func mutate(
        taskID: UUID,
        now: Date = Date(),
        _ transform: (inout ConversionTaskRecord) -> Void
    ) throws -> ConversionTaskRecord? {
        lock.lock()
        defer { lock.unlock() }
        var all = loadLocked()
        guard let index = all.firstIndex(where: { $0.id == taskID }) else { return nil }
        transform(&all[index])
        all[index].updatedAt = now
        let updated = all[index]
        try saveLocked(all)
        return updated
    }

    public func remove(id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        var all = loadLocked()
        all.removeAll { $0.id == id }
        try saveLocked(all)
    }

    public func removeAll() throws {
        lock.lock()
        defer { lock.unlock() }
        try saveLocked([])
    }

    /// Drops records older than the retention window. Running tasks are always kept.
    @discardableResult
    public func prune(olderThan cutoff: Date) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        var all = loadLocked()
        let before = all.count
        all.removeAll { $0.createdAt < cutoff && !$0.isActive }
        if all.count != before { try saveLocked(all) }
        return before - all.count
    }

    // MARK: - Crash recovery

    /// Converts every task that was still running at launch into an interrupted task and reports
    /// the quota reservations the caller must settle. Idempotent: a second call finds nothing.
    @discardableResult
    public func recoverInterrupted(at date: Date = Date()) throws -> [TaskRecovery] {
        lock.lock()
        defer { lock.unlock() }
        var all = loadLocked()
        var recoveries: [TaskRecovery] = []
        var changed = false
        for index in all.indices where all[index].isActive {
            var task = all[index]
            var toRelease: [QuotaReservation] = []
            var toCommit: [QuotaReservation] = []
            for itemIndex in task.items.indices {
                var item = task.items[itemIndex]
                switch item.state {
                case .pending, .converting, .saving:
                    item.state = .interrupted
                case .saved, .failed, .cancelled, .skipped, .deferred, .interrupted:
                    break
                }
                if item.quotaState == .reserved, let reservation = item.quotaReservation {
                    if item.state == .saved {
                        toCommit.append(reservation)
                    } else {
                        // Only a confirmed save settles a slot. Anything else gives the slot
                        // back immediately instead of holding it until the 30 minute expiry,
                        // and a vaulted result stays re-savable for free.
                        item.quotaState = .released
                        toRelease.append(reservation)
                    }
                }
                task.items[itemIndex] = item
            }
            task.state = .interrupted
            task.updatedAt = date
            all[index] = task
            changed = true
            recoveries.append(TaskRecovery(
                task: task,
                reservationsToRelease: toRelease,
                reservationsToCommit: toCommit
            ))
        }
        if changed { try saveLocked(all) }
        return recoveries
    }

    // MARK: - Private

    private func loadLocked() -> [ConversionTaskRecord] {
        guard let data = try? Data(contentsOf: storeURL) else { return [] }
        do {
            return try Self.decoder().decode([ConversionTaskRecord].self, from: data)
        } catch {
            // Keep the damaged ledger for diagnosis instead of silently overwriting history.
            let quarantine = storeURL.deletingLastPathComponent()
                .appendingPathComponent("tasks.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? fileManager.moveItem(at: storeURL, to: quarantine)
            return []
        }
    }

    private func saveLocked(_ tasks: [ConversionTaskRecord]) throws {
        try fileManager.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.encoder().encode(tasks)
        try data.write(to: storeURL, options: .atomic)
    }

    private static func trimmed(_ tasks: [ConversionTaskRecord], keeping limit: Int) -> [ConversionTaskRecord] {
        guard tasks.count > limit else { return tasks }
        let sorted = tasks.sorted { $0.createdAt > $1.createdAt }
        let keep = sorted.prefix(limit)
        let active = sorted.filter { $0.isActive }
        var merged = Dictionary(uniqueKeysWithValues: keep.map { ($0.id, $0) })
        for task in active where merged[task.id] == nil { merged[task.id] = task }
        return Array(merged.values)
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}