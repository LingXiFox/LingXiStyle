import SwiftUI
import LingXiKit

/// Shows the real pipeline, step by step. No percentages, no invented time estimates: the
/// current step is fed by the engine's stage callbacks. 1.5 uses a 44pt inset group.
struct StageProgressView: View {
    let stage: ConversionStage?
    var failed: Bool = false

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride
    private var reduceMotion: Bool { systemReduceMotion || reduceMotionOverride }

    private var pipeline: [ConversionStage] { ConversionStage.pipeline }
    private var currentIndex: Int? {
        guard let stage else { return nil }
        if stage == .finished { return pipeline.count }
        return pipeline.firstIndex(of: stage)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(pipeline.enumerated()), id: \.element) { index, step in
                row(for: step, index: index)
                if index < pipeline.count - 1 {
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 0.5)
                        .padding(.leading, 44)
                }
            }
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func row(for step: ConversionStage, index: Int) -> some View {
        let done = (currentIndex ?? -1) > index || stage == .finished
        let isCurrent = currentIndex == index && !failed
        let isFailedHere = failed && currentIndex == index
        let suffix = done
            ? String(localized: "stage.done", defaultValue: "，已完成")
            : isFailedHere
                ? String(localized: "stage.failed", defaultValue: "，失败")
                : isCurrent ? String(localized: "stage.current", defaultValue: "，进行中") : ""

        HStack(spacing: Spacing.s) {
            Group {
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Palette.success)
                } else if isFailedHere {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Palette.error)
                } else if isCurrent {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Palette.running)
                } else {
                    Circle()
                        .strokeBorder(Palette.textTertiary.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                }
            }
            .frame(width: 24, height: 20)

            Text(step.title)
                .font(isCurrent ? Typography.bodyEmphasized : Typography.body)
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, Spacing.m)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "progress.stageAccessibility", defaultValue: "\(step.title)\(suffix)"))
    }
}
