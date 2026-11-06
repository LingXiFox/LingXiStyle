import SwiftUI

struct InlineErrorNotice: View {
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.error)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
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
        .padding(Spacing.s)
        .background(Palette.error.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                .strokeBorder(Palette.error.opacity(0.24), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
