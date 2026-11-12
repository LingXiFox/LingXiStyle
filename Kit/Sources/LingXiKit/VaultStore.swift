import Foundation

/// How long a converted result stays in the in-app vault.
///
/// The vault exists because the only copy of a conversion used to be the photo we wrote into the
/// user's library. If that photo is later deleted, or the save itself fails, the result is gone.
public enum VaultRetention: Int, CaseIterable, Codable, Sendable, Identifiable {
    case threeDays = 3
    case sevenDays = 7
    case fourteenDays = 14
    case thirtyDays = 30
    /// Keep results until the user deletes them or the device runs out of space.
    case forever = 0

    public static var allCases: [VaultRetention] {
        [.threeDays, .sevenDays, .fourteenDays, .thirtyDays, .forever]
    }

    public static let standard: VaultRetention = .sevenDays

    public var id: Int { rawValue }

    /// nil means "no automatic expiry".
    public var dayCount: Int? { self == .forever ? nil : rawValue }

    public var timeInterval: TimeInterval? {
        guard let dayCount else { return nil }
        return TimeInterval(dayCount) * 24 * 60 * 60
    }

    public func expiration(from date: Date) -> Date {
        guard let timeInterval else { return .distantFuture }
        return date.addingTimeInterval(timeInterval)
    }

    /// Localized label for settings and the vault retention menu.
    public var title: String {
        switch self {
        case .threeDays:
            return String(localized: "vault.retention.threeDays", defaultValue: "保留 3 天")
        case .sevenDays:
            return String(localized: "vault.retention.sevenDays", defaultValue: "保留 7 天")
        case .fourteenDays:
            return String(localized: "vault.retention.fourteenDays", defaultValue: "保留 14 天")
        case .thirtyDays:
            return String(localized: "vault.retention.thirtyDays", defaultValue: "保留 30 天")
        case .forever:
            return String(localized: "vault.retention.forever", defaultValue: "永久保留")
        }
    }
}

/// One converted result kept inside the app container.
///
/// A Live Photo record owns both the still and the paired video so restoring it produces a real
/// Live Photo instead of a flattened image.
public struct VaultRecord: Codable, Identifiable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case still
        case livePhoto
    }

    public let id: UUID
    public let createdAt: Date
    public internal(set) var expiresAt: Date
    public let displayName: String
    public let kind: Kind
    public let photoFileName: String
    public let videoFileName: String?
    public let photoByteCount: Int
    public let videoByteCount: Int?
    /// Raw value of LivePhotoProcessingMode. nil for stills and for older records.
    public let livePhotoMode: String?
    /// Links the record back to its task so cleanup never removes work that is still in flight.
    public let sourceTaskID: UUID?
    public let sourceItemID: UUID?
    public internal(set) var retention: VaultRetention
    public internal(set) var savedAssetIdentifier: String?
    public internal(set) var lastSavedAt: Date?
    /// How many times the record was written back to Photos. Re-saving never consumes quota,
    /// but the count is useful when diagnosing duplicate-looking libraries.
    public internal(set) var saveCount: Int

    public var totalByteCount: Int { photoByteCount + (videoByteCount ?? 0) }
    public var isLivePhoto: Bool { kind == .livePhoto }

    public func isExpired(at date: Date = Date()) -> Bool { expiresAt <= date }

    public func remainingLifetime(at date: Date = Date()) -> TimeInterval? {
        guard expiresAt != .distantFuture else { return nil }
        return max(0, expiresAt.timeIntervalSince(date))
    }
}

public struct VaultPurgeResult: Sendable, Equatable {
    public let removedCount: Int
    public let freedByteCount: Int
    public let failedCount: Int

    public init(removedCount: Int = 0, freedByteCount: Int = 0, failedCount: Int = 0) {
        self.removedCount = removedCount
        self.freedByteCount = freedByteCount
        self.failedCount = failedCount
    }
}

public enum VaultError: LocalizedError, Equatable, Sendable {
    case missingPhoto
    case insufficientSpace(required: Int64, available: Int64)
    case recordNotFound
    case storageUnavailable

    public var errorDescription: String? {
        switch self {
        case .missingPhoto:
            return String(localized: "转换结果文件已不存在，无法放入成果保险箱。")
        case let .insufficientSpace(required, available):
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return String(
                format: String(localized: "设备可用空间不足，存放这一项需要 %@，当前可用 %@。请清理空间后重试。"),
                formatter.string(fromByteCount: required),
                formatter.string(fromByteCount: available)
            )
        case .recordNotFound:
            return String(localized: "保险箱中的这条成果已经不存在了。")
        case .storageUnavailable:
            return String(localized: "无法访问 App 存储目录，请重启 App 后重试。")
        }
    }
}

