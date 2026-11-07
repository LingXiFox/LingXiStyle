import SwiftUI
import PhotosUI

struct SelectionView: View {
    @ObservedObject var model: AppModel
    @Environment(\.contentMargin) private var margin
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showPicker = false

    private var heroHeight: CGFloat { verticalSizeClass == .compact ? 220 : 360 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                header
                ZStack {
                    // A restrained halo lifts the photo off the background without altering it.
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(LinearGradient(colors: [Palette.accent.opacity(0.12), Palette.accentSecondary.opacity(0.05)],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .blur(radius: 22)
                        .padding(10)
                        .accessibilityHidden(true)

                    PhotoHeroCard(image: selected?.image,
                                  isWorking: selected?.phase == .preparing,
                                  isScanning: false,
                                  badge: badgeKind,
                                  selectionID: selected?.id)
                        .frame(height: heroHeight)
                }

                if let selected {
                    detailCard(for: selected)
                        .id(selected.id)
                }
            }
            .padding(.horizontal, margin)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .photosPicker(isPresented: $showPicker,
                      selection: $model.pickerSelection,
                      maxSelectionCount: max(1, AppModel.maxSelection - model.items.count),
                      matching: .images,
                      photoLibrary: .shared())
    }

    private var selected: PhotoItem? { model.selectedItem }

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text("已选照片")
                    .font(Typography.section)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("确认兼容性后开始解锁，原件不会被修改")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text("\(model.items.count) / \(AppModel.maxSelection)")
                .font(Typography.captionEmphasized)
                .monospacedDigit()
                .foregroundStyle(Palette.accentText)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, 5)
                .background(Palette.surfaceElevated, in: Capsule())
                .accessibilityLabel("已选 \(model.items.count) 张，最多 \(AppModel.maxSelection) 张")
            Button("清空") { model.reset() }
                .font(Typography.captionEmphasized)
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHint("清空队列并回到首页，不会删除任何照片")
        }
    }

    private var badgeKind: CompatibilityBadge.Kind? {
        guard let selected else { return nil }
        switch selected.phase {
        case .preparing:
            return .downloading
        case .preparingFailed:
            return .failed
        case .ready:
            switch selected.verdict?.status {
            case .ready: return .convertible
            case .alreadyEnhanced: return .noChange
            case .unsupported: return .unsupported
            case nil: return nil
            }
        }
    }

    @ViewBuilder
    private func detailCard(for item: PhotoItem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text(item.displayName)
                    .font(Typography.captionEmphasized)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: Spacing.xs)
                if let inspection = item.inspection {
                    Text("\(inspection.pixelWidth) × \(inspection.pixelHeight)")
                        .font(Typography.micro)
                        .foregroundStyle(Palette.textSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }

            switch item.phase {
            case .preparing:
                preparingDetail(for: item)
            case .preparingFailed(let message):
                InlineErrorNotice(message: message)
            case .ready:
                readyDetail(for: item)
            }

            if item.traits.isEdited {
                Label("系统相册里已有编辑记录。解锁会新增一张照片，不覆盖原图或现有编辑。",
                      systemImage: "pencil.tip")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func preparingDetail(for item: PhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Spacing.xs) {
                Text(item.downloadProgress == nil ? "正在读取原始 HEIC" : "正在从 iCloud 下载原件")
                    .font(Typography.status)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
                if let progress = item.downloadProgress {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(Typography.captionEmphasized)
                        .foregroundStyle(Palette.accentText)
                        .monospacedDigit()
                }
            }

            if let progress = item.downloadProgress {
                ProgressView(value: progress)
                    .tint(Palette.accent)
                    .accessibilityLabel("iCloud 原件下载进度")
                    .accessibilityValue("\(Int((progress * 100).rounded()))%")
            } else {
                ProgressView()
                    .tint(Palette.accent)
                    .accessibilityLabel("正在读取原始 HEIC")
            }

            Text(item.downloadProgress == nil
                 ? "先读取完整文件，再进行兼容性检查。"
                 : "下载完成后会自动检查，其他照片可以继续准备。")
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func readyDetail(for item: PhotoItem) -> some View {
        if let verdict = item.verdict {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verdict.headline)
                    .font(Typography.status)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verdict.detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                metadataRow(for: item)
            }
        }
    }

    @ViewBuilder
    private func metadataRow(for item: PhotoItem) -> some View {
        if let inspection = item.inspection {
            HStack(spacing: Spacing.xxs) {
                if inspection.hasHDRGainMap { chip("HDR") }
                if inspection.hasStyleMetadata { chip("风格") }
                if inspection.hasExif { chip("EXIF") }
                if inspection.hasThumbnail { chip("缩略图") }
                Spacer(minLength: 0)
            }
            .padding(.top, Spacing.xxs)
        }
    }

    private func chip(_ title: String) -> some View {
        Text(title)
            .font(Typography.micro)
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 4)
            .background(Palette.surfaceElevated, in: Capsule())
    }

    private var bottomBar: some View {
        VStack(spacing: Spacing.xs) {
            PhotoThumbnailStrip(items: model.items,
                                selectedID: $model.selectedID,
                                onRemove: model.remove,
                                onAdd: { showPicker = true },
                                canAdd: model.items.count < AppModel.maxSelection)

            HStack(spacing: Spacing.xs) {
                Label("\(model.convertibleCount) 张可解锁", systemImage: "sparkles")
                    .font(Typography.captionEmphasized)
                    .foregroundStyle(model.convertibleCount > 0 ? Palette.success : Palette.textSecondary)
                Spacer(minLength: Spacing.s)
                if model.isBusyPreparing {
                    ProgressView().controlSize(.small).tint(Palette.accent)
                    Text("正在准备")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                } else if model.skippedCount > 0 {
                    Text("\(model.skippedCount) 张会跳过")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(.horizontal, margin)

            HStack {
                QuotaBadge(quota: model.quota, isPro: model.isPro, compact: true) {
                    model.presentPro()
                }
                Spacer(minLength: 0)
                if let quota = model.quota, !model.isPro, quota.isAvailable, quota.remaining < model.convertibleCount {
                    Text("超出部分留到明天")
                        .font(Typography.micro)
                        .foregroundStyle(Palette.warning)
                }
            }
            .padding(.horizontal, margin)

            if let quota = model.quota, !model.isPro, quota.isAvailable, quota.remaining == 0 {
                PrimaryActionButton(title: "今日免费额度已用完",
                                    systemImage: "clock.badge.exclamationmark",
                                    isEnabled: model.convertibleCount > 0 && !model.isBusyPreparing,
                                    isWorking: model.isBusyPreparing) {
                    model.presentQuotaExhausted()
                }
                .padding(.horizontal, margin)
            } else {
                PrimaryActionButton(title: model.ctaTitle,
                                    systemImage: "sparkles",
                                    isEnabled: model.convertibleCount > 0 && !model.isBusyPreparing,
                                    isWorking: model.isBusyPreparing) {
                    model.startConversion()
                }
                .padding(.horizontal, margin)
            }

            Text("仅在本机处理 · 原图始终保留")
                .font(Typography.micro)
                .foregroundStyle(Palette.textSecondary)
                .padding(.bottom, Spacing.xxs)
        }
        .padding(.top, Spacing.xxs)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.hairline).frame(height: 0.5)
        }
    }
}
