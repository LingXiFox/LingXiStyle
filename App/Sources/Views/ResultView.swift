import SwiftUI
import UIKit

struct ResultView: View {
    @ObservedObject var model: AppModel
    var onShowDiagnostics: () -> Void
    @Environment(\.contentMargin) private var margin

    private var summary: ConversionSummary { model.summary ?? ConversionSummary(items: model.items) }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.m) {
                if let summary = model.summary {
                    ConversionSummaryCard(summary: summary)
                }

                if !summary.failures.isEmpty {
                    failuresCard
                }

                if !summary.skippedReasons.isEmpty {
                    skippedCard
                }

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
    }

    private var failuresCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("没有完成的照片")
                .font(Typography.status)
                .foregroundStyle(Palette.textPrimary)

            ForEach(summary.failures) { failure in
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
                    Text(failure.code)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Palette.textSecondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Spacing.xxs)
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
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(Palette.hairline, lineWidth: 1))
    }

    private var bottomBar: some View {
        VStack(spacing: Spacing.xs) {
            if summary.savedCount > 0 {
                PrimaryActionButton(title: "打开相册", systemImage: "photo.stack") {
                    openPhotos()
                }
            } else if summary.failedCount > 0 {
                PrimaryActionButton(title: "重试失败项", systemImage: "arrow.clockwise") {
                    model.retryFailed()
                }
            }

            if summary.failedCount > 0 && summary.savedCount > 0 {
                SecondaryActionButton(title: "重试失败项", systemImage: "arrow.clockwise") {
                    model.retryFailed()
                }
            }

            Button("再处理一批") { model.reset() }
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

    /// photos-redirect:// is an undocumented system scheme. It is only a convenience jump;
    /// when it is unavailable we fall back to the app's settings page instead of failing silently.
    private func openPhotos() {
        guard let url = URL(string: "photos-redirect://") else { return }
        UIApplication.shared.open(url, options: [:]) { opened in
            guard !opened, let settings = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(settings)
        }
    }
}

struct PermissionDeniedView: View {
    var onRetry: () -> Void
    @Environment(\.contentMargin) private var margin

    var body: some View {
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
            Text("LingXiStyle 只读取你选中的 HEIC 原片，读取和保存都在这台设备上完成。没有权限时无法打开图库。")
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryActionButton(title: "打开系统设置", systemImage: "gearshape") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .padding(.top, Spacing.s)

            SecondaryActionButton(title: "重新检查", systemImage: "arrow.clockwise", action: onRetry)

            Spacer(minLength: Spacing.xl)
        }
        .padding(.horizontal, margin)
        .frame(maxWidth: .infinity)
    }
}
