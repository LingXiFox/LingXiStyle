import AppIntents
import Foundation
import UniformTypeIdentifiers
import LingXiKit
import LingXiEngine
import LingXiServices

/// Shortcut entry point. Like every other entry it only talks to ConversionService; the file
/// is copied into our own sandbox before anything is inspected.
struct UnlockTextureIntent: AppIntent {
    static let title: LocalizedStringResource = "解锁第三代摄影风格"
    static let description = IntentDescription("为 HEIC 原片追加第三代 Texture / Grain，并另存为新照片。原图保持不变。")
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
        Summary("解锁 \(\.$photos) 的第三代风格") {
            \.$saveToLibrary
            \.$returnsFiles
            \.$checkOnly
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> & ProvidesDialog {
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
        var firstFailure: String?

        for (index, file) in photos.enumerated() {
            let name = Self.safeName(file.filename, fallbackIndex: index)
            let source = workDirectory.appendingPathComponent(name)
            do {
                try Self.copy(file, to: source)
            } catch {
                failed += 1
                firstFailure = firstFailure ?? "\(name)：无法读取文件"
                continue
            }

            let urlType = UTType(filenameExtension: source.pathExtension)
            let traits = AssetTraits(originalIsHEIC: urlType?.conforms(to: .heic) == true
                                     || urlType?.conforms(to: .heif) == true)

            let service = ConversionService.shared
            do {
                let outcome = try await Task.detached(priority: .userInitiated) {
                    try service.inspect(fileURL: source, traits: traits)
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
                let result = try await service.convert(.init(fileURL: source,
                                                             traits: traits,
                                                             preferredName: preferredName,
                                                             saveToLibrary: saveToLibrary,
                                                             returnsFile: returnsFiles)) { _ in }
                converted += 1
                if saveToLibrary { savedToLibrary += 1 }
                if returnsFiles, let outputURL = result.outputURL {
                    // The intent's work directory is deleted when perform() returns, and the
                    // conversion service owns its temporary output. Copy the bytes into the
                    // IntentFile so Shortcuts receives a file that outlives both.
                    do {
                        let data = try Data(contentsOf: outputURL)
                        outputs.append(IntentFile(data: data, filename: preferredName, type: .heic))
                    } catch {
                        firstFailure = firstFailure ?? "\(preferredName)：无法读取转换结果"
                    }
                    let parent = outputURL.deletingLastPathComponent()
                    if parent.lastPathComponent.hasPrefix("LingXiOutput-") {
                        try? FileManager.default.removeItem(at: parent)
                    }
                }
            } catch let failure as ConversionFailure {
                failed += 1
                firstFailure = firstFailure ?? "\(name)：\(failure.message)"
            } catch let failure as PhotoLibraryError {
                failed += 1
                firstFailure = firstFailure ?? "\(name)：\(failure.errorDescription ?? "保存失败")"
            } catch {
                failed += 1
                firstFailure = firstFailure ?? "\(name)：\(error.localizedDescription)"
            }
        }

        let dialog: String
        if checkOnly {
            dialog = "可解锁 \(ready) 张，跳过 \(skipped) 张，失败 \(failed) 张。"
        } else {
            dialog = "已转换 \(converted) 张，其中 \(savedToLibrary) 张已存入相册；跳过 \(skipped) 张，失败 \(failed) 张。"
                + (firstFailure.map { "\n第一处问题：\($0)" } ?? "")
        }

        return .result(value: outputs, dialog: IntentDialog(stringLiteral: dialog))
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
        let base = trimmed.isEmpty ? "photo-\(fallbackIndex + 1).heic" : trimmed
        return base.replacingOccurrences(of: "/", with: "_")
    }

    private static func outputName(for name: String) -> String {
        let stem = (name as NSString).deletingPathExtension
        let base = stem.hasSuffix("_TextureGrain") ? stem : stem + "_TextureGrain"
        return base + ".HEIC"
    }

    enum IntentError: LocalizedError {
        case noInput
        case noOutput

        var errorDescription: String? {
            switch self {
            case .noInput: return "请先选择至少一张 HEIC 照片。"
            case .noOutput: return "请至少打开「保存到相册」或「返回转换后的文件」。"
            }
        }
    }
}

struct LingXiShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: UnlockTextureIntent(),
                    phrases: ["用 \(.applicationName) 解锁第三代摄影风格",
                              "让 \(.applicationName) 给照片加上第三代质感"],
                    shortTitle: "解锁第三代风格",
                    systemImageName: "camera.filters")
    }
}
