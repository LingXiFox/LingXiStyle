import SwiftUI
import LingXiKit

struct ConvertingView: View {
    @ObservedObject var model: AppModel
    @Environment(\.contentMargin) private var margin
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride
    private var reduceMotion: Bool { systemReduceMotion || reduceMotionOverride }

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

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.m) {
                header

                ZStack {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .fill(LinearGradient(colors: [Palette.accent.opacity(0.10), Palette.accentSecondary.opacity(0.06)],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .blur(radius: 24)
                        .padding(8)
                        .accessibilityHidden(true)

                    PhotoHeroCard(image: current?.image,
                                  isWorking: current?.stage == .readingOriginal,
                                  isScanning: false,
                                  badge: .convertible,
                                  selectionID: current?.id)
                        .overlay {
                            ConversionStageAura(stage: current?.stage, reduceMotion: reduceMotion)
                        }
                        .frame(height: heroHeight)
                }

                StageProgressView(stage: current?.stage,
                                  failed: current?.failedDuringStage ?? false,
                                  photoIndex: currentIndex,
                                  photoTotal: max(model.items.count, 1),
                                  photoName: current?.displayName ?? "")

                Label("照片内容保持原样，光效只发生在边框与背景上。",
                      systemImage: "lock.shield")
                    .font(Typography.micro)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Spacing.s)
            }
            .padding(.horizontal, margin)
            .padding(.top, Spacing.s)
            .padding(.bottom, Spacing.l)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom, spacing: 0) { cancelBar }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text("正在解锁第三代质感")
                    .font(Typography.section)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(current?.stage == .saving ? "正在写入相册，请稍候" : "照片始终保持清晰，不预览虚假效果")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer(minLength: 0)
            Text("\(completedCount) / \(model.items.count)")
                .font(Typography.captionEmphasized)
                .foregroundStyle(Palette.textSecondary)
                .monospacedDigit()
                .accessibilityLabel("已完成 \(completedCount) 张，共 \(model.items.count) 张")
        }
    }

    private var cancelBar: some View {
        VStack(spacing: Spacing.xs) {
            SecondaryActionButton(title: model.isCancelling ? "正在完成当前照片…" : "取消队列",
                                  systemImage: "xmark.circle") {
                model.cancelConversion()
            }
            .disabled(model.isCancelling)
            .opacity(model.isCancelling ? 0.6 : 1)

            Text("取消后不会再开始新照片；已经保存的新照片会保留。")
                .font(Typography.micro)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, Spacing.xs)
        }
        .padding(.top, Spacing.s)
        .padding(.horizontal, margin)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.hairline).frame(height: 0.5)
        }
    }
}
