import Foundation
import LingXiKit

#if canImport(UIKit)
import Photos
import UIKit
import UniformTypeIdentifiers

/// The Photos-library destination the iPhone and iPad builds use. The macOS build exports files
/// instead, so it never links PhotoKit.
extension PhotoLibraryService: PhotoDestination {}

/// The still plus, for a Live Photo, the paired movie PhotoKit handed over with it.
public struct ExportedOriginal: Sendable {
    public let imageURL: URL
    /// Nil when the asset claims to be a Live Photo but PhotoKit has no paired movie for it.
    public let videoURL: URL?
    public let isLivePhoto: Bool

    public init(imageURL: URL, videoURL: URL?, isLivePhoto: Bool) {
        self.imageURL = imageURL
        self.videoURL = videoURL
        self.isLivePhoto = isLivePhoto
    }
}

public enum PhotoLibraryError: LocalizedError {
    case noHEICResource([String])
    case exportFailed(String)
    case addPermissionDenied
    case saveFailed(String)
    case savedAssetMissing
    case savedAssetIsNotHEIC([String])
    case livePhotoNotSupported

    public var errorDescription: String? {
        switch self {
        case .noHEICResource(let types):
            return String(localized: "library.error.noHEIC", defaultValue: "这张照片没有 HEIC 原件（\(types.joined(separator: "、"))），请在 \(Brand.name) 内从图库选择原片。")
        case .exportFailed(let detail):
            return String(localized: "library.error.download", defaultValue: "下载原件失败：\(detail)")
        case .addPermissionDenied:
            return String(localized: "library.error.addPermission", defaultValue: "没有相册写入权限。请在系统设置中允许 \(Brand.name) 添加照片，再回来重试。")
        case .saveFailed(let detail):
            return String(localized: "library.error.save", defaultValue: "保存到相册失败：\(detail)")
        case .savedAssetMissing:
            return String(localized: "照片已写入，但系统没有返回它的标识。")
        case .savedAssetIsNotHEIC(let types):
            return String(localized: "library.error.savedNotHEIC", defaultValue: "保存后的资源不是 HEIC（\(types.joined(separator: "、"))），已停止确认流程。")
        case .livePhotoNotSupported:
            return String(localized: "library.error.livePhotoUnsupported", defaultValue: "这台设备无法把动态画面和主照片一起保存为实况照片。")
        }
    }

    public var diagnosticCode: String {
        switch self {
        case .noHEICResource: return "E_PHOTO_NO_HEIC"
        case .exportFailed: return "E_PHOTO_EXPORT"
        case .addPermissionDenied: return "E_PHOTO_ADD_DENIED"
        case .saveFailed: return "E_PHOTO_SAVE"
        case .savedAssetMissing: return "E_PHOTO_SAVED_MISSING"
        case .savedAssetIsNotHEIC: return "E_PHOTO_SAVED_NOT_HEIC"
        case .livePhotoNotSupported: return "E_PHOTO_LIVE_UNSUPPORTED"
        }
    }
}

/// Thin PhotoKit adapter. It never edits pixels and never re-encodes: it only hands the
/// original resource file to the engine, and writes the engine's file back as a new asset.
public struct PhotoLibraryService {
    public init() {}

    public static let supportedContentTypes: [UTType] = [.heic, .heif]

    // MARK: Authorization

