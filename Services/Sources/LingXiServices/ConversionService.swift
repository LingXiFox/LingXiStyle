import Foundation
import LingXiKit
import LingXiEngine

/// The only conversion entry point. The app, the shortcut and the share extension all call
/// this type; none of them talks to the engine directly.
public final class ConversionService: @unchecked Sendable {
    public static let shared = ConversionService()

    public struct Request: Sendable {
        public let fileURL: URL
        /// The paired movie of a Live Photo, already exported next to the still. `nil` for a
        /// regular HEIC: the engine then runs the plain still pipeline.
        public let pairedVideoURL: URL?
        /// Which Live Photo pipeline to run. Ignored when `pairedVideoURL` is `nil`.
        public let livePhotoMode: LivePhotoProcessingMode?
        public let traits: AssetTraits
        public let preferredName: String
        public let saveToLibrary: Bool
        /// Ask for a file copy even when the photo is also saved to the library (shortcuts/share).
        public var returnsFile: Bool
        /// Optional caller-owned directory for the returned HEIC. The app passes a folder inside
        /// its session workspace so the result can be previewed/shared and cleaned up with it.
        public var outputDirectory: URL?

        /// Identity of the task/item this conversion belongs to. The app passes both so the
        /// conversion can update the task journal as it moves through reserve → save → commit.
        /// The share extension and shortcuts leave them nil and keep their own containers.
        public let taskID: UUID?
        public let itemID: UUID?
        /// When set, a finished result is copied into the vault before it is saved, so the user
        /// can re-save or export it later without paying the allowance twice.
        public let vaultRetention: VaultRetention?

        public init(fileURL: URL,
                    pairedVideoURL: URL? = nil,
                    livePhotoMode: LivePhotoProcessingMode? = nil,
                    traits: AssetTraits,
                    preferredName: String,
                    saveToLibrary: Bool,
                    returnsFile: Bool = false,
                    outputDirectory: URL? = nil,
                    taskID: UUID? = nil,
                    itemID: UUID? = nil,
                    vaultRetention: VaultRetention? = nil) {
            self.fileURL = fileURL
            self.pairedVideoURL = pairedVideoURL
            self.livePhotoMode = livePhotoMode
            self.traits = traits
            self.preferredName = preferredName
            self.saveToLibrary = saveToLibrary
            self.returnsFile = returnsFile
            self.outputDirectory = outputDirectory
            self.taskID = taskID
            self.itemID = itemID
            self.vaultRetention = vaultRetention
        }

        /// The movie file name that belongs next to `preferredName`.
        public var preferredVideoName: String {
            let stem = (preferredName as NSString).deletingPathExtension
            return (stem.isEmpty ? "LivePhoto" : stem) + "." + ConversionEngine.outputVideoExtension
        }
    }

    public struct Result: Sendable {
        public let savedAssetIdentifier: String?
        public let saveWarning: String?
        public let outputURL: URL?
        /// Set when a Live Photo movie travelled with the still.
        public let outputVideoURL: URL?
        public let outputByteCount: Int
        public let integrity: IntegrityReport
        public let inspectionBefore: HEICInspection
        public let inspectionAfter: HEICInspection
        public let mode: String
        /// `.stillOnly` / `.full` for a Live Photo, `nil` for a regular still.
        public let livePhotoMode: LivePhotoProcessingMode?
        public let videoFrameCount: Int?
        /// The vault record that keeps this result for the configured retention window.
        public let vaultRecordID: UUID?
        /// Set when the result was produced but could not be kept in the vault (for example a
        /// nearly full disk). The conversion itself still succeeded.
        public let vaultWarning: String?
    }

    private let engine: ConversionEngine
    private let library: any PhotoDestination
    private let entitlementProvider: any ProEntitlementProviding
    private let quotaManager: any QuotaManaging
    private let fileManager = FileManager.default
    private let storageConfiguration = StorageConfiguration()

    /// Vault and task journal are attached by the app at launch. The share extension and the
    /// shortcut intents keep them nil: they run in their own containers and must not write into
    /// the app's vault.
    public func configureStorage(vault: VaultStore?, journal: TaskJournal?) {
        storageConfiguration.update(vault: vault, journal: journal)
    }

