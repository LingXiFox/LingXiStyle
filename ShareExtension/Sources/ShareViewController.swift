import SwiftUI
import UIKit
import Photos
import UniformTypeIdentifiers
import LingXiKit
import LingXiEngine
import LingXiServices

/// Share-sheet entry point. It copies the shared file into its own sandbox before doing
/// anything, validates that the bytes are a complete HEIC, then hands the file to the same
/// ConversionService the app and shortcuts use.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 0, height: 470)
        view.backgroundColor = .systemBackground

        let host = UIHostingController(rootView: ShareFlowView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)

        model.onClose = { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
        model.begin(providers: extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? [])
    }
}

@MainActor
final class ShareModel: ObservableObject {
    enum Phase: Equatable {
        case reading
        case inspecting
        case converting(ConversionStage)
        case saving
        case done
        case failed
    }

    @Published private(set) var phase: Phase = .reading
    @Published private(set) var title = "正在读取分享的照片"
    @Published private(set) var message = "文件会先复制到 LingXiStyle 的沙盒，再检查结构。"
    @Published private(set) var diagnosticCode: String?
    @Published private(set) var canRetry = false

    var onClose: (() -> Void)?

    private var workDirectory: URL?
    private var sharedFile: URL?
    private var isBusy = false

    func begin(providers: [NSItemProvider]) {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) else {
            fail(title: "没有收到照片", message: "请回到系统「照片」重新分享，或直接在 LingXiStyle 内从图库选择照片。", retry: false)
            return
        }
        load(provider)
    }

    func retry() {
        guard let sharedFile else { return }
        process(sharedFile)
    }

    private func load(_ provider: NSItemProvider) {
        let identifiers = [UTType.heic.identifier, UTType.heif.identifier, UTType.image.identifier]
        guard let identifier = identifiers.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) else {
            fail(title: "没有收到照片", message: "请分享一张 HEIC 原片，或直接在 LingXiStyle 内从图库选择照片。", retry: false)
            return
        }
        phase = .reading
        // Read the suggested name before the @Sendable callback: NSItemProvider is not Sendable.
        let suggestedName = provider.suggestedName
        provider.loadFileRepresentation(forTypeIdentifier: identifier) { [weak self] url, error in
            guard let self else { return }
            guard let url else {
                Task { @MainActor in
                    self.fail(title: "无法读取分享的文件",
                              message: error?.localizedDescription ?? "系统没有提供可读取的文件副本。请直接在 LingXiStyle 内从图库选择照片。",
                              retry: false)
                }
                return
            }
            // The provider's URL is only valid inside this callback: copy it right away.
            // Use only the last path component: a provider-supplied name must never escape
            // the extension's temporary directory.
            let rawName = (suggestedName ?? url.lastPathComponent) as NSString
            let candidate = Self.sanitized(rawName.lastPathComponent)
            let name = candidate.isEmpty || candidate == "." || candidate == ".." ? "SharedPhoto.heic" : candidate
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("LingXiShare-\(UUID().uuidString)", isDirectory: true)
            let destination = directory.appendingPathComponent(name)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: url, to: destination)
            } catch {
                try? FileManager.default.removeItem(at: directory)
                Task { @MainActor in
                    self.fail(title: "无法复制这个文件", message: "分享扩展没有拿到文件的读写权限。请在 LingXiStyle 内从图库选择照片。", retry: false)
                }
                return
            }
            Task { @MainActor in
                self.workDirectory = directory
                self.sharedFile = destination
                self.process(destination)
            }
        }
    }

    private func process(_ fileURL: URL) {
        guard !isBusy else { return }
        isBusy = true
        canRetry = false
        diagnosticCode = nil
        phase = .inspecting
        title = "正在检查 HEIC 结构"
        message = "确认这是完整原片，并检查是否已经带有第三代质感。"

        Task {
            defer { isBusy = false }
            let traits = AssetTraits(originalIsHEIC: true)
            let outcome: InspectionOutcome
            do {
                outcome = try await Task.detached(priority: .userInitiated) { [service = ConversionService.shared] in
                    try service.inspect(fileURL: fileURL, traits: traits)
                }.value
            } catch {
                let failure = error as? ConversionFailure
                fail(title: "这不是可处理的 HEIC 原片",
                     message: "请在 LingXiStyle 内从图库选择照片。分享面板有时会转成 JPEG 或只给出预览图，这时无法保留原始编码。",
                     code: failure?.diagnosticCode,
                     retry: false)
                return
            }

            guard outcome.verdict.isReady else {
                fail(title: outcome.verdict.headline,
                     message: outcome.verdict.detail + " 请在 LingXiStyle 内从图库选择照片。",
                     code: outcome.verdict.issues.map(\.rawValue).joined(separator: ","),
                     retry: false)
                return
            }

            phase = .converting(.readingOriginal)
            title = "正在补上第三代质感"
            message = "照片保持清晰，只处理纹理与颗粒层。"

            let status = await PhotoLibraryService.requestAddAuthorization()
            guard status == .authorized || status == .limited else {
                fail(title: "没有相册写入权限",
                     message: "请在系统设置中允许 LingXiStyle 添加照片，或在 LingXiStyle 内从图库选择照片。",
                     code: "E_PHOTO_ADD_DENIED",
                     retry: true)
                return
            }

            do {
                let request = ConversionService.Request(
                    fileURL: fileURL,
                    traits: traits,
                    preferredName: Self.outputName(for: fileURL),
                    saveToLibrary: true,
                    returnsFile: false
                )
                let result = try await ConversionService.shared.convert(request) { stage in
                    Task { @MainActor in
                        self.phase = .converting(stage)
                    }
                }
                phase = .done
                title = "已保存新照片"
                message = "原照片没有被修改。新照片已出现在系统「照片」中，可以继续编辑。"
                if let identifier = result.savedAssetIdentifier {
                    diagnosticCode = "SAVED:\(identifier)"
                }
            } catch {
                isBusy = false
                present(error)
            }
        }
    }

    private func present(_ error: Error) {
        if let failure = error as? ConversionFailure {
            fail(title: "转换没有完成", message: failure.message, code: failure.diagnosticCode, retry: true)
        } else if let libraryError = error as? PhotoLibraryError {
            fail(title: "保存到相册失败", message: libraryError.localizedDescription, code: libraryError.diagnosticCode, retry: true)
        } else {
            fail(title: "转换没有完成", message: error.localizedDescription, code: nil, retry: true)
        }
    }

    private func fail(title: String, message: String, code: String? = nil, retry: Bool) {
        phase = .failed
        self.title = title
        self.message = message
        self.diagnosticCode = code
        self.canRetry = retry
    }

    func close() {
        cleanup()
        onClose?()
    }

    private func cleanup() {
        if let workDirectory {
            try? FileManager.default.removeItem(at: workDirectory)
        }
        workDirectory = nil
        sharedFile = nil
    }

    nonisolated private static func sanitized(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func outputName(for url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        let base = stem.hasSuffix("_TextureGrain") ? stem : stem + "_TextureGrain"
        return base + ".HEIC"
    }
}

struct ShareFlowView: View {
    @ObservedObject var model: ShareModel

    private var accent: Color { Color(red: 0.51, green: 0.84, blue: 1.0) }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .fill(accent.opacity(0.16))
                    .frame(width: 76, height: 76)
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(spacing: 8) {
                Text(model.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(model.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.phase == .done {
                Label("已存为相册中的新照片", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.green)
            } else if model.phase == .failed {
                if let code = model.diagnosticCode {
                    Text(code)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(accent)
            }

            Spacer(minLength: 8)

            HStack(spacing: 12) {
                if model.canRetry {
                    Button("重试") { model.retry() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                Button(model.phase == .failed ? "关闭" : "完成") { model.close() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(accent)
                    .foregroundStyle(.black)
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var symbol: String {
        switch model.phase {
        case .done: return "checkmark"
        case .failed: return "exclamationmark"
        default: return "camera.filters"
        }
    }

    private var iconColor: Color {
        switch model.phase {
        case .done: return .green
        case .failed: return .orange
        default: return accent
        }
    }
}
