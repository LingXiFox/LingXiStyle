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
    @Published var permissionStatus: PHAuthorizationStatus = PhotoLibraryService.authorizationStatus

    private let library = PhotoLibraryService()
    private var sessionDirectory: URL?
    private var conversionTask: Task<Void, Never>?
    private var cancelledByUser = false

    static let maxSelection = 9

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
        if convertibleCount > 1 { return "解锁 \(convertibleCount) 张照片" }
        return "解锁第三代摄影风格"
    }

    var isBusyPreparing: Bool { items.contains { $0.phase == .preparing } }

    // MARK: Lifecycle

    func onAppear() async {
        permissionStatus = PhotoLibraryService.authorizationStatus
        if permissionStatus == .notDetermined {
            permissionStatus = await PhotoLibraryService.requestAuthorization()
        }
        if permissionStatus == .denied || permissionStatus == .restricted {
            screen = .permissionDenied
        }
    }

    func reset() {
        conversionTask?.cancel()
        conversionTask = nil
        items = []
        selectedID = nil
        summary = nil
        diagnosticsText = nil
        screen = .idle
        removeSessionDirectory()
    }

    private func removeSessionDirectory() {
        if let sessionDirectory {
            try? FileManager.default.removeItem(at: sessionDirectory)
        }
        sessionDirectory = nil
    }

    private func ensureSessionDirectory() throws -> URL {
        if let sessionDirectory { return sessionDirectory }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingXiSession-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        sessionDirectory = url
        return url
    }

    // MARK: Selection

    func handlePickerSelection() async {
        let picked = pickerSelection
        pickerSelection = []
        guard !picked.isEmpty else { return }

        var assets: [PHAsset] = []
        var missing = 0
        for item in picked {
            guard let identifier = item.itemIdentifier else { missing += 1; continue }
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            if let asset = result.firstObject { assets.append(asset) }
        }
        if missing > 0 {
            notice = "有 \(missing) 张照片拿不到图库原件标识，请在系统相册里重新选择。"
        }
        await enqueue(assets: assets)
    }

    func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task { await enqueue(fileURLs: urls) }
        case .failure(let error):
            notice = "导入失败：\(error.localizedDescription)"
        }
    }

    func enqueue(assets: [PHAsset]) async {
        guard !assets.isEmpty else { return }
        let room = Self.maxSelection - items.count
        guard room > 0 else {
            notice = "一次最多处理 \(Self.maxSelection) 张照片。"
            return
        }
        let accepted = Array(assets.prefix(room))
        if assets.count > room {
            notice = "只加入了前 \(room) 张，一次最多 \(Self.maxSelection) 张。"
        }

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

        for asset in accepted {
            await prepare(asset: asset)
        }
    }

    func enqueue(fileURLs: [URL]) async {
        let room = Self.maxSelection - items.count
        guard room > 0 else {
            notice = "一次最多处理 \(Self.maxSelection) 张照片。"
            return
        }
        for url in fileURLs.prefix(room) {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                // Every imported file gets its own folder: two different sources can share a
                // filename (IMG_0001.HEIC) and must never overwrite each other in the session.
                let directory = try ensureSessionDirectory()
                    .appendingPathComponent("Import-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = directory.appendingPathComponent(url.lastPathComponent)
                do {
                    try FileManager.default.copyItem(at: url, to: destination)
                } catch {
                    try? FileManager.default.removeItem(at: directory)
                    throw error
                }
                let traits = AssetTraits(originalIsHEIC: PhotoLibraryService.isHEIF(
                    UTType(filenameExtension: destination.pathExtension)?.identifier ?? ""
                ))
                var item = PhotoItem(assetIdentifier: nil,
                                     displayName: destination.lastPathComponent,
                                     image: Self.previewImage(for: destination),
                                     traits: traits)
                item.fileURL = destination
                items.append(item)
                if selectedID == nil { selectedID = item.id }
                inspect(itemID: item.id, fileURL: destination, traits: traits)
            } catch {
                notice = "无法导入 \(url.lastPathComponent)：\(error.localizedDescription)"
            }
        }
        if !items.isEmpty { screen = .selecting }
    }

    private func prepare(asset: PHAsset) async {
        guard let item = items.first(where: { $0.assetIdentifier == asset.localIdentifier }) else { return }
        let id = item.id
        let thumbnail = await library.thumbnail(for: asset, targetSize: CGSize(width: 1400, height: 1700))
        if let thumbnail { update(id) { $0.image = thumbnail } }

        do {
            let directory = try ensureSessionDirectory()
            let url = try await library.exportOriginal(for: asset, to: directory)
            update(id) { $0.fileURL = url }
            // Parsing a 48MP HEIC is CPU and I/O work; keep it off the main actor.
            let traits = item.traits
            let outcome = try await Task.detached(priority: .userInitiated) { [service = ConversionService.shared] in
                try service.inspect(fileURL: url, traits: traits)
            }.value
            update(id) {
                $0.inspection = outcome.inspection
                $0.verdict = outcome.verdict
                $0.phase = .ready
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            update(id) { $0.phase = .preparingFailed(message) }
        }
    }

    private func inspect(itemID: UUID, fileURL: URL, traits: AssetTraits) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let outcome = try await Task.detached(priority: .userInitiated) { [service = ConversionService.shared] in
                    try service.inspect(fileURL: fileURL, traits: traits)
                }.value
                self.update(itemID) {
                    $0.image = Self.previewImage(for: fileURL, fallback: $0.image)
                    $0.inspection = outcome.inspection
                    $0.verdict = outcome.verdict
                    $0.phase = .ready
                }
            } catch {
                self.update(itemID) { $0.phase = .preparingFailed(error.localizedDescription) }
            }
        }
    }

    func remove(_ item: PhotoItem) {
        items.removeAll { $0.id == item.id }
        if selectedID == item.id { selectedID = items.first?.id }
        if items.isEmpty {
            summary = nil
            screen = .idle
        }
    }

    func select(_ item: PhotoItem) {
        selectedID = item.id
    }

    // MARK: Conversion

    func startConversion() {
        guard convertibleCount > 0 else { return }
        summary = nil
        cancelledByUser = false
        screen = .converting
        conversionTask = Task { [weak self] in
            await self?.runQueue()
        }
    }

    func cancelConversion() {
        guard !isCancelling else { return }
        cancelledByUser = true
        isCancelling = true
        conversionTask?.cancel()
    }

    private func runQueue() async {
        for item in items {
            guard !Task.isCancelled else { break }
            // Retrying failures must never re-save photos that already succeeded.
            guard item.outcome == nil else { continue }
            let id = item.id
            guard item.isConvertible, let fileURL = item.fileURL else {
                if item.verdict?.status == .alreadyEnhanced {
                    update(id) { $0.outcome = .skipped(.alreadyHasTexture) }
                } else if item.verdict?.status == .unsupported {
                    update(id) { $0.outcome = .skipped(item.verdict?.issues.first ?? .notHEIC) }
                } else {
                    update(id) { $0.outcome = .cancelled }
                }
                continue
            }

            update(id) { $0.stage = .readingOriginal }
            let preferredName = Self.preferredName(for: item)
            do {
                let result = try await ConversionService.shared.convert(
                    .init(fileURL: fileURL,
                          traits: item.traits,
                          preferredName: preferredName,
                          saveToLibrary: true)
                ) { stage in
                    Task { @MainActor in
                        self.update(id) { $0.stage = stage }
                    }
                }
                update(id) {
                    $0.stage = .finished
                    $0.integrity = result.integrity
                    $0.outcome = .saved(assetIdentifier: result.savedAssetIdentifier,
                                        byteCount: result.outputByteCount)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch {
                let message: String
                let code: String
                if let failure = error as? ConversionFailure {
                    message = failure.message
                    code = failure.diagnosticCode
                } else if let libraryError = error as? PhotoLibraryError {
                    message = libraryError.errorDescription ?? "保存失败"
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
            }
        }

        for item in items where item.outcome == nil {
            update(item.id) { $0.outcome = .cancelled }
        }
        finish()
    }

    private func finish() {
        let summary = ConversionSummary(items: items)
        self.summary = summary
        diagnosticsText = buildDiagnostics(summary: summary)
        conversionTask = nil
        isCancelling = false
        screen = .result
    }

    func retryFailed() {
        guard items.contains(where: { if case .failed? = $0.outcome { return true } else { return false } }) else { return }
        for item in items {
            if case .failed? = item.outcome {
                update(item.id) { $0.outcome = nil; $0.stage = nil; $0.failedDuringStage = false }
            }
        }
        startConversion()
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
    static func previewImage(for url: URL, fallback: UIImage? = nil) -> UIImage {
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
