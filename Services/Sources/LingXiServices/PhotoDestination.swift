import Foundation

/// A photo the pipeline handed to a destination. On iOS this is a Photos asset; the macOS build
/// only exports files, so its destination never produces one.
public struct SavedPhoto: Sendable {
    public let identifier: String
    /// Set when the asset exists but the post-save re-read could not confirm HEIC. The photo is
    /// already in the library, so callers must treat it as saved (never retry and duplicate it).
    public let warning: String?
    /// True when PhotoKit stored the still and the movie as one Live Photo. A false value after a
    /// requested Live Photo save means the pair was split, which the UI reports as a warning.
    public let isLivePhoto: Bool

    public init(identifier: String, warning: String? = nil, isLivePhoto: Bool = false) {
        self.identifier = identifier
        self.warning = warning
        self.isLivePhoto = isLivePhoto
    }
}

/// Where a finished conversion goes. The pipeline only knows this protocol: iOS writes into the
/// Photos library, macOS hands the exported files back to the app.
public protocol PhotoDestination: Sendable {
    func saveNewPhoto(from fileURL: URL, preferredName: String) async throws -> SavedPhoto
    func saveNewLivePhoto(still: URL, video: URL, preferredName: String) async throws -> SavedPhoto
}

public enum PhotoDestinationError: LocalizedError {
    case libraryUnavailable

    public var errorDescription: String? {
        switch self {
        case .libraryUnavailable:
            return String(localized: "library.error.unavailable",
                          defaultValue: "这台设备上没有可写入的照片图库，请改用导出到文件夹。")
        }
    }
}

/// macOS fallback. The desktop build always exports to a folder the user picked, so the library
/// path is unreachable; failing loudly beats silently pretending a save happened.
public struct ExportOnlyPhotoDestination: PhotoDestination {
    public init() {}

    public func saveNewPhoto(from fileURL: URL, preferredName: String) async throws -> SavedPhoto {
        throw PhotoDestinationError.libraryUnavailable
    }

    public func saveNewLivePhoto(still: URL, video: URL, preferredName: String) async throws -> SavedPhoto {
        throw PhotoDestinationError.libraryUnavailable
    }
}

public enum PhotoDestinations {
    /// The destination an entry point gets when it does not inject one.
    public static var standard: any PhotoDestination {
        #if canImport(UIKit)
        PhotoLibraryService()
        #else
        ExportOnlyPhotoDestination()
        #endif
    }
}
