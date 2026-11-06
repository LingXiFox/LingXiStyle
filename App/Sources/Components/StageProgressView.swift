import SwiftUI
import LingXiKit

/// Shows the real pipeline, step by step. No percentages, no invented time estimates: the
/// current step is fed by the engine's stage callbacks.
struct StageProgressView: View {
    let stage: ConversionStage?
    var failed: Bool = false
    let photoIndex: Int
    let photoTotal: Int
    let photoName: String

    private var pipeline: [ConversionStage] { ConversionStage.pipeline }
    private var currentIndex: Int? {
        guard let stage else { return nil }
        if stage == .finished { return pipeline.count }
        return pipeline.firstIndex(of: stage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(statusText)
                    .font(Typography.status)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: Spacing.s)
                Text("第 \(photoIndex) / \(photoTotal) 张")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: Spacing.xs + 2) {
                ForEach(Array(pipeline.enumerated()), id: \.element) { index, step in
                    row(for: step, index: index)
                }
            }

            Text(photoName)
                .font(Typography.micro)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(Spacing.m)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        if failed { return "这一步没有完成" }
        guard let stage else { return "准备中" }
        if stage == .finished { return "已保存新照片" }
        return "正在\(stage.title)"
    }

    @ViewBuilder
    private func row(for step: ConversionStage, index: Int) -> some View {
        let done = (currentIndex ?? -1) > index || stage == .finished
        let isCurrent = currentIndex == index && !failed
        let isFailedHere = failed && currentIndex == index

        HStack(spacing: Spacing.s) {
            ZStack {
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.success)
                } else if isFailedHere {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Palette.error)
                } else if isCurrent {
                    Circle().fill(Palette.accent).frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Palette.accent.opacity(0.35), lineWidth: 5))
                } else {
                    Circle().strokeBorder(Palette.textSecondary.opacity(0.45), lineWidth: 1.5)
                        .frame(width: 8, height: 8)
                }
            }
            .frame(width: 20, height: 20)
            .animation(Motion.stageChange, value: done)
            .animation(Motion.stageChange, value: isCurrent)

            Text(step.title)
                .font(isCurrent ? Typography.bodyEmphasized : Typography.caption)
                .foregroundStyle(isCurrent ? Palette.textPrimary : Palette.textSecondary)
            Spacer(minLength: 0)
        }
        .accessibilityLabel("\(step.title)\(done ? "，已完成" : isFailedHere ? "，失败" : isCurrent ? "，进行中" : "")")
    }
}
