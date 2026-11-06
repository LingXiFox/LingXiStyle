import SwiftUI

/// Filled primary action. Foreground flips with the scheme so both palettes clear 4.5:1.
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
        .accessibilityHint(isEnabled ? "" : "当前没有可解锁的照片")
    }
}

/// Shared between the real button and the PhotosPicker label.
struct PrimaryActionLabel: View {
    let title: String
    var systemImage: String?
    var isEnabled: Bool = true
    var isWorking: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if isWorking {
                ProgressView()
                    .tint(colorScheme == .dark ? .black : .white)
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
        .frame(maxWidth: .infinity, minHeight: Layout.minimumTouchTarget + 8)
        .foregroundStyle(colorScheme == .dark ? Color(light: 0x0B101A, dark: 0x0B101A) : .white)
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
                Text(title).font(Typography.bodyEmphasized)
            }
            .frame(maxWidth: .infinity, minHeight: Layout.minimumTouchTarget + 4)
            .foregroundStyle(Palette.textPrimary)
            .background(Palette.surfaceElevated,
                        in: RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
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
