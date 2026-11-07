import SwiftUI
import UIKit
import Photos
import UniformTypeIdentifiers
import os
import LingXiKit
import LingXiEngine
import LingXiServices

private let shareLogger = Logger(subsystem: "com.lingxifox.LingXiStyle.Share", category: "read")

/// The public surface ShareModel needs from an item provider. NSItemProvider is the production
/// implementation; tests supply controlled success, failure, delay and cancellation callbacks.
protocol ShareItemProviding: AnyObject {
    var registeredTypeIdentifiers: [String] { get }
    var suggestedName: String? { get }
    func hasItemConformingToTypeIdentifier(_ typeIdentifier: String) -> Bool
    @discardableResult
    func loadFileRepresentation(forTypeIdentifier typeIdentifier: String,
                                completionHandler: @escaping @Sendable (URL?, Error?) -> Void) -> Progress
    @discardableResult
    func loadDataRepresentation(forTypeIdentifier typeIdentifier: String,
                                completionHandler: @escaping @Sendable (Data?, Error?) -> Void) -> Progress
}

extension NSItemProvider: ShareItemProviding {}

struct ShareConversionResult: Sendable {
    let savedAssetIdentifier: String?
}

/// The conversion surface used by the share flow. Production always routes through
/// ConversionService; tests can inject failures without fabricating a saved photo.
protocol ShareConversionRunning: Sendable {
    func inspect(fileURL: URL, traits: AssetTraits) async throws -> InspectionOutcome
    func convert(fileURL: URL,
                 traits: AssetTraits,
                 preferredName: String,
                 onStage: @escaping @Sendable (ConversionStage) -> Void) async throws -> ShareConversionResult
}

struct LiveShareConversionRunner: ShareConversionRunning {
    func inspect(fileURL: URL, traits: AssetTraits) async throws -> InspectionOutcome {
        let service = ConversionService.shared
        return try await Task.detached(priority: .userInitiated) {
            try service.inspect(fileURL: fileURL, traits: traits)
        }.value
    }

    func convert(fileURL: URL,
                 traits: AssetTraits,
                 preferredName: String,
                 onStage: @escaping @Sendable (ConversionStage) -> Void) async throws -> ShareConversionResult {
        let result = try await ConversionService.shared.convert(.init(fileURL: fileURL,
                                                                      traits: traits,
                                                                      preferredName: preferredName,
                                                                      saveToLibrary: true,
                                                                      returnsFile: false),
                                                                 onStage: onStage)
        return ShareConversionResult(savedAssetIdentifier: result.savedAssetIdentifier)
    }
}

/// Share-sheet entry point. It copies the shared file into its own sandbox before doing
/// anything, validates that the bytes are a complete HEIC, then hands the file to the same
/// ConversionService the app and shortcuts use. The extension never pretends a running job is
/// finished: while work is in flight the only action is an explicit cancel.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 0, height: 500)
        view.backgroundColor = .systemBackground

        let host = UIHostingController(rootView: ShareFlowView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)

        model.onClose = { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
        model.begin(providers: extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? [])
    }
}

@MainActor
final class ShareModel: ObservableObject {
    enum Phase: Equatable {
        case reading
        case inspecting
        case converting(ConversionStage)
        case cancelling
        case done
        case cancelled
        case failed
    }

    @Published private(set) var phase: Phase = .reading
    @Published private(set) var title = String(localized: "正在读取分享的照片")
    @Published private(set) var message = String(localized: "share.copyHint", defaultValue: "文件会先复制到 \(Brand.name) 的沙盒，再检查结构。")
    @Published private(set) var diagnosticCode: String?
    @Published private(set) var canRetry = false
    @Published private(set) var failureHint: String?

    var onClose: (() -> Void)?

    private let service: any ShareConversionRunning
    private let temporaryDirectory: URL
    private let fallbackDelay: TimeInterval
    private let readTimeout: TimeInterval

    init(service: any ShareConversionRunning = LiveShareConversionRunner(),
         temporaryDirectory: URL = FileManager.default.temporaryDirectory,
         fallbackDelay: TimeInterval = 3,
         readTimeout: TimeInterval = 15) {
        self.service = service
        self.temporaryDirectory = temporaryDirectory
        self.fallbackDelay = fallbackDelay
        self.readTimeout = readTimeout
    }

