import Foundation
import LingXiKit
import StylePortCore

/// The single place the app, the share extension and the shortcut all go through.
/// It owns no PhotoKit, no UI and no global state: bytes in, bytes out.
public struct ConversionEngine: Sendable {
    public init() {}

    public static let outputSuffix = "_TextureGrain"
    public static let outputExtension = "heic"

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
            throw ConversionFailure.engineMessage("核心没有进入增量注入路径（\(result.report.mode.rawValue)）")
        }

        onStage?(.verifying)
        let after = try parsed(result.data)
        let integrity = IntegrityVerifier.verify(original: data, result: result.data)
        guard integrity.passed else { throw ConversionFailure.verificationFailed(integrity) }

        let directory = outputDirectory ?? fileURL.deletingLastPathComponent()
        let outputURL = directory.appendingPathComponent(Self.outputName(for: fileURL))
        do {
            try result.data.write(to: outputURL, options: .atomic)
        } catch {
            throw ConversionFailure.writeFailed(error.localizedDescription)
        }

        return ConversionOutput(outputURL: outputURL,
                                outputByteCount: result.data.count,
                                inspectionBefore: before,
                                inspectionAfter: after,
                                integrity: integrity,
                                mode: result.report.mode.rawValue,
                                texture: result.report.texture,
                                warnings: result.report.warnings)
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

    private func read(_ url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw ConversionFailure.unreadable(error.localizedDescription)
        }
    }

    private func parsed(_ data: Data) throws -> HEICInspection {
        do {
            return try HEICInspector.inspect(data, hashing: true)
        } catch {
            throw ConversionFailure.corrupted("无法解析 HEIC 结构：\(error)")
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
}

public enum ConversionFailure: Error, Sendable, LocalizedError {
    case unreadable(String)
    case corrupted(String)
    case unsupported(CompatibilityVerdict)
    case engine(StylePortError)
    case engineMessage(String)
    case verificationFailed(IntegrityReport)
    case writeFailed(String)
    case quota(QuotaError)

    public var errorDescription: String? { message }

    /// What the user reads. Plain Chinese, no error domain noise.
    public var message: String {
        switch self {
        case .unreadable: return "无法读取这个文件，它可能已被移动或没有访问权限。"
        case .corrupted(let detail): return "文件结构无法解析。\(detail)"
        case .unsupported(let verdict): return verdict.detail
        case .engine(.alreadyHasTexture): return "这张照片已经带有第三代质感。"
        case .engine(.originalIsNotHEIC): return "这不是 HEIC 原片，请在 LingXiStyle 中从图库选择原始照片。"
        case .engine(.invalidData(let detail)): return "核心拒绝了这个文件的布局：\(detail)"
        case .engine(.missingResource(let name)): return "缺少核心需要的资源：\(name)"
        case .engine(let error): return "转换核心返回了错误：\(error)"
        case .engineMessage(let text): return text
        case .verificationFailed(let report): return "输出没通过无损校验：\(report.summary)"
        case .writeFailed(let detail): return "写入临时文件失败：\(detail)"
        case .quota(let error): return error.errorDescription ?? "今日免费额度不可用。"
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
