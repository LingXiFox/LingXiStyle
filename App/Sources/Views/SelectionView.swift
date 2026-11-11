import SwiftUI
import PhotosUI
import LingXiKit

/// 1.5 selection: three-column nav, a single large photo with a material info bar, the
/// thumbnail strip, a two-row summary, and one primary action at the bottom.
struct SelectionView: View {
    @ObservedObject var model: AppModel
    @Environment(\.contentMargin) private var margin
    @Environment(\.duoControlInset) private var controlInset
    @Environment(\.duoLayout) private var duoLayout
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showPicker = false
    @ScaledMetric(relativeTo: .title2) private var innerHeaderSize: CGFloat = 28

    private var heroHeight: CGFloat { verticalSizeClass == .compact ? 220 : 392 }

    var body: some View {
        content
            .photosPicker(isPresented: $showPicker,
                          selection: $model.pickerSelection,
                          maxSelectionCount: max(1, AppModel.maxSelection - model.items.count),
                          matching: .images,
                          photoLibrary: .shared())
    }

    @ViewBuilder
    private var content: some View {
        switch duoLayout {
        case .phone:
            standardBody
        case .cover:
            coverBody
        case .inner:
            innerBody
        }
    }

    private var selected: PhotoItem? { model.selectedItem }

    // MARK: - Standard phone

