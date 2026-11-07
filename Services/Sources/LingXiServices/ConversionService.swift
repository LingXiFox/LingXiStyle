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

    private let engine: ConversionEngine
    private let library: PhotoLibraryService
    private let entitlementProvider: any ProEntitlementProviding
    private let quotaManager: any QuotaManaging
    private let fileManager = FileManager.default

    public init(engine: ConversionEngine = ConversionEngine(),
                library: PhotoLibraryService = PhotoLibraryService(),
                entitlementProvider: any ProEntitlementProviding = StoreKitEntitlementProvider(),
                quotaManager: any QuotaManaging = QuotaManager.shared) {
        self.engine = engine
        self.library = library
        self.entitlementProvider = entitlementProvider
        self.quotaManager = quotaManager
    }

    /// Reads the same allowance the conversion path will enforce. The app uses this for its
    /// preflight; Share Extension and App Shortcuts get the identical StoreKit-backed answer.
    public func quotaStatus() async -> QuotaStatus {
        let isPro = await entitlementProvider.isPro()
        do {
            return try quotaManager.status(isPro: isPro)
        } catch {
            return .unavailable()
        }
    }

    public func entitlementIsPro() async -> Bool {
        await entitlementProvider.isPro()
    }

    /// Inspects without converting. Used when a photo enters the queue.
    public func inspect(fileURL: URL, traits: AssetTraits) throws -> InspectionOutcome {
        try engine.inspect(fileURL: fileURL, traits: traits)
    }

    public func convert(_ request: Request,
                        onStage: @escaping @Sendable (ConversionStage) -> Void) async throws -> Result {
        let isPro = await entitlementProvider.isPro()
        let reservation: QuotaReservation?
        do {
            reservation = try quotaManager.reserve(isPro: isPro)
        } catch let error as QuotaError {
            throw ConversionFailure.quota(error)
        } catch {
            throw ConversionFailure.quota(.database(error.localizedDescription))
        }

        // A reservation is released on every failure path: incompatible file, engine error,
        // cancellation, or a failed save. A successful output commits it exactly once.
        var didCommit = false
        defer {
            if !didCommit, let reservation {
                try? quotaManager.release(reservation)
            }
        }

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

        // The photo is already saved at this point. A quota-store failure must not turn a
        // successful conversion into an error that invites a duplicate retry; the reservation
        // is left to expire if the commit could not be written.
        didCommit = true
        if let reservation {
            try? quotaManager.commit(reservation)
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
