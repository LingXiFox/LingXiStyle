import Foundation
import LingXiKit
import StylePortCore

/// The single place the app, the share extension and the shortcut all go through.
/// It owns no PhotoKit, no UI and no global state: bytes in, bytes out.
public struct ConversionEngine: Sendable {
    public init() {}

    public static let outputSuffix = "_TextureGrain"
    public static let outputExtension = "heic"
    public static let outputVideoExtension = "mov"

    /// Reads the file and explains what would happen to it, without converting anything.
    public func inspect(fileURL: URL, traits: AssetTraits = AssetTraits()) throws -> InspectionOutcome {
        let data = try read(fileURL)
        let inspection = try parsed(data)
        let verdict = CompatibilityEvaluator.evaluate(inspection, traits: traits)
        return InspectionOutcome(inspection: inspection, verdict: verdict, byteCount: data.count)
    }

    /// Adds Apple's third-generation Texture/Grain data to a native style photo and proves the
    /// pixels did not move. Throws `ConversionFailure` when it is not safe to continue.
    public func convert(fileURL: URL,
                        traits: AssetTraits = AssetTraits(),
                        outputDirectory: URL? = nil,
                        onStage: (@Sendable (ConversionStage) -> Void)? = nil) throws -> ConversionOutput {
        onStage?(.readingOriginal)
        let data = try read(fileURL)
        let still = try styledStill(from: data, traits: traits, onStage: onStage)

        onStage?(.verifying)
        let verified = try verifyStill(original: data, styled: still.data)

        let directory = outputDirectory ?? fileURL.deletingLastPathComponent()
        let outputURL = directory.appendingPathComponent(Self.outputName(for: fileURL))
        try write(still.data, to: outputURL)

        return ConversionOutput(outputURL: outputURL,
                                outputByteCount: still.data.count,
                                inspectionBefore: still.inspectionBefore,
                                inspectionAfter: verified.inspection,
                                integrity: verified.integrity,
                                mode: still.mode,
                                texture: still.texture,
                                warnings: still.warnings,
                                pairedVideoURL: nil,
                                livePhotoMode: nil,
                                videoFrameCount: nil,
                                videoByteCount: nil)
    }

    /// Only the structural check, without keeping the whole file in memory any longer than needed.
    public func quickCheck(fileURL: URL, traits: AssetTraits = AssetTraits()) -> CompatibilityVerdict? {
        guard let data = try? read(fileURL), let inspection = try? parsed(data) else { return nil }
        return CompatibilityEvaluator.evaluate(inspection, traits: traits)
    }

    public func outputName(for input: URL) -> String {
        Self.outputName(for: input)
    }

    static func outputName(for input: URL) -> String {
        let base = input.deletingPathExtension().lastPathComponent
        let stem = base.hasSuffix(outputSuffix) ? base : base + outputSuffix
        return stem + "." + outputExtension
    }

    static func outputVideoName(for input: URL) -> String {
        let base = input.deletingPathExtension().lastPathComponent
        let stem = base.hasSuffix(outputSuffix) ? base : base + outputSuffix
        return stem + "." + outputVideoExtension
    }

    // MARK: Shared steps

    struct StyledStill: Sendable {
        let data: Data
        let inspectionBefore: HEICInspection
        let mode: String
        let texture: String
        let warnings: [String]
    }

    /// Runs the lossless texture injection on a still. Emits `.inspecting` and `.converting`;
    /// verification and writing stay with the caller so a Live Photo can add its movie first.
    func styledStill(from data: Data,
                     traits: AssetTraits,
                     onStage: (@Sendable (ConversionStage) -> Void)?) throws -> StyledStill {
        onStage?(.inspecting)
        let before = try parsed(data)
        let verdict = CompatibilityEvaluator.evaluate(before, traits: traits)
        guard verdict.isReady else { throw ConversionFailure.unsupported(verdict) }

        onStage?(.converting)
        let porter = StylePorter()
        let result: StylePortResult
        do {
            result = try porter.patch(data, options: StylePortOptions(
                analyzePhoto: false,
                texture: true,
                livePhoto: false,
                sdr: false,
                converted: false,
                detectPeople: false
            ))
        } catch let error as StylePortError {
            throw ConversionFailure.engine(error)
        } catch {
            throw ConversionFailure.engineMessage(error.localizedDescription)
        }
        guard result.report.mode == .addTexture, result.report.addedTexture else {
            throw ConversionFailure.engineMessage(String(localized: "engine.error.unexpectedMode", defaultValue: "核心没有进入增量注入路径（\(result.report.mode.rawValue)）"))
        }

        return StyledStill(data: result.data,
                           inspectionBefore: before,
                           mode: result.report.mode.rawValue,
                           texture: result.report.texture,
                           warnings: result.report.warnings)
    }

