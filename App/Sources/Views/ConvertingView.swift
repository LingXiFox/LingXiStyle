import SwiftUI
import LingXiKit

/// 1.5 processing page: real stage callbacks, a deterministic 4pt bar, one untouched photo,
/// and a 44pt stage group. Nothing loops, pulses, or invents progress.
struct ConvertingView: View {
    @ObservedObject var model: AppModel
    @Environment(\.contentMargin) private var margin
    @Environment(\.duoControlInset) private var controlInset
    @Environment(\.duoLayout) private var duoLayout
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ScaledMetric(relativeTo: .title2) private var innerHeaderSize: CGFloat = 28

    private var heroHeight: CGFloat { verticalSizeClass == .compact ? 180 : 300 }

    private var current: PhotoItem? {
        model.items.first { $0.stage != nil && $0.outcome == nil }
            ?? model.items.first { $0.isConvertible && $0.outcome == nil }
    }

    private var currentIndex: Int {
        guard let current, let index = model.items.firstIndex(where: { $0.id == current.id }) else { return 0 }
        return index + 1
    }

    private var completedCount: Int {
        model.items.filter { $0.outcome != nil }.count
    }

    private var total: Int { max(model.items.count, 1) }

    var body: some View {
        switch duoLayout {
        case .phone:
            standardBody
        case .cover:
            coverBody
        case .inner:
            innerBody
        }
    }

    // MARK: - Standard phone

    private var standardBody: some View {
        ScrollView {
            VStack(spacing: Spacing.l) {
                header
                    .padding(.trailing, controlInset)

                hero
                    .frame(height: heroHeight)

                stageList(rowHeight: 44)

                footnote
            }
            .padding(.horizontal, margin)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.l)
            .frame(maxWidth: Layout.iPadContentMaxWidth + 48)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) { cancelBar }
    }

    private var header: some View {
        VStack(spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text("正在处理")
                    .font(Typography.section)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                completedLabel
            }

            progressBar
        }
    }

    private var completedLabel: some View {
        Text("已完成 \(completedCount) / \(model.items.count)")
            .font(Typography.caption)
            .foregroundStyle(Palette.textSecondary)
            .monospacedDigit()
            .accessibilityLabel(String(localized: "converting.completedAccessibility", defaultValue: "已完成 \(completedCount) 张，共 \(model.items.count) 张"))
    }

    private var progressBar: some View {
        ProgressView(value: Double(completedCount), total: Double(total))
            .progressViewStyle(.linear)
            .tint(Palette.accent)
            .frame(height: 4)
            .accessibilityLabel(String(localized: "已完成 \(completedCount) / \(model.items.count)"))
    }

    private var hero: some View {
        PhotoHeroCard(image: current?.image,
                      badge: nil,
                      selectionID: current?.id,
                      statusText: String(localized: "progress.photoCounter", defaultValue: "第 \(currentIndex) / \(total) 张"),
                      showsRunningDot: true)
    }

    private func stageList(rowHeight: CGFloat) -> some View {
        StageProgressView(stage: current?.stage,
                          livePhotoMode: current?.hasLivePhotoVideo == true ? model.effectiveLivePhotoMode : nil,
                          failed: current?.failedDuringStage ?? false,
                          rowHeight: rowHeight)
    }

    private var footnote: some View {
        Text("取消后不会再开始新照片；已经保存的新照片会保留。")
            .font(Typography.micro)
            .foregroundStyle(Palette.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var cancelBar: some View {
        VStack(spacing: Spacing.xs) {
            SecondaryActionButton(title: model.isCancelling ? "正在完成当前照片…" : "取消",
                                  systemImage: model.isCancelling ? nil : "xmark") {
                model.cancelConversion()
            }
            .disabled(model.isCancelling)
            .opacity(model.isCancelling ? 0.6 : 1)
        }
        .padding(.top, Spacing.s)
        .padding(.horizontal, margin)
        .padding(.bottom, Spacing.xs)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.hairline).frame(height: 0.5)
        }
    }

    // MARK: - Duo cover (466 × 678)

    private var coverBody: some View {
        ScrollView {
            VStack(spacing: Spacing.m) {
                header

                hero
                    .frame(height: DuoMetrics.coverConvertingPreviewHeight)

                stageList(rowHeight: 40)
            }
            .padding(.horizontal, DuoMetrics.coverMargin)
            .padding(.top, Spacing.xs)
            .padding(.bottom, DuoMetrics.coverBottom)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) { coverCancelBar }
    }

    private var coverCancelBar: some View {
        HStack(alignment: .center, spacing: Spacing.s) {
            Text("取消后不会再开始新照片；已经保存的新照片会保留。")
                .font(Typography.micro)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            SecondaryActionButton(title: model.isCancelling ? "正在完成…" : "取消",
                                  systemImage: model.isCancelling ? nil : "xmark",
                                  height: 48) {
                model.cancelConversion()
            }
            .frame(width: 104)
            .disabled(model.isCancelling)
            .opacity(model.isCancelling ? 0.6 : 1)
        }
        .padding(.horizontal, DuoMetrics.coverMargin)
        .padding(.top, Spacing.s)
        .padding(.bottom, Spacing.s)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.hairline).frame(height: 0.5)
        }
    }

    // MARK: - Duo inner (951 × 669)

    private var innerBody: some View {
        DuoInnerSplit {
            VStack(alignment: .leading, spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                        Text("正在处理")
                            .font(.system(size: innerHeaderSize, weight: .bold))
                            .foregroundStyle(Palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 0)
                        completedLabel
                    }
                    progressBar
                }

                hero
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.leading, DuoMetrics.innerLeadingPadding)
            .padding(.trailing, DuoMetrics.innerTrailingPadding)
            .padding(.top, 28)
            .padding(.bottom, DuoMetrics.innerBottom)
        } trailing: {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("这张照片的处理步骤")
                    .font(Typography.bodyEmphasized)
                    .foregroundStyle(Palette.textSecondary)

                stageList(rowHeight: 48)

                Spacer(minLength: 0)

                footnote

                SecondaryActionButton(title: model.isCancelling ? "正在完成当前照片…" : "取消",
                                      systemImage: model.isCancelling ? nil : "xmark") {
                    model.cancelConversion()
                }
                .disabled(model.isCancelling)
                .opacity(model.isCancelling ? 0.6 : 1)
            }
            .padding(.trailing, DuoMetrics.innerRightPadding)
            .padding(.top, 28)
            .padding(.bottom, DuoMetrics.innerBottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
