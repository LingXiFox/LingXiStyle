import SwiftUI
import UIKit
import Photos
import UniformTypeIdentifiers
import LingXiKit
import LingXiEngine
import LingXiServices

/// Share-sheet entry point. It copies the shared file into its own sandbox before doing
/// anything, validates that the bytes are a complete HEIC, then hands the file to the same
/// ConversionService the app and shortcuts use. The extension never pretends a running job is
/// finished: while work is in flight the only action is an explicit cancel.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 0, height: 500)
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
        case cancelling
        case done
        case cancelled
        case failed
    }

    @Published private(set) var phase: Phase = .reading
    @Published private(set) var title = String(localized: "正在读取分享的照片")
    @Published private(set) var message = String(localized: "share.copyHint", defaultValue: "文件会先复制到 \(Brand.name) 的沙盒，再检查结构。")
    @Published private(set) var diagnosticCode: String?
    @Published private(set) var canRetry = false

    var onClose: (() -> Void)?

    private var workDirectory: URL?
    private var sharedFile: URL?
    private var processingTask: Task<Void, Never>?
    private var sessionID = UUID()
    private var loadGeneration = UUID()
    private var cancelRequested = false
    private var closeWhenFinished = false
    private var didClose = false

    var isBusy: Bool {
        switch phase {
        case .reading, .inspecting, .converting, .cancelling: return true
        case .done, .cancelled, .failed: return false
        }
    }

    var canCancel: Bool {
        guard isBusy else { return false }
        if case .cancelling = phase { return false }
        return true
    }

    func begin(providers: [NSItemProvider]) {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) else {
            fail(title: String(localized: "没有收到照片"), message: String(localized: "share.error.noProviders", defaultValue: "请回到系统「照片」重新分享，或直接在 \(Brand.name) 内从图库选择照片。"), retry: false)
            return
        }
        load(provider)
    }

    func retry() {
        guard let sharedFile, !isBusy else { return }
        process(sharedFile)
    }

    /// Starts work. The caller owns the file until the task reaches a safe boundary, so closing
    /// the sheet cannot delete a file that PhotoKit or the engine is still reading.
    private func load(_ provider: NSItemProvider) {
        let identifiers = [UTType.heic.identifier, UTType.heif.identifier, UTType.image.identifier]
        guard let identifier = identifiers.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) else {
            fail(title: String(localized: "没有收到照片"), message: String(localized: "share.error.notHEIC", defaultValue: "请分享一张 HEIC 原片，或直接在 \(Brand.name) 内从图库选择照片。"), retry: false)
            return
        }
        phase = .reading
        let generation = UUID()
        loadGeneration = generation
        // Read the suggested name before the @Sendable callback: NSItemProvider is not Sendable.
        let suggestedName = provider.suggestedName
        provider.loadFileRepresentation(forTypeIdentifier: identifier) { [weak self] url, error in
            guard let self else { return }
            guard let url else {
                let detail = error?.localizedDescription ?? String(localized: "share.error.noFile", defaultValue: "系统没有提供可读取的文件副本。请直接在 \(Brand.name) 内从图库选择照片。")
                Task { @MainActor in
                    guard self.loadGeneration == generation else { return }
                    self.fail(title: String(localized: "无法读取分享的文件"), message: detail, retry: false)
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
                    guard self.loadGeneration == generation else { return }
                    self.fail(title: String(localized: "无法复制这个文件"),
                              message: String(localized: "share.error.noAccess", defaultValue: "分享扩展没有拿到文件的读写权限。请在 \(Brand.name) 内从图库选择照片。"),
                              retry: false)
                }
                return
            }
            Task { @MainActor in
                guard self.loadGeneration == generation, self.phase == .reading else {
                    try? FileManager.default.removeItem(at: directory)
                    return
                }
                self.workDirectory = directory
                self.sharedFile = destination
                self.process(destination)
            }
        }
    }

    private func process(_ fileURL: URL) {
        guard processingTask == nil, !isBusy else { return }
        let session = UUID()
        sessionID = session
        cancelRequested = false
        closeWhenFinished = false
        canRetry = false
        diagnosticCode = nil
        phase = .inspecting
        title = String(localized: "正在检查 HEIC 结构")
        message = String(localized: "确认这是完整原片，并检查是否已经带有纹理与颗粒。")

        processingTask = Task { [weak self] in
            await self?.run(fileURL: fileURL, session: session)
        }
    }

    private func run(fileURL: URL, session: UUID) async {
        defer {
            if sessionID == session {
                processingTask = nil
            }
            if closeWhenFinished {
                finishClose()
            }
        }

        let traits = AssetTraits(originalIsHEIC: true)
        let outcome: InspectionOutcome
        do {
            outcome = try await Task.detached(priority: .userInitiated) { [service = ConversionService.shared] in
                try service.inspect(fileURL: fileURL, traits: traits)
            }.value
        } catch {
            guard sessionID == session else { return }
            let failure = error as? ConversionFailure
            fail(title: String(localized: "这不是可处理的 HEIC 原片"),
                 message: String(localized: "share.error.unsupportedDetail", defaultValue: "请在 \(Brand.name) 内从图库选择照片。分享面板有时会转成 JPEG 或只给出预览图，这时无法保留原始编码。"),
                 code: failure?.diagnosticCode,
                 retry: false)
            return
        }

        guard sessionID == session else { return }
        guard outcome.verdict.isReady else {
            fail(title: outcome.verdict.headline,
                 message: String(localized: "share.unsupported.message", defaultValue: "\(outcome.verdict.detail) 请在 \(Brand.name) 内从图库选择照片。"),
                 code: outcome.verdict.issues.map(\.rawValue).joined(separator: ","),
                 retry: false)
            return
        }

        do {
            try Task.checkCancellation()
            phase = .converting(.readingOriginal)
            title = String(localized: "正在添加纹理与颗粒")
            message = String(localized: "照片保持清晰，只处理纹理与颗粒层。")

            let request = ConversionService.Request(
                fileURL: fileURL,
                traits: traits,
                preferredName: Self.outputName(for: fileURL),
                saveToLibrary: true,
                returnsFile: false
            )
            let result = try await ConversionService.shared.convert(request) { [weak self] stage in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionID == session, !self.cancelRequested else { return }
                    self.phase = .converting(stage)
                    self.title = stage.inProgressTitle
                    self.message = Self.message(for: stage)
                }
            }
            guard sessionID == session else { return }
            phase = .done
            title = String(localized: "已保存新照片")
            message = cancelRequested
                ? String(localized: "取消请求到达时，这张照片已经写入相册，已保留。原照片没有被修改。")
                : String(localized: "原照片没有被修改。新照片已出现在系统「照片」中，可以继续编辑。")
            diagnosticCode = result.savedAssetIdentifier.map { "SAVED:\($0)" }
            canRetry = false
            cleanupInput()
        } catch is CancellationError {
            guard sessionID == session else { return }
            phase = .cancelled
            title = String(localized: "已取消，没有保存新照片")
            message = String(localized: "没有写入相册，原照片保持不变。")
            diagnosticCode = nil
            canRetry = sharedFile != nil
        } catch {
            guard sessionID == session else { return }
            present(error)
        }
    }

    private func present(_ error: Error) {
        if let failure = error as? ConversionFailure {
            fail(title: String(localized: "处理没有完成"), message: failure.message, code: failure.diagnosticCode, retry: true)
        } else if let libraryError = error as? PhotoLibraryError {
            let denied: Bool
            switch libraryError {
            case .addPermissionDenied: denied = true
            default: denied = false
            }
            fail(title: denied ? String(localized: "没有相册写入权限") : String(localized: "保存到相册失败"),
                 message: libraryError.localizedDescription,
                 code: libraryError.diagnosticCode,
                 retry: true)
        } else {
            fail(title: String(localized: "处理没有完成"), message: error.localizedDescription, code: nil, retry: true)
        }
    }

    private func fail(title: String, message: String, code: String? = nil, retry: Bool) {
        phase = .failed
        self.title = title
        self.message = message
        self.diagnosticCode = code
        self.canRetry = retry && sharedFile != nil
    }

    /// A user-visible cancel. Work already written to Photos is never deleted; work that has not
    /// crossed the save boundary is stopped cooperatively.
    func cancel() {
        switch phase {
        case .reading:
            loadGeneration = UUID()
            phase = .cancelled
            title = String(localized: "已取消")
            message = String(localized: "没有读取或保存任何照片。")
            canRetry = false
            cleanupInput()
        case .inspecting, .converting:
            cancelRequested = true
            phase = .cancelling
            title = String(localized: "正在取消")
            message = String(localized: "已保存的照片会保留；正在写入的照片会先完成保存。")
            processingTask?.cancel()
        case .cancelling:
            break
        case .done, .cancelled, .failed:
            close()
        }
    }

    func close() {
        if isBusy {
            if case .reading = phase {
                loadGeneration = UUID()
                cleanupInput()
                finishClose()
            } else {
                closeWhenFinished = true
                cancel()
            }
            return
        }
        finishClose()
    }

    private func finishClose() {
        guard !didClose else { return }
        didClose = true
        cleanup()
        onClose?()
    }

    private func cleanupInput() {
        if let workDirectory {
            try? FileManager.default.removeItem(at: workDirectory)
        }
        workDirectory = nil
        sharedFile = nil
    }

    private func cleanup() {
        cleanupInput()
    }

    private static func message(for stage: ConversionStage) -> String {
        switch stage {
        case .readingOriginal: return String(localized: "正在读取原始 HEIC，照片内容不会被改动。")
        case .inspecting: return String(localized: "正在确认主图、HDR、EXIF 与风格元数据。")
        case .converting: return String(localized: "只追加纹理与颗粒层，主图编码保持原样。")
        case .verifying: return String(localized: "正在逐项比对转换前后的完整性。")
        case .saving: return String(localized: "正在把新照片写入系统相册。")
        case .finished: return String(localized: "新照片已经保存，原照片保留。")
        case .failed: return String(localized: "这一步没有完成，请重试。")
        }
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

    private var accent: Color { SharePalette.accent }

    var body: some View {
        ZStack {
            SharePalette.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer(minLength: 8)

                ZStack {
                    Circle()
                        .fill(SharePalette.surface)
                        .frame(width: 88, height: 88)
                    Circle()
                        .strokeBorder(SharePalette.hairline, lineWidth: 0.5)
                        .frame(width: 88, height: 88)
                    Image(systemName: symbol)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(iconColor)
                }

                VStack(spacing: 8) {
                    Text(model.title)
                        .font(.system(.title2, design: .default, weight: .bold))
                        .foregroundStyle(SharePalette.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(model.message)
                        .font(.subheadline)
                        .foregroundStyle(SharePalette.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                statusArea

                Spacer(minLength: 8)

                actions
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .tint(accent)
    }

    @ViewBuilder
    private var statusArea: some View {
        switch model.phase {
        case .done:
            Label("已存为相册中的新照片", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(SharePalette.success)
        case .cancelled:
            Label("没有保存新照片", systemImage: "xmark.circle")
                .font(.footnote.weight(.medium))
                .foregroundStyle(SharePalette.textSecondary)
        case .failed:
            Text(model.canRetry ? String(localized: "可以重试，不会覆盖原照片。") : String(localized: "请返回主 App 重新选择这张照片。"))
                .font(.caption)
                .foregroundStyle(SharePalette.textSecondary)
        case .cancelling:
            ProgressView()
                .controlSize(.large)
                .tint(accent)
        case .converting(let stage):
            VStack(spacing: 8) {
                ShareStageRail(stage: stage)
                ProgressView()
                    .controlSize(.small)
                    .tint(SharePalette.running)
            }
        case .reading, .inspecting:
            ProgressView()
                .controlSize(.large)
                .tint(SharePalette.running)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if model.isBusy {
            Button("取消") { model.cancel() }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(SharePalette.textPrimary)
                .disabled(!model.canCancel)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
        } else {
            HStack(spacing: 12) {
                if model.canRetry {
                    Button("重试") { model.retry() }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(SharePalette.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                }
                Button(model.phase == .done ? String(localized: "完成") : String(localized: "关闭")) { model.close() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .tint(accent)
                    .foregroundStyle(SharePalette.onAccent)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
            }
        }
    }

    private var symbol: String {
        switch model.phase {
        case .done: return "checkmark"
        case .failed: return "exclamationmark"
        case .cancelled: return "xmark"
        case .cancelling: return "xmark.circle"
        default: return "camera.filters"
        }
    }

    private var iconColor: Color {
        switch model.phase {
        case .done: return SharePalette.success
        case .failed: return SharePalette.warning
        case .cancelled, .cancelling: return SharePalette.textSecondary
        default: return accent
        }
    }
}

/// A compact, real-stage rail. It does not show a percentage or a timer.
private struct ShareStageRail: View {
    let stage: ConversionStage

    private var currentIndex: Int {
        ConversionStage.pipeline.firstIndex(of: stage) ?? 0
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(ConversionStage.pipeline.enumerated()), id: \.element) { index, step in
                Capsule()
                    .fill(index <= currentIndex ? SharePalette.accent : SharePalette.fillControl)
                    .frame(height: 4)
                    .overlay {
                        if index == currentIndex {
                            Capsule().strokeBorder(SharePalette.accent.opacity(0.35), lineWidth: 1)
                        }
                    }
                    .accessibilityLabel(Text(String(localized: "share.stage.accessibility", defaultValue: "\(step.title)\(stepSuffix(index))")))
            }
        }
        .frame(maxWidth: 220)
        .accessibilityElement(children: .contain)
    }

    private func stepSuffix(_ index: Int) -> String {
        if index < currentIndex { return String(localized: "stage.done", defaultValue: "，已完成") }
        if index == currentIndex { return String(localized: "stage.current", defaultValue: "，进行中") }
        return ""
    }
}

private enum SharePalette {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let textPrimary = Color(uiColor: .label)
    static let textSecondary = Color(uiColor: .secondaryLabel)
    static let fillControl = Color(uiColor: .tertiarySystemFill)
    static let hairline = Color(uiColor: .separator)
    static let accent = Color(light: 0xE8A13A, dark: 0xE8A13A)
    static let onAccent = Color(light: 0x1A1410, dark: 0x1A1410)
    static let running = Color(light: 0x0E8A85, dark: 0x3CC9BD)
    static let success = Color(light: 0x248A3D, dark: 0x30DB5B)
    static let warning = Color(light: 0xB25000, dark: 0xFFD426)
}

private extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}