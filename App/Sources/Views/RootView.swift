import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct RootView: View {
    @StateObject private var model = AppModel()
    @State private var diagnostics: DiagnosticsPayload?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride
    private var reduceMotion: Bool { systemReduceMotion || reduceMotionOverride }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Palette.background.ignoresSafeArea()
                content
                    .environment(\.contentMargin, Spacing.margin(for: proxy.size.width))
                    .animation(reduceMotion ? nil : Motion.entrance, value: model.screen)
            }
        }
        .tint(Palette.accent)
        .overlay(alignment: .top) { noticeBanner }
        .task { await model.onAppear() }
        .onChange(of: model.pickerSelection) { _, selection in
            guard !selection.isEmpty else { return }
            Task { await model.handlePickerSelection() }
        }
        .fileImporter(isPresented: $model.isImportingFiles,
                      allowedContentTypes: [.heic, .heif],
                      allowsMultipleSelection: true) { result in
            model.handleFileImport(result)
        }
        .sheet(item: $diagnostics) { payload in
            DiagnosticsSheet(text: payload.text)
        }
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
                diagnostics = DiagnosticsPayload(text: model.diagnosticsText ?? "暂无诊断信息")
            }
            .transition(.opacity)
        case .permissionDenied:
            PermissionDeniedView {
                Task { await model.onAppear() }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var noticeBanner: some View {
        if let notice = model.notice {
            HStack(alignment: .top, spacing: Spacing.s) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Palette.accent)
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
                .strokeBorder(Palette.hairline, lineWidth: 1))
            .shadow(color: Palette.shadow, radius: 10, y: 4)
            .padding(.horizontal, Spacing.m)
            .padding(.top, Spacing.xs)
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
