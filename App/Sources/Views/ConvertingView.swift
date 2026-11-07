import SwiftUI
import LingXiKit

/// 1.5 processing page: real stage callbacks, a deterministic 4pt bar, one untouched photo,
/// and a 44pt stage group. Nothing loops, pulses, or invents progress.
struct ConvertingView: View {
    @ObservedObject var model: AppModel
    @Environment(\.contentMargin) private var margin
    @Environment(\.verticalSizeClass) private var verticalSizeClass

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
        ScrollView {
            VStack(spacing: Spacing.l) {
                header

                PhotoHeroCard(image: current?.image,
                              badge: nil,
                              selectionID: current?.id,
                              statusText: String(localized: "progress.photoCounter", defaultValue: "第 \(currentIndex) / \(total) 张"),
                              showsRunningDot: true)
                    .frame(height: heroHeight)

                StageProgressView(stage: current?.stage,
                                  failed: current?.failedDuringStage ?? false)

                Text("取消后不会再开始新照片；已经保存的新照片会保留。")
                    .font(Typography.micro)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, margin)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.l)
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
                Text("已完成 \(completedCount) / \(model.items.count)")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
                    .accessibilityLabel(String(localized: "converting.completedAccessibility", defaultValue: "已完成 \(completedCount) 张，共 \(model.items.count) 张"))
            }

            ProgressView(value: Double(completedCount), total: Double(total))
                .progressViewStyle(.linear)
                .tint(Palette.accent)
                .frame(height: 4)
                .accessibilityLabel(String(localized: "已完成 \(completedCount) / \(model.items.count)"))
        }
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
}
