import SwiftUI
import PhotosUI
import LingXiKit

/// 1.5 home: quota capsule and settings in the top bar, centered brand mark and promise,
/// a three-row inset group, then the two entry points. No decorative viewfinder, no gradient
/// border, no separate privacy footer; the privacy promise lives in the group.
struct EmptyStateView: View {
    @ObservedObject var model: AppModel
    @Environment(\.contentMargin) private var margin
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride
    private var reduceMotion: Bool { systemReduceMotion || reduceMotionOverride }
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                topBar
                    .padding(.top, Spacing.xs)

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

                infoGroup
                    .padding(.top, Spacing.l)

                actions
                    .padding(.top, Spacing.l)

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
        .opacity(appeared || reduceMotion ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 8)
        .onAppear {
            guard !reduceMotion else { appeared = true; return }
            withAnimation(Motion.entrance) { appeared = true }
        }
    }

    private var topBar: some View {
        HStack(spacing: Spacing.s) {
            QuotaBadge(quota: model.quota, isPro: model.isPro, compact: true) {
                model.presentPro()
            }
            Spacer(minLength: 0)
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
        }
        .frame(minHeight: Layout.minimumTouchTarget)
    }

    private var infoGroup: some View {
        VStack(spacing: 0) {
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

            SecondaryActionButton(title: String(localized: "从「文件」导入"), systemImage: "folder") {
                model.isImportingFiles = true
            }
        }
    }
}
