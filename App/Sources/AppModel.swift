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

    enum Modal: String, Identifiable {
        case pro
        case quotaExhausted
        case settings

        var id: String { rawValue }
    }

    struct BatchQuotaPrompt: Identifiable, Equatable {
        let id = UUID()
        let requested: Int
        let available: Int
        let clearFailures: Bool
    }

    let purchases = PurchaseManager()
    private let library = PhotoLibraryService()
    private var deferredItemIDs: Set<UUID> = []
    private var workspace: SessionWorkspace?
    private var preparationGeneration = UUID()
    private var conversionTask: Task<Void, Never>?
    private var preparationTasks: [Task<Void, Never>] = []
    private var run: ConversionRun?
    /// Identifies the current "start" intent. reset() replaces it so a permission prompt that
    /// returns late can never attach an old request to a newly selected batch.
    private var startToken = UUID()

    static let maxSelection = 9
    private static let firstQuotaReminderKey = "LingXiStyle.hasShownFirstQuotaReminder"

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

    // MARK: Lifecycle

    func onAppear() async {
        // Never jump straight to a permission wall at launch: file import and the rest of the
        // UI remain usable without photo-library access. The permission page appears only when
        // a PhotoKit action actually needs read access.
        refreshPermissions()
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
        cancelPreparation()
        run = nil
        isCancelling = false
        isStartingConversion = false
        startToken = UUID()
        items = []
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
            let url = try await library.exportOriginal(for: asset, to: workspace.directory) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, self.preparationGeneration == generation else { return }
                    let clamped = min(max(progress, 0), 1)
                    self.updatePreparedItem(id, generation: generation) {
                        $0.downloadProgress = clamped
                    }
                }
            }
            guard generation == preparationGeneration else { return }
            updatePreparedItem(id, generation: generation) {
                $0.fileURL = url
                $0.downloadProgress = 1
            }
            try await inspectPreparedItem(id: id, fileURL: url, traits: item.traits, generation: generation)
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
        let newRun = ConversionRun(entries: entries)
        workspace.begin()
        run = newRun
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
            case .skip(let id):
                guard let item = items.first(where: { $0.id == id }) else { continue }
                let issue = item.verdict?.issues.first
                update(id) {
                    $0.outcome = .skipped(issue ?? .alreadyHasTexture)
                    $0.stage = nil
                }
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
                do {
                    let result = try await ConversionService.shared.convert(
                        .init(fileURL: fileURL,
                              traits: item.traits,
                              preferredName: preferredName,
                              saveToLibrary: true,
                              returnsFile: true,
                              outputDirectory: outputDirectory)
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
        diagnosticsText = buildDiagnostics(summary: summary)
        run = nil
        conversionTask = nil
        isCancelling = false
        screen = .result
        Task { [weak self] in
            guard let self else { return }
            await self.refreshQuota()
            self.presentFirstQuotaUpsellIfNeeded()
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