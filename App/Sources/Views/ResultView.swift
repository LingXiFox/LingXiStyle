import SwiftUI
import UIKit

struct ResultView: View {
    @ObservedObject var model: AppModel
    var onShowDiagnostics: () -> Void
    @Environment(\.contentMargin) private var margin
    @State private var viewer: ViewerPayload?

    private var summary: ConversionSummary { model.summary ?? ConversionSummary(items: model.items) }
    private var savedItems: [PhotoItem] { model.savedItems }
    private var shareableURLs: [URL] { savedItems.compactMap(\.outputURL) }
    private var warnedItems: [PhotoItem] { savedItems.filter { $0.saveWarning != nil } }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.m) {
                ResultHeroCard(summary: summary,
                               savedItems: savedItems,
                               onView: { viewer = ViewerPayload(index: 0) },
                               onViewItem: { index in viewer = ViewerPayload(index: index) })

                if !warnedItems.isEmpty { warningCard }

                if !summary.failures.isEmpty { failuresCard }

                if !summary.skippedReasons.isEmpty { skippedCard }

                if model.deferredCount > 0 { deferredCard }

                Button(action: onShowDiagnostics) {
                    Label("查看诊断信息", systemImage: "stethoscope")
                        .font(Typography.captionEmphasized)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: Layout.minimumTouchTarget)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, margin)
            .padding(.top, Spacing.m)
            .padding(.bottom, Spacing.l)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .fullScreenCover(item: $viewer) { payload in
            SavedResultsViewer(items: savedItems, startIndex: payload.index)
        }
    }

    private var warningCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Label("照片已保存，但有一项回读提示", systemImage: "exclamationmark.triangle.fill")
                .font(Typography.captionEmphasized)
                .foregroundStyle(Palette.warning)
            ForEach(warnedItems) { item in
                if let warning = item.saveWarning {
                    Text("\(item.displayName)：\(warning)")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("照片已经写入相册，不需要重试。可以打开系统「照片」确认资源类型。")
                .font(Typography.micro)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(Palette.warning.opacity(0.28), lineWidth: 1))
    }

    private var failuresCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("没有完成的照片")
                .font(Typography.status)
                .foregroundStyle(Palette.textPrimary)

            ForEach(summary.failures) { failure in
                HStack(alignment: .top, spacing: Spacing.s) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(.body, design: .default, weight: .medium))
                        .foregroundStyle(Palette.error)
                        .padding(.top, 2)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(failure.name)
                            .font(Typography.captionEmphasized)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(failure.message)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Spacing.xxs)
            }

            if summary.failedCount > 0 {
                Button {
                    model.retryFailed()
                } label: {
                    Label("重试失败项", systemImage: "arrow.clockwise")
                        .font(Typography.captionEmphasized)
                        .foregroundStyle(Palette.accentText)
                        .frame(minHeight: Layout.minimumTouchTarget)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(Palette.hairline, lineWidth: 1))
    }

    private var skippedCard: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("跳过的照片")
                .font(Typography.status)
                .foregroundStyle(Palette.textPrimary)
            ForEach(Array(summary.skippedReasons.enumerated()), id: \.offset) { _, reason in
                Text(reason)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("这些照片没有被修改，也没有保存副本。")
                .font(Typography.micro)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(Palette.hairline, lineWidth: 1))
    }

    private var deferredCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label("还有 \(model.deferredCount) 张未处理", systemImage: "clock.badge.exclamationmark")
                .font(Typography.captionEmphasized)
                .foregroundStyle(Palette.warning)
            Text("今日免费额度不足，这些照片没有转换，也没有消耗额度。明天 00:00 后会恢复免费额度。")
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.isPro {
                PrimaryActionButton(title: "继续处理剩余 \(model.deferredCount) 张", systemImage: "sparkles") {
                    model.startConversion()
                }
            } else {
                SecondaryActionButton(title: "升级 Pro 继续处理", systemImage: "sparkles") {
                    model.presentPro()
                }
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(Palette.warning.opacity(0.24), lineWidth: 1))
    }

    private var bottomBar: some View {
        VStack(spacing: Spacing.xs) {
            if summary.savedCount > 0 {
                HStack(spacing: Spacing.s) {
                    PrimaryActionButton(title: "查看成果", systemImage: "photo.stack") {
                        viewer = ViewerPayload(index: 0)
                    }
                    if !shareableURLs.isEmpty {
                        ShareLink(items: shareableURLs) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(.headline, design: .default, weight: .semibold))
                                .foregroundStyle(Palette.textPrimary)
                                .frame(width: 56, height: Layout.minimumTouchTarget + 8)
                                .background(Palette.surfaceElevated,
                                            in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                                    .strokeBorder(Palette.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("分享成果")
                        .accessibilityHint("分享已保存的 HEIC 文件")
                    }
                }
                if summary.failedCount > 0 {
                    SecondaryActionButton(title: "重试失败项", systemImage: "arrow.clockwise") {
                        model.retryFailed()
                    }
                }
            } else if summary.failedCount > 0 {
                PrimaryActionButton(title: "重试失败项", systemImage: "arrow.clockwise") {
                    model.retryFailed()
                }
            }

            Button("继续处理") { model.reset() }
                .font(Typography.captionEmphasized)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: Layout.minimumTouchTarget)
        }
        .padding(.top, Spacing.s)
        .padding(.horizontal, margin)
        .padding(.bottom, Spacing.xs)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.hairline).frame(height: 0.5)
        }
    }
}

