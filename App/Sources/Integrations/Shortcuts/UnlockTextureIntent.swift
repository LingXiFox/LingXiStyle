import AppIntents
import Foundation
import UniformTypeIdentifiers
import LingXiKit
import LingXiEngine
import LingXiServices

/// Shortcut entry point. Like every other entry it only talks to ConversionService; the file
/// is copied into our own sandbox before anything is inspected.
struct UnlockTextureIntent: AppIntent {
    static let title: LocalizedStringResource = "添加纹理与颗粒"
    static let description = IntentDescription("为 HEIC 原片追加纹理与颗粒，并另存为新照片。原图保持不变。")
    static let openAppWhenRun = false

    @Parameter(title: "照片")
    var photos: [IntentFile]

    @Parameter(title: "保存到相册", default: true)
    var saveToLibrary: Bool

    @Parameter(title: "返回转换后的文件", default: false)
    var returnsFiles: Bool

    @Parameter(title: "仅检查兼容性", default: false)
    var checkOnly: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("为 \(\.$photos) 添加纹理与颗粒") {
            \.$saveToLibrary
            \.$returnsFiles
            \.$checkOnly
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> & ProvidesDialog {
        let outcome = try await Self.run(photos: photos,
                                         saveToLibrary: saveToLibrary,
                                         returnsFiles: returnsFiles,
                                         checkOnly: checkOnly,
                                         service: ConversionService.shared)
        return .result(value: outcome.outputs, dialog: IntentDialog(stringLiteral: outcome.dialog))
    }

    /// The orchestration is separate from the AppIntent wrapper so the integration tests can
    /// exercise the exact request/response path with a controlled or real ConversionService.
    @MainActor
    static func run(photos: [IntentFile],
                    saveToLibrary: Bool,
                    returnsFiles: Bool,
                    checkOnly: Bool,
                    service: any ShortcutConverting) async throws -> ShortcutRunResult {
        guard !photos.isEmpty else {
            throw IntentError.noInput
        }
        // Without at least one visible output the shortcut would do work nobody can use.
        guard checkOnly || saveToLibrary || returnsFiles else {
            throw IntentError.noOutput
        }

        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LingXiIntent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        var outputs: [IntentFile] = []
        var ready = 0
        var converted = 0
        var savedToLibrary = 0
        var skipped = 0
        var failed = 0
        var unprocessed = 0
        var quotaExhausted = false
        var firstFailure: String?

        for (index, file) in photos.enumerated() {
            try Task.checkCancellation()
            let name = Self.safeName(file.filename, fallbackIndex: index)
            // One directory per photo: two inputs can share a filename, and the second must not
            // overwrite the first before it has been converted.
            let itemDirectory = workDirectory.appendingPathComponent("item-\(index)", isDirectory: true)
            let source = itemDirectory.appendingPathComponent(name)
            do {
                try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
                try Self.copy(file, to: source)
            } catch {
                failed += 1
                firstFailure = firstFailure ?? String(localized: "intent.error.unreadable", defaultValue: "\(name)：无法读取文件")
                continue
            }

            let urlType = UTType(filenameExtension: source.pathExtension)
            let traits = AssetTraits(originalIsHEIC: urlType?.conforms(to: .heic) == true
                                     || urlType?.conforms(to: .heif) == true)

            do {
                let outcome = try await Task.detached(priority: .userInitiated) {
                    try service.inspectForShortcut(fileURL: source, traits: traits)
                }.value

                if checkOnly {
                    if outcome.verdict.isReady { ready += 1 } else { skipped += 1 }
                    continue
                }

                guard outcome.verdict.isReady else {
                    skipped += 1
                    continue
                }

                let preferredName = Self.outputName(for: name)
                let result = try await service.convertForShortcut(.init(fileURL: source,
                                                                        traits: traits,
                                                                        preferredName: preferredName,
                                                                        saveToLibrary: saveToLibrary,
                                                                        returnsFile: returnsFiles),
                                                                  onStage: { _ in })
                if saveToLibrary { savedToLibrary += 1 }
                if returnsFiles {
                    guard let outputURL = result.outputURL else {
                        failed += 1
                        firstFailure = firstFailure ?? String(localized: "intent.error.unreadableOutput", defaultValue: "\(preferredName)：无法读取转换结果")
                        continue
                    }
                    // The intent's work directory is deleted when perform() returns, and the
                    // conversion service owns its temporary output. Copy the bytes into the
                    // IntentFile so Shortcuts receives a file that outlives both.
                    do {
                        let data = try Data(contentsOf: outputURL)
                        outputs.append(IntentFile(data: data, filename: preferredName, type: .heic))
                    } catch {
                        failed += 1
                        firstFailure = firstFailure ?? String(localized: "intent.error.unreadableOutput", defaultValue: "\(preferredName)：无法读取转换结果")
                        let parent = outputURL.deletingLastPathComponent()
                        if parent.lastPathComponent.hasPrefix("LingXiOutput-") {
                            try? FileManager.default.removeItem(at: parent)
                        }
                        continue
                    }
                    let parent = outputURL.deletingLastPathComponent()
                    if parent.lastPathComponent.hasPrefix("LingXiOutput-") {
                        try? FileManager.default.removeItem(at: parent)
                    }
                }
                converted += 1
            } catch let failure as ConversionFailure {
                if case .quota(.exhausted) = failure {
                    quotaExhausted = true
                    unprocessed = photos.count - index
                    firstFailure = firstFailure ?? String(localized: "intent.error.conversion", defaultValue: "\(name)：\(failure.message)")
                    break
                }
                failed += 1
                firstFailure = firstFailure ?? String(localized: "intent.error.conversion", defaultValue: "\(name)：\(failure.message)")
            } catch let failure as PhotoLibraryError {
                failed += 1
                firstFailure = firstFailure ?? String(localized: "intent.error.library", defaultValue: "\(name)：\(failure.errorDescription ?? String(localized: "保存失败"))")
            } catch {
                failed += 1
                firstFailure = firstFailure ?? String(localized: "intent.error.generic", defaultValue: "\(name)：\(error.localizedDescription)")
            }
        }

        let dialog: String
        if checkOnly {
            dialog = String(localized: "intent.dialog.check", defaultValue: "可处理 \(ready) 张，跳过 \(skipped) 张，失败 \(failed) 张。")
        } else {
            dialog = String(localized: "intent.dialog.convert", defaultValue: "已转换 \(converted) 张，其中 \(savedToLibrary) 张已存入相册；跳过 \(skipped) 张，失败 \(failed) 张。")
                + (quotaExhausted ? String(localized: "intent.dialog.quota", defaultValue: "\n\(unprocessed) 张因今日免费额度用完未处理。") : "")
                + (firstFailure.map { String(localized: "intent.dialog.firstFailure", defaultValue: "\n第一处问题：\($0)") } ?? "")
        }

        return ShortcutRunResult(outputs: outputs,
                                 dialog: dialog,
                                 ready: ready,
                                 converted: converted,
                                 savedToLibrary: savedToLibrary,
                                 skipped: skipped,
                                 failed: failed,
                                 unprocessed: unprocessed,
                                 quotaExhausted: quotaExhausted)
    }

    // MARK: Helpers

    private static func copy(_ file: IntentFile, to destination: URL) throws {
        if let source = file.fileURL {
            // Files handed over by Shortcuts may live outside our sandbox and need a scope.
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        } else {
            try file.data.write(to: destination, options: .atomic)
        }
    }

    private static func safeName(_ name: String, fallbackIndex: Int) -> String {
        let trimmed = (name as NSString).lastPathComponent
        let cleaned = trimmed
            .components(separatedBy: .controlCharacters).joined()
            .replacingOccurrences(of: "/", with: "_")
        let base = cleaned.isEmpty || cleaned == "." || cleaned == ".."
            ? "photo-\(fallbackIndex + 1).heic"
            : cleaned
        return String(base.prefix(160))
    }

    private static func outputName(for name: String) -> String {
        let stem = (name as NSString).deletingPathExtension
        let base = stem.hasSuffix("_TextureGrain") ? stem : stem + "_TextureGrain"
        return base + ".HEIC"
    }

}

// MARK: - Conversion seam

protocol ShortcutConverting: Sendable {
    func inspectForShortcut(fileURL: URL, traits: AssetTraits) throws -> InspectionOutcome
    func convertForShortcut(_ request: ConversionService.Request,
                            onStage: @escaping @Sendable (ConversionStage) -> Void) async throws -> ShortcutConversionOutcome
}

struct ShortcutConversionOutcome: Sendable {
    let outputURL: URL?
}

extension ConversionService: ShortcutConverting {
    func inspectForShortcut(fileURL: URL, traits: AssetTraits) throws -> InspectionOutcome {
        try inspect(fileURL: fileURL, traits: traits)
    }

    func convertForShortcut(_ request: ConversionService.Request,
                            onStage: @escaping @Sendable (ConversionStage) -> Void) async throws -> ShortcutConversionOutcome {
        let result = try await convert(request, onStage: onStage)
        return ShortcutConversionOutcome(outputURL: result.outputURL)
    }
}

struct ShortcutRunResult {
    let outputs: [IntentFile]
    let dialog: String
    let ready: Int
    let converted: Int
    let savedToLibrary: Int
    let skipped: Int
    let failed: Int
    let unprocessed: Int
    let quotaExhausted: Bool
}

extension UnlockTextureIntent {
    enum IntentError: LocalizedError {
        case noInput
        case noOutput

        var errorDescription: String? {
            switch self {
            case .noInput: return String(localized: "请先选择至少一张 HEIC 照片。")
            case .noOutput: return String(localized: "请至少打开「保存到相册」或「返回转换后的文件」。")
            }
        }
    }
}

struct LingXiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: UnlockTextureIntent(),
                    phrases: ["用 \(.applicationName) 添加纹理与颗粒"],
                    shortTitle: "添加纹理与颗粒",
                    systemImageName: "square.3.layers.3d")
    }
}