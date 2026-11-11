import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import LingXiKit

struct RootView: View {
    @StateObject private var model = AppModel()
    @State private var diagnostics: DiagnosticsPayload?
    @State private var duoControlInset: CGFloat = 0
    @State private var displayCornerInset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    private var reduceMotion: Bool { systemReduceMotion || reduceMotionOverride }

    private var ambient: AmbientIntensity {
        switch model.screen {
        case .idle: return .empty
        case .selecting, .converting, .result, .permissionDenied: return .standard
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let expansion = horizontalExpansion(for: proxy)
            let cornerInset = cornerSafeInset(for: proxy)
            ZStack {
                Palette.background.ignoresSafeArea()
                AmbientBackdrop(intensity: ambient)
                Group {
                    if isTwoColumn(proxy.size) {
                        HStack(spacing: 0) {
                            WorkspaceRail(model: model)
                                .frame(width: railWidth(for: proxy.size))

                            Rectangle()
                                .fill(Palette.hairline)
                                .frame(width: 0.5)

                            content
                                .environment(\.contentMargin, Spacing.margin(for: min(proxy.size.width - railWidth(for: proxy.size), Layout.iPadContentMaxWidth)))
                                .frame(maxWidth: Layout.iPadContentMaxWidth)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        content
                            .environment(\.contentMargin, Spacing.margin(for: min(proxy.size.width, Layout.iPadContentMaxWidth)))
                            .frame(maxWidth: Layout.iPadContentMaxWidth)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, cornerInset)
                    .animation(reduceMotion ? nil : Motion.entrance, value: model.screen)
            }
            .frame(width: expansion.width, alignment: .topLeading)
            .offset(x: -expansion.leading)
            .onAppear {
                duoControlInset = expansion.controlInset
                displayCornerInset = cornerInset
            }
            .onChange(of: expansion.controlInset) { _, newValue in
                duoControlInset = newValue
            }
            .onChange(of: cornerInset) { _, newValue in
                displayCornerInset = newValue
            }
        }
        .tint(Palette.accent)
        .environment(\.duoControlInset, duoControlInset)
        .environment(\.displayCornerInset, displayCornerInset)
        .overlay(alignment: .top) { noticeBanner }
        .task {
            await model.onAppear()
            model.presentTutorialIfFirstLaunch()
        }
        .sheet(isPresented: $model.isTutorialPresented, onDismiss: { model.dismissTutorial() }) {
            TutorialView(model: model,
                         isFirstRun: !model.hasSeenTutorial,
                         onClose: { model.dismissTutorial() })
                .presentationDragIndicator(.visible)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            model.refreshPermissions()
            Task { await model.refreshQuota() }
        }
        .onChange(of: model.pickerSelection) { _, selection in
            guard !selection.isEmpty else { return }
            model.handlePickerSelection()
        }
        .fileImporter(isPresented: $model.isImportingFiles,
                      allowedContentTypes: [.heic, .heif],
                      allowsMultipleSelection: true) { result in
            model.handleFileImport(result)
        }
        .sheet(item: $diagnostics) { payload in
            DiagnosticsSheet(text: payload.text)
        }
        .sheet(item: $model.activeModal) { modal in
            switch modal {
            case .pro:
                ProPurchaseView(
                    purchases: model.purchases,
                    onEntitlementChanged: {
                        Task { await model.refreshQuota() }
                    },
                    onClose: { model.dismissModal() },
                    controlInset: duoControlInset
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            case .quotaExhausted:
                QuotaExhaustedView(
                    limit: QuotaConfiguration.freeDailyLimit,
                    onUpgrade: { model.activeModal = .pro },
                    onDismiss: { model.dismissModal() },
                    controlInset: duoControlInset
                )
                .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(404)])
                .presentationDragIndicator(.visible)
            case .settings:
                SettingsView(
                    model: model,
                    purchases: model.purchases,
                    onClose: { model.dismissModal() },
                    controlInset: duoControlInset
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: model.activeModal) { _, modal in
            if modal == nil {
                Task { await model.refreshQuota() }
            }
        }
        .alert("免费额度不足",
               isPresented: Binding(
                    get: { model.batchQuotaPrompt != nil },
                    set: { if !$0 { model.batchQuotaPrompt = nil } }
               ),
               presenting: model.batchQuotaPrompt) { prompt in
            Button(String(localized: "batch.convertAvailable", defaultValue: "仅处理 \(prompt.available) 张")) {
                model.batchQuotaPrompt = nil
                model.startConversion(clearFailures: prompt.clearFailures, limit: prompt.available)
            }
            Button("升级 Pro") {
                model.batchQuotaPrompt = nil
                model.presentPro()
            }
            Button("取消", role: .cancel) {
                model.batchQuotaPrompt = nil
            }
        } message: { prompt in
            Text(String(localized: "batch.message", defaultValue: "已选 \(prompt.requested) 张可处理照片，今日还剩 \(prompt.available) 张免费额度。超出部分不会处理，也不会消耗额度。"))
        }
    }

    /// Two columns only where there is real room: Duo unfolded, or any regular-width
    /// iPad-like surface. Duo's inner display reports regular width at 669pt, so size
    /// classes decide instead of a device idiom; compact-height phone landscape stays single.
    private func isTwoColumn(_ size: CGSize) -> Bool {
        horizontalSizeClass == .regular
            && verticalSizeClass == .regular
            && size.width >= Layout.duoBreakpoint
    }

    /// Keep the persisted queue readable without squeezing the detail pane in a
    /// floating or split-view window.
    private func railWidth(for size: CGSize) -> CGFloat {
        min(Layout.duoRailWidth, max(Layout.duoRailMinWidth, size.width * 0.38))
    }

    private struct HorizontalExpansion {
        let width: CGFloat
        let leading: CGFloat
        let controlInset: CGFloat
    }

    /// Duo's folded cover screen reports an 84pt trailing safe-area inset for the camera
    /// island column, but the area below the island is usable. Expand only for that
    /// asymmetric case; symmetric phone landscape insets and regular-width iPads keep
    /// their normal safe area.
    private func horizontalExpansion(for proxy: GeometryProxy) -> HorizontalExpansion {
        let insets = proxy.safeAreaInsets
        let spread = abs(insets.leading - insets.trailing)
        guard spread >= 40, proxy.size.width < Layout.duoBreakpoint else {
            return HorizontalExpansion(width: proxy.size.width, leading: 0, controlInset: 0)
        }
        return HorizontalExpansion(
            width: proxy.size.width + insets.leading + insets.trailing,
            leading: insets.leading,
            controlInset: max(insets.leading, insets.trailing)
        )
    }

    /// Duo's cover and inner displays report a zero top safe-area inset even though
    /// their rounded corners still cut into the top-left and top-right corners. Add a
    /// fixed inset only when the display is vertically regular and the system has not
    /// already reserved space for a notch or status bar.
    private func cornerSafeInset(for proxy: GeometryProxy) -> CGFloat {
        guard verticalSizeClass == .regular, proxy.safeAreaInsets.top < 1 else { return 0 }
        return Layout.displayCornerInset
    }

    @ViewBuilder
    private var content: some View {
        switch model.screen {
        case .idle:
            EmptyStateView(model: model)
                .transition(.opacity)
        case .selecting:
            SelectionView(model: model)
                .transition(.opacity)
        case .converting:
            ConvertingView(model: model)
                .transition(.opacity)
        case .result:
            ResultView(model: model) {
                diagnostics = DiagnosticsPayload(text: model.diagnosticsText ?? String(localized: "暂无诊断信息"))
            }
            .transition(.opacity)
        case .permissionDenied:
            PermissionDeniedView(
                onRetry: { Task { await model.onAppear() } },
                onImportFiles: { model.isImportingFiles = true }
            )
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var noticeBanner: some View {
        if let notice = model.notice {
            HStack(alignment: .top, spacing: Spacing.s) {
                Image(systemName: "info.circle")
                    .font(.system(.body, design: .default, weight: .medium))
                    .foregroundStyle(Palette.info)
                Text(notice)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    model.notice = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(.caption, design: .default, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 24, height: 24)
                }
                .accessibilityLabel("关闭提示")
            }
            .padding(Spacing.s)
            .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.5))
            .shadow(color: Palette.shadow, radius: 10, y: 4)
            .padding(.horizontal, Spacing.m)
            .padding(.top, Spacing.xs + displayCornerInset)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: notice) {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if model.notice == notice {
                    withAnimation(Motion.notice) { model.notice = nil }
                }
            }
        }
    }
}

struct DiagnosticsPayload: Identifiable {
    let id = UUID()
    let text: String
}

// MARK: - Adaptive page margin

private struct ContentMarginKey: EnvironmentKey {
    static let defaultValue: CGFloat = 20
}

extension EnvironmentValues {
    var contentMargin: CGFloat {
        get { self[ContentMarginKey.self] }
        set { self[ContentMarginKey.self] = newValue }
    }
}

// MARK: - Display corner inset

/// Additional top inset for displays whose rounded corners cut into content while
/// the system reports a zero safe-area inset (Duo cover and inner screens).
struct DisplayCornerInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var displayCornerInset: CGFloat {
        get { self[DisplayCornerInsetKey.self] }
        set { self[DisplayCornerInsetKey.self] = newValue }
    }
}

// MARK: - Duo cover-screen control inset

/// Horizontal space reserved by the Duo cover screen's camera island. Custom top bars
/// add this trailing padding so controls stay clear while the page uses the full width.
struct DuoControlInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var duoControlInset: CGFloat {
        get { self[DuoControlInsetKey.self] }
        set { self[DuoControlInsetKey.self] = newValue }
    }
}

// MARK: - Duo sheet width

/// Expands sheet content into the Duo cover screen's camera-island column without
/// shifting it left. The navigation bar stays inside the system safe area; the page
/// below it uses the full sheet width.
struct DuoSheetWidth: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            content
                .frame(width: proxy.size.width + insets.leading + insets.trailing,
                       alignment: .topLeading)
                .offset(x: -insets.leading)
        }
    }
}

extension View {
    func duoSheetWidth() -> some View {
        modifier(DuoSheetWidth())
    }
}
