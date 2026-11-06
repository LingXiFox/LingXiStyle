import SwiftUI

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

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.m) {
                PhotoHeroCard(image: current?.image,
                              isWorking: true,
                              isScanning: isScanning,
                              badge: .convertible,
                              selectionID: current?.id)
                    .frame(height: heroHeight)

                StageProgressView(stage: current?.stage,
                                  failed: current?.failedDuringStage ?? false,
                                  photoIndex: currentIndex,
                                  photoTotal: max(model.items.count, 1),
                                  photoName: current?.displayName ?? "")

                Text("一张一张处理。当前这张完成前，后面的照片不会开始。")
                    .font(Typography.micro)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, margin)
            .padding(.top, Spacing.m)
            .padding(.bottom, Spacing.l)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { cancelBar }
    }

    private var isScanning: Bool {
        guard let stage = current?.stage else { return false }
        return stage == .inspecting || stage == .verifying
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
