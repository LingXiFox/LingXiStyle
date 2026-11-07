import SwiftUI

/// Inline failure copy: same surface language as the rest of 1.5, with a status-colored icon
/// and textPrimary body. The action uses accentText, never accent as text.
struct InlineErrorNotice: View {
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(.body, design: .default, weight: .medium))
                .foregroundStyle(Palette.error)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(message)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(Typography.captionEmphasized)
                        .foregroundStyle(Palette.accentText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.m)
        .background(Palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.5)
        )
        .shadow(color: Palette.shadow, radius: 10, y: 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
