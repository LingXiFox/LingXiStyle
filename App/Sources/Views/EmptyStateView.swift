import SwiftUI
import UIKit
import PhotosUI
import LingXiKit

/// 1.5 home: quota capsule and settings in the top bar, centered brand mark and promise,
/// a three-row inset group, then the two entry points. No decorative viewfinder, no gradient
/// border, no separate privacy footer; the privacy promise lives in the group.
struct EmptyStateView: View {
    @ObservedObject var model: AppModel
    @Environment(\.contentMargin) private var margin
    @Environment(\.duoControlInset) private var controlInset
    @Environment(\.duoLayout) private var duoLayout
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride
    private var reduceMotion: Bool { systemReduceMotion || reduceMotionOverride }
    @State private var appeared = false
    @ScaledMetric(relativeTo: .title) private var coverTitleSize: CGFloat = 28
    @ScaledMetric(relativeTo: .largeTitle) private var innerTitleSize: CGFloat = 36
    @ScaledMetric(relativeTo: .largeTitle) private var padTitleSize: CGFloat = 44
    private var usesPadLayout: Bool {
        horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad
    }
    var body: some View {
        content
            .accessibilityIdentifier("home.root")
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 8)
            .onAppear {
                guard !reduceMotion else { appeared = true; return }
                withAnimation(Motion.entrance) { appeared = true }
            }
    }

    @ViewBuilder
    private var content: some View {
        if usesPadLayout {
            padBody
        } else {
            switch duoLayout {
            case .phone:
                standardBody
            case .cover:
                coverBody
            case .inner:
                innerBody
            }
        }
    }

    // MARK: - iPad

    /// iPad has room for both the promise and the picker at once: text on the left,
    /// a fixed-width picker card on the right, bounded so paragraphs never stretch.
    private var padBody: some View {
        GeometryReader { proxy in
            ScrollView {
            VStack(spacing: 0) {
                topBar
                    .frame(maxWidth: Layout.iPadHomeMaxWidth)
                    .padding(.top, Spacing.xs)


                HStack(alignment: .center, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: 0) {
                        BrandMark(size: 72)

                        Text("为原片添上\n纹理与颗粒")
                            .font(.system(size: padTitleSize, weight: .bold))
                            .foregroundStyle(Palette.textPrimary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Spacing.l)
                            .accessibilityAddTraits(.isHeader)

                        Text("只追加纹理与颗粒层，主图像素逐块校验不变。结果另存为一张新照片。")
                            .font(.system(size: 17))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, Spacing.s)

                        fullInfoGroup
                            .padding(.top, Spacing.xl)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    pickerZone
                        .frame(width: Layout.iPadPickerWidth, height: 420)
                }
                .frame(maxWidth: Layout.iPadHomeMaxWidth)
                .padding(.top, Spacing.xl)

                Spacer(minLength: Spacing.l)
            }
            .padding(.horizontal, Spacing.xl)
            .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: - Standard phone

    private var standardBody: some View {
        ScrollView {
            VStack(spacing: 0) {
                topBar
                    .padding(.top, Spacing.xs)
                    .padding(.trailing, controlInset)

                BrandMark(size: 64)
                    .padding(.top, Spacing.l)

                Text("为原片添上\n纹理与颗粒")
                    .font(Typography.hero)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.m)
                    .accessibilityAddTraits(.isHeader)

                Text("只追加纹理与颗粒层，主图像素逐块校验不变。结果另存为一张新照片。")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.xs)

                fullInfoGroup
                    .padding(.top, Spacing.l)

                actions
                    .padding(.top, Spacing.l)

                tutorialLink
                    .padding(.top, Spacing.xs)

                Text("最多 \(AppModel.maxSelection) 张 · HEIC / HEIF")
                    .font(Typography.micro)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.top, Spacing.s)
                    .padding(.bottom, Spacing.l)
            }
            .padding(.horizontal, margin)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var topBar: some View {
        HStack(spacing: Spacing.s) {
            QuotaBadge(quota: model.quota, isPro: model.isPro, compact: true) {
                model.presentPro()
            }
            .accessibilityIdentifier("home.quota")
            Spacer(minLength: 0)
            vaultButton
            settingsButton
        }
        .frame(minHeight: Layout.minimumTouchTarget)
    }

    private var settingsButton: some View {
        Button {
            model.presentSettings()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: Layout.minimumTouchTarget, height: Layout.minimumTouchTarget)
                .background(Palette.fillControl, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "settings.title", defaultValue: "设置"))
        .accessibilityIdentifier("home.settings")
    }
    private var vaultButton: some View {
        Button {
            model.activeModal = .vault
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: Layout.minimumTouchTarget, height: Layout.minimumTouchTarget)
                    .background(Palette.fillControl, in: Circle())
                if !model.vaultRecords.isEmpty {
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 8, height: 8)
                        .offset(x: -2, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "vault.title", defaultValue: "成果保险箱"))
        .accessibilityIdentifier("home.vault")
    }


    // MARK: - Duo cover (466 × 678)

    private var coverBody: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: Spacing.s) {
                    QuotaBadge(quota: model.quota, isPro: model.isPro, compact: true) {
                        model.presentPro()
                    }
                    .accessibilityIdentifier("home.quota")
                    Spacer(minLength: 0)
                }
                .frame(minHeight: Layout.minimumTouchTarget)

                HStack(alignment: .top, spacing: Spacing.s) {
                    BrandMark(size: 56)
                    Text("为原片添上\n纹理与颗粒")
                        .font(.system(size: coverTitleSize, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                }
                .padding(.top, Spacing.l)

                Text("只追加纹理与颗粒层，主图像素逐块校验不变。结果另存为一张新照片。")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.s)

                coverInfoGroup
                    .padding(.top, Spacing.l)

                HStack(spacing: Spacing.xs) {
                    PhotosPicker(selection: $model.pickerSelection,
                                 maxSelectionCount: AppModel.maxSelection,
                                 matching: .images,
                                 photoLibrary: .shared()) {
                        PrimaryActionLabel(title: String(localized: "选择照片"), systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(String(localized: "empty.pickerHint", defaultValue: "打开系统图库，最多选择 \(AppModel.maxSelection) 张 HEIC 原片"))
                    .accessibilityIdentifier("home.selectPhotos")

                    SecondaryActionButton(title: String(localized: "从「文件」导入"),
                                          systemImage: "folder",
                                          height: DuoMetrics.coverButtonHeight) {
                        model.isImportingFiles = true
                    }
                    .accessibilityIdentifier("home.importFiles")
                }
                .padding(.top, Spacing.l)

                tutorialLink
                    .padding(.top, Spacing.xs)

                Text("最多 \(AppModel.maxSelection) 张 · HEIC / HEIF")
                    .font(Typography.micro)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.top, Spacing.s)
                    .padding(.bottom, DuoMetrics.coverBottom)
            }
            .padding(.horizontal, DuoMetrics.coverMargin)
            .padding(.trailing, DuoMetrics.coverRailWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .overlay(alignment: .topTrailing) {
            DuoCoverRail {
                DuoRailButton(systemImage: "gearshape",
                              label: String(localized: "settings.title", defaultValue: "设置"),
                              identifier: "home.settings") {
                    model.presentSettings()
                }
            }
        }
    }

    // MARK: - Duo inner (951 × 669)

    private var innerBody: some View {
        DuoInnerSplit {
            VStack(alignment: .leading, spacing: 0) {
                BrandMark(size: 64)

                Text("为原片添上\n纹理与颗粒")
                    .font(.system(size: innerTitleSize, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.l)
                    .accessibilityAddTraits(.isHeader)

                Text("只追加纹理与颗粒层，主图像素逐块校验不变。结果另存为一张新照片。")
                    .font(.system(size: 17))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.s)

                fullInfoGroup
                    .padding(.top, Spacing.xl)

                Spacer(minLength: 0)
            }
            .padding(.leading, DuoMetrics.innerLeadingPadding)
            .padding(.trailing, DuoMetrics.innerTrailingPadding)
            .padding(.top, 28)
            .padding(.bottom, DuoMetrics.innerBottom)
        } trailing: {
            VStack(alignment: .leading, spacing: Spacing.m) {
                HStack(spacing: Spacing.s) {
                    QuotaBadge(quota: model.quota, isPro: model.isPro, compact: true) {
                        model.presentPro()
                    }
                    .accessibilityIdentifier("home.quota")
                    Spacer(minLength: 0)
                    vaultButton
                    settingsButton
                }
                .frame(minHeight: Layout.minimumTouchTarget)

                pickerZone
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.trailing, DuoMetrics.innerRightPadding)
            .padding(.top, 28)
            .padding(.bottom, DuoMetrics.innerBottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pickerZone: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.textSecondary)
                .accessibilityHidden(true)

            Text(String(localized: "选择要处理的原片"))
                .font(Typography.section)
                .foregroundStyle(Palette.textPrimary)

            Text("最多 \(AppModel.maxSelection) 张 · HEIC / HEIF")
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)

            VStack(spacing: Spacing.s) {
                PhotosPicker(selection: $model.pickerSelection,
                             maxSelectionCount: AppModel.maxSelection,
                             matching: .images,
                             photoLibrary: .shared()) {
                    PrimaryActionLabel(title: String(localized: "选择照片"), systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.plain)
                .accessibilityHint(String(localized: "empty.pickerHint", defaultValue: "打开系统图库，最多选择 \(AppModel.maxSelection) 张 HEIC 原片"))
                .accessibilityIdentifier("home.selectPhotos")

                SecondaryActionButton(title: String(localized: "从「文件」导入"), systemImage: "folder") {
                    model.isImportingFiles = true
                }
                .accessibilityIdentifier("home.importFiles")
            }
            .frame(maxWidth: DuoMetrics.innerPickerMaxWidth)
            .padding(.top, Spacing.xs)

            tutorialLink
                .padding(.top, Spacing.xxs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.l)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
        )
    }

    // MARK: - Shared pieces

    private var tutorialLink: some View {
        Button {
            model.presentTutorial()
        } label: {
            Label(String(localized: "教程", defaultValue: "使用教程"), systemImage: "book")
                .font(Typography.captionEmphasized)
                .foregroundStyle(Palette.accentText)
                .frame(minHeight: Layout.minimumTouchTarget)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.tutorial")
    }

    private var fullInfoGroup: some View {
        infoGroup {
            infoRow(symbol: "square.3.layers.3d",
                    title: String(localized: "原图始终保留"),
                    detail: String(localized: "不覆盖、不转码，新照片另存进相册"))
            divider
            infoRow(symbol: "checkmark.shield",
                    title: String(localized: "仅在本机处理"),
                    detail: String(localized: "照片不上传，处理全程离线"))
            divider
            infoRow(symbol: "photo",
                    title: String(localized: "HEIC 原片"),
                    detail: String(localized: "适用于 iPhone 16 / 17 系列拍摄的照片"))
        }
    }

    private var coverInfoGroup: some View {
        infoGroup {
            infoRow(symbol: "square.3.layers.3d",
                    title: String(localized: "原图始终保留"),
                    detail: String(localized: "不覆盖、不转码，新照片另存进相册"))
            divider
            infoRow(symbol: "checkmark.shield",
                    title: String(localized: "仅在本机处理"),
                    detail: String(localized: "照片不上传，处理全程离线"))
        }
    }

    private func infoGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func infoRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: symbol)
                .font(.system(.body, design: .default, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 24, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.bodyEmphasized)
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s - 1)
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(height: 0.5)
            .padding(.leading, 52)
    }

    private var actions: some View {
        VStack(spacing: Spacing.xs) {
            PhotosPicker(selection: $model.pickerSelection,
                         maxSelectionCount: AppModel.maxSelection,
                         matching: .images,
                         photoLibrary: .shared()) {
                PrimaryActionLabel(title: String(localized: "选择照片"), systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.plain)
            .accessibilityHint(String(localized: "empty.pickerHint", defaultValue: "打开系统图库，最多选择 \(AppModel.maxSelection) 张 HEIC 原片"))
            .accessibilityIdentifier("home.selectPhotos")

            SecondaryActionButton(title: String(localized: "从「文件」导入"), systemImage: "folder") {
                model.isImportingFiles = true
            }
            .accessibilityIdentifier("home.importFiles")
        }
    }
}