    private var workDirectory: URL?
    private var sharedFile: URL?
    private var processingTask: Task<Void, Never>?
    private var sessionID = UUID()
    private var loadGeneration = UUID()
    private var cancelRequested = false
    private var closeWhenFinished = false
    private var didClose = false

    // Reading state. The provider's file callback can be dropped by the host, so the model
    // keeps two independent public representations in flight and uses the first complete one.
    private var pendingProvider: (any ShareItemProviding)?
    private var pendingIdentifier: String?
    private var pendingSuggestedName: String?
    private var readFallbackTask: Task<Void, Never>?
    private var readTimeoutTask: Task<Void, Never>?
    private var dataReadStarted = false
    private var fileReadFailed = false
    private var dataReadFailed = false

    var isBusy: Bool {
        switch phase {
        case .reading, .inspecting, .converting, .cancelling: return true
        case .done, .cancelled, .failed: return false
        }
    }

    var canCancel: Bool {
        guard isBusy else { return false }
        if case .cancelling = phase { return false }
        return true
    }

    func begin(providers: [NSItemProvider]) {
        begin(items: providers)
    }

    /// Test seam and production overload. The system path enters through `begin(providers:)`.
    func begin(items: [any ShareItemProviding]) {
        cleanupStaleWorkDirectories()
        shareLogger.notice("begin providers=\(items.count, privacy: .public) types=\(items.flatMap(\.registeredTypeIdentifiers).joined(separator: ","), privacy: .public)")
        // Photos normally hands over a public.image item. Files hands over a file URL;
        // accepting both still leaves the byte-level HEIC validation in process().
        let provider = items.first { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
            ?? items.first { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard let provider else {
            fail(title: String(localized: "没有收到照片"), message: String(localized: "share.error.noProviders", defaultValue: "请回到系统「照片」重新分享，或直接在 \(Brand.name) 内从图库选择照片。"), retry: false)
            return
        }
        load(provider)
    }

    /// The extension process can be killed while a conversion is in flight, leaving its copy in
    /// temporaryDirectory. Only old directories are removed so a concurrently running share is
    /// never touched.
    private func cleanupStaleWorkDirectories() {
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]
        guard let entries = try? fileManager.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-60 * 60)
        for entry in entries where entry.lastPathComponent.hasPrefix("LingXiShare-") {
            guard let values = try? entry.resourceValues(forKeys: keys),
                  values.isDirectory == true,
                  let modified = values.contentModificationDate,
                  modified < cutoff else { continue }
            try? fileManager.removeItem(at: entry)
        }
    }

    func retry() {
        guard !isBusy else { return }
        if let sharedFile {
            process(sharedFile)
            return
        }
        guard let pendingProvider, let pendingIdentifier else { return }
        load(pendingProvider, identifier: pendingIdentifier)
    }

    /// Starts work. The caller owns the file until the task reaches a safe boundary, so closing
    /// the sheet cannot delete a file that PhotoKit or the engine is still reading.
    private func load(_ provider: any ShareItemProviding) {
        // Ask for the concrete type the provider registered (public.heic, public.jpeg, …).
        // Requesting the abstract public.image can leave some providers without a file
        // representation, which shows up as an endless "reading" spinner.
        let imageIdentifiers = provider.registeredTypeIdentifiers.filter {
            UTType($0)?.conforms(to: .image) == true
        }
        let identifier = imageIdentifiers.first { UTType($0)?.conforms(to: .heic) == true }
            ?? imageIdentifiers.first { UTType($0)?.conforms(to: .heif) == true }
            ?? imageIdentifiers.first
            ?? (provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ? UTType.fileURL.identifier : nil)
        guard let identifier else {
            fail(title: String(localized: "没有收到照片"), message: String(localized: "share.error.notHEIC", defaultValue: "请分享一张 HEIC 原片，或直接在 \(Brand.name) 内从图库选择照片。"), retry: false)
            return
        }
        load(provider, identifier: identifier)
    }