private struct ViewerPayload: Identifiable {
    let id = UUID()
    let index: Int
}

// MARK: - Result hero

private struct ResultHeroCard: View {
    let summary: ConversionSummary
    let savedItems: [PhotoItem]
    let onView: () -> Void
    let onViewItem: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride
    @State private var appeared = false

    private var reduceMotion: Bool { systemReduceMotion || reduceMotionOverride }

    var body: some View {
        VStack(spacing: 0) {
            if let first = savedItems.first {
                Button(action: onView) {
                    ZStack {
                        Palette.background
                        Image(uiImage: first.image)
                            .resizable()
                            .scaledToFit()
                            .padding(Spacing.s)
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .clipped()
                    .overlay(alignment: .topTrailing) {
                        Text(savedItems.count > 1 ? "\(savedItems.count) 张" : "新照片")
                            .font(Typography.micro)
                            .foregroundStyle(Palette.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(Spacing.s)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看已保存照片")
                .accessibilityHint("打开成果预览")
            } else {
                ZStack {
                    LinearGradient(colors: [Palette.surfaceElevated, Palette.surface],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                    Image(systemName: summary.failedCount > 0 ? "exclamationmark.seal" : "checkmark.seal")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(summary.failedCount > 0 ? Palette.warning : Palette.textSecondary)
                }
                .frame(height: 154)
                .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(alignment: .top, spacing: Spacing.s) {
                    Image(systemName: summary.savedCount > 0 ? "checkmark.seal.fill" : "info.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(summary.savedCount > 0 ? Palette.success : Palette.warning)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(summary.headline)
                            .font(Typography.section)
                            .foregroundStyle(Palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(subline)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: Spacing.xs) {
                    countPill("成功", value: summary.savedCount, tint: Palette.success)
                    if summary.skippedCount > 0 { countPill("跳过", value: summary.skippedCount, tint: Palette.textSecondary) }
                    if summary.failedCount > 0 { countPill("失败", value: summary.failedCount, tint: Palette.error) }
                    if summary.cancelledCount > 0 { countPill("取消", value: summary.cancelledCount, tint: Palette.warning) }
                    Spacer(minLength: 0)
                }

                if savedItems.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.xs) {
                            ForEach(Array(savedItems.enumerated()), id: \.element.id) { index, item in
                                Button { onViewItem(index) } label: {
                                    Image(uiImage: item.image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 62, height: 62)
                                        .clipShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                                            .strokeBorder(Palette.hairline, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("查看第 \(index + 1) 张成果")
                            }
                        }
                    }
                }
            }
            .padding(Spacing.l)
        }
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .shadow(color: Palette.shadow, radius: 16, y: 6)
        .offset(y: appeared || reduceMotion ? 0 : 10)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .onAppear {
            guard !reduceMotion else { appeared = true; return }
            withAnimation(Motion.result) { appeared = true }
        }
    }

    private var subline: String {
        if summary.savedCount > 0 {
            return "原图没有被修改，新照片已存入系统相册。"
        }
        if summary.failedCount > 0 { return "没有写入新照片，原图保持不变。" }
        if summary.cancelledCount > 0 { return "任务已取消，没有写入新照片。" }
        return "这些照片不需要生成新副本。"
    }

    private func countPill(_ title: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(title).font(Typography.micro).foregroundStyle(Palette.textSecondary)
            Text("\(value)").font(Typography.numeric).foregroundStyle(Palette.textPrimary)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 6)
        .background(Palette.surfaceElevated, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value) 张")
    }
}

// MARK: - Saved result viewer

struct SavedResultsViewer: View {
    let items: [PhotoItem]
    @State private var index: Int
    @Environment(\.dismiss) private var dismiss

    init(items: [PhotoItem], startIndex: Int) {
        self.items = items
        _index = State(initialValue: min(max(startIndex, 0), max(items.count - 1, 0)))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if items.isEmpty {
                Text("没有可预览的照片")
                    .font(Typography.body)
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                TabView(selection: $index) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                        VStack(spacing: Spacing.s) {
                            Image(uiImage: item.image)
                                .resizable()
                                .scaledToFit()
                                .padding(.horizontal, Spacing.s)
                            if let warning = item.saveWarning {
                                Text(warning)
                                    .font(Typography.caption)
                                    .foregroundStyle(.orange)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, Spacing.l)
                            }
                        }
                        .tag(offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(.body, design: .default, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: Layout.minimumTouchTarget, height: Layout.minimumTouchTarget)
                            .background(.black.opacity(0.35), in: Circle())
                    }
                    .accessibilityLabel("关闭预览")
                    Spacer()
                    if !items.isEmpty {
                        Text("\(index + 1) / \(items.count)")
                            .font(Typography.captionEmphasized)
                            .foregroundStyle(.white)
                            .padding(.horizontal, Spacing.s)
                            .padding(.vertical, Spacing.xs)
                            .background(.black.opacity(0.35), in: Capsule())
                    }
                }
                .padding(.horizontal, Spacing.m)
                .padding(.top, Spacing.xs)
                Spacer()
                if items.indices.contains(index), let url = items[index].outputURL {
                    ShareLink(item: url) {
                        Label("分享这张 HEIC", systemImage: "square.and.arrow.up")
                            .font(Typography.bodyEmphasized)
                            .foregroundStyle(.black)
                            .padding(.horizontal, Spacing.l)
                            .frame(minHeight: Layout.minimumTouchTarget + 4)
                            .background(.white, in: Capsule())
                    }
                    .padding(.bottom, Spacing.m)
                }
            }
        }
        .statusBarHidden()
    }
}

// MARK: - Permission

struct PermissionDeniedView: View {
    var onRetry: () -> Void
    var onImportFiles: () -> Void
    @Environment(\.contentMargin) private var margin

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.m) {
                Spacer(minLength: Spacing.xl)
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(Palette.warning)
                    .accessibilityHidden(true)
                Text("需要照片访问权限")
                    .font(Typography.section)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                Text("LingXiStyle 只读取你选中的 HEIC 原片，读取和保存都在这台设备上完成。没有相册权限时，仍然可以从「文件」导入 HEIC。")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryActionButton(title: "打开系统设置", systemImage: "gearshape") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .padding(.top, Spacing.s)

                SecondaryActionButton(title: "从文件导入 HEIC", systemImage: "folder", action: onImportFiles)
                SecondaryActionButton(title: "重新检查", systemImage: "arrow.clockwise", action: onRetry)

                Text("文件导入不需要相册权限。")
                    .font(Typography.micro)
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: Spacing.xl)
            }
            .padding(.horizontal, margin)
            .frame(maxWidth: .infinity)
        }
    }
}
