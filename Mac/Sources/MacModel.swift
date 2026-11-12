import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import LingXiEngine
import LingXiKit
import LingXiServices

/// State for the macOS build. It reuses the same conversion service, vault, task journal and
/// entitlement stack as the iPhone app; only the presentation and the file-based import/export
/// differ, because the desktop app never touches PhotoKit.
@MainActor
final class MacModel: ObservableObject {
    enum Screen: Equatable {
        case idle
        case converting
        case result
    }

    enum ItemState: Equatable {
        case inspecting
        case ready
        case unsupported(String)
        case converting(ConversionStage)
        case saved
        case failed(String)
        case cancelled
        case deferred
    }

    struct Item: Identifiable {
        let id: UUID
        let url: URL
        let videoURL: URL?
        let displayName: String
        var byteCount: Int?
        var isSecurityScoped: Bool
        var state: ItemState
        var outputURL: URL?
        var outputVideoURL: URL?
        var vaultRecordID: UUID?

        var isLivePhoto: Bool { videoURL != nil }
        var isSaved: Bool { state == .saved }
        var failureMessage: String? {
            if case .failed(let message) = state { return message }
            return nil
        }
        var isRetryable: Bool {
            switch state {
            case .failed, .cancelled, .deferred: return true
            default: return false
            }
        }
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var screen: Screen = .idle
    @Published private(set) var isConverting = false
    @Published private(set) var isCancelling = false
    @Published private(set) var quota: QuotaStatus = .unavailable()
    @Published private(set) var vaultRecords: [VaultRecord] = []
    @Published private(set) var history: [ConversionTaskRecord] = []
    @Published private(set) var vaultRetention: VaultRetention = .standard
    @Published private(set) var exportFolder: URL?
    @Published private(set) var livePhotoMode: LivePhotoProcessingMode = .defaultMode
    @Published var notice: String?
    @Published var isPurchasePresented = false
    @Published var previewRecord: VaultRecord?
    @Published var isDropTargeted = false
    @Published var isImportPresented = false
    @Published var isFolderImportPresented = false

    let purchases = PurchaseManager()
    let vaultStore: VaultStore
    let taskJournal: TaskJournal

    private let service = ConversionService.shared
    private var conversionTask: Task<Void, Never>?
    private var currentTaskID: UUID?
    private var exportFolderAccess = false

    static let retentionKey = "LingXiStyle.vaultRetention"
    static let livePhotoModeKey = "LingXiStyle.livePhotoMode"
    static let exportBookmarkKey = "LingXiStyle.macExportFolder"

    init() {
        let vault = VaultStore(rootURL: VaultStore.defaultRootURL())
        let journal = TaskJournal(storeURL: TaskJournal.defaultStoreURL())
        vaultStore = vault
        taskJournal = journal
        if let raw = UserDefaults.standard.object(forKey: Self.retentionKey) as? Int,
           let retention = VaultRetention(rawValue: raw) {
            vaultRetention = retention
        }
        if let raw = UserDefaults.standard.string(forKey: Self.livePhotoModeKey),
           let mode = LivePhotoProcessingMode(rawValue: raw) {
            livePhotoMode = mode
        }
        ConversionService.shared.configureStorage(vault: vault, journal: journal)
        resolveExportFolder()
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        await purchases.start()
        await purchases.loadPlans()
        await refreshQuota()
        recoverInterruptedTasks()
        refreshVault()
        refreshHistory()
    }

    func refreshQuota() async {
        quota = await service.quotaStatus()
    }

    // MARK: - Import

    func importFiles(_ urls: [URL]) {
        let files = urls.flatMap(Self.expand)
        guard !files.isEmpty else {
            notice = String(localized: "mac.notice.noHEIC",
                            defaultValue: "没有找到 HEIC 原片。纹粒只读取 HEIC，不做转码。")
            return
        }
        let existing = Set(items.map(\.url.standardizedFileURL))
        var added: [Item] = []
        for url in files where !existing.contains(url.standardizedFileURL) {
            let scoped = url.startAccessingSecurityScopedResource()
            let video = Self.pairedMovie(for: url)
            if let video { _ = video.startAccessingSecurityScopedResource() }
            let item = Item(id: UUID(),
                            url: url,
                            videoURL: video,
                            displayName: url.lastPathComponent,
                            byteCount: nil,
                            isSecurityScoped: scoped,
                            state: .inspecting,
                            outputURL: nil,
                            outputVideoURL: nil,
                            vaultRecordID: nil)
            added.append(item)
        }
        guard !added.isEmpty else { return }
        items.append(contentsOf: added)
        screen = .idle
        for item in added {
            inspect(itemID: item.id)
        }
    }