    private func load(_ provider: any ShareItemProviding, identifier: String) {
        phase = .reading
        title = String(localized: "正在读取分享的照片")
        message = String(localized: "share.copyHint", defaultValue: "文件会先复制到 \(Brand.name) 的沙盒，再检查结构。")
        diagnosticCode = nil
        failureHint = nil
        canRetry = false

        let generation = UUID()
        loadGeneration = generation
        dataReadStarted = false
        fileReadFailed = false
        dataReadFailed = false
        pendingProvider = provider
        pendingIdentifier = identifier
        pendingSuggestedName = provider.suggestedName
        shareLogger.notice("load start identifier=\(identifier, privacy: .public)")

        // The file representation is the preferred path because the provider can stream a large
        // original without loading it into memory. Some hosts (Photos on iOS 27.3) never call the
        // completion handler, so a second public representation is started after a short grace
        // period. Whichever callback produces complete bytes first wins.
        let suggestedName = provider.suggestedName
        provider.loadFileRepresentation(forTypeIdentifier: identifier) { [weak self] url, error in
            guard let self else { return }
            if let url {
                let copied = Self.copyToSandbox(fileURL: url,
                                                suggestedName: suggestedName,
                                                typeIdentifier: identifier,
                                                in: temporaryDirectory)
                Task { @MainActor in
                    guard self.loadGeneration == generation else {
                        try? FileManager.default.removeItem(at: copied.directory)
                        return
                    }
                    switch copied.result {
                    case .success(let destination):
                        shareLogger.notice("file callback copied bytes=\(Self.fileSize(destination), privacy: .public)")
                        self.completeRead(directory: copied.directory, destination: destination, generation: generation)
                    case .failure:
                        try? FileManager.default.removeItem(at: copied.directory)
                        self.fileReadFailed = true
                        shareLogger.error("file callback copy failed")
                        self.startDataFallback(generation: generation)
                        self.failIfBothReadsFailed(generation: generation)
                    }
                }
            } else {
                let detail = error?.localizedDescription ?? "no file URL"
                Task { @MainActor in
                    guard self.loadGeneration == generation else { return }
                    shareLogger.error("file callback failed error=\(detail, privacy: .public)")
                    self.fileReadFailed = true
                    self.startDataFallback(generation: generation)
                    self.failIfBothReadsFailed(generation: generation)
                }
            }
        }

        scheduleReadDeadline(generation, seconds: fallbackDelay, action: .startDataFallback)
        scheduleReadDeadline(generation, seconds: readTimeout, action: .fail)
    }

    private enum ReadDeadlineAction {
        case startDataFallback
        case fail
    }

