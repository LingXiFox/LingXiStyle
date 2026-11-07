import SwiftUI
import UIKit
import LingXiKit

struct ResultView: View {
    @ObservedObject var model: AppModel
    var onShowDiagnostics: () -> Void
    @Environment(\.contentMargin) private var margin
    @State private var viewer: ViewerPayload?

    private var summary: ConversionSummary { model.summary ?? ConversionSummary(items: model.items) }
    private var savedItems: [PhotoItem] { model.savedItems }
    private var warnedItems: [PhotoItem] { savedItems.filter { $0.saveWarning != nil } }
    private var integrity: IntegrityReport? { savedItems.compactMap(\.integrity).first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                header

                statsRow

                if let first = savedItems.first {
                    previewCard(first)
                }

                if let integrity {
                    integrityGroup(integrity)
                }

                if !warnedItems.isEmpty { warningNotice }

                if !summary.failures.isEmpty { failuresGroup }

                if !summary.skippedReasons.isEmpty { skippedGroup }

                if model.deferredCount > 0 { deferredCard }

                if integrity == nil { diagnosticsRow }
            }
            .padding(.horizontal, margin)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.l)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .fullScreenCover(item: $viewer) { payload in
            SavedResultsViewer(items: savedItems, startIndex: payload.index)
        }
    }

    // MARK: Header and stats

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: Spacing.s) {
                Image(systemName: summary.savedCount > 0 ? "checkmark.circle" : (summary.failedCount > 0 ? "exclamationmark.circle" : "info.circle"))
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(summary.savedCount > 0 ? Palette.success : (summary.failedCount > 0 ? Palette.error : Palette.warning))
                    .accessibilityHidden(true)
                Text(title)
                    .font(Typography.sheetTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            Text(subline)
                .font(.system(.subheadline))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Spacing.m)
    }

    private var title: String {
        if summary.savedCount > 0 { return String(localized: "result.title.saved", defaultValue: "已存入相册") }
        if summary.failedCount > 0 { return String(localized: "result.title.failed", defaultValue: "这次没有保存成功") }
        if summary.cancelledCount > 0 { return String(localized: "result.title.cancelled", defaultValue: "已取消") }
        return String(localized: "result.title.empty", defaultValue: "没有需要处理的照片")
    }

    private var statsRow: some View {
        HStack(spacing: Spacing.xs) {
            statCell(String(localized: "成功"), value: summary.savedCount, symbol: "checkmark", tint: Palette.success)
            statCell(String(localized: "跳过"), value: summary.skippedCount, symbol: "minus", tint: Palette.textTertiary)
            statCell(String(localized: "失败"), value: summary.failedCount, symbol: "xmark", tint: Palette.error)
        }
    }

    private func statCell(_ title: String, value: Int, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(Typography.statNumber)
                .foregroundStyle(value == 0 ? Palette.textTertiary : Palette.textPrimary)
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, 10)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.stat, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "summary.countAccessibility", defaultValue: "\(title) \(value) 张"))
    }

    private var subline: String {
        if summary.savedCount > 0 {
            return String(localized: "原图没有被修改，新照片已另存为单独的一张。")
        }
        if summary.failedCount > 0 { return String(localized: "没有写入新照片，原图保持不变。") }
        if summary.cancelledCount > 0 { return String(localized: "任务已取消，没有写入新照片。") }
        return String(localized: "这些照片不需要生成新副本。")
    }

    // MARK: Preview

    private func previewCard(_ item: PhotoItem) -> some View {
        VStack(spacing: Spacing.xs) {
            ZStack {
                Color.black.opacity(0.92)
                Button {
                    viewer = ViewerPayload(index: 0)
                } label: {
                    Image(uiImage: item.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "查看已保存照片"))
                .accessibilityHint(String(localized: "打开成果预览"))

                if let url = item.outputURL {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.42), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("分享这张 HEIC")
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 270)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

            HStack(spacing: Spacing.s) {
                Text(item.outputURL?.lastPathComponent ?? item.displayName)
                    .font(Typography.monospaced)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if savedItems.count > 1 {
                    HStack(spacing: 5) {
                        ForEach(0..<savedItems.count, id: \.self) { index in
                            Capsule()
                                .fill(index == 0 ? Palette.textPrimary : Palette.textTertiary.opacity(0.4))
                                .frame(width: index == 0 ? 16 : 6, height: 6)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(localized: "result.pages", defaultValue: "第 1 张，共 \(savedItems.count) 张"))
                }
            }
            .padding(.horizontal, Spacing.xxs)
        }
    }

    // MARK: Integrity

    private func integrityGroup(_ report: IntegrityReport) -> some View {
        let primary = report.checks.first { $0.id == "primary" }
        let preservedIDs = ["hdr", "exif", "thumbnail", "gainmap"]
        let preserved = report.checks.filter { preservedIDs.contains($0.id) }
        let preservedPassed = !preserved.isEmpty && preserved.allSatisfy(\.passed)

        return VStack(spacing: 0) {
            integrityRow(title: String(localized: "result.integrity.primary", defaultValue: "主图像素逐块校验一致"),
                        passed: primary?.passed ?? report.passed,
                        trailing: nil)

            Divider().overlay(Palette.hairline).padding(.leading, 40)

            integrityRow(title: String(localized: "result.integrity.metadata", defaultValue: "HDR、EXIF、缩略图已保留"),
                        passed: preservedPassed,
                        trailing: AnyView(
                            Button(action: onShowDiagnostics) {
                                Text(String(localized: "查看诊断信息"))
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.accentText)
                                    .frame(minHeight: Layout.minimumTouchTarget)
                            }
                            .buttonStyle(.plain)
                        ))
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
    }

    private func integrityRow(title: String, passed: Bool, trailing: AnyView?) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: passed ? "checkmark" : "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(passed ? Palette.success : Palette.error)
                .frame(width: 18)
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let trailing { trailing }
        }
        .padding(.horizontal, Spacing.m)
        .frame(minHeight: 44)
    }

    // MARK: Warnings, failures, skips, deferred

    private var warningNotice: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(alignment: .top, spacing: Spacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.warning)
                Text(String(localized: "result.warning.title", defaultValue: "照片已保存，但有一项回读提示"))
                    .font(Typography.captionEmphasized)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(warnedItems) { item in
                if let warning = item.saveWarning {
                    Text(String(localized: "result.warningLine", defaultValue: "\(item.displayName)：\(warning)"))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("照片已经写入相册，不需要重试。可以打开系统「照片」确认资源类型。")
                .font(Typography.micro)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.group, style: .continuous)
            .strokeBorder(Palette.warning.opacity(0.28), lineWidth: 1))
    }

    private var failuresGroup: some View {
        VStack(spacing: 0) {
            groupHeader(String(localized: "result.failures.title", defaultValue: "未完成 \(summary.failedCount) 张"), symbol: "exclamationmark.circle.fill", tint: Palette.error)

            ForEach(summary.failures) { failure in
                Divider().overlay(Palette.hairline).padding(.leading, Spacing.m)
                HStack(alignment: .top, spacing: Spacing.s) {
                    VStack(alignment: .leading, spacing: 2) {
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
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, 10)
            }

            if summary.failedCount > 0 {
                Divider().overlay(Palette.hairline).padding(.leading, Spacing.m)
                Button {
                    model.retryFailed()
                } label: {
                    Label(String(localized: "重试失败项"), systemImage: "arrow.clockwise")
                        .font(Typography.captionEmphasized)
                        .foregroundStyle(Palette.accentText)
                        .frame(maxWidth: .infinity, minHeight: Layout.minimumTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
    }

    private var skippedGroup: some View {
        VStack(spacing: 0) {
            groupHeader(String(localized: "result.skipped.title", defaultValue: "跳过 \(summary.skippedCount) 张"), symbol: "minus.circle", tint: Palette.textTertiary)

            ForEach(Array(summary.skippedReasons.enumerated()), id: \.offset) { _, reason in
                Divider().overlay(Palette.hairline).padding(.leading, Spacing.m)
                Text(reason)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.m)
                    .padding(.vertical, 10)
            }

            Divider().overlay(Palette.hairline).padding(.leading, Spacing.m)
            Text("这些照片没有被修改，也没有保存副本。")
                .font(Typography.micro)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, 10)
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
    }

    private var deferredCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label(String(localized: "result.deferred", defaultValue: "还有 \(model.deferredCount) 张未处理"), systemImage: "clock.badge.exclamationmark")
                .font(Typography.captionEmphasized)
                .foregroundStyle(Palette.warning)
            Text(String(localized: "result.deferredQuota", defaultValue: "今日免费额度不足，这些照片没有处理，也没有消耗额度。明天 00:00 后会恢复免费额度。"))
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.isPro {
                PrimaryActionButton(title: String(localized: "result.continueRemaining", defaultValue: "继续处理剩余 \(model.deferredCount) 张"), systemImage: "sparkles") {
                    model.startConversion()
                }
            } else {
                SecondaryActionButton(title: String(localized: "升级 Pro 继续处理"), systemImage: "sparkles") {
                    model.presentPro()
                }
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
    }

    private func groupHeader(_ title: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(Typography.bodyEmphasized)
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.m)
        .frame(minHeight: 44)
    }

    private var diagnosticsRow: some View {
        Button(action: onShowDiagnostics) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "stethoscope")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 22)
                Text(String(localized: "查看诊断信息"))
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, Spacing.m)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: Spacing.xs) {
            if summary.failedCount > 0 {
                SecondaryActionButton(title: String(localized: "重试失败项"), systemImage: "arrow.clockwise") {
                    model.retryFailed()
                }
            }
            PrimaryActionButton(title: String(localized: "result.continueNew", defaultValue: "继续处理新照片"), systemImage: "plus") {
                model.reset()
            }
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
                            .foregroundStyle(Palette.onAccent)
                            .padding(.horizontal, Spacing.l)
                            .frame(minHeight: Layout.minimumTouchTarget + 4)
                            .background(Palette.accent, in: Capsule())
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

                ZStack {
                    Circle()
                        .fill(Palette.fillControl)
                        .frame(width: 72, height: 72)
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                }
                .accessibilityHidden(true)

                Text("需要照片访问权限")
                    .font(Typography.sheetTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text("纹粒只读取你选中的 HEIC 原片，并把新照片另存进相册。照片不经过任何服务器。")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: Spacing.s) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Palette.info)
                        .frame(width: 22, height: 22)
                    Text(String(localized: "没有相册权限时，仍然可以从「文件」导入 HEIC。"))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))

                PrimaryActionButton(title: String(localized: "前往设置开启"), systemImage: "gearshape") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }

                SecondaryActionButton(title: String(localized: "从「文件」导入"), systemImage: "folder", action: onImportFiles)

                Button(action: onRetry) {
                    Text(String(localized: "重新检查"))
                        .font(Typography.captionEmphasized)
                        .foregroundStyle(Palette.accentText)
                        .frame(minHeight: Layout.minimumTouchTarget)
                }
                .buttonStyle(.plain)

                Spacer(minLength: Spacing.xl)
            }
            .padding(.horizontal, margin)
            .frame(maxWidth: .infinity)
        }
    }
}