import Foundation
import Photos
import UIKit
import UniformTypeIdentifiers
import LingXiKit

public enum PhotoLibraryError: LocalizedError {
    case noHEICResource([String])
    case exportFailed(String)
    case saveFailed(String)
    case savedAssetMissing
    case savedAssetIsNotHEIC([String])

    public var errorDescription: String? {
        switch self {
        case .noHEICResource(let types):
            return "这张照片没有 HEIC 原件（\(types.joined(separator: ", "))），请在 LingXiStyle 内从图库选择原片。"
        case .exportFailed(let detail):
            return "下载原件失败：\(detail)"
        case .saveFailed(let detail):
            return "保存到相册失败：\(detail)"
        case .savedAssetMissing:
            return "照片已写入，但系统没有返回它的标识。"
        case .savedAssetIsNotHEIC(let types):
            return "保存后的资源不是 HEIC（\(types.joined(separator: ", "))），已停止确认流程。"
        }
    }

    public var diagnosticCode: String {
        switch self {
        case .noHEICResource: return "E_PHOTO_NO_HEIC"
        case .exportFailed: return "E_PHOTO_EXPORT"
        case .saveFailed: return "E_PHOTO_SAVE"
        case .savedAssetMissing: return "E_PHOTO_SAVED_MISSING"
        case .savedAssetIsNotHEIC: return "E_PHOTO_SAVED_NOT_HEIC"
        }
    }
}

/// Thin PhotoKit adapter. It never edits pixels and never re-encodes: it only hands the
/// original resource file to the engine, and writes the engine's file back as a new asset.
public struct PhotoLibraryService {
    public init() {}

    public static let supportedContentTypes: [UTType] = [.heic, .heif]

    // MARK: Authorization

    public static var authorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    public static func requestAuthorization() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
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

    public func thumbnail(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return await withCheckedContinuation { continuation in
            let box = ResumeBox()
            PHImageManager.default().requestImage(for: asset,
                                                  targetSize: targetSize,
                                                  contentMode: .aspectFill,
                                                  options: options) { image, _ in
                guard box.claim() else { return }
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: Original export

    /// Copies the photo resource's original bytes to disk. Network access lets PhotoKit pull an
    /// iCloud original, which is why the UI has a real "正在下载原件" phase.
    public func exportOriginal(for asset: PHAsset, to directory: URL) async throws -> URL {
        let resources = PHAssetResource.assetResources(for: asset)
        let heifPhotos = resources.filter { $0.type == .photo && Self.isHEIF($0.uniformTypeIdentifier) }
        guard let resource = heifPhotos.first else {
            throw PhotoLibraryError.noHEICResource(resources.map(\.uniformTypeIdentifier))
        }
        // Every export gets its own directory: two assets can share originalFilename (IMG_0001.HEIC),
        // and writing both into one session directory would silently overwrite the first original.
        let itemDirectory = directory.appendingPathComponent("Photo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
        let filename = URL(fileURLWithPath: resource.originalFilename).lastPathComponent
        let url = itemDirectory.appendingPathComponent(filename.isEmpty ? "original.heic" : filename)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
                    if let error {
                        continuation.resume(throwing: PhotoLibraryError.exportFailed(error.localizedDescription))
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: itemDirectory)
            throw error
        }
        return url
    }

    // MARK: Save

    /// Adds the converted file as a brand-new asset, then reads it back to prove PhotoKit kept HEIC.
    @discardableResult
    public func saveNewPhoto(from fileURL: URL, preferredName: String) async throws -> String {
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
        try verifySavedAssetIsHEIC(identifier: identifier)
        return identifier
    }

    private func verifySavedAssetIsHEIC(identifier: String) throws {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject else { throw PhotoLibraryError.savedAssetMissing }
        let resources = PHAssetResource.assetResources(for: asset)
        let photos = resources.filter { $0.type == .photo }
        let isHEIC = photos.contains { Self.isHEIF($0.uniformTypeIdentifier) }
        guard isHEIC else {
            throw PhotoLibraryError.savedAssetIsNotHEIC(photos.map(\.uniformTypeIdentifier))
        }
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

/// PHImageManager can deliver a degraded image first; the continuation must resume exactly once.
private final class ResumeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return false }
        resumed = true
        return true
    }
}