    private func inspect(itemID: UUID) {
        guard let item = items.first(where: { $0.id == itemID }) else { return }
        let url = item.url
        let traits = Self.traits(for: item)
        Task.detached(priority: .userInitiated) {
            let result: Result<InspectionOutcome, Error> = Result(catching: {
                try ConversionService.shared.inspect(fileURL: url, traits: traits)
            })
            await MainActor.run {
                guard let index = self.items.firstIndex(where: { $0.id == itemID }) else { return }
                switch result {
                case .success(let outcome):
                    self.items[index].byteCount = outcome.byteCount
                    self.items[index].state = outcome.verdict.isReady
                        ? .ready
                        : .unsupported(outcome.verdict.headline + " " + outcome.verdict.detail)
                case .failure(let error):
                    self.items[index].state = .unsupported(error.localizedDescription)
                }
            }
        }
    }

    private nonisolated static func traits(for item: Item) -> AssetTraits {
        AssetTraits(isLivePhoto: item.videoURL != nil,
                    livePhotoVideoAvailable: item.videoURL != nil,
                    originalIsHEIC: true)
    }

    /// A Live Photo imported from Finder is a HEIC next to a movie with the same stem.
    private static func pairedMovie(for url: URL) -> URL? {
        let folder = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let candidates = (try? FileManager.default.contentsOfDirectory(at: folder,
                                                                      includingPropertiesForKeys: nil)) ?? []
        return candidates.first { candidate in
            ["mov", "MOV"].contains(candidate.pathExtension)
                && candidate.deletingPathExtension().lastPathComponent == stem
        }
    }

