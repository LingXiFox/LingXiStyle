import Foundation
import LingXiKit
import LingXiEngine

/// The only conversion entry point. The app, the shortcut and the share extension all call
/// this type; none of them talks to the engine directly.
public final class ConversionService: @unchecked Sendable {
    public static let shared = ConversionService()

    public struct Request: Sendable {
        public let fileURL: URL
        public let traits: AssetTraits
        public let preferredName: String
        public let saveToLibrary: Bool
        /// Ask for a file copy even when the photo is also saved to the library (shortcuts).
        public var returnsFile: Bool

        public init(fileURL: URL,
                    traits: AssetTraits,
                    preferredName: String,
                    saveToLibrary: Bool,
                    returnsFile: Bool = false) {
            self.fileURL = fileURL
            self.traits = traits
            self.preferredName = preferredName
            self.saveToLibrary = saveToLibrary
            self.returnsFile = returnsFile
        }
    }

    public struct Result: Sendable {
        public let savedAssetIdentifier: String?
        public let outputURL: URL?
        public let outputByteCount: Int
        public let integrity: IntegrityReport
        public let inspectionBefore: HEICInspection
        public let inspectionAfter: HEICInspection
        public let mode: String
    }

    private let engine = ConversionEngine()
    private let library = PhotoLibraryService()
    private let fileManager = FileManager.default

    /// Inspects without converting. Used when a photo enters the queue.
    public func inspect(fileURL: URL, traits: AssetTraits) throws -> InspectionOutcome {
        try engine.inspect(fileURL: fileURL, traits: traits)
    }

    public func convert(_ request: Request,
                        onStage: @escaping @Sendable (ConversionStage) -> Void) async throws -> Result {
        let workDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("LingXiConvert-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        // When the caller asked for the file, hand back a copy that outlives this scope.
        // On success the export directory is never removed here: its URL is the caller's only handle.
        var handedBack: URL?
        defer { try? fileManager.removeItem(at: workDirectory) }

        let engine = self.engine
        let output = try await Task.detached(priority: .userInitiated) {
            try engine.convert(fileURL: request.fileURL,
                               traits: request.traits,
                               outputDirectory: workDirectory,
                               onStage: onStage)
        }.value

        // Materialize the caller's copy before touching the library. If the copy fails (for
        // example, the disk is full), no photo has been saved yet, so retrying cannot duplicate
        // an asset. If the later save fails, remove the now-orphaned copy.
        var exportDirectory: URL?
        if request.returnsFile || !request.saveToLibrary {
            let directory = fileManager.temporaryDirectory
                .appendingPathComponent("LingXiOutput-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(request.preferredName)
            do {
                try fileManager.copyItem(at: output.outputURL, to: destination)
                exportDirectory = directory
                handedBack = destination
            } catch {
                try? fileManager.removeItem(at: directory)
                throw error
            }
        }

        var savedIdentifier: String?
        if request.saveToLibrary {
            do {
                savedIdentifier = try await library.saveNewPhoto(from: output.outputURL,
                                                                 preferredName: request.preferredName)
            } catch {
                if let exportDirectory { try? fileManager.removeItem(at: exportDirectory) }
                throw error
            }
        }

        return Result(savedAssetIdentifier: savedIdentifier,
                      outputURL: handedBack,
                      outputByteCount: output.outputByteCount,
                      integrity: output.integrity,
                      inspectionBefore: output.inspectionBefore,
                      inspectionAfter: output.inspectionAfter,
                      mode: output.mode)
    }
}
