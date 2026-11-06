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

                privacyLine
                    .padding(.top, Spacing.s)
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
            Text("LingXiStyle")
                .font(Typography.brand)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("为你的原片补上第三代摄影风格")
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
            Text("HEIC 原片 · 仅追加 Texture / Grain")
                .font(Typography.micro)
                .foregroundStyle(Palette.accentText)
                .padding(.horizontal, Spacing.s)
                .padding(.vertical, 6)
                .background(Palette.accent.opacity(0.12), in: Capsule())
                .padding(.top, Spacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compositionFrame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.surface)

            ThirdsGrid()
                .stroke(Palette.textSecondary.opacity(0.10), lineWidth: 0.5)
                .padding(1)

            CornerBrackets()
                .stroke(Palette.accent.opacity(0.55), lineWidth: 1.5)
                .padding(14)

            VStack(spacing: Spacing.s) {
                Image(systemName: "camera.filters")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Palette.accent)
                Text("选择一张 HEIC 原片")
                    .font(Typography.status)
                    .foregroundStyle(Palette.textPrimary)
                Text("HDR、景深、风格元数据全部保留")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Spacing.l)

            VStack {
                Spacer()
                HStack {
                    Text("16 · 17 系列风格")
                        .font(Typography.micro)
                        .foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: 0)
                    Text("4:5")
                        .font(Typography.micro)
                        .foregroundStyle(Palette.textSecondary.opacity(0.7))
                }
                .padding(Spacing.m)
            }
        }
        .aspectRatio(Layout.heroAspect, contentMode: .fit)
        .frame(maxHeight: 420)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
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
        Label("仅在本机处理 · 原图始终保留", systemImage: "lock.shield")
            .font(Typography.caption)
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity)
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