    private static func expand(_ url: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return [] }
        if isDirectory.boolValue {
            let contents = (try? FileManager.default.contentsOfDirectory(at: url,
                                                                        includingPropertiesForKeys: nil,
                                                                        options: [.skipsHiddenFiles])) ?? []
            return contents
                .filter { ["heic", "heif"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        guard ["heic", "heif"].contains(url.pathExtension.lowercased()) else { return [] }
        return [url]
    }

    func remove(_ id: UUID) {
        guard !isConverting, let index = items.firstIndex(where: { $0.id == id }) else { return }
        releaseAccess(items[index])
        items.remove(at: index)
        if items.isEmpty { screen = .idle }
    }

    func removeAll() {
        guard !isConverting else { return }
        items.forEach(releaseAccess)
        items.removeAll()
        screen = .idle
    }

    private func releaseAccess(_ item: Item) {
        if item.isSecurityScoped { item.url.stopAccessingSecurityScopedResource() }
        if let video = item.videoURL { video.stopAccessingSecurityScopedResource() }
    }

    // MARK: - Export folder

    func setExportFolder(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        let bookmark = try? url.bookmarkData(options: .withSecurityScope,
                                             includingResourceValuesForKeys: nil,
                                             relativeTo: nil)
        if scoped { url.stopAccessingSecurityScopedResource() }
        if let bookmark {
            UserDefaults.standard.set(bookmark, forKey: Self.exportBookmarkKey)
        }
        exportFolder = url
    }

    private func resolveExportFolder() {
        guard let data = UserDefaults.standard.data(forKey: Self.exportBookmarkKey) else { return }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data,
                              options: [.withSecurityScope],
                              relativeTo: nil,
                              bookmarkDataIsStale: &stale) {
            exportFolder = url
        }
    }

    // MARK: - Conversion

    func startConversion() {
        guard !isConverting else { return }
        guard let folder = exportFolder else {
            notice = String(localized: "mac.notice.chooseFolder",
                            defaultValue: "先选择一个导出文件夹，转换结果会写在那里。")
            return
        }
        let candidates = items.filter { $0.state == .ready || $0.isRetryable }
        guard !candidates.isEmpty else { return }

        conversionTask = Task { [weak self] in
            await self?.run(items: candidates.map(\.id), folder: folder)
        }
    }

    func cancelConversion() {
        guard isConverting else { return }
        isCancelling = true
        conversionTask?.cancel()
    }

    func retryFailed() {
        guard !isConverting else { return }
        for index in items.indices where items[index].isRetryable {
            items[index].state = .ready
        }
        startConversion()
    }

    private func run(items ids: [UUID], folder: URL) async {
        guard !isConverting else { return }
        isConverting = true
        isCancelling = false
        screen = .converting
        defer {
            isConverting = false
            isCancelling = false
        }

        exportFolderAccess = folder.startAccessingSecurityScopedResource()

        let status = await service.quotaStatus()
        quota = status
        var allowance = status.isPro ? Int.max : max(0, status.remaining)
        if allowance == 0 {
            notice = String(localized: "mac.notice.quota",
                            defaultValue: "今天的 \(QuotaConfiguration.freeDailyLimit) 张免费额度已经用完，升级 Pro 后可继续。")
            screen = .idle
            stopExportAccess()
            return
        }

        let taskID = startTaskRecord(ids: ids, isPro: status.isPro)
        currentTaskID = taskID

        for id in ids {
            if Task.isCancelled { break }
            guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
            guard items[index].state == .ready || items[index].isRetryable else { continue }
            if allowance <= 0 {
                items[index].state = .deferred
                markJournalItem(id, state: .deferred)
                continue
            }

            items[index].state = .converting(.inspecting)
            let request = ConversionService.Request(
                fileURL: items[index].url,
                pairedVideoURL: items[index].videoURL,
                livePhotoMode: items[index].isLivePhoto ? livePhotoMode : nil,
                traits: Self.traits(for: items[index]),
                preferredName: Self.outputName(for: items[index].url),
                saveToLibrary: false,
                returnsFile: true,
                outputDirectory: folder,
                taskID: taskID,
                itemID: id,
                vaultRetention: vaultRetention
            )

            do {
                let result = try await self.service.convert(request) { [weak self] stage in
                    Task { @MainActor [weak self] in
                        self?.updateStage(id: id, stage: stage)
                    }
                }
                guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
                items[index].state = .saved
                items[index].outputURL = result.outputURL
                items[index].outputVideoURL = result.outputVideoURL
                items[index].vaultRecordID = result.vaultRecordID
                if !status.isPro, allowance != Int.max { allowance -= 1 }
            } catch is CancellationError {
                guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
                items[index].state = .cancelled
                markJournalItem(id, state: .cancelled)
            } catch {
                guard let index = items.firstIndex(where: { $0.id == id }) else { continue }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                items[index].state = .failed(message)
                markJournalItem(id, state: .failed,
                                failure: (Self.diagnosticCode(error), message))
            }
        }

        completeTaskRecord(isCancelled: Task.isCancelled)
        stopExportAccess()
        await refreshQuota()
        refreshVault()
        refreshHistory()
        screen = .result
    }

    private func updateStage(id: UUID, stage: ConversionStage) {
        guard isConverting, let index = items.firstIndex(where: { $0.id == id }) else { return }
        if case .converting = items[index].state {
            items[index].state = .converting(stage)
        }
    }

    private func stopExportAccess() {
        if exportFolderAccess, let folder = exportFolder {
            folder.stopAccessingSecurityScopedResource()
            exportFolderAccess = false
        }
    }

    static func outputName(for url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        let base = stem.hasSuffix("_TextureGrain") ? stem : stem + "_TextureGrain"
        return base + ".HEIC"
    }

    private static func diagnosticCode(_ error: Error) -> String {
        if let failure = error as? ConversionFailure {
            switch failure {
            case .quota(let quota): return quota.diagnosticCode
            case .unsupported: return "E_UNSUPPORTED"
            case .corrupted: return "E_CORRUPTED"
            case .unreadable: return "E_UNREADABLE"
            case .verificationFailed: return "E_INTEGRITY"
            case .writeFailed: return "E_WRITE"
            case .livePhotoVideo: return "E_LIVE_PHOTO_VIDEO"
            case .engine, .engineMessage: return "E_ENGINE"
            }
        }
        return "E_UNKNOWN"
    }

    // MARK: - Task journal

    private func startTaskRecord(ids: [UUID], isPro: Bool) -> UUID {
        let records = ids.compactMap { id -> TaskItemRecord? in
            guard let item = items.first(where: { $0.id == id }) else { return nil }
            return TaskItemRecord(id: id,
                                  displayName: item.displayName,
                                  isLivePhoto: item.isLivePhoto,
                                  livePhotoMode: item.isLivePhoto ? livePhotoMode.rawValue : nil)
        }
        let task = ConversionTaskRecord(origin: .mac, isPro: isPro, items: records)
        _ = try? taskJournal.upsert(task)
        return task.id
    }

    private func markJournalItem(_ id: UUID,
                                 state: ConversionItemState,
                                 failure: (String, String)? = nil) {
        guard let taskID = currentTaskID else { return }
        try? taskJournal.mutate(taskID: taskID) { task in
            guard let index = task.items.firstIndex(where: { $0.id == id }) else { return }
            task.items[index].state = state
            if let failure {
                task.items[index].failureCode = failure.0
                task.items[index].failureMessage = failure.1
            }
        }
    }

    private func completeTaskRecord(isCancelled: Bool) {
        guard let taskID = currentTaskID,
              var task = try? taskJournal.task(id: taskID) else {
            currentTaskID = nil
            return
        }
        for index in task.items.indices {
            guard let item = items.first(where: { $0.id == task.items[index].id }) else { continue }
            switch item.state {
            case .saved: task.items[index].state = .saved
            case .failed(let message):
                task.items[index].state = .failed
                task.items[index].failureMessage = message
            case .cancelled: task.items[index].state = .cancelled
            case .deferred: task.items[index].state = .deferred
            case .unsupported(let message):
                task.items[index].state = .skipped
                task.items[index].failureMessage = message
            case .ready, .inspecting:
                task.items[index].state = isCancelled ? .cancelled : .skipped
            case .converting:
                task.items[index].state = isCancelled ? .cancelled : .interrupted
            }
        }
        task.applyResolvedState(isCancelled: isCancelled)
        _ = try? taskJournal.upsert(task)
        currentTaskID = nil
        refreshHistory()
    }

    private func recoverInterruptedTasks() {
        guard let recoveries = try? taskJournal.recoverInterrupted(), !recoveries.isEmpty else { return }
        for recovery in recoveries {
            for reservation in recovery.reservationsToRelease {
                try? QuotaManager.shared.release(reservation)
            }
            for reservation in recovery.reservationsToCommit {
                try? QuotaManager.shared.commit(reservation)
            }
        }
        notice = String(localized: "mac.notice.recovered",
                        defaultValue: "上次退出时有 \(recoveries.count) 个任务没有结束，已标记为中断；失败的照片不会扣额度。")
        refreshHistory()
    }

    func refreshHistory() {
        history = ((try? taskJournal.tasks()) ?? []).filter { !$0.isActive }
    }

    // MARK: - Vault

    func refreshVault() {
        vaultRecords = (try? vaultStore.records()) ?? []
    }

    var vaultByteCount: Int {
        (try? vaultStore.totalByteCount()) ?? 0
    }

    var vaultAvailable: Int64? {
        vaultStore.availableByteCount()
    }

    func setRetention(_ retention: VaultRetention) {
        vaultRetention = retention
        UserDefaults.standard.set(retention.rawValue, forKey: Self.retentionKey)
        _ = try? vaultStore.applyRetention(retention)
        refreshVault()
    }

    func setLivePhotoMode(_ mode: LivePhotoProcessingMode) {
        livePhotoMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.livePhotoModeKey)
    }

