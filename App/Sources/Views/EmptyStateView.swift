import SwiftUI
import PhotosUI

struct EmptyStateView: View {
    @ObservedObject var model: AppModel
    @Environment(\.contentMargin) private var margin
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride
    private var reduceMotion: Bool { systemReduceMotion || reduceMotionOverride }
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.top, Spacing.xl)

                compositionFrame
                    .padding(.top, Spacing.xl)

                Spacer(minLength: Spacing.xl)

                actions
                    .padding(.top, Spacing.l)

                QuotaBadge(quota: model.quota, isPro: model.isPro) {
                    model.presentPro()
                }
                .padding(.top, Spacing.m)

                privacyLine
                    .padding(.top, Spacing.m)
                    .padding(.bottom, Spacing.l)
            }
            .padding(.horizontal, margin)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 8)
        .onAppear {
            guard !reduceMotion else { appeared = true; return }
            withAnimation(Motion.entrance) { appeared = true }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: 7) {
                Circle()
                    .fill(LinearGradient(colors: [Palette.accent, Palette.accentSecondary],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .frame(width: 7, height: 7)
                Text("LINGXI STYLE")
                    .font(.system(.caption2, design: .default, weight: .semibold))
                    .tracking(2.4)
                    .foregroundStyle(Palette.accentText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("LingXiStyle")

            Text("为原片补上\n第三代摄影质感")
                .font(.system(.largeTitle, design: .default, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("照片本身保持清晰，只追加纹理与颗粒。HDR、景深和原始信息都留在原片里。")
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Spacing.xs) {
                miniBadge("HEIC 原片", systemImage: "photo")
                miniBadge("仅补质感", systemImage: "sparkles")
            }
            .padding(.top, Spacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func miniBadge(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(Typography.micro)
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 5)
            .background(Palette.surface.opacity(0.7), in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
    }

    private var compositionFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(LinearGradient(colors: [Palette.surface, Palette.surfaceElevated.opacity(0.75)],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))

            // A soft aperture glow sits behind the framing marks, never on top of a photo.
            Circle()
                .fill(RadialGradient(colors: [Palette.accent.opacity(0.20), Palette.accentSecondary.opacity(0.05), .clear],
                                     center: .center,
                                     startRadius: 4,
                                     endRadius: 180))
                .frame(width: 300, height: 300)
                .blur(radius: 10)
                .accessibilityHidden(true)

            ThirdsGrid()
                .stroke(Palette.textSecondary.opacity(0.12), lineWidth: 0.5)
                .padding(1)

            CornerBrackets()
                .stroke(LinearGradient(colors: [Palette.accent.opacity(0.8), Palette.accentSecondary.opacity(0.55)],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing),
                        lineWidth: 1.5)
                .padding(14)

            VStack(spacing: Spacing.s) {
                ZStack {
                    Circle()
                        .fill(Palette.surfaceElevated)
                        .frame(width: 78, height: 78)
                    Circle()
                        .strokeBorder(Palette.accent.opacity(0.24), lineWidth: 1)
                        .frame(width: 78, height: 78)
                    Image(systemName: "camera.filters")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Palette.accent)
                }
                .shadow(color: Palette.accent.opacity(0.18), radius: 18)
                Text("一张原片，一层质感")
                    .font(Typography.status)
                    .foregroundStyle(Palette.textPrimary)
                Text("保留原始光影，只让质感更接近第三代风格")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.l)

        }
        .frame(maxHeight: 300)
        .aspectRatio(Layout.heroAspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Palette.accent.opacity(0.24), Palette.hairline, Palette.accentSecondary.opacity(0.18)],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing),
                              lineWidth: 1)
        )
        .shadow(color: Palette.shadow, radius: 22, y: 10)
        .accessibilityHidden(true)
    }

    private var actions: some View {
        VStack(spacing: Spacing.s) {
            PhotosPicker(selection: $model.pickerSelection,
                         maxSelectionCount: AppModel.maxSelection,
                         matching: .images,
                         photoLibrary: .shared()) {
                PrimaryActionLabel(title: "选择照片", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开系统图库，最多选择 \(AppModel.maxSelection) 张 HEIC 原片")

            SecondaryActionButton(title: "从文件导入", systemImage: "folder") {
                model.isImportingFiles = true
            }
        }
    }

    private var privacyLine: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "lock.shield")
                .font(.system(.caption, design: .default, weight: .medium))
            Text("仅在本机处理")
            Text("·").foregroundStyle(Palette.textSecondary.opacity(0.5))
            Text("原图始终保留")
        }
        .font(Typography.caption)
        .foregroundStyle(Palette.textSecondary)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("仅在本机处理，原图始终保留")
    }
}

/// Decorative rule-of-thirds grid. Kept faint so it never competes with the copy.
struct ThirdsGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 1...2 {
            let x = rect.minX + rect.width * CGFloat(index) / 3
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            let y = rect.minY + rect.height * CGFloat(index) / 3
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

/// Four corner brackets, drawn as a single stroke so it scales with the card.
struct CornerBrackets: Shape {
    var arm: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 1, 1),
            (CGPoint(x: rect.maxX, y: rect.minY), -1, 1),
            (CGPoint(x: rect.minX, y: rect.maxY), 1, -1),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1)
        ]
        for (point, dx, dy) in corners {
            path.move(to: CGPoint(x: point.x, y: point.y + arm * dy))
            path.addLine(to: point)
            path.addLine(to: CGPoint(x: point.x + arm * dx, y: point.y))
        }
        return path
    }
}