    public init(engine: ConversionEngine = ConversionEngine(),
                library: any PhotoDestination = PhotoDestinations.standard,
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
        let storage = storageConfiguration.current
        let taskID = request.taskID
        let itemID = request.itemID

        @Sendable func mutateItem(_ update: (inout TaskItemRecord) -> Void) {
            guard let journal = storage.journal, let taskID, let itemID else { return }
            _ = try? journal.mutate(taskID: taskID) { task in
                guard let index = task.items.firstIndex(where: { $0.id == itemID }) else { return }
                update(&task.items[index])
            }
        }

        mutateItem { $0.state = .converting }
        do {
            let result = try await convertCore(
                request,
                onStage: onStage,
                onReserved: { reservation in
                    mutateItem { $0.attachReservation(reservation) }
                },
                onVaultStored: { recordID in
                    mutateItem { $0.vaultRecordID = recordID }
                }
            )
            mutateItem {
                $0.state = .saved
                $0.savedAssetIdentifier = result.savedAssetIdentifier
                $0.outputByteCount = result.outputByteCount
                $0.quotaState = .committed
            }
            return result
        } catch {
            let cancelled = error is CancellationError || Task.isCancelled
            let failure = error as? ConversionFailure
            mutateItem {
                $0.state = cancelled ? .cancelled : .failed
                $0.failureCode = failure?.diagnosticCode ?? (cancelled ? "E_CANCELLED" : "E_UNKNOWN")
                $0.failureMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                if $0.quotaState == .reserved { $0.quotaState = .released }
            }
            throw error
        }
    }

    private func convertCore(_ request: Request,
                             onStage: @escaping @Sendable (ConversionStage) -> Void,
                             onReserved: @Sendable (QuotaReservation) -> Void,
                             onVaultStored: @Sendable (UUID) -> Void) async throws -> Result {
        let isPro = await entitlementProvider.isPro()
        // One Live Photo is one photo: the reservation happens once per asset, whatever the
        // mode and however many frames the movie has.
        let reservation: QuotaReservation?
        do {
            reservation = try quotaManager.reserve(isPro: isPro)
        } catch let error as QuotaError {
            throw ConversionFailure.quota(error)
        } catch {
            throw ConversionFailure.quota(.database(error.localizedDescription))
        }

        if let reservation {
            onReserved(reservation)
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
            if let videoURL = request.pairedVideoURL {
                return try await engine.convertLivePhoto(
                    LivePhotoRequest(stillURL: request.fileURL,
                                     videoURL: videoURL,
                                     mode: request.livePhotoMode ?? .defaultMode,
                                     traits: request.traits,
                                     outputDirectory: workDirectory),
                    onStage: onStage)
            }
            return try engine.convert(fileURL: request.fileURL,
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

        var vaultRecordID: UUID?
        var vaultWarning: String?
        if let retention = request.vaultRetention, let vault = storageConfiguration.current.vault {
            do {
                let record = try vault.insert(photoURL: output.outputURL,
                                              videoURL: output.pairedVideoURL,
                                              displayName: request.preferredName,
                                              livePhotoMode: request.livePhotoMode?.rawValue,
                                              sourceTaskID: request.taskID,
                                              sourceItemID: request.itemID,
                                              retention: retention)
                vaultRecordID = record.id
                onVaultStored(record.id)
            } catch {
                vaultWarning = (error as? LocalizedError)?.errorDescription
                    ?? String(localized: "vault.error.store", defaultValue: "无法把成果存入保险箱。")
            }
        }

        var handedBack: URL?
        var handedBackVideo: URL?
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
            try replaceCopy(from: output.outputURL, to: destination)
            handedBack = destination
            if let movie = output.pairedVideoURL {
                let videoDestination = destinationDirectory
                    .appendingPathComponent(request.preferredVideoName)
                try replaceCopy(from: movie, to: videoDestination)
                handedBackVideo = videoDestination
            }
        }

        var savedIdentifier: String?
        var saveWarning: String?
        if request.saveToLibrary {
            try Task.checkCancellation()
            onStage(.saving)
            let saved: SavedPhoto
            if let movie = output.pairedVideoURL {
                saved = try await library.saveNewLivePhoto(still: output.outputURL,
                                                           video: movie,
                                                           preferredName: request.preferredName)
            } else {
                saved = try await library.saveNewPhoto(from: output.outputURL,
                                                       preferredName: request.preferredName)
            }
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
                      outputVideoURL: handedBackVideo,
                      outputByteCount: output.outputByteCount,
                      integrity: output.integrity,
                      inspectionBefore: output.inspectionBefore,
                      inspectionAfter: output.inspectionAfter,
                      mode: output.mode,
                      livePhotoMode: output.livePhotoMode,
                      videoFrameCount: output.videoFrameCount,
                      vaultRecordID: vaultRecordID,
                      vaultWarning: vaultWarning)
    }

    private final class StorageConfiguration: @unchecked Sendable {
        private let lock = NSLock()
        private var vault: VaultStore?
        private var journal: TaskJournal?

        func update(vault: VaultStore?, journal: TaskJournal?) {
            lock.lock()
            defer { lock.unlock() }
            self.vault = vault
            self.journal = journal
        }

        var current: (vault: VaultStore?, journal: TaskJournal?) {
            lock.lock()
            defer { lock.unlock() }
            return (vault, journal)
        }
    }

    private func replaceCopy(from source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }
}
