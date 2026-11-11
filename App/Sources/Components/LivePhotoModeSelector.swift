import SwiftUI
import LingXiKit

/// One radio group for the two Live Photo modes. It is used by the selection screen (temporary
/// switch for the current batch), Settings (saved default) and the tutorial (first-run choice).
/// The quota line is part of the component on purpose: both modes cost exactly one slot.
struct LivePhotoModeSelector: View {
    var selection: LivePhotoProcessingMode
    var onSelect: (LivePhotoProcessingMode) -> Void
    var showsQuotaNote: Bool = true
    /// Explains the scope of the choice, e.g. "only affects this batch" on the selection screen.
    var scopeNote: String?
    /// The tutorial shows the choice without the long explanation under each row.
    var showsDetails: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(LivePhotoProcessingMode.allCases.enumerated()), id: \.element) { index, mode in
                row(mode)
                if index < LivePhotoProcessingMode.allCases.count - 1 {
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 0.5)
                        .padding(.leading, 52)
                }
            }

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 0.5)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.info)
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                    Text(LivePhotoProcessingMode.quotaNote)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                if let scopeNote {
                    Text(scopeNote)
                        .font(Typography.micro)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 18 + Spacing.xs)
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "settings.livePhoto.section", defaultValue: "实况照片处理方式"))
    }

    private func row(_ mode: LivePhotoProcessingMode) -> some View {
        let isSelected = selection == mode
        return Button {
            onSelect(mode)
        } label: {
            HStack(alignment: .top, spacing: Spacing.s) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(isSelected ? Palette.accentText : Palette.textTertiary)
                    .frame(width: 24, height: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(Typography.bodyEmphasized)
                        .foregroundStyle(Palette.textPrimary)
                    if showsDetails {
                        Text(mode.detail)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .frame(minHeight: Layout.minimumTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("livePhoto.mode.\(mode.rawValue)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "livePhoto.mode.accessibility",
                                       defaultValue: "\(mode.title)：\(showsDetails ? mode.detail : mode.shortDetail)"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#if DEBUG
#Preview("实况模式 · 浅色") {
    LivePhotoModeSelector(selection: .stillOnly, onSelect: { _ in })
        .padding()
        .background(Palette.background)
        .preferredColorScheme(.light)
}
#endif
