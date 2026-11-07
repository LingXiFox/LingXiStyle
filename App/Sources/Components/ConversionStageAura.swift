import SwiftUI
import LingXiKit

/// Decorative light that follows the real pipeline stage. It lives strictly on the card edge:
/// the photo below is never tinted, blurred, scaled, or replaced.
struct ConversionStageAura: View {
    let stage: ConversionStage?
    let reduceMotion: Bool

    @State private var angle: Double = 0
    @State private var scanProgress: CGFloat = 0
    @State private var showScan = false
    @State private var savingCollapsed = false

    var body: some View {
        ZStack {
            if reduceMotion, let stage, stage != .finished {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Palette.accent.opacity(0.32), lineWidth: 1.5)
            }

            if stage == .converting, !reduceMotion {
                AngularGradient(colors: [Palette.accent,
                                         Palette.accentSecondary,
                                         Palette.accent],
                                center: .center)
                    .rotationEffect(.degrees(angle))
                    .mask {
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .strokeBorder(lineWidth: 2.5)
                    }
                    .shadow(color: Palette.accent.opacity(0.35), radius: 8)
            }

            if showScan {
                GeometryReader { proxy in
                    LinearGradient(colors: [.clear, Palette.accent.opacity(0.95), .clear],
                                   startPoint: .leading,
                                   endPoint: .trailing)
                        .frame(height: 1.5)
                        .offset(y: scanProgress * max(proxy.size.height - 1.5, 0))
                        .mask {
                            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                .stroke(lineWidth: 2)
                        }
                }
            }

            if stage == .saving, !reduceMotion {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Palette.accent, Palette.accentSecondary],
                                                 startPoint: .topLeading,
                                                 endPoint: .bottomTrailing),
                                  lineWidth: 2)
                    .scaleEffect(savingCollapsed ? 0.992 : 1.012)
                    .opacity(savingCollapsed ? 0 : 0.7)
            }

            if stage == .finished {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Palette.success.opacity(0.65), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: stage) { await animate(for: stage) }
    }

    private func animate(for stage: ConversionStage?) async {
        angle = 0
        scanProgress = 0
        showScan = false
        savingCollapsed = false

        guard !reduceMotion, let stage else { return }

        switch stage {
        case .inspecting, .verifying:
            // One measured pass along the frame, matching the structural check.
            showScan = true
            do {
                try await Task.sleep(nanoseconds: 30_000_000)
            } catch {
                return
            }
            withAnimation(.linear(duration: 0.68)) { scanProgress = 1 }
            do {
                try await Task.sleep(nanoseconds: 720_000_000)
            } catch {
                return
            }
            withAnimation(.easeOut(duration: 0.16)) { showScan = false }

        case .converting:
            // A slow ice-blue → lavender sweep, edge only.
            do {
                try await Task.sleep(nanoseconds: 30_000_000)
            } catch {
                return
            }
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                angle = 360
            }

        case .saving:
            withAnimation(.easeOut(duration: 0.9)) { savingCollapsed = true }

        default:
            break
        }
    }
}