    /// Re-parses the output and proves the original pixels and metadata are untouched.
    func verifyStill(original: Data, styled: Data) throws -> (inspection: HEICInspection, integrity: IntegrityReport) {
        let after = try parsed(styled)
        let integrity = IntegrityVerifier.verify(original: original, result: styled)
        guard integrity.passed else { throw ConversionFailure.verificationFailed(integrity) }
        return (after, integrity)
    }

    func read(_ url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw ConversionFailure.unreadable(error.localizedDescription)
        }
    }

    func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ConversionFailure.writeFailed(error.localizedDescription)
        }
    }

    func parsed(_ data: Data) throws -> HEICInspection {
        do {
            return try HEICInspector.inspect(data, hashing: true)
        } catch {
            throw ConversionFailure.corrupted(String(localized: "engine.error.parse", defaultValue: "无法解析 HEIC 结构：\(String(describing: error))"))
        }
    }
}

public struct InspectionOutcome: Sendable {
    public let inspection: HEICInspection
    public let verdict: CompatibilityVerdict
    public let byteCount: Int
}

public struct ConversionOutput: Sendable {
    public let outputURL: URL
    public let outputByteCount: Int
    public let inspectionBefore: HEICInspection
    public let inspectionAfter: HEICInspection
    public let integrity: IntegrityReport
    public let mode: String
    public let texture: String
    public let warnings: [String]
    /// Present only for Live Photos: the paired movie written next to the still.
    public let pairedVideoURL: URL?
    public let livePhotoMode: LivePhotoProcessingMode?
    public let videoFrameCount: Int?
    public let videoByteCount: Int?
}

public enum ConversionFailure: Error, Sendable, LocalizedError {
    case unreadable(String)
    case corrupted(String)
    case unsupported(CompatibilityVerdict)
    case engine(StylePortError)
    case engineMessage(String)
    case verificationFailed(IntegrityReport)
    case writeFailed(String)
    case livePhotoVideo(String)
    case quota(QuotaError)

    public var errorDescription: String? { message }

    /// What the user reads. Plain Chinese, no error domain noise.
    public var message: String {
        switch self {
        case .unreadable: return String(localized: "无法读取这个文件，它可能已被移动或没有访问权限。")
        case .corrupted(let detail): return String(localized: "engine.error.corruptDetail", defaultValue: "文件结构无法解析。\(detail)")
        case .unsupported(let verdict): return verdict.detail
        case .engine(.alreadyHasTexture): return String(localized: "这张照片已经带有纹理与颗粒。")
        case .engine(.originalIsNotHEIC): return String(localized: "engine.error.notHEIC", defaultValue: "这不是 HEIC 原片，请在 \(Brand.name) 中从图库选择原始照片。")
        case .engine(.invalidData(let detail)): return String(localized: "engine.error.invalidData", defaultValue: "核心拒绝了这个文件的布局：\(detail)")
        case .engine(.missingResource(let name)): return String(localized: "engine.error.missingResource", defaultValue: "缺少核心需要的资源：\(name)")
        case .engine(let error): return String(localized: "engine.error.other", defaultValue: "转换核心返回了错误：\(String(describing: error))")
        case .engineMessage(let text): return text
        case .verificationFailed(let report): return String(localized: "engine.error.verification", defaultValue: "输出没通过无损校验：\(report.summary)")
        case .writeFailed(let detail): return String(localized: "engine.error.write", defaultValue: "写入临时文件失败：\(detail)")
        case .livePhotoVideo(let detail): return String(localized: "engine.error.livePhotoVideo", defaultValue: "无法完整处理这段动态视频（\(detail)）。可以改用「只处理主帧」，主照片依然会得到纹理与颗粒。")
        case .quota(let error): return error.errorDescription ?? String(localized: "今日免费额度不可用。")
        }
    }

    /// Kept for the diagnostics sheet, never shown as the primary message.
    public var diagnosticCode: String {
        switch self {
        case .unreadable: return "E_UNREADABLE"
        case .corrupted: return "E_CORRUPT"
        case .unsupported(let verdict): return "E_UNSUPPORTED:" + verdict.issues.map(\.rawValue).joined(separator: ",")
        case .engine(.alreadyHasTexture): return "E_ALREADY_TEXTURED"
        case .engine(let error): return "E_ENGINE:\(error)"
        case .engineMessage(let text): return "E_ENGINE:\(text)"
        case .verificationFailed(let report): return "E_VERIFY:" + report.failures.map(\.id).joined(separator: ",")
        case .writeFailed: return "E_WRITE"
        case .livePhotoVideo(let detail): return "E_LIVEPHOTO_VIDEO:" + detail
        case .quota(let error): return error.diagnosticCode
        }
    }

    public var integrityReport: IntegrityReport? {
        if case .verificationFailed(let report) = self { return report }
        return nil
    }

    public var verdict: CompatibilityVerdict? {
        if case .unsupported(let verdict) = self { return verdict }
        return nil
    }
}