/// File-backed vault for converted results.
///
/// Layout: root/<uuid>/metadata.json plus photo.<ext> and, for Live Photos, video.<ext>.
/// Writes go to a staging directory and are published with a single directory rename, so a crash
/// can never leave a half-written record that the UI would list as restorable.
public final class VaultStore: @unchecked Sendable {
    public static let metadataFileName = "metadata.json"
    public static let stagingDirectoryName = ".staging"
    /// Headroom kept free on the volume so the system and the Photos write still have room.
    public static let requiredHeadroom: Int64 = 32 * 1024 * 1024

    public let rootURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    /// Application Support is the right home: it survives relaunches, is not user-visible in
    /// Files, and is removed with the app. The directory is excluded from iCloud backup because
    /// the same pixels already live in the user's photo library.
    public static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("Texel", isDirectory: true)
            .appendingPathComponent("Vault", isDirectory: true)
    }

    // MARK: - Paths

    public func directoryURL(for record: VaultRecord) -> URL {
        rootURL.appendingPathComponent(record.id.uuidString, isDirectory: true)
    }

    public func photoURL(for record: VaultRecord) -> URL {
        directoryURL(for: record).appendingPathComponent(record.photoFileName)
    }

    public func videoURL(for record: VaultRecord) -> URL? {
        record.videoFileName.map { directoryURL(for: record).appendingPathComponent($0) }
    }

    // MARK: - Reading

    /// Newest first. Corrupt or half-removed records are skipped instead of failing the listing,
    /// so one bad directory cannot hide the rest of the vault.
    public func records() throws -> [VaultRecord] {
        lock.lock()
        defer { lock.unlock() }
        return try loadRecordsLocked().sorted { $0.createdAt > $1.createdAt }
    }

    public func record(id: UUID) throws -> VaultRecord? {
        lock.lock()
        defer { lock.unlock() }
        return try loadRecordsLocked().first { $0.id == id }
    }

    public func totalByteCount() throws -> Int {
        try records().reduce(0) { $0 + $1.totalByteCount }
    }

    /// Capacity that matters for a user-facing "can I keep this?" decision; nil when the volume
    /// cannot report it (for example some network volumes).
    public func availableByteCount() -> Int64? {
        try? rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }

    // MARK: - Writing

    @discardableResult
    public func insert(
        photoURL: URL,
        videoURL: URL? = nil,
        displayName: String,
        livePhotoMode: String? = nil,
        sourceTaskID: UUID? = nil,
        sourceItemID: UUID? = nil,
        retention: VaultRetention = .standard,
        now: Date = Date()
    ) throws -> VaultRecord {
        let photoSize = Self.fileSize(at: photoURL)
        guard photoSize > 0 else { throw VaultError.missingPhoto }
        let videoSize = videoURL.map { Self.fileSize(at: $0) } ?? 0
        if videoURL != nil, videoSize <= 0 { throw VaultError.missingPhoto }
        let required = Int64(photoSize + videoSize) + Self.requiredHeadroom
        if let available = availableByteCount(), available > 0, available < required {
            throw VaultError.insufficientSpace(required: required, available: available)
        }

        lock.lock()
        defer { lock.unlock() }

        try prepareRootLocked()

        let id = UUID()
        let stagingRoot = rootURL.appendingPathComponent(Self.stagingDirectoryName, isDirectory: true)
        let stagingURL = stagingRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        try? fileManager.removeItem(at: stagingURL)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)

        let photoFileName = "photo." + Self.normalizedExtension(of: photoURL)
        do {
            try fileManager.copyItem(at: photoURL, to: stagingURL.appendingPathComponent(photoFileName))
            var videoFileName: String?
            if let videoURL {
                let name = "video." + Self.normalizedExtension(of: videoURL)
                try fileManager.copyItem(at: videoURL, to: stagingURL.appendingPathComponent(name))
                videoFileName = name
            }

            let record = VaultRecord(
                id: id,
                createdAt: now,
                expiresAt: retention.expiration(from: now),
                displayName: displayName,
                kind: videoFileName == nil ? .still : .livePhoto,
                photoFileName: photoFileName,
                videoFileName: videoFileName,
                photoByteCount: photoSize,
                videoByteCount: videoFileName == nil ? nil : videoSize,
                livePhotoMode: livePhotoMode,
                sourceTaskID: sourceTaskID,
                sourceItemID: sourceItemID,
                retention: retention,
                savedAssetIdentifier: nil,
                lastSavedAt: nil,
                saveCount: 0
            )
            let metadata = try Self.encoder().encode(record)
            try metadata.write(to: stagingURL.appendingPathComponent(Self.metadataFileName), options: .atomic)

            let destination = rootURL.appendingPathComponent(id.uuidString, isDirectory: true)
            try fileManager.moveItem(at: stagingURL, to: destination)
            return record
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
    }

    /// Records a successful write back to Photos. Never touches quota.
    @discardableResult
    public func markSaved(id: UUID, assetIdentifier: String?, at date: Date = Date()) throws -> VaultRecord {
        lock.lock()
        defer { lock.unlock() }
        var all = try loadRecordsLocked()
        guard let index = all.firstIndex(where: { $0.id == id }) else { throw VaultError.recordNotFound }
        all[index].saveCount += 1
        all[index].lastSavedAt = date
        if let assetIdentifier {
            all[index].savedAssetIdentifier = assetIdentifier
        }
        try writeMetadataLocked(all[index])
        return all[index]
    }

    /// Applies a new policy to every existing record. Shortening never deletes results on the
    /// spot: the new window starts now, so changing a setting cannot wipe the vault by accident.
    @discardableResult
    public func applyRetention(_ retention: VaultRetention, now: Date = Date()) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        var all = try loadRecordsLocked()
        for index in all.indices {
            all[index].retention = retention
            all[index].expiresAt = retention.expiration(from: now)
            try writeMetadataLocked(all[index])
        }
        return all.count
    }

    /// Removes expired records. Records whose task is still running are never touched, even if
    /// their timestamp is old, because the task may still need to commit or repair them.
    @discardableResult
    public func purgeExpired(now: Date = Date(), keepingTaskIDs: Set<UUID> = []) throws -> VaultPurgeResult {
        lock.lock()
        defer { lock.unlock() }
        var removed = 0
        var freed = 0
        var failed = 0
        for record in try loadRecordsLocked() where record.expiresAt <= now {
            if let taskID = record.sourceTaskID, keepingTaskIDs.contains(taskID) { continue }
            do {
                try fileManager.removeItem(at: directoryURL(for: record))
                removed += 1
                freed += record.totalByteCount
            } catch {
                failed += 1
            }
        }
        return VaultPurgeResult(removedCount: removed, freedByteCount: freed, failedCount: failed)
    }

    public func delete(id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let record = try loadRecordsLocked().first(where: { $0.id == id }) else {
            throw VaultError.recordNotFound
        }
        try fileManager.removeItem(at: directoryURL(for: record))
    }

    public func deleteAll() throws {
        lock.lock()
        defer { lock.unlock() }
        guard fileManager.fileExists(atPath: rootURL.path) else { return }
        for name in try fileManager.contentsOfDirectory(atPath: rootURL.path)
        where name != Self.stagingDirectoryName {
            try? fileManager.removeItem(at: rootURL.appendingPathComponent(name))
        }
    }

    // MARK: - Private

    private func prepareRootLocked() throws {
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(
                at: rootURL.appendingPathComponent(Self.stagingDirectoryName, isDirectory: true),
                withIntermediateDirectories: true
            )
        } catch {
            throw VaultError.storageUnavailable
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableRoot = rootURL
        try? mutableRoot.setResourceValues(values)
    }

    private func loadRecordsLocked() throws -> [VaultRecord] {
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
        let names = try fileManager.contentsOfDirectory(atPath: rootURL.path)
        let decoder = Self.decoder()
        var records: [VaultRecord] = []
        for name in names where name != Self.stagingDirectoryName {
            let metadataURL = rootURL
                .appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent(Self.metadataFileName)
            guard let data = try? Data(contentsOf: metadataURL),
                  let record = try? decoder.decode(VaultRecord.self, from: data) else { continue }
            records.append(record)
        }
        return records
    }

    private func writeMetadataLocked(_ record: VaultRecord) throws {
        let data = try Self.encoder().encode(record)
        try data.write(
            to: directoryURL(for: record).appendingPathComponent(Self.metadataFileName),
            options: .atomic
        )
    }

    private static func normalizedExtension(of url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? "heic" : ext
    }

    private static func fileSize(at url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}