    public static var readAuthorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    public static var addAuthorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .addOnly)
    }

    /// Kept for callers that only need to know whether the library can be read.
    public static var authorizationStatus: PHAuthorizationStatus {
        readAuthorizationStatus
    }

    public static func requestReadAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Backwards-compatible alias used by older call sites.
    public static func requestAuthorization() async -> PHAuthorizationStatus {
        await requestReadAuthorization()
    }

    public static func requestAddAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }

    // MARK: Traits

    public func traits(for asset: PHAsset) -> AssetTraits {
        let resources = PHAssetResource.assetResources(for: asset)
        let hasHEICPhoto = resources.contains { resource in
            resource.type == .photo && Self.isHEIF(resource.uniformTypeIdentifier)
        }
        let hasRAW = resources.contains { resource in
            guard resource.type == .photo || resource.type == .alternatePhoto else { return false }
            return Self.isRAW(resource.uniformTypeIdentifier)
        }
        return AssetTraits(
            isLivePhoto: asset.mediaSubtypes.contains(.photoLive),
            isRAWPlusHEIC: hasRAW && hasHEICPhoto,
            isEdited: asset.hasAdjustments,
            originalIsHEIC: hasHEICPhoto
        )
    }

    // MARK: Thumbnails

    /// Returns only the final image. PhotoKit may call the handler with a degraded preview
    /// first; ignoring those callbacks prevents the picker from being stuck on a blurry image.
    /// Cancelling the surrounding Task cancels the PhotoKit request as well.
    public func thumbnail(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.version = .current

        let state = ImageRequestState()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                state.install(continuation)
                let requestID = PHImageManager.default().requestImage(for: asset,
                                                                      targetSize: targetSize,
                                                                      contentMode: .aspectFit,
                                                                      options: options) { image, info in
                    if info?[PHImageErrorKey] != nil {
                        state.finish(nil)
                        return
                    }
                    if (info?[PHImageCancelledKey] as? Bool) == true {
                        state.finish(nil)
                        return
                    }
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    guard !isDegraded else { return }
                    state.finish(image)
                }
                state.setRequestID(requestID)
            }
        } onCancel: {
            state.cancel()
        }
    }

    // MARK: Original export

    /// Copies the photo resource's original bytes to disk, plus the paired movie for a Live
    /// Photo. Network access lets PhotoKit pull an iCloud original, which is why the UI has a real
    /// String(localized: "正在下载原件") phase.
    ///
    /// PhotoKit's writeData API has no cancellable request ID and no synchronous cancellation.
    /// We therefore resume the caller immediately on Task cancellation and clean up the item
    /// directory when the eventual completion arrives.
    public func exportOriginal(for asset: PHAsset,
                               to directory: URL,
                               progress: (@Sendable (Double) -> Void)? = nil) async throws -> ExportedOriginal {
        let resources = PHAssetResource.assetResources(for: asset)
        let heifPhotos = resources.filter { $0.type == .photo && Self.isHEIF($0.uniformTypeIdentifier) }
        guard let resource = heifPhotos.first else {
            throw PhotoLibraryError.noHEICResource(resources.map(\.uniformTypeIdentifier))
        }
        let isLivePhoto = asset.mediaSubtypes.contains(.photoLive)
        // Every export gets its own directory: two assets can share originalFilename (IMG_0001.HEIC),
        // and writing both into one session directory would silently overwrite the first original.
        let itemDirectory = directory.appendingPathComponent("Photo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
        let filename = URL(fileURLWithPath: resource.originalFilename).lastPathComponent
        let url = itemDirectory.appendingPathComponent(filename.isEmpty ? "original.heic" : filename)

        do {
            // The movie is normally the larger resource, so the still takes the first 40% of the
            // bar and the movie the rest. Both numbers still come from PhotoKit's own handler.
            let stillProgress: (@Sendable (Double) -> Void)? = progress.map { report -> @Sendable (Double) -> Void in
                { value in report(value * 0.4) }
            }
            try await write(resource: resource, to: url, progress: stillProgress)

            var videoURL: URL?
            if isLivePhoto, let movie = pairedVideoResource(of: resources) {
                let movieURL = itemDirectory.appendingPathComponent(Self.videoFilename(for: url))
                let movieProgress: (@Sendable (Double) -> Void)? = progress.map { report -> @Sendable (Double) -> Void in
                    { value in report(0.4 + value * 0.6) }
                }
                try await write(resource: movie, to: movieURL, progress: movieProgress)
                videoURL = movieURL
                progress?(1)
            }
            return ExportedOriginal(imageURL: url, videoURL: videoURL, isLivePhoto: isLivePhoto)
        } catch {
            try? FileManager.default.removeItem(at: itemDirectory)
            throw error
        }
    }

    private func pairedVideoResource(of resources: [PHAssetResource]) -> PHAssetResource? {
        resources.first { $0.type == .pairedVideo } ?? resources.first { $0.type == .fullSizePairedVideo }
    }

    static func videoFilename(for stillURL: URL) -> String {
        stillURL.deletingPathExtension().lastPathComponent + ".MOV"
    }

    private func write(resource: PHAssetResource,
                       to url: URL,
                       progress: (@Sendable (Double) -> Void)?) async throws {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        if let progress {
            options.progressHandler = { value in
                progress(value)
            }
        }

        let state = ExportRequestState()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                state.install(continuation)
                PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
                    let claimed = state.finish(error: error.map {
                        PhotoLibraryError.exportFailed($0.localizedDescription)
                    })
                    if !claimed {
                        // The caller already cancelled and removed the directory. If PhotoKit
                        // finished writing afterwards, make sure no orphan bytes remain.
                        try? FileManager.default.removeItem(at: url)
                    }
                }
            }
        } onCancel: {
            state.cancel()
        }
    }

    // MARK: Save

    /// Adds the converted file as a brand-new asset, then reads it back to prove PhotoKit kept HEIC.
    /// The add-only permission is requested at the moment of saving, never at app launch.
    @discardableResult
    public func saveNewPhoto(from fileURL: URL, preferredName: String) async throws -> SavedPhoto {
        try await ensureAddPermission()

        var placeholderIdentifier: String?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = preferredName
                options.shouldMoveFile = false
                request.addResource(with: .photo, fileURL: fileURL, options: options)
                placeholderIdentifier = request.placeholderForCreatedAsset?.localIdentifier
            }
        } catch {
            throw PhotoLibraryError.saveFailed(error.localizedDescription)
        }
        guard let identifier = placeholderIdentifier else { throw PhotoLibraryError.savedAssetMissing }
        return verifySaved(identifier: identifier, expectsLivePhoto: false)
    }

    /// Saves the still and its movie as one new Live Photo. Both resources go into a single
    /// `performChanges` transaction so Photos can never keep two unrelated assets, and the pair
    /// keeps the content identifier the engine preserved.
    @discardableResult
    public func saveNewLivePhoto(still: URL, video: URL, preferredName: String) async throws -> SavedPhoto {
        try await ensureAddPermission()
        let supported = PHAssetCreationRequest.supportsAssetResourceTypes([
            NSNumber(value: PHAssetResourceType.photo.rawValue),
            NSNumber(value: PHAssetResourceType.pairedVideo.rawValue)
        ])
        guard supported else { throw PhotoLibraryError.livePhotoNotSupported }

        var placeholderIdentifier: String?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()

                let photoOptions = PHAssetResourceCreationOptions()
                photoOptions.originalFilename = preferredName
                photoOptions.shouldMoveFile = false
                request.addResource(with: .photo, fileURL: still, options: photoOptions)

                let videoOptions = PHAssetResourceCreationOptions()
                videoOptions.originalFilename = (preferredName as NSString).deletingPathExtension + ".MOV"
                videoOptions.shouldMoveFile = false
                request.addResource(with: .pairedVideo, fileURL: video, options: videoOptions)

                placeholderIdentifier = request.placeholderForCreatedAsset?.localIdentifier
            }
        } catch {
            throw PhotoLibraryError.saveFailed(error.localizedDescription)
        }
        guard let identifier = placeholderIdentifier else { throw PhotoLibraryError.savedAssetMissing }
        return verifySaved(identifier: identifier, expectsLivePhoto: true)
    }

    private func ensureAddPermission() async throws {
        var status = Self.addAuthorizationStatus
        if status == .notDetermined {
            status = await Self.requestAddAuthorization()
        }
        guard status == .authorized || status == .limited else {
            throw PhotoLibraryError.addPermissionDenied
        }
    }

    /// Reads the new asset back. The asset is already in the library, so a failed re-read is a
    /// warning, never an error: retrying would create a duplicate photo.
    private func verifySaved(identifier: String, expectsLivePhoto: Bool) -> SavedPhoto {
        do {
            let check = try inspectSavedAsset(identifier: identifier, expectsLivePhoto: expectsLivePhoto)
            return SavedPhoto(identifier: identifier, warning: check.warning, isLivePhoto: check.isLivePhoto)
        } catch let error as PhotoLibraryError {
            return SavedPhoto(identifier: identifier, warning: error.errorDescription, isLivePhoto: false)
        } catch {
            return SavedPhoto(identifier: identifier, warning: error.localizedDescription, isLivePhoto: false)
        }
    }

    private func inspectSavedAsset(identifier: String, expectsLivePhoto: Bool) throws -> (warning: String?, isLivePhoto: Bool) {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject else { throw PhotoLibraryError.savedAssetMissing }
        let resources = PHAssetResource.assetResources(for: asset)
        let photos = resources.filter { $0.type == .photo }
        guard photos.contains(where: { Self.isHEIF($0.uniformTypeIdentifier) }) else {
            throw PhotoLibraryError.savedAssetIsNotHEIC(photos.map(\.uniformTypeIdentifier))
        }
        guard expectsLivePhoto else { return (nil, false) }
        let keptPair = asset.mediaSubtypes.contains(.photoLive)
            && resources.contains { $0.type == .pairedVideo || $0.type == .fullSizePairedVideo }
        guard keptPair else {
            return (String(localized: "library.warning.splitLivePhoto", defaultValue: "已另存为新照片，但系统没有把动态画面一起识别为实况照片。原片未改动。"), false)
        }
        return (nil, true)
    }

    // MARK: Helpers

    public static func isHEIF(_ identifier: String) -> Bool {
        guard let type = UTType(identifier) else { return false }
        return type.conforms(to: .heic) || type.conforms(to: .heif)
    }

    public static func isRAW(_ identifier: String) -> Bool {
        guard let type = UTType(identifier) else { return false }
        return type.conforms(to: .rawImage) || type.conforms(to: .dng)
    }
}