    private func scheduleReadDeadline(_ generation: UUID, seconds: Double, action: ReadDeadlineAction) {
        let task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            } catch {
                return
            }
            guard let self, self.loadGeneration == generation, self.phase == .reading else { return }
            switch action {
            case .startDataFallback:
                self.startDataFallback(generation: generation)
            case .fail:
                shareLogger.error("read deadline expired")
                self.fail(title: String(localized: "无法读取分享的文件"),
                          message: String(localized: "share.error.timeout", defaultValue: "系统没有在限定时间内返回照片。请返回系统「照片」重新分享，或直接在 \(Brand.name) 内从图库选择照片。"),
                          code: "E_SHARE_READ_TIMEOUT",
                          retry: true)
            }
        }
        if action == .startDataFallback {
            readFallbackTask?.cancel()
            readFallbackTask = task
        } else {
            readTimeoutTask?.cancel()
            readTimeoutTask = task
        }
    }

    /// Public fallback used when the file representation is dropped by the host. The bytes are
    /// still copied to the extension's own sandbox and validated as a complete HEIC by the engine;
    /// a JPEG preview can never be presented as success.
    private func startDataFallback(generation: UUID) {
        guard loadGeneration == generation, phase == .reading, !dataReadStarted else { return }
        guard let provider = pendingProvider, let identifier = pendingIdentifier else { return }
        let suggestedName = pendingSuggestedName
        dataReadStarted = true
        readFallbackTask?.cancel()
        shareLogger.notice("data fallback start")
        message = String(localized: "share.reading.fallback", defaultValue: "系统读取文件较慢，正在改用数据方式读取。")
        provider.loadDataRepresentation(forTypeIdentifier: identifier) { [weak self] data, error in
            guard let self else { return }
            guard let data, !data.isEmpty else {
                let detail = error?.localizedDescription ?? "empty data"
                Task { @MainActor in
                    guard self.loadGeneration == generation else { return }
                    shareLogger.error("data fallback failed error=\(detail, privacy: .public)")
                    self.dataReadFailed = true
                    self.failIfBothReadsFailed(generation: generation)
                }
                return
            }
            let copied = Self.writeToSandbox(data: data,
                                             suggestedName: suggestedName,
                                             typeIdentifier: identifier,
                                             in: temporaryDirectory)
            Task { @MainActor in
                guard self.loadGeneration == generation else {
                    try? FileManager.default.removeItem(at: copied.directory)
                    return
                }
                switch copied.result {
                case .success(let destination):
                    shareLogger.notice("data callback copied bytes=\(data.count, privacy: .public)")
                    self.completeRead(directory: copied.directory, destination: destination, generation: generation)
                case .failure:
                    try? FileManager.default.removeItem(at: copied.directory)
                    self.dataReadFailed = true
                    self.failIfBothReadsFailed(generation: generation)
                }
            }
        }
    }

    private func completeRead(directory: URL, destination: URL, generation: UUID) {
        guard loadGeneration == generation, phase == .reading else {
            try? FileManager.default.removeItem(at: directory)
            return
        }
        readFallbackTask?.cancel()
        readTimeoutTask?.cancel()
        workDirectory = directory
        sharedFile = destination
        process(destination)
    }

    private func failIfBothReadsFailed(generation: UUID) {
        guard loadGeneration == generation, phase == .reading, fileReadFailed, dataReadFailed else { return }
        fail(title: String(localized: "无法读取分享的文件"),
             message: String(localized: "share.error.noFile", defaultValue: "系统没有提供可读取的文件副本。请直接在 \(Brand.name) 内从图库选择照片。"),
             code: "E_SHARE_READ",
             retry: true)
    }

    private func process(_ fileURL: URL) {
        // Reading is still the current phase when the first complete representation arrives;
        // rejecting busy states here silently dropped the file and left the sheet on the
        // "reading" spinner forever. Only an in-flight processing task may block a new run.
        guard processingTask == nil else { return }
        shareLogger.notice("process start bytes=\(Self.fileSize(fileURL), privacy: .public)")
        let session = UUID()
        sessionID = session
        cancelRequested = false
        closeWhenFinished = false
        canRetry = false
        diagnosticCode = nil
        failureHint = nil
        phase = .inspecting
        title = String(localized: "正在检查 HEIC 结构")
        message = String(localized: "确认这是完整原片，并检查是否已经带有纹理与颗粒。")

        processingTask = Task { [weak self] in
            await self?.run(fileURL: fileURL, session: session)
        }
    }

    private func run(fileURL: URL, session: UUID) async {
        defer {
            if sessionID == session {
                processingTask = nil
            }
            if closeWhenFinished {
                finishClose()
            }
        }

        let traits = AssetTraits(originalIsHEIC: true)
        let outcome: InspectionOutcome
        do {
            outcome = try await service.inspect(fileURL: fileURL, traits: traits)
        } catch {
            guard sessionID == session else { return }
            let failure = error as? ConversionFailure
            fail(title: String(localized: "这不是可处理的 HEIC 原片"),
                 message: String(localized: "share.error.unsupportedDetail", defaultValue: "请在 \(Brand.name) 内从图库选择照片。分享面板有时会转成 JPEG 或只给出预览图，这时无法保留原始编码。"),
                 code: failure?.diagnosticCode,
                 retry: false)
            return
        }

        guard sessionID == session else { return }
        guard outcome.verdict.isReady else {
            fail(title: outcome.verdict.headline,
                 message: String(localized: "share.unsupported.message", defaultValue: "\(outcome.verdict.detail) 请在 \(Brand.name) 内从图库选择照片。"),
                 code: outcome.verdict.issues.map(\.rawValue).joined(separator: ","),
                 retry: false)
            return
        }

        do {
            try Task.checkCancellation()
            phase = .converting(.readingOriginal)
            title = String(localized: "正在添加纹理与颗粒")
            message = String(localized: "照片保持清晰，只处理纹理与颗粒层。")

            let result = try await service.convert(fileURL: fileURL,
                                                   traits: traits,
                                                   preferredName: Self.outputName(for: fileURL)) { [weak self] stage in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == session, !self.cancelRequested else { return }
                    self.phase = .converting(stage)
                    self.title = stage.inProgressTitle
                    self.message = Self.message(for: stage)
                }
            }
            guard sessionID == session else { return }
            phase = .done
            title = String(localized: "已保存新照片")
            message = cancelRequested
                ? String(localized: "取消请求到达时，这张照片已经写入相册，已保留。原照片没有被修改。")
                : String(localized: "原照片没有被修改。新照片已出现在系统「照片」中，可以继续编辑。")
            diagnosticCode = result.savedAssetIdentifier.map { "SAVED:\($0)" }
            canRetry = false
            cleanupInput()
        } catch is CancellationError {
            guard sessionID == session else { return }
            phase = .cancelled
            title = String(localized: "已取消，没有保存新照片")
            message = String(localized: "没有写入相册，原照片保持不变。")
            diagnosticCode = nil
            canRetry = sharedFile != nil
            cleanupInput()
        } catch {
            guard sessionID == session else { return }
            present(error)
        }
    }

    private func present(_ error: Error) {
        if let failure = error as? ConversionFailure {
            if case .quota(let quotaError) = failure {
                switch quotaError {
                case .exhausted:
                    // Another entry point spent the last slot first. Retrying the same file
                    // cannot succeed until tomorrow or after Pro is unlocked.
                    fail(title: String(localized: "今日免费额度已用完"),
                         message: failure.message,
                         code: failure.diagnosticCode,
                         retry: false,
                         hint: String(localized: "share.quotaHint", defaultValue: "免费额度会在本地时间 00:00 重置，也可以打开 \(Brand.name) 了解纹粒 Pro。"))
                case .unavailable, .database:
                    fail(title: String(localized: "处理没有完成"),
                         message: failure.message,
                         code: failure.diagnosticCode,
                         retry: true)
                }
                return
            }
            fail(title: String(localized: "处理没有完成"), message: failure.message, code: failure.diagnosticCode, retry: true)
        } else if let libraryError = error as? PhotoLibraryError {
            let denied: Bool
            switch libraryError {
            case .addPermissionDenied: denied = true
            default: denied = false
            }
            fail(title: denied ? String(localized: "没有相册写入权限") : String(localized: "保存到相册失败"),
                 message: libraryError.localizedDescription,
                 code: libraryError.diagnosticCode,
                 retry: true)
        } else {
            fail(title: String(localized: "处理没有完成"), message: error.localizedDescription, code: nil, retry: true)
        }
    }

    private func fail(title: String, message: String, code: String? = nil, retry: Bool, hint: String? = nil) {
        phase = .failed
        self.title = title
        self.message = message
        self.diagnosticCode = code
        // A failed read can be retried even before a file copy exists; the provider is retained
        // until the user closes the sheet.
        self.canRetry = retry
        self.failureHint = hint
    }

    /// A user-visible cancel. Work already written to Photos is never deleted; work that has not
    /// crossed the save boundary is stopped cooperatively.
    func cancel() {
        switch phase {
        case .reading:
            loadGeneration = UUID()
            phase = .cancelled
            title = String(localized: "已取消")
            message = String(localized: "没有读取或保存任何照片。")
            canRetry = false
            cleanupInput()
        case .inspecting, .converting:
            cancelRequested = true
            phase = .cancelling
            title = String(localized: "正在取消")
            message = String(localized: "已保存的照片会保留；正在写入的照片会先完成保存。")
            processingTask?.cancel()
        case .cancelling:
            break
        case .done, .cancelled, .failed:
            close()
        }
    }

    func close() {
        if isBusy {
            if case .reading = phase {
                loadGeneration = UUID()
                cleanupInput()
                finishClose()
            } else {
                closeWhenFinished = true
                cancel()
            }
            return
        }
        finishClose()
    }

    private func finishClose() {
        guard !didClose else { return }
        didClose = true
        cleanup()
        onClose?()
    }

    private func cleanupInput() {
        readFallbackTask?.cancel()
        readFallbackTask = nil
        readTimeoutTask?.cancel()
        readTimeoutTask = nil
        pendingProvider = nil
        pendingIdentifier = nil
        pendingSuggestedName = nil
        dataReadStarted = false
        fileReadFailed = false
        dataReadFailed = false
        if let workDirectory {
            try? FileManager.default.removeItem(at: workDirectory)
        }
        workDirectory = nil
        sharedFile = nil
    }

    private func cleanup() {
        cleanupInput()
    }

    private static func message(for stage: ConversionStage) -> String {
        switch stage {
        case .readingOriginal: return String(localized: "正在读取原始 HEIC，照片内容不会被改动。")
        case .inspecting: return String(localized: "正在确认主图、HDR、EXIF 与风格元数据。")
        case .converting: return String(localized: "只追加纹理与颗粒层，主图编码保持原样。")
        case .verifying: return String(localized: "正在逐项比对转换前后的完整性。")
        case .saving: return String(localized: "正在把新照片写入系统相册。")
        case .finished: return String(localized: "新照片已经保存，原照片保留。")
        case .failed: return String(localized: "这一步没有完成，请重试。")
        }
    }

    nonisolated private static func sanitized(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func destinationName(suggestedName: String?, typeIdentifier: String) -> String {
        let fallbackExtension = UTType(typeIdentifier)?.preferredFilenameExtension ?? "heic"
        guard let suggestedName, !suggestedName.isEmpty else { return "SharedPhoto.\(fallbackExtension)" }
        let last = (suggestedName as NSString).lastPathComponent
        let candidate = sanitized(last)
        guard !candidate.isEmpty, candidate != ".", candidate != ".." else {
            return "SharedPhoto.\(fallbackExtension)"
        }
        return candidate
    }

    nonisolated private static func copyToSandbox(
        fileURL: URL,
        suggestedName: String?,
        typeIdentifier: String,
        in root: URL
    ) -> (directory: URL, result: Result<URL, Error>) {
        let directory = root
            .appendingPathComponent("LingXiShare-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(destinationName(suggestedName: suggestedName, typeIdentifier: typeIdentifier))
            try FileManager.default.copyItem(at: fileURL, to: destination)
            return (directory, .success(destination))
        } catch {
            return (directory, .failure(error))
        }
    }

    nonisolated private static func writeToSandbox(
        data: Data,
        suggestedName: String?,
        typeIdentifier: String,
        in root: URL
    ) -> (directory: URL, result: Result<URL, Error>) {
        let directory = root
            .appendingPathComponent("LingXiShare-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(destinationName(suggestedName: suggestedName, typeIdentifier: typeIdentifier))
            try data.write(to: destination, options: .atomic)
            return (directory, .success(destination))
        } catch {
            return (directory, .failure(error))
        }
    }

    nonisolated private static func fileSize(_ url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private static func outputName(for url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        let base = stem.hasSuffix("_TextureGrain") ? stem : stem + "_TextureGrain"
        return base + ".HEIC"
    }
}

struct ShareFlowView: View {
    @ObservedObject var model: ShareModel

    private var accent: Color { SharePalette.accent }

    var body: some View {
        ZStack {
            SharePalette.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer(minLength: 8)

                ZStack {
                    Circle()
                        .fill(SharePalette.surface)
                        .frame(width: 88, height: 88)
                    Circle()
                        .strokeBorder(SharePalette.hairline, lineWidth: 0.5)
                        .frame(width: 88, height: 88)
                    Image(systemName: symbol)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(iconColor)
                }

                VStack(spacing: 8) {
                    Text(model.title)
                        .font(.system(.title2, design: .default, weight: .bold))
                        .foregroundStyle(SharePalette.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(model.message)
                        .font(.subheadline)
                        .foregroundStyle(SharePalette.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                statusArea

                Spacer(minLength: 8)

                actions
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .tint(accent)
    }

    @ViewBuilder
    private var statusArea: some View {
        switch model.phase {
        case .done:
            Label("已存为相册中的新照片", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(SharePalette.success)
        case .cancelled:
            Label("没有保存新照片", systemImage: "xmark.circle")
                .font(.footnote.weight(.medium))
                .foregroundStyle(SharePalette.textSecondary)
        case .failed:
            Text(model.failureHint ?? (model.canRetry ? String(localized: "可以重试，不会覆盖原照片。") : String(localized: "请返回主 App 重新选择这张照片。")))
                .font(.caption)
                .foregroundStyle(SharePalette.textSecondary)
                .multilineTextAlignment(.center)
        case .cancelling:
            ProgressView()
                .controlSize(.large)
                .tint(accent)
        case .converting(let stage):
            VStack(spacing: 8) {
                ShareStageRail(stage: stage)
                ProgressView()
                    .controlSize(.small)
                    .tint(SharePalette.running)
            }
        case .reading, .inspecting:
            ProgressView()
                .controlSize(.large)
                .tint(SharePalette.running)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if model.isBusy {
            Button("取消") { model.cancel() }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(SharePalette.textPrimary)
                .disabled(!model.canCancel)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
        } else {
            HStack(spacing: 12) {
                if model.canRetry {
                    Button("重试") { model.retry() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(SharePalette.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                }
                Button(model.phase == .done ? String(localized: "完成") : String(localized: "关闭")) { model.close() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .tint(accent)
                    .foregroundStyle(SharePalette.onAccent)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
            }
        }
    }

    private var symbol: String {
        switch model.phase {
        case .done: return "checkmark"
        case .failed: return "exclamationmark"
        case .cancelled: return "xmark"
        case .cancelling: return "xmark.circle"
        default: return "camera.filters"
        }
    }

    private var iconColor: Color {
        switch model.phase {
        case .done: return SharePalette.success
        case .failed: return SharePalette.warning
        case .cancelled, .cancelling: return SharePalette.textSecondary
        default: return accent
        }
    }
}

/// A compact, real-stage rail. It does not show a percentage or a timer.
private struct ShareStageRail: View {
    let stage: ConversionStage

    private var currentIndex: Int {
        ConversionStage.pipeline.firstIndex(of: stage) ?? 0
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(ConversionStage.pipeline.enumerated()), id: \.element) { index, step in
                Capsule()
                    .fill(index <= currentIndex ? SharePalette.accent : SharePalette.fillControl)
                    .frame(height: 4)
                    .overlay {
                        if index == currentIndex {
                            Capsule().strokeBorder(SharePalette.accent.opacity(0.35), lineWidth: 1)
                        }
                    }
                    .accessibilityLabel(Text(String(localized: "share.stage.accessibility", defaultValue: "\(step.title)\(stepSuffix(index))")))
            }
        }
        .frame(maxWidth: 220)
        .accessibilityElement(children: .contain)
    }

    private func stepSuffix(_ index: Int) -> String {
        if index < currentIndex { return String(localized: "stage.done", defaultValue: "，已完成") }
        if index == currentIndex { return String(localized: "stage.current", defaultValue: "，进行中") }
        return ""
    }
}

private enum SharePalette {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let textPrimary = Color(uiColor: .label)
    static let textSecondary = Color(uiColor: .secondaryLabel)
    static let fillControl = Color(uiColor: .tertiarySystemFill)
    static let hairline = Color(uiColor: .separator)
    static let accent = Color(light: 0xE8A13A, dark: 0xE8A13A)
    static let onAccent = Color(light: 0x1A1410, dark: 0x1A1410)
    static let running = Color(light: 0x0E8A85, dark: 0x3CC9BD)
    static let success = Color(light: 0x248A3D, dark: 0x30DB5B)
    static let warning = Color(light: 0xB25000, dark: 0xFFD426)
}

private extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}