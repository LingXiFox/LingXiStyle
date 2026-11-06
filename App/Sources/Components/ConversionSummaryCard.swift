import SwiftUI

/// Result summary. It reports counts and reasons; it never invents a success for a failure.
struct ConversionSummaryCard: View {
    let summary: ConversionSummary

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride
    private var reduceMotion: Bool { systemReduceMotion || reduceMotionOverride }
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.s) {
                Image(systemName: summary.isCompletelySuccessful ? "checkmark.seal.fill" : "exclamationmark.seal.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(summary.isCompletelySuccessful ? Palette.success : Palette.warning)
                    .scaleEffect(summary.isCompletelySuccessful && !appeared && !reduceMotion ? 0.85 : 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(summary.headline)
                        .font(Typography.section)
                        .foregroundStyle(Palette.textPrimary)
                    if summary.savedCount > 0 {
                        Text("原图没有被修改，新照片已存入系统相册。")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }

            HStack(spacing: Spacing.s) {
                countPill("成功", value: summary.savedCount, tint: Palette.success)
                if summary.skippedCount > 0 { countPill("跳过", value: summary.skippedCount, tint: Palette.textSecondary) }
                if summary.failedCount > 0 { countPill("失败", value: summary.failedCount, tint: Palette.error) }
                if summary.cancelledCount > 0 { countPill("取消", value: summary.cancelledCount, tint: Palette.warning) }
                Spacer(minLength: 0)
            }
        }
        .padding(Spacing.l)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .shadow(color: Palette.shadow, radius: 16, y: 6)
        .offset(y: appeared || reduceMotion ? 0 : 10)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .onAppear {
            guard !reduceMotion else { appeared = true; return }
            withAnimation(Motion.result) { appeared = true }
        }
    }

    private func countPill(_ title: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(title).font(Typography.caption).foregroundStyle(Palette.textSecondary)
            Text("\(value)").font(Typography.numeric).foregroundStyle(Palette.textPrimary)
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, 7)
        .background(Palette.surfaceElevated, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value) 张")
    }
}
