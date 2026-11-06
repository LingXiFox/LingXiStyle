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
                PhotoHeroCard(image: selected?.image,
                              isWorking: selected?.phase == .preparing,
                              isScanning: false,
                              badge: badgeKind,
                              selectionID: selected?.id)
                    .frame(height: heroHeight)
                    .animation(Motion.selection, value: selected?.id)

                if let selected {
                    detailCard(for: selected)
                        .id(selected.id)
                }
            }
            .padding(.horizontal, margin)
            .padding(.top, Spacing.m)
            .padding(.bottom, Spacing.l)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .photosPicker(isPresented: $showPicker,
                      selection: $model.pickerSelection,
                      maxSelectionCount: max(1, AppModel.maxSelection - model.items.count),
                      matching: .images,
                      photoLibrary: .shared())
    }

    private var selected: PhotoItem? { model.selectedItem }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("已选 \(model.items.count) 张")
                    .font(Typography.section)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("最多 \(AppModel.maxSelection) 张 · 原件不会被修改")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
            Button("清空") { model.reset() }
                .font(Typography.captionEmphasized)
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHint("清空队列并回到首页，不会删除任何照片")
        }
    }

    private var badgeKind: CompatibilityBadge.Kind? {
        guard let selected else { return nil }
        switch selected.phase {
        case .preparing: return .downloading
        case .preparingFailed: return .failed
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
            HStack(spacing: Spacing.s) {
                if let badgeKind { CompatibilityBadge(kind: badgeKind) }
                Spacer(minLength: 0)
                if let inspection = item.inspection {
                    Text("\(inspection.pixelWidth) × \(inspection.pixelHeight)")
                        .font(Typography.micro)
                        .foregroundStyle(Palette.textSecondary)
                        .monospacedDigit()
                }
            }

            switch item.phase {
            case .preparing:
                HStack(spacing: Spacing.s) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("正在读取原始 HEIC")
                            .font(Typography.status)
                            .foregroundStyle(Palette.textPrimary)
                        Text("如果原件在 iCloud，会先下载完整文件再检查。")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            case .preparingFailed(let message):
                InlineErrorNotice(message: message)
            case .ready:
                readyDetail(for: item)
            }

            if item.traits.isEdited {
                Label("这张照片在系统相册里编辑过。解锁只会新增一张照片，不会覆盖原图或现有编辑记录。",
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
    private func readyDetail(for item: PhotoItem) -> some View {
        if let verdict = item.verdict {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(verdict.headline)
                    .font(Typography.status)
                    .foregroundStyle(Palette.textPrimary)
                Text(verdict.detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !verdict.issues.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(verdict.issues.prefix(2).enumerated()), id: \.offset) { _, issue in
                            Text("· \(issue.guidance)")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .padding(.top, 2)
                }

                metadataRow(for: item)
            }
        }
    }

    @ViewBuilder
    private func metadataRow(for item: PhotoItem) -> some View {
        if let inspection = item.inspection {
            HStack(spacing: Spacing.xs) {
                if inspection.hasHDRGainMap { chip("HDR") }
                if inspection.hasStyleMetadata { chip("风格元数据") }
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

            HStack {
                Text("已选 \(model.items.count) 张")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: Spacing.s)
                Text("\(model.convertibleCount) 张可解锁")
                    .font(Typography.captionEmphasized)
                    .foregroundStyle(model.convertibleCount > 0 ? Palette.success : Palette.textSecondary)
            }
            .padding(.horizontal, margin)

            PrimaryActionButton(title: model.ctaTitle,
                                systemImage: "sparkles",
                                isEnabled: model.convertibleCount > 0 && !model.isBusyPreparing,
                                isWorking: model.isBusyPreparing) {
                model.startConversion()
            }
            .padding(.horizontal, margin)

            Text("仅在本机处理 · 原图始终保留")
                .font(Typography.micro)
                .foregroundStyle(Palette.textSecondary)
                .padding(.bottom, Spacing.xs)
        }
        .padding(.top, Spacing.xxs)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.hairline).frame(height: 0.5)
        }
    }
}