/// PHImageManager can deliver a degraded image first and can answer after cancellation. This
/// small gate makes sure the continuation resumes exactly once and cancels the right request.
private final class ImageRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UIImage?, Never>?
    private var requestID: PHImageRequestID = PHInvalidImageRequestID
    private var finished = false
    private var cancelled = false

    func install(_ continuation: CheckedContinuation<UIImage?, Never>) {
        lock.lock()
        if finished {
            lock.unlock()
            continuation.resume(returning: nil)
            return
        }
        self.continuation = continuation
        let cancelNow = cancelled
        let id = requestID
        lock.unlock()
        if cancelNow, id != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(id)
        }
    }

    func setRequestID(_ requestID: PHImageRequestID) {
        lock.lock()
        if finished || cancelled {
            lock.unlock()
            if requestID != PHInvalidImageRequestID {
                PHImageManager.default().cancelImageRequest(requestID)
            }
            return
        }
        self.requestID = requestID
        lock.unlock()
    }

    func finish(_ image: UIImage?) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: image)
    }

    func cancel() {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        cancelled = true
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        let requestID = self.requestID
        lock.unlock()
        if requestID != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(requestID)
        }
        continuation?.resume(returning: nil)
    }
}

/// PhotoKit's writeData completion is the only signal that the file is fully written. The state
/// lets a cancelled caller resume immediately while still cleaning up a late completion.
private final class ExportRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var finished = false

    func install(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        if finished {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    /// Returns true when this completion owns the continuation.
    func finish(error: Error?) -> Bool {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return false
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
        return true
    }

    func cancel() {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: CancellationError())
    }
}

#endif