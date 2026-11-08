import SwiftUI

/// The single filled primary action on a screen. Fox orange always carries brand ink, never white.
struct PrimaryActionButton: View {
    let title: String
    var systemImage: String?
    var isEnabled: Bool = true
    var isWorking: Bool = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            PrimaryActionLabel(title: title,
                               systemImage: systemImage,
                               isEnabled: isEnabled,
                               isWorking: isWorking)
        }
        .buttonStyle(PressableButtonStyle(reduceMotion: reduceMotion))
        .disabled(!isEnabled || isWorking)
        .accessibilityHint(isEnabled ? "" : String(localized: "当前没有可处理的照片"))
    }
}

/// Shared between the real button and the PhotosPicker label.
struct PrimaryActionLabel: View {
    let title: String
    var systemImage: String?
    var isEnabled: Bool = true
    var isWorking: Bool = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if isWorking {
                ProgressView()
                    .tint(Palette.onAccent)
                    .controlSize(.small)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(.headline, design: .default, weight: .semibold))
            }
            Text(title)
                .font(Typography.status)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: Layout.primaryButtonHeight)
        .foregroundStyle(Palette.onAccent)
        .background(Palette.accent.opacity(isEnabled ? 1 : 0.45),
                    in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
    }
}

struct SecondaryActionButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(.body, design: .default, weight: .medium))
                }
                Text(LocalizedStringKey(title)).font(Typography.bodyEmphasized)
            }
            .frame(maxWidth: .infinity, minHeight: Layout.secondaryButtonHeight)
            .foregroundStyle(Palette.textPrimary)
            .background(Palette.fillControl,
                        in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct PressableButtonStyle: ButtonStyle {
    var reduceMotion: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.98 : 1))
            .animation(reduceMotion ? nil : Motion.selection, value: configuration.isPressed)
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}
