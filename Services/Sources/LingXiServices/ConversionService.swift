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
        /// Ask for a file copy even when the photo is also saved to the library (shortcuts/share).
        public var returnsFile: Bool
        /// Optional caller-owned directory for the returned HEIC. The app passes a folder inside
        /// its session workspace so the result can be previewed/shared and cleaned up with it.
        public var outputDirectory: URL?

        public init(fileURL: URL,
                    traits: AssetTraits,
                    preferredName: String,
                    saveToLibrary: Bool,
                    returnsFile: Bool = false,
                    outputDirectory: URL? = nil) {
            self.fileURL = fileURL
            self.traits = traits
            self.preferredName = preferredName
            self.saveToLibrary = saveToLibrary
            self.returnsFile = returnsFile
            self.outputDirectory = outputDirectory
        }
    }

    public struct Result: Sendable {
        public let savedAssetIdentifier: String?
        public let saveWarning: String?
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

        var exportDirectory: URL?
        var didSucceed = false
        defer {
            try? fileManager.removeItem(at: workDirectory)
            if !didSucceed, let exportDirectory {
                try? fileManager.removeItem(at: exportDirectory)
            }
        }

        let engine = self.engine
        let engineTask = Task.detached(priority: .userInitiated) {
            try engine.convert(fileURL: request.fileURL,
                               traits: request.traits,
                               outputDirectory: workDirectory,
                               onStage: onStage)
        }
        let output = try await withTaskCancellationHandler {
            try await engineTask.value
        } onCancel: {
            engineTask.cancel()
        }

        // The engine has reached a safe boundary. From here on every await is preceded by a
        // cancellation check, so a cancelled app session cannot silently save a photo.
        try Task.checkCancellation()

        var handedBack: URL?
        if request.returnsFile || !request.saveToLibrary {
            try Task.checkCancellation()
            let destinationDirectory: URL
            if let outputDirectory = request.outputDirectory {
                try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
                destinationDirectory = outputDirectory
            } else {
                let directory = fileManager.temporaryDirectory
                    .appendingPathComponent("LingXiOutput-\(UUID().uuidString)", isDirectory: true)
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                exportDirectory = directory
                destinationDirectory = directory
            }
            onStage(.saving)
            let destination = destinationDirectory.appendingPathComponent(request.preferredName)
            do {
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: output.outputURL, to: destination)
                handedBack = destination
            } catch {
                throw error
            }
        }

        var savedIdentifier: String?
        var saveWarning: String?
        if request.saveToLibrary {
            try Task.checkCancellation()
            onStage(.saving)
            let saved = try await library.saveNewPhoto(from: output.outputURL,
                                                       preferredName: request.preferredName)
            savedIdentifier = saved.identifier
            saveWarning = saved.warning
        }

        onStage(.finished)
        didSucceed = true
        return Result(savedAssetIdentifier: savedIdentifier,
                      saveWarning: saveWarning,
                      outputURL: handedBack,
                      outputByteCount: output.outputByteCount,
                      integrity: output.integrity,
                      inspectionBefore: output.inspectionBefore,
                      inspectionAfter: output.inspectionAfter,
                      mode: output.mode)
    }
}
