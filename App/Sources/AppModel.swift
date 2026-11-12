import Foundation
import SwiftUI
import ImageIO
import Photos
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import LingXiKit
import LingXiEngine
import LingXiServices

@MainActor
final class AppModel: ObservableObject {
    enum Screen: Equatable {
        case idle
        case selecting
        case converting
        case result
        case permissionDenied
    }

    @Published var screen: Screen = .idle
    @Published var items: [PhotoItem] = []
    @Published var selectedID: UUID?
    @Published var pickerSelection: [PhotosPickerItem] = []
    @Published var isImportingFiles = false
    @Published var summary: ConversionSummary?
    @Published var diagnosticsText: String?
    @Published var notice: String?
    @Published var isCancelling = false
    @Published var isStartingConversion = false
    @Published var permissionStatus: PHAuthorizationStatus = PhotoLibraryService.readAuthorizationStatus
    @Published var addPermissionDenied = false
    @Published var quota: QuotaStatus?
    @Published var isPro = false
    @Published var activeModal: Modal?
    @Published var batchQuotaPrompt: BatchQuotaPrompt?
    /// The saved default for Live Photos, editable from Settings. New selections start from it.
    @Published private(set) var livePhotoModePreference: LivePhotoProcessingMode = .defaultMode
    /// A temporary choice made on the selection screen. It only applies to the current batch and
    /// never touches the saved default, which is what "temporary switch" means here.
    @Published private(set) var livePhotoModeOverride: LivePhotoProcessingMode?
    /// First-run tutorial. Presented once automatically, then available from Home and Settings.
    @Published var isTutorialPresented = false
    /// Vault records newest first. Refreshed whenever a conversion finishes or the vault changes.
    @Published var vaultRecords: [VaultRecord] = []
    /// Tasks that already reached a final state, newest first.
    @Published var history: [ConversionTaskRecord] = []
    /// How long finished results stay in the vault. Persisted per install.
    @Published private(set) var vaultRetention: VaultRetention = .standard
    /// One-line feedback for vault actions (re-saved, deleted, cleanup, storage errors).
    @Published var vaultMessage: String?

    enum Modal: String, Identifiable {
        case pro
        case quotaExhausted
        case settings
        case vault
        case history

        var id: String { rawValue }
    }

    struct BatchQuotaPrompt: Identifiable, Equatable {
        let id = UUID()
        let requested: Int
        let available: Int
        let clearFailures: Bool
    }

    let purchases = PurchaseManager()
    /// Finished results live here so the user can re-save or export without paying again.
    let vaultStore: VaultStore
    /// Durable task log: survives crashes, feeds the history list and interrupted-task recovery.
    let taskJournal: TaskJournal
    private var currentTaskID: UUID?
    private let library = PhotoLibraryService()
    private var deferredItemIDs: Set<UUID> = []
    private var workspace: SessionWorkspace?
    private var preparationGeneration = UUID()
    private var conversionTask: Task<Void, Never>?
    private var preparationTasks: [Task<Void, Never>] = []
    private var run: ConversionRun?
    /// Set when another entry point wins the last free slot after this pass preflighted it.
    /// The affected items are deferred, not failed, and the user sees the quota page at the end.
    private var quotaExhaustedDuringRun = false
    /// Identifies the current "start" intent. reset() replaces it so a permission prompt that
    /// returns late can never attach an old request to a newly selected batch.
    private var startToken = UUID()

    static let maxSelection = 9
    static let livePhotoModeKey = "LingXiStyle.livePhotoMode"
    private static let firstQuotaReminderKey = "LingXiStyle.hasShownFirstQuotaReminder"
    private static let hasSeenTutorialKey = "LingXiStyle.hasSeenTutorial"
    private static let vaultRetentionKey = "LingXiStyle.vaultRetention"

