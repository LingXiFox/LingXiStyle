import SwiftUI
import LingXiKit

/// Duo unfolded layout: a persistent queue on the left, the active page on the right.
/// Both columns observe the same `AppModel`, so folding or unfolding at any stage keeps the
/// queue, the current photo, real progress and saved results — no reprocessing, no extra quota.
struct WorkspaceRail: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            separator

            if model.items.isEmpty {
                emptyState
            } else {
                queue
            }

            separator
            footer
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.background)
        .accessibilityIdentifier("workspace.rail")
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text(String(localized: "workspace.queue.title", defaultValue: "照片队列"))
                .font(Typography.section)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            Text(counterText)
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .monospacedDigit()
        }
        .padding(.horizontal, Spacing.m)
        .padding(.top, Spacing.m)
        .padding(.bottom, Spacing.s)
    }

    private var counterText: String {
        guard !model.items.isEmpty else { return "" }
        let done = model.items.filter { $0.outcome != nil }.count
        if done > 0 || model.screen == .converting {
            return String(localized: "workspace.queue.counter", defaultValue: "已完成 \(done) / \(model.items.count)")
        }
        return String(localized: "workspace.queue.total", defaultValue: "共 \(model.items.count) 张")
    }

    // MARK: Queue

    private var queue: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.xxs) {
                ForEach(model.items) { item in
                    row(item)
                }
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.s)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func row(_ item: PhotoItem) -> some View {
        let focused = model.selectedItem?.id == item.id
        return Button {
            model.select(item)
        } label: {
            HStack(spacing: Spacing.s) {
                thumbnail(item)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(Typography.captionEmphasized)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(statusText(item))
                        .font(Typography.micro)
                        .foregroundStyle(statusTint(item))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
                statusIcon(item)
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 6)
            .background(focused ? Palette.surfaceElevated : Color.clear,
                        in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "thumbnail.accessibilityLabel",
                                    defaultValue: "\(item.displayName)，\(statusText(item))"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(focused ? .isSelected : AccessibilityTraits())
    }

    private func thumbnail(_ item: PhotoItem) -> some View {
        Image(uiImage: item.image)
            .resizable()
            .scaledToFill()
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 0.5)
            )
            .overlay(alignment: .bottomTrailing) {
                if item.hasLivePhotoVideo {
                    Image(systemName: "livephoto")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(2)
                        .background(.black.opacity(0.45), in: Circle())
                        .offset(x: 3, y: 3)
                        .accessibilityHidden(true)
                }
            }
    }

    private func statusText(_ item: PhotoItem) -> String {
        if let outcome = item.outcome {
            switch outcome {
            case .saved:
                return item.savedAsLivePhoto
                    ? String(localized: "workspace.queue.savedLivePhoto", defaultValue: "实况照片已保存")
                    : String(localized: "workspace.queue.saved", defaultValue: "已保存")
            case .skipped:
                return String(localized: "workspace.queue.skipped", defaultValue: "已跳过")
            case .failed:
                return String(localized: "workspace.queue.failed", defaultValue: "未完成")
            case .cancelled:
                return String(localized: "workspace.queue.cancelled", defaultValue: "已取消")
            }
        }
        if let stage = item.stage { return stage.inProgressTitle }
        return item.phase.label
    }

    private func statusTint(_ item: PhotoItem) -> Color {
        guard let outcome = item.outcome else {
            return item.stage != nil ? Palette.accentText : Palette.textSecondary
        }
        switch outcome {
        case .saved: return Palette.success
        case .failed: return Palette.error
        case .skipped, .cancelled: return Palette.textSecondary
        }
    }

    @ViewBuilder
    private func statusIcon(_ item: PhotoItem) -> some View {
        if item.isSaved {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.success)
                .accessibilityHidden(true)
        } else if case .failed? = item.outcome {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.error)
                .accessibilityHidden(true)
        } else if item.stage != nil {
            Image(systemName: "circle.dotted")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.accentText)
                .accessibilityHidden(true)
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: "photo.stack")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Palette.textTertiary)

            Text(String(localized: "workspace.queue.empty", defaultValue: "还没有选照片。选好的照片会在这里排队，右边显示当前照片。"))
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.m)
        .accessibilityElement(children: .combine)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            QuotaBadge(quota: model.quota, isPro: model.isPro, compact: true)

            if model.convertibleLivePhotoCount > 0 {
                Text(String(localized: "workspace.queue.liveMode", defaultValue: "实况照片按「\(model.effectiveLivePhotoMode.title)」处理。"))
                    .font(Typography.micro)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(LivePhotoProcessingMode.quotaNote)
                    .font(Typography.micro)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.m)
    }

    private var separator: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 0.5)
    }
}