    private var standardBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.m) {
                header
                    .padding(.trailing, controlInset)

                hero
                    .frame(height: heroHeight)

                if let message = prepareFailureMessage {
                    InlineErrorNotice(message: message)
                }

                if model.convertibleLivePhotoCount > 0 {
                    livePhotoGroup
                        .padding(.top, Spacing.xxs)
                }

                summary
                    .padding(.top, Spacing.xxs)

                editedNote
            }
            .padding(.horizontal, margin)
            .padding(.top, Spacing.xs)
            .padding(.bottom, Spacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
    }

    private var header: some View {
        HStack(spacing: Spacing.s) {
            Button("取消") { model.reset() }
                .font(Typography.bodyEmphasized)
                .foregroundStyle(Palette.accentText)
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)

            Spacer(minLength: 0)
            Text("已选照片")
                .font(Typography.status)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)

            countLabel
        }
    }

    private var countLabel: some View {
        Text("\(model.items.count) / \(AppModel.maxSelection)")
            .font(Typography.caption)
            .monospacedDigit()
            .foregroundStyle(Palette.textSecondary)
            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
            .accessibilityLabel(String(localized: "selection.countAccessibility", defaultValue: "已选 \(model.items.count) 张，最多 \(AppModel.maxSelection) 张"))
    }

    private var hero: some View {
        PhotoHeroCard(image: selected?.image,
                      badge: badgeKind,
                      isPreparing: selected?.phase == .preparing,
                      selectionID: selected?.id,
                      infoLeading: infoLeading,
                      infoTrailing: infoTrailing)
    }

    private var livePhotoGroup: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Label(String(localized: "settings.livePhoto.section", defaultValue: "实况照片处理方式"),
                      systemImage: "livephoto")
                    .font(Typography.bodyEmphasized)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
                if model.livePhotoModeOverride != nil {
                    Text(String(localized: "本批临时设置"))
                        .font(Typography.micro)
                        .foregroundStyle(Palette.textSecondary)
                }
            }

            LivePhotoModeSelector(
                selection: model.effectiveLivePhotoMode,
                onSelect: { model.setLivePhotoModeOverride($0) },
                scopeNote: model.hasMixedLivePhotoBatch
                    ? String(localized: "只影响这批里的 \(model.convertibleLivePhotoCount) 张实况照片；其余照片不受影响。默认值可以在设置里修改。")
                    : String(localized: "只影响本次处理；默认值可以在设置里修改。")
            )
        }
    }

    private var summary: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "checkmark.circle")
                    .font(.system(.body, design: .default, weight: .medium))
                    .foregroundStyle(Palette.success)
                    .frame(width: 24, height: 22)
                Text(String(localized: "selection.readyCount", defaultValue: "\(model.convertibleCount) 张可添加"))
                    .font(Typography.bodyEmphasized)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, Spacing.m)

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 0.5)
                .padding(.leading, 52)

            HStack(alignment: .top, spacing: Spacing.s) {
                Image(systemName: "minus.circle")
                    .font(.system(.body, design: .default, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 24, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "selection.skippedCount", defaultValue: "\(model.skippedCount) 张会跳过"))
                        .font(Typography.body)
                        .foregroundStyle(Palette.textPrimary)
                    if let skipReason {
                        Text(skipReason)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .padding(.vertical, Spacing.xs)
            .padding(.horizontal, Spacing.m)
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var editedNote: some View {
        Group {
            if selected?.traits.isEdited == true {
                Label("系统相册里已有编辑记录。会新增一张照片，不覆盖原图或现有编辑。",
                      systemImage: "pencil.tip")
                    .font(Typography.micro)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: Spacing.xs) {
            PhotoThumbnailStrip(items: model.items,
                                selectedID: $model.selectedID,
                                onRemove: model.remove,
                                onAdd: { showPicker = true },
                                canAdd: model.items.count < AppModel.maxSelection)

            busyIndicator
                .padding(.horizontal, margin)

            primaryAction
                .padding(.horizontal, margin)

            Text(footnote)
                .font(Typography.micro)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Spacing.xxs)
        }
        .padding(.top, Spacing.xxs)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.hairline).frame(height: 0.5)
        }
    }

    // MARK: - Duo cover (466 × 678)

    private var coverBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(spacing: Spacing.s) {
                    Text("已选照片")
                        .font(.system(.title2, design: .default, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    countLabel
                }

                hero
                    .frame(height: DuoMetrics.coverPreviewHeight)

                if let message = prepareFailureMessage {
                    InlineErrorNotice(message: message)
                }

                if model.convertibleLivePhotoCount > 0 {
                    DuoLivePhotoModeRow(selection: model.effectiveLivePhotoMode,
                                        onSelect: { model.setLivePhotoModeOverride($0) })
                }

                coverSummary

                PhotoThumbnailStrip(items: model.items,
                                    selectedID: $model.selectedID,
                                    onRemove: model.remove,
                                    onAdd: { showPicker = true },
                                    canAdd: model.items.count < AppModel.maxSelection,
                                    side: DuoMetrics.coverThumbnailSide)
                    .padding(.horizontal, -DuoMetrics.coverMargin)

                editedNote
            }
            .padding(.horizontal, DuoMetrics.coverMargin)
            .padding(.trailing, DuoMetrics.coverRailWidth)
            .padding(.top, Spacing.xs)
            .padding(.bottom, DuoMetrics.coverBottom)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) { coverBottomBar }
        .overlay(alignment: .topTrailing) {
            DuoCoverRail {
                DuoRailButton(systemImage: "xmark",
                              label: String(localized: "取消"),
                              identifier: "selection.cancel") {
                    model.reset()
                }
            }
        }
    }

    private var coverSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Spacing.xs) {
                Label(String(localized: "selection.readyCount", defaultValue: "\(model.convertibleCount) 张可添加"),
                      systemImage: "checkmark.circle")
                    .foregroundStyle(Palette.success)
                Text("·")
                    .foregroundStyle(Palette.textTertiary)
                Label(String(localized: "selection.skippedCount", defaultValue: "\(model.skippedCount) 张会跳过"),
                      systemImage: "minus.circle")
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 0)
            }
            .font(Typography.caption)

            if let skipReason {
                Text(skipReason)
                    .font(Typography.micro)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Spacing.s)
        .frame(minHeight: 40)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var coverBottomBar: some View {
        VStack(spacing: Spacing.xs) {
            busyIndicator

            primaryAction

            Text(footnote)
                .font(Typography.micro)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DuoMetrics.coverMargin)
        .padding(.top, Spacing.xs)
        .padding(.bottom, Spacing.s)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.hairline).frame(height: 0.5)
        }
    }

    // MARK: - Duo inner (951 × 669)

    private var innerBody: some View {
        DuoInnerSplit {
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(spacing: Spacing.s) {
                    Text("已选照片")
                        .font(.system(size: innerHeaderSize, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    countLabel
                }

                DuoQueueGrid(items: model.items,
                             selectedID: $model.selectedID,
                             onRemove: model.remove,
                             onAdd: { showPicker = true },
                             canAdd: model.items.count < AppModel.maxSelection)

                if model.convertibleLivePhotoCount > 0 {
                    DuoLivePhotoModeRow(selection: model.effectiveLivePhotoMode,
                                        onSelect: { model.setLivePhotoModeOverride($0) },
                                        showsQuotaNote: false)
                }

                summary

                editedNote

                Spacer(minLength: 0)

                Text(footnote)
                    .font(Typography.micro)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, DuoMetrics.innerLeadingPadding)
            .padding(.trailing, DuoMetrics.innerTrailingPadding)
            .padding(.top, 28)
            .padding(.bottom, DuoMetrics.innerBottom)
        } trailing: {
            VStack(spacing: Spacing.s) {
                hero
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topTrailing) {
                        DuoRailButton(systemImage: "xmark",
                                      label: String(localized: "取消"),
                                      identifier: "selection.cancel") {
                            model.reset()
                        }
                        .padding(Spacing.s)
                    }

                busyIndicator

                primaryAction
            }
            .padding(.trailing, DuoMetrics.innerRightPadding)
            .padding(.top, 28)
            .padding(.bottom, DuoMetrics.innerBottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Shared controls

    @ViewBuilder
    private var primaryAction: some View {
        if quotaExhausted {
            PrimaryActionButton(title: String(localized: "今日免费额度已用完"),
                                isEnabled: model.convertibleCount > 0 && !model.isBusyPreparing,
                                isWorking: model.isBusyPreparing) {
                model.presentQuotaLimit()
            }
        } else {
            PrimaryActionButton(title: model.ctaTitle,
                                isEnabled: model.convertibleCount > 0 && !model.isBusyPreparing,
                                isWorking: model.isBusyPreparing) {
                model.startConversion()
            }
        }
    }

    @ViewBuilder
    private var busyIndicator: some View {
        if model.isBusyPreparing {
            HStack(spacing: Spacing.xs) {
                ProgressView().controlSize(.small).tint(Palette.running)
                Text("正在检查原件")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Derived state

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

    private var infoLeading: String? {
        guard let inspection = selected?.inspection else { return nil }
        let width = inspection.pixelWidth.formatted(.number.grouping(.automatic))
        let height = inspection.pixelHeight.formatted(.number.grouping(.automatic))
        let megapixels = (inspection.pixelWidth * inspection.pixelHeight) / 1_000_000
        return "\(width) × \(height) · \(megapixels)MP"
    }

    private var infoTrailing: String? {
        guard let inspection = selected?.inspection else { return nil }
        var parts: [String] = []
        if selected?.isLivePhoto == true { parts.append(String(localized: "实况照片")) }
        if inspection.hasHDRGainMap { parts.append("HDR") }
        if inspection.hasStyleMetadata { parts.append(String(localized: "含风格信息")) }
        return parts.isEmpty ? String(localized: "标准 HEIC") : parts.joined(separator: " · ")
    }

    private var prepareFailureMessage: String? {
        guard case .preparingFailed(let message) = selected?.phase else { return nil }
        return message
    }

    private var skippedItems: [PhotoItem] {
        model.items.filter { $0.phase == .ready && !$0.isConvertible }
    }

    private var skipReason: String? {
        let reasons = skippedItems.compactMap { item -> String? in
            guard let verdict = item.verdict else { return nil }
            switch verdict.status {
            case .alreadyEnhanced: return String(localized: "已带有纹理与颗粒")
            case .unsupported: return verdict.issues.first?.title
            case .ready: return nil
            }
        }
        let unique = Array(NSOrderedSet(array: reasons)) as? [String] ?? reasons
        return unique.isEmpty ? nil : unique.prefix(2).joined(separator: "、")
    }

    private var quotaExhausted: Bool {
        guard let quota = model.quota, !model.isPro, quota.isAvailable else { return false }
        return quota.remaining == 0
    }

    private var footnote: String {
        let base = String(localized: "原件不会被修改")
        if model.isPro { return String(localized: "无限转换 · \(base)") }
        guard let quota = model.quota, quota.isAvailable else { return base }
        if quota.remaining == 0 { return String(localized: "今日免费额度已用完 · \(base)") }
        return String(localized: "今日免费额度还剩 \(quota.remaining) 张 · \(base)")
    }
}