    func purgeExpired() {
        let keeping = Set((try? taskJournal.activeTasks().map(\.id)) ?? [])
        guard let result = try? vaultStore.purgeExpired(keepingTaskIDs: keeping) else { return }
        notice = String(localized: "mac.notice.purged",
                        defaultValue: "已清理 \(result.removedCount) 项过期成果，释放 \(Self.byteText(result.freedByteCount))。")
        refreshVault()
    }

    func delete(_ record: VaultRecord) {
        try? vaultStore.delete(id: record.id)
        if previewRecord?.id == record.id { previewRecord = nil }
        refreshVault()
    }

    func reveal(_ record: VaultRecord) {
        let url = vaultStore.photoURL(for: record)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Exporting a vault record never charges the allowance again.
    func export(_ record: VaultRecord) {
        let photo = vaultStore.photoURL(for: record)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = record.displayName
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "heic") ?? .image]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: photo, to: destination)
            if let video = vaultStore.videoURL(for: record) {
                let movie = destination.deletingPathExtension().appendingPathExtension("MOV")
                if FileManager.default.fileExists(atPath: movie.path) {
                    try FileManager.default.removeItem(at: movie)
                }
                try FileManager.default.copyItem(at: video, to: movie)
            }
            notice = String(localized: "mac.notice.exported",
                            defaultValue: "已导出到 \(destination.deletingLastPathComponent().path)。")
        } catch {
            notice = error.localizedDescription
        }
    }

    func clearVault() {
        try? vaultStore.deleteAll()
        refreshVault()
    }

    static func byteText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Shared with the vault rows; days/hours/minutes keep the same three catalog keys as iOS.
    nonisolated static func lifetimeText(_ interval: TimeInterval) -> String {
        let seconds = max(0, interval)
        let days = Int(seconds / 86_400)
        if days >= 1 {
            return String(localized: "vault.lifetime.days", defaultValue: "\(days) 天")
        }
        let hours = Int(seconds / 3_600)
        if hours >= 1 {
            return String(localized: "vault.lifetime.hours", defaultValue: "\(hours) 小时")
        }
        let minutes = max(1, Int(seconds / 60))
        return String(localized: "vault.lifetime.minutes", defaultValue: "\(minutes) 分钟")
    }

    // MARK: - Pro

    func purchase(_ plan: ProPlan) async {
        await purchases.purchase(plan: plan)
        await refreshQuota()
    }

    func claimTrial() async {
        _ = await purchases.claimTrial()
        await refreshQuota()
    }

    func restore() async {
        await purchases.restore()
        await refreshQuota()
    }
}