    var hasSeenTutorial: Bool { UserDefaults.standard.bool(forKey: Self.hasSeenTutorialKey) }

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.livePhotoModeKey)
        livePhotoModePreference = stored.flatMap(LivePhotoProcessingMode.init(rawValue:)) ?? .defaultMode
        vaultStore = VaultStore(rootURL: VaultStore.defaultRootURL())
        taskJournal = TaskJournal(storeURL: TaskJournal.defaultStoreURL())
        let storedRetention = UserDefaults.standard.object(forKey: Self.vaultRetentionKey) as? Int
        vaultRetention = storedRetention.flatMap(VaultRetention.init(rawValue:)) ?? .standard
        ConversionService.shared.configureStorage(vault: vaultStore, journal: taskJournal)
    }

    // MARK: Derived state

    var selectedItem: PhotoItem? {
        if let selectedID, let match = items.first(where: { $0.id == selectedID }) { return match }
        return items.first
    }

    var convertibleCount: Int { items.filter(\.isConvertible).count }
    var readyCount: Int { items.filter { $0.verdict?.status == .ready }.count }
    var skippedCount: Int {
        items.filter { item in
            item.verdict?.status == .alreadyEnhanced || item.verdict?.status == .unsupported
        }.count
    }

    var ctaTitle: String {
        if convertibleCount > 1 { return String(localized: "cta.addTexture", defaultValue: "添加纹理与颗粒（\(convertibleCount) 张）") }
        return String(localized: "添加纹理与颗粒")
    }

    var isBusyPreparing: Bool { items.contains { $0.phase == .preparing } }

    var savedItems: [PhotoItem] { items.filter(\.isSaved) }

    var deferredCount: Int { deferredItemIDs.count }

    /// The mode a run would use right now: the temporary choice when one was made, the saved
    /// default otherwise.
    var effectiveLivePhotoMode: LivePhotoProcessingMode { livePhotoModeOverride ?? livePhotoModePreference }

    /// Live Photos that actually have their movie exported and can be converted.
    var convertibleLivePhotoCount: Int {
        items.filter { $0.isConvertible && $0.hasLivePhotoVideo }.count
    }

    /// True when the batch mixes stills and Live Photos, so the mode row explains who it affects.
    var hasMixedLivePhotoBatch: Bool {
        let live = convertibleLivePhotoCount
        return live > 0 && live < convertibleCount
    }

    func setLivePhotoModePreference(_ mode: LivePhotoProcessingMode) {
        livePhotoModePreference = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.livePhotoModeKey)
    }

    func setLivePhotoModeOverride(_ mode: LivePhotoProcessingMode?) {
        livePhotoModeOverride = mode
    }

    /// Shows the full tutorial on the very first launch only; the flag is written on dismissal.
    func presentTutorialIfFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: Self.hasSeenTutorialKey) else { return }
        isTutorialPresented = true
    }

    func presentTutorial() {
        isTutorialPresented = true
    }

    func dismissTutorial() {
        isTutorialPresented = false
        UserDefaults.standard.set(true, forKey: Self.hasSeenTutorialKey)
    }

    // MARK: Lifecycle

    func onAppear() async {
        // Never jump straight to a permission wall at launch: file import and the rest of the
        // UI remain usable without photo-library access. The permission page appears only when
        // a PhotoKit action actually needs read access.
        refreshPermissions()
        recoverInterruptedTasks()
        refreshVault()
        refreshHistory()
        // Read quota before StoreKit warms up so the badge never shows a
        // misleading unavailable state while the entitlement check is pending.
        await refreshQuota()
        await purchases.start()
        await refreshQuota()
    }

    /// Reads the StoreKit-backed allowance used by every conversion entry point.
    func refreshQuota() async {
        let status = await ConversionService.shared.quotaStatus()
        quota = status
        isPro = status.isPro
    }

    func presentPro() {
        activeModal = .pro
        Task { [weak self] in
            guard let self else { return }
            await self.purchases.start()
            if self.purchases.product == nil {
                await self.purchases.loadProduct()
            }
        }
    }

    func presentSettings() {
        activeModal = .settings
        Task { [weak self] in
            guard let self else { return }
            await self.purchases.start()
            if self.purchases.product == nil {
                await self.purchases.loadProduct()
            }
        }
    }

    /// The first time the free allowance runs out, show the Pro page once. Later exhaustion
    /// always uses the quieter quota page, which still has a manual upgrade entry.
    func presentQuotaLimit() {
        guard !isPro else { return }
        if !hasShownFirstQuotaReminder {
            hasShownFirstQuotaReminder = true
            presentPro()
        } else {
            presentQuotaExhausted()
        }
    }

    func presentQuotaExhausted() {
        activeModal = .quotaExhausted
    }

    private var hasShownFirstQuotaReminder: Bool {
        get { UserDefaults.standard.bool(forKey: Self.firstQuotaReminderKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.firstQuotaReminderKey) }
    }

    /// Called after a conversion commits its last free slot. It never fires on a cold launch,
    /// so the first screen a new user sees is still the free home screen.
    private func presentFirstQuotaUpsellIfNeeded() {
        guard !isPro, quota?.isExhausted == true, !hasShownFirstQuotaReminder else { return }
        guard activeModal == nil, screen != .converting else { return }
        hasShownFirstQuotaReminder = true
        presentPro()
    }

    func dismissModal() {
        activeModal = nil
        Task { [weak self] in await self?.refreshQuota() }
    }

    func purchaseFlowFinished() {
        activeModal = nil
        Task { [weak self] in await self?.refreshQuota() }
    }

    /// Called when the app returns from Settings. Never triggers a permission prompt.
    func refreshPermissions() {
        let read = PhotoLibraryService.readAuthorizationStatus
        permissionStatus = read
        let add = PhotoLibraryService.addAuthorizationStatus
        addPermissionDenied = add == .denied || add == .restricted
        if read != .denied, read != .restricted, screen == .permissionDenied {
            // Returning from Settings restores the screen the user came from. We never push the
            // permission page on launch, so a denied status alone leaves the current screen alone.
            screen = items.isEmpty ? .idle : .selecting
        }
    }

    func reset() {
        conversionTask?.cancel()
        conversionTask = nil
        if run != nil || currentTaskID != nil { completeTaskRecord(isCancelled: true) }
        cancelPreparation()
        run = nil
        quotaExhaustedDuringRun = false
        isCancelling = false
        isStartingConversion = false
        startToken = UUID()
        items = []
        livePhotoModeOverride = nil
        selectedID = nil
        deferredItemIDs = []
        summary = nil
        diagnosticsText = nil
        notice = nil
        isImportingFiles = false
        addPermissionDenied = false
        screen = .idle
        // Stop using the old directory immediately, but only delete it once the conversion and
        // preparation operations that still hold files inside it have reached their safe end.
        workspace?.retire()
        workspace = nil
        preparationGeneration = UUID()
    }

    private func ensureWorkspace() throws -> SessionWorkspace {
        if let workspace { return workspace }
        let created = try SessionWorkspace()
        workspace = created
        preparationGeneration = UUID()
        return created
    }

    // MARK: Selection

    /// Starts picking work in a tracked task so reset() can cancel iCloud downloads and file
    /// copies instead of letting them run against a retired workspace.
    func handlePickerSelection() {
        let picked = pickerSelection
        pickerSelection = []
        guard !picked.isEmpty else { return }
        preparationTasks.append(Task { [weak self] in
            await self?.processPickerSelection(picked)
        })
    }

    private func processPickerSelection(_ picked: [PhotosPickerItem]) async {
        guard !Task.isCancelled else { return }

        var status = PhotoLibraryService.readAuthorizationStatus
        if status == .notDetermined {
            status = await PhotoLibraryService.requestReadAuthorization()
        }
        permissionStatus = status
        guard !Task.isCancelled else { return }
        guard status == .authorized || status == .limited else {
            screen = .permissionDenied
            notice = String(localized: "需要照片读取权限才能取得原始 HEIC。也可以从文件导入。")
            return
        }

        var assets: [PHAsset] = []
        var missing = 0
        for item in picked {
            guard let identifier = item.itemIdentifier else { missing += 1; continue }
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            if let asset = result.firstObject { assets.append(asset) }
        }
        if missing > 0 {
            notice = String(localized: "notice.missingAssetIdentifiers", defaultValue: "有 \(missing) 张照片拿不到图库原件标识，请在系统相册里重新选择。")
        }
        await enqueue(assets: assets)
    }

    func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            preparationTasks.append(Task { [weak self] in
                await self?.enqueue(fileURLs: urls)
            })
        case .failure(let error):
            notice = String(localized: "notice.importFailed", defaultValue: "导入失败：\(error.localizedDescription)")
        }
    }

    func enqueue(assets: [PHAsset]) async {
        guard !Task.isCancelled, !assets.isEmpty else { return }
        let room = Self.maxSelection - items.count
        guard room > 0 else {
            notice = String(localized: "notice.tooManyPhotos", defaultValue: "一次最多处理 \(Self.maxSelection) 张照片。")
            return
        }

        var seen = Set(items.compactMap(\.assetIdentifier))
        let unique = assets.filter { asset in
            guard !seen.contains(asset.localIdentifier) else { return false }
            seen.insert(asset.localIdentifier)
            return true
        }
        if unique.count < assets.count {
            notice = String(localized: "已跳过重复选择的照片。")
        }
        let accepted = Array(unique.prefix(room))
        guard !accepted.isEmpty else { return }
        if unique.count > room {
            notice = String(localized: "notice.partialBatch", defaultValue: "只加入了前 \(room) 张，一次最多 \(Self.maxSelection) 张。")
        }

        let workspace: SessionWorkspace
        do {
            workspace = try ensureWorkspace()
        } catch {
            notice = String(localized: "notice.workspaceFailed", defaultValue: "无法创建临时目录：\(error.localizedDescription)")
            return
        }
        let generation = preparationGeneration
        workspace.begin()
        defer { workspace.end() }

        for asset in accepted {
            var item = PhotoItem(assetIdentifier: asset.localIdentifier,
                                 displayName: Self.displayName(for: asset),
                                 image: UIImage(systemName: "photo") ?? UIImage(),
                                 traits: library.traits(for: asset))
            item.phase = .preparing
            items.append(item)
            if selectedID == nil { selectedID = item.id }
        }
        screen = .selecting

        await withBoundedConcurrency(accepted, limit: 2) { asset in
            await self.prepare(asset: asset, generation: generation, workspace: workspace)
        }
    }

    func enqueue(fileURLs: [URL]) async {
        guard !Task.isCancelled else { return }
        let room = Self.maxSelection - items.count
        guard room > 0 else {
            notice = String(localized: "notice.tooManyPhotos", defaultValue: "一次最多处理 \(Self.maxSelection) 张照片。")
            return
        }

        var seen = Set(items.compactMap { $0.fileURL?.standardizedFileURL.path })
        var accepted: [(source: URL, destination: URL, id: UUID)] = []
        let workspace: SessionWorkspace
        do {
            workspace = try ensureWorkspace()
        } catch {
            notice = String(localized: "notice.workspaceFailed", defaultValue: "无法创建临时目录：\(error.localizedDescription)")
            return
        }
        let generation = preparationGeneration

        for url in fileURLs.prefix(room) {
            let path = url.standardizedFileURL.path
            guard !seen.contains(path) else { continue }
            seen.insert(path)
            let id = UUID()
            let directory = workspace.directory
                .appendingPathComponent("Import-\(id.uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                notice = String(localized: "notice.importFileFailed", defaultValue: "无法导入 \(url.lastPathComponent)：\(error.localizedDescription)")
                continue
            }
            accepted.append((url, directory.appendingPathComponent(url.lastPathComponent), id))
        }
        guard !accepted.isEmpty else { return }

        workspace.begin()
        defer { workspace.end() }
        for entry in accepted {
            let traits = AssetTraits(originalIsHEIC: PhotoLibraryService.isHEIF(
                UTType(filenameExtension: entry.destination.pathExtension)?.identifier ?? ""
            ))
            var item = PhotoItem(id: entry.id,
                                 assetIdentifier: nil,
                                 displayName: entry.destination.lastPathComponent,
                                 image: UIImage(systemName: "doc") ?? UIImage(),
                                 traits: traits)
            item.phase = .preparing
            items.append(item)
            if selectedID == nil { selectedID = item.id }
        }
        if !items.isEmpty { screen = .selecting }

        await withBoundedConcurrency(accepted, limit: 2) { entry in
            await self.prepareImportedFile(source: entry.source,
                                           destination: entry.destination,
                                           itemID: entry.id,
                                           generation: generation)
        }
    }

    /// At most two preparations run at once. The order of the queue is decided before this call,
    /// so a slow iCloud download cannot reorder the user's selection.
    private func withBoundedConcurrency<T>(_ values: [T],
                                          limit: Int,
                                          operation: @escaping (T) async -> Void) async {
        guard !values.isEmpty else { return }
        let limit = max(1, min(limit, values.count))
        await withTaskGroup(of: Void.self) { group in
            var iterator = values.makeIterator()
            for _ in 0..<limit {
                guard let value = iterator.next() else { break }
                group.addTask { await operation(value) }
            }
            while await group.next() != nil {
                guard let value = iterator.next() else { break }
                group.addTask { await operation(value) }
            }
        }
    }

    private func prepare(asset: PHAsset, generation: UUID, workspace: SessionWorkspace) async {
        guard !Task.isCancelled,
              generation == preparationGeneration,
              let item = items.first(where: { $0.assetIdentifier == asset.localIdentifier }) else { return }
        let id = item.id
        let thumbnail = await library.thumbnail(for: asset, targetSize: CGSize(width: 1400, height: 1700))
        guard generation == preparationGeneration else { return }
        if let thumbnail {
            updatePreparedItem(id, generation: generation) { $0.image = thumbnail }
        }

        do {
            let exported = try await library.exportOriginal(for: asset, to: workspace.directory) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, self.preparationGeneration == generation else { return }
                    let clamped = min(max(progress, 0), 1)
                    self.updatePreparedItem(id, generation: generation) {
                        $0.downloadProgress = clamped
                    }
                }
            }
            guard generation == preparationGeneration else { return }
            // A Live Photo without its movie is reported as an explicit issue by the evaluator
            // instead of silently degrading to a still-only conversion.
            var traits = item.traits
            if traits.isLivePhoto {
                traits.livePhotoVideoAvailable = exported.videoURL != nil
            }
            updatePreparedItem(id, generation: generation) {
                $0.fileURL = exported.imageURL
                $0.videoURL = exported.videoURL
                $0.traits = traits
                $0.downloadProgress = 1
            }
            try await inspectPreparedItem(id: id,
                                          fileURL: exported.imageURL,
                                          traits: traits,
                                          generation: generation)
        } catch is CancellationError {
            guard generation == preparationGeneration else { return }
            updatePreparedItem(id, generation: generation) {
                $0.phase = .preparingFailed(String(localized: "读取原件已取消"))
                $0.downloadProgress = nil
            }
        } catch {
            guard generation == preparationGeneration else { return }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            updatePreparedItem(id, generation: generation) {
                $0.phase = .preparingFailed(message)
                $0.downloadProgress = nil
            }
        }
    }

    private func prepareImportedFile(source: URL,
                                     destination: URL,
                                     itemID: UUID,
                                     generation: UUID) async {
        guard !Task.isCancelled else { return }
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            let image = await Task.detached(priority: .userInitiated) {
                Self.previewImage(for: destination)
            }.value
            guard generation == preparationGeneration else { return }
            updatePreparedItem(itemID, generation: generation) {
                $0.image = image
                $0.fileURL = destination
            }
            let traits = AssetTraits(originalIsHEIC: PhotoLibraryService.isHEIF(
                UTType(filenameExtension: destination.pathExtension)?.identifier ?? ""
            ))
            try await inspectPreparedItem(id: itemID,
                                          fileURL: destination,
                                          traits: traits,
                                          generation: generation)
        } catch is CancellationError {
            guard generation == preparationGeneration else { return }
            updatePreparedItem(itemID, generation: generation) {
                $0.phase = .preparingFailed(String(localized: "导入已取消"))
            }
        } catch {
            guard generation == preparationGeneration else { return }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            updatePreparedItem(itemID, generation: generation) {
                $0.phase = .preparingFailed(message)
            }
        }
    }

    private func inspectPreparedItem(id: UUID,
                                     fileURL: URL,
                                     traits: AssetTraits,
                                     generation: UUID) async throws {
        // Parsing a 48MP HEIC is CPU and I/O work; keep it off the main actor.
        let outcome = try await Task.detached(priority: .userInitiated) { [service = ConversionService.shared] in
            try service.inspect(fileURL: fileURL, traits: traits)
        }.value
        guard generation == preparationGeneration else { return }
        updatePreparedItem(id, generation: generation) {
            $0.inspection = outcome.inspection
            $0.verdict = outcome.verdict
            $0.phase = .ready
            $0.downloadProgress = nil
        }
    }

    func remove(_ item: PhotoItem) {
        items.removeAll { $0.id == item.id }
        if selectedID == item.id { selectedID = items.first?.id }
        if items.isEmpty {
            summary = nil
            screen = .idle
            cancelPreparation()
            workspace?.retire()
            workspace = nil
            preparationGeneration = UUID()
        }
    }

    func select(_ item: PhotoItem) {
        selectedID = item.id
    }

    // MARK: Conversion

    func startConversion(clearFailures: Bool = false, limit: Int? = nil) {
        guard !isStartingConversion, run == nil, conversionTask == nil else { return }
        guard !isBusyPreparing else {
            notice = String(localized: "还在读取原件，读完后再开始。")
            return
        }
        guard convertibleCount > 0 else {
            notice = String(localized: "当前没有可处理的照片。")
            return
        }
        isStartingConversion = true
        let token = UUID()
        startToken = token
        Task { [weak self] in
            await self?.beginConversion(token: token, clearFailures: clearFailures, limit: limit)
        }
    }

    private func beginConversion(token: UUID, clearFailures: Bool, limit: Int?) async {
        defer {
            if startToken == token { isStartingConversion = false }
        }

        var addStatus = PhotoLibraryService.addAuthorizationStatus
        if addStatus == .notDetermined {
            addStatus = await PhotoLibraryService.requestAddAuthorization()
            // The user may have reset or changed the batch while the system prompt was open.
            guard startToken == token else { return }
        }
        addPermissionDenied = addStatus == .denied || addStatus == .restricted
        permissionStatus = PhotoLibraryService.readAuthorizationStatus
        guard addStatus == .authorized || addStatus == .limited else {
            notice = String(localized: "notice.addPermission", defaultValue: "没有相册写入权限。请在系统设置中允许 \(Brand.name) 添加照片，再回来开始。")
            return
        }
        guard startToken == token,
              run == nil,
              conversionTask == nil else { return }

        if clearFailures {
            // Only drop the previous failure records once permission checks have passed and
            // a workspace exists; otherwise the result screen would lose them without a retry.
            guard items.contains(where: { item in
                if case .failed? = item.outcome { return item.isConvertible }
                return false
            }) else {
                notice = String(localized: "没有可以重试的照片。")
                return
            }
        }

        // The UI checks the same StoreKit-backed allowance that ConversionService enforces.
        // This is advisory: the service still reserves atomically, so two entry points racing
        // for the last free photo cannot both succeed.
        let status = await ConversionService.shared.quotaStatus()
        guard startToken == token else { return }
        quota = status
        isPro = status.isPro

        let requested = items.filter(\.isConvertible).count
        guard requested > 0 else {
            notice = String(localized: "当前没有可处理的照片。")
            return
        }
        if !status.isPro {
            guard status.isAvailable else {
                notice = String(localized: "暂时无法读取今日免费额度，请稍后重试。")
                return
            }
            if status.remaining <= 0 {
                presentQuotaLimit()
                return
            }
            if let limit, limit > status.remaining {
                batchQuotaPrompt = BatchQuotaPrompt(requested: requested,
                                                     available: status.remaining,
                                                     clearFailures: clearFailures)
                return
            }
            if limit == nil, requested > status.remaining {
                batchQuotaPrompt = BatchQuotaPrompt(requested: requested,
                                                     available: status.remaining,
                                                     clearFailures: clearFailures)
                return
            }
        }

        let convertibleIDs = items.filter(\.isConvertible).map(\.id)
        let allowedCount = status.isPro ? convertibleIDs.count : min(limit ?? convertibleIDs.count, status.remaining)
        let allowedIDs = Set(convertibleIDs.prefix(allowedCount))
        deferredItemIDs = Set(convertibleIDs.dropFirst(allowedCount))

        let workspace: SessionWorkspace
        do {
            workspace = try ensureWorkspace()
        } catch {
            notice = String(localized: "notice.workspaceFailed", defaultValue: "无法创建临时目录：\(error.localizedDescription)")
            return
        }

        if clearFailures {
            for item in items where allowedIDs.contains(item.id) {
                if case .failed? = item.outcome {
                    update(item.id) {
                        $0.outcome = nil
                        $0.stage = nil
                        $0.failedDuringStage = false
                    }
                }
            }
        }
        guard convertibleCount > 0 else {
            notice = String(localized: "当前没有可处理的照片。")
            return
        }

        let entries = items.map { item -> (UUID, ConversionRun.ItemState) in
            if item.isConvertible && !allowedIDs.contains(item.id) {
                return (item.id, .deferred)
            }
            return (item.id, Self.initialState(for: item))
        }
        let taskID = startTaskRecord(isPro: status.isPro)
        currentTaskID = taskID
        let newRun = ConversionRun(entries: entries)
        workspace.begin()
        run = newRun
        quotaExhaustedDuringRun = false
        summary = nil
        diagnosticsText = nil
        isCancelling = false
        screen = .converting
        conversionTask = Task { [weak self] in
            await self?.runQueue(sessionID: newRun.id, workspace: workspace)
        }
    }

    func cancelConversion() {
        guard screen == .converting, !isCancelling else { return }
        isCancelling = true
        run?.requestCancel()
        conversionTask?.cancel()
    }

    private func runQueue(sessionID: UUID, workspace: SessionWorkspace) async {
        defer {
            workspace.end()
            if run?.id == sessionID {
                conversionTask = nil
            }
        }

        while run?.id == sessionID, let step = run?.next() {
            switch step {
            case .finished:
                finish(sessionID: sessionID)
                return
            case .cancel(let id):
                update(id) {
                    $0.outcome = .cancelled
                    $0.stage = nil
                    $0.failedDuringStage = false
                }
                markJournalItem(id, state: .cancelled)
            case .skip(let id):
                guard let item = items.first(where: { $0.id == id }) else { continue }
                let issue = item.verdict?.issues.first
                update(id) {
                    $0.outcome = .skipped(issue ?? .alreadyHasTexture)
                    $0.stage = nil
                    $0.stage = nil
                }
                markJournalItem(id, state: .skipped)
            case .convert(let id):
                guard let item = items.first(where: { $0.id == id }) else {
                    run?.complete(id, state: .cancelled)
                    continue
                }
                guard item.isConvertible, let fileURL = item.fileURL else {
                    update(id) { $0.outcome = .cancelled }
                    run?.complete(id, state: .cancelled)
                    continue
                }
                update(id) {
                    $0.stage = .readingOriginal
                    $0.failedDuringStage = false
                }
                let preferredName = Self.preferredName(for: item)
                let outputDirectory = workspace.directory
                    .appendingPathComponent("Output-\(id.uuidString)", isDirectory: true)
                // Resolved once per item so a mid-run settings change cannot split a batch, and a
                // retry of the same item keeps the mode it was started with.
                let livePhotoMode: LivePhotoProcessingMode? = item.videoURL == nil
                    ? nil
                    : (item.livePhotoMode ?? effectiveLivePhotoMode)
                do {
                    let result = try await ConversionService.shared.convert(
                        .init(fileURL: fileURL,
                              pairedVideoURL: item.videoURL,
                              livePhotoMode: livePhotoMode,
                              traits: item.traits,
                              preferredName: preferredName,
                              saveToLibrary: true,
                              returnsFile: true,
                              outputDirectory: outputDirectory,
                              taskID: currentTaskID,
                              itemID: id,
                              vaultRetention: vaultRetention)
                    ) { [weak self] stage in
                        Task { @MainActor [weak self] in
                            guard let self, self.run?.id == sessionID else { return }
                            self.update(id) { $0.stage = stage }
                        }
                    }
                    guard run?.id == sessionID else { return }
                    update(id) {
                        $0.stage = .finished
                        $0.integrity = result.integrity
                        $0.outputURL = result.outputURL
                        $0.livePhotoMode = result.livePhotoMode
                        $0.videoFrameCount = result.videoFrameCount
                        $0.saveWarning = result.saveWarning
                        $0.outcome = .saved(assetIdentifier: result.savedAssetIdentifier,
                                            byteCount: result.outputByteCount)
                    }
                    run?.complete(id, state: .saved)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } catch is CancellationError {
                    guard run?.id == sessionID else { return }
                    update(id) {
                        $0.stage = nil
                        $0.outcome = .cancelled
                    }
                    run?.complete(id, state: .cancelled)
                } catch {
                    guard run?.id == sessionID else { return }
                    // Preflight is advisory. If another process reserves the last slot first,
                    // this item and the rest of the queue are deferred instead of being
                    // reported as hard failures. The result screen still shows what saved.
                    if let failure = error as? ConversionFailure,
                       case .quota(.exhausted) = failure {
                        update(id) {
                            $0.stage = nil
                            $0.failedDuringStage = false
                            $0.outcome = nil
                        }
                        run?.complete(id, state: .deferred)
                        let queued = run?.deferRemaining() ?? []
                        deferredItemIDs.insert(id)
                        deferredItemIDs.formUnion(queued)
                        quotaExhaustedDuringRun = true
                        continue
                    }
                    let message: String
                    let code: String
                    if let failure = error as? ConversionFailure {
                        message = failure.message
                        code = failure.diagnosticCode
                    } else if let libraryError = error as? PhotoLibraryError {
                        message = libraryError.errorDescription ?? String(localized: "保存失败")
                        code = libraryError.diagnosticCode
                    } else {
                        message = error.localizedDescription
                        code = "E_UNKNOWN"
                    }
                    update(id) {
                        // Keep the stage that actually failed so the progress list can point at it.
                        $0.failedDuringStage = true
                        $0.integrity = (error as? ConversionFailure)?.integrityReport
                        $0.outcome = .failed(message: message, code: code)
                    }
                    markJournalItem(id, state: .failed, failure: (code, message))
                    run?.complete(id, state: .failed)
                }
            }
        }
        if run?.id == sessionID {
            finish(sessionID: sessionID)
        }
    }

    private func finish(sessionID: UUID) {
        guard run?.id == sessionID else { return }
        let summary = ConversionSummary(items: items)
        self.summary = summary
        completeTaskRecord(isCancelled: isCancelling)
        diagnosticsText = buildDiagnostics(summary: summary)
        run = nil
        conversionTask = nil
        isCancelling = false
        let raced = quotaExhaustedDuringRun
        quotaExhaustedDuringRun = false
        if raced, summary.savedCount == 0, summary.failedCount == 0 {
            // Nothing was saved: leave the result screen for a real outcome and keep the
            // selection so the user can upgrade or come back tomorrow.
            self.summary = nil
            diagnosticsText = nil
            screen = .selecting
        } else {
            screen = .result
        }
        Task { [weak self] in
            guard let self else { return }
            await self.refreshQuota()
            if raced {
                self.presentQuotaLimit()
            } else {
                self.presentFirstQuotaUpsellIfNeeded()
            }
        }
    }

    func retryFailed() {
        guard items.contains(where: { if case .failed? = $0.outcome { return true } else { return false } }) else { return }
        guard run == nil, conversionTask == nil else { return }
        startConversion(clearFailures: true)
    }

    private func cancelPreparation() {
        guard !preparationTasks.isEmpty else { return }
        for task in preparationTasks { task.cancel() }
        preparationTasks.removeAll()
    }

    // MARK: Diagnostics

    private func buildDiagnostics(summary: ConversionSummary) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let item = items.first { if case .failed? = $0.outcome { return true } else { return false } } ?? selectedItem
        let failure: String?
        if let item, case .failed(let message, let code)? = item.outcome {
            failure = "\(code) — \(message)"
        } else {
            failure = nil
        }
        return DiagnosticsFormatter.report(appVersion: version,
                                           build: build,
                                           systemVersion: UIDevice.current.systemVersion,
                                           deviceModel: UIDevice.current.model,
                                           inspection: item?.inspection,
                                           verdict: item?.verdict,
                                           integrity: item?.integrity,
                                           failure: failure)
    }

    // MARK: Helpers

    private func update(_ id: UUID, _ mutate: (inout PhotoItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
    }

    private func updatePreparedItem(_ id: UUID,
                                    generation: UUID,
                                    _ mutate: (inout PhotoItem) -> Void) {
        guard generation == preparationGeneration else { return }
        update(id, mutate)
    }

    private static func initialState(for item: PhotoItem) -> ConversionRun.ItemState {
        if case .saved? = item.outcome { return .saved }
        if case .skipped? = item.outcome { return .skipped }
        if case .cancelled? = item.outcome { return .cancelled }
        if case .failed? = item.outcome { return .pending }
        if item.isConvertible { return .pending }
        if item.verdict?.status == .alreadyEnhanced || item.verdict?.status == .unsupported {
            return .unsupported
        }
        return .unavailable
    }

    static func preferredName(for item: PhotoItem) -> String {
        let stem = (item.displayName as NSString).deletingPathExtension
        let base = stem.hasSuffix("_TextureGrain") ? stem : stem + "_TextureGrain"
        return base + ".HEIC"
    }

    static func displayName(for asset: PHAsset) -> String {
        if let filename = PHAssetResource.assetResources(for: asset).first(where: { $0.type == .photo })?.originalFilename {
            return filename
        }
        return "IMG_\(asset.localIdentifier.prefix(4)).HEIC"
    }

    /// Previews are downsampled with ImageIO so a 48MP HEIC never gets fully decoded on the
    /// main actor. This only produces a display thumbnail; the conversion path never touches it.
    nonisolated static func previewImage(for url: URL, fallback: UIImage? = nil) -> UIImage {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600,
                kCGImageSourceShouldCacheImmediately: true
            ]
            if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return UIImage(cgImage: thumbnail)
            }
        }
        return fallback ?? UIImage(systemName: "photo") ?? UIImage()
    }

    // MARK: - Vault

    var vaultTotalByteCount: Int { (try? vaultStore.totalByteCount()) ?? 0 }
    var vaultAvailableByteCount: Int? { vaultStore.availableByteCount().map { Int(clamping: $0) } }

    func refreshVault() {
        vaultRecords = (try? vaultStore.records()) ?? []
    }

    func refreshHistory() {
        history = taskJournal.tasks().filter { !$0.isActive }
    }

    func vaultRecord(id: UUID?) -> VaultRecord? {
        guard let id else { return nil }
        return vaultRecords.first { $0.id == id }
    }

    func setVaultRetention(_ retention: VaultRetention) {
        guard retention != vaultRetention else { return }
        vaultRetention = retention
        UserDefaults.standard.set(retention.rawValue, forKey: Self.vaultRetentionKey)
        do {
            try vaultStore.applyRetention(retention)
        } catch {
            vaultMessage = error.localizedDescription
        }
        refreshVault()
    }

    /// Manual cleanup from Settings. Results of tasks that are still running are never purged.
    func purgeExpiredVault() {
        var keeping = Set(taskJournal.activeTasks().map(\.id))
        if let currentTaskID { keeping.insert(currentTaskID) }
        do {
            let result = try vaultStore.purgeExpired(keepingTaskIDs: keeping)
            if result.removedCount == 0 {
                vaultMessage = String(localized: "vault.cleanupNothing", defaultValue: "没有可清理的过期成果。")
            } else {
                vaultMessage = String(localized: "vault.cleanupDone", defaultValue: "已清理 \(result.removedCount) 项，释放 \(Self.byteText(result.freedByteCount))。")
            }
        } catch {
            vaultMessage = error.localizedDescription
        }
        refreshVault()
    }

    func deleteVaultRecord(_ record: VaultRecord) {
        do {
            try vaultStore.delete(id: record.id)
        } catch {
            vaultMessage = error.localizedDescription
        }
        refreshVault()
    }

    func deleteAllVaultRecords() {
        do {
            try vaultStore.deleteAll()
        } catch {
            vaultMessage = error.localizedDescription
        }
        refreshVault()
    }

    /// Saves a vault copy back to Photos without reserving or committing allowance: the
    /// original conversion already paid for it, and re-saving must stay free.
    func resaveFromVault(_ record: VaultRecord) async {
        guard !record.isExpired() else {
            vaultMessage = String(localized: "vault.expired", defaultValue: "这项成果已过保留期，无法再次保存。")
            refreshVault()
            return
        }
        let photoURL = vaultStore.photoURL(for: record)
        do {
            let saved: SavedPhoto
            if record.isLivePhoto, let videoURL = vaultStore.videoURL(for: record) {
                saved = try await library.saveNewLivePhoto(still: photoURL, video: videoURL, preferredName: record.displayName)
            } else {
                saved = try await library.saveNewPhoto(from: photoURL, preferredName: record.displayName)
            }
            _ = try? vaultStore.markSaved(id: record.id, assetIdentifier: saved.identifier)
            vaultMessage = String(localized: "vault.resaved", defaultValue: "已重新保存到相册。")
            refreshVault()
        } catch {
            vaultMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    static func byteText(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    static func lifetimeText(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes >= 24 * 60 {
            return String(localized: "vault.lifetime.days", defaultValue: "\(minutes / (24 * 60)) 天")
        }
        if minutes >= 60 {
            return String(localized: "vault.lifetime.hours", defaultValue: "\(minutes / 60) 小时")
        }
        return String(localized: "vault.lifetime.minutes", defaultValue: "不到 1 小时")
    }

    // MARK: - Task journal plumbing

    private func recoverInterruptedTasks() {
        guard let recoveries = try? taskJournal.recoverInterrupted(), !recoveries.isEmpty else { return }
        for recovery in recoveries {
            // A reservation without a vault copy means the conversion never finished, so the
            // allowance goes back. A reservation with a vault copy was saved but not settled.
            for reservation in recovery.reservationsToRelease {
                try? QuotaManager.shared.release(reservation)
            }
            for reservation in recovery.reservationsToCommit {
                try? QuotaManager.shared.commit(reservation)
            }
        }
        notice = String(localized: "tasks.recovered", defaultValue: "上次有 \(recoveries.count) 个任务中断。已完成的结果留在保险箱，可在任务历史中重存。")
    }

    private func startTaskRecord(isPro: Bool) -> UUID {
        let id = UUID()
        var record = ConversionTaskRecord(id: id, origin: .app, isPro: isPro)
        record.items = items.map { item in
            var entry = TaskItemRecord(
                id: item.id,
                displayName: item.displayName,
                isLivePhoto: item.videoURL != nil,
                livePhotoMode: item.videoURL == nil ? nil : (item.livePhotoMode ?? effectiveLivePhotoMode).rawValue
            )
            if !item.isConvertible { entry.state = .skipped }
            if deferredItemIDs.contains(item.id) { entry.state = .deferred }
            if case .skipped? = item.outcome { entry.state = .skipped }
            return entry
        }
        record.state = .running
        _ = try? taskJournal.upsert(record)
        return id
    }

    private func markJournalItem(_ id: UUID,
                                 state: ConversionItemState,
                                 failure: (code: String, message: String)? = nil) {
        guard let taskID = currentTaskID else { return }
        _ = try? taskJournal.mutate(taskID: taskID) { record in
            guard let index = record.items.firstIndex(where: { $0.id == id }) else { return }
            record.items[index].state = state
            if let failure {
                record.items[index].failureCode = failure.code
                record.items[index].failureMessage = failure.message
            }
        }
    }

    /// Reconciles the journal with what the run actually did, then closes the task. The
    /// conversion service already wrote saved/failed details and quota fields; this only
    /// fills in items that never reached it (skipped, cancelled while queued, deferred).
    private func completeTaskRecord(isCancelled: Bool) {
        guard let taskID = currentTaskID,
              var record = taskJournal.task(id: taskID) else { return }
        for index in record.items.indices {
            guard let item = items.first(where: { $0.id == record.items[index].id }) else { continue }
            let state = record.items[index].state
            guard state == .pending || state == .converting || state == .saving else { continue }
            if case .saved? = item.outcome {
                record.items[index].state = .saved
            } else if case .skipped? = item.outcome {
                record.items[index].state = .skipped
            } else if case .cancelled? = item.outcome {
                record.items[index].state = .cancelled
            } else if case .failed(let message, let code)? = item.outcome {
                record.items[index].state = .failed
                record.items[index].failureMessage = message
                record.items[index].failureCode = code
            } else {
                record.items[index].state = deferredItemIDs.contains(item.id)
                    ? .deferred
                    : (isCancelled ? .cancelled : .interrupted)
            }
        }
        record.applyResolvedState(isCancelled: isCancelled)
        _ = try? taskJournal.upsert(record)
        currentTaskID = nil
        refreshHistory()
        refreshVault()
    }
}

/// Keeps a session's temporary directory alive while a conversion or preparation still reads
/// from it. reset() only retires the workspace; the last operation deletes the directory.
@MainActor
private final class SessionWorkspace {
    let directory: URL
    private var activeOperations = 0
    private var isRetired = false

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingXiSession-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func begin() {
        activeOperations += 1
    }

    func end() {
        activeOperations = max(0, activeOperations - 1)
        cleanupIfNeeded()
    }

    func retire() {
        isRetired = true
        cleanupIfNeeded()
    }

    private func cleanupIfNeeded() {
        guard isRetired, activeOperations == 0 else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}