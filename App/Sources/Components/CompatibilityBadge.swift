import SwiftUI

/// Compatibility state on a neutral material capsule. Only the icon carries status color;
/// the label stays textPrimary so it cannot rely on color alone.
struct CompatibilityBadge: View {
    enum Kind: Equatable {
        case convertible
        case noChange
        case unsupported
        case downloading
        case failed

        var title: String {
            switch self {
            case .convertible: return String(localized: "可添加")
            case .noChange: return String(localized: "无需处理")
            case .unsupported: return String(localized: "暂不支持")
            case .downloading: return String(localized: "下载原件")
            case .failed: return String(localized: "读取失败")
            }
        }

        var symbol: String {
            switch self {
            case .convertible: return "checkmark"
            case .noChange: return "checkmark.circle"
            case .unsupported: return "exclamationmark.triangle"
            case .downloading: return "icloud.and.arrow.down"
            case .failed: return "xmark.octagon"
            }
        }

        var tint: Color {
            switch self {
            case .convertible: return Palette.success
            case .noChange: return Palette.textSecondary
            case .unsupported: return Palette.warning
            case .downloading: return Palette.running
            case .failed: return Palette.error
            }
        }
    }

    let kind: Kind
    var showsSymbol: Bool = true

    var body: some View {
        HStack(spacing: Spacing.xxs + 2) {
            if showsSymbol {
                Image(systemName: kind.symbol)
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(kind.tint)
            }
            Text(kind.title)
                .font(Typography.captionEmphasized)
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(.horizontal, Spacing.s - 2)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.title)
    }
}
