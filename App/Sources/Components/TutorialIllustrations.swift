import SwiftUI

/// Large, quiet illustrations for the step-by-step tutorial. Each artboard is laid out on a
/// fixed 360 x 220 canvas and scaled down to the available width, so the composition stays
/// intact on Duo's outer display and in larger Dynamic Type layouts.
struct TutorialIllustration: View {
    let kind: TutorialStepKind

    var body: some View {
        GeometryReader { proxy in
            let scale = min(1, min(proxy.size.width / 360, proxy.size.height / 220))
            ZStack {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Palette.surfaceElevated)
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 0.5)

                art
                    .frame(width: 360, height: 220)
                    .scaleEffect(scale)
                    .frame(width: 360 * scale, height: 220 * scale)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var art: some View {
        switch kind {
        case .layers:
            LayersArt()
        case .styles:
            StylesArt()
        case .compatibility:
            CompatibilityArt()
        case .pick:
            PickerArt()
        case .livePhoto:
            LivePhotoArt()
        case .result:
            ResultArt()
        case .edit:
            EditArt()
        case .invisible:
            InvisibleArt()
        case .quota:
            QuotaArt()
        }
    }
}

// MARK: - Shared art pieces

private struct MiniPhoto: View {
    var corner: CGFloat = 12

    var body: some View {
        ZStack {
            LinearGradient(colors: [Palette.running.opacity(0.78), Palette.accent.opacity(0.68)],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
            Circle()
                .fill(.white.opacity(0.72))
                .frame(width: 20, height: 20)
                .offset(x: 26, y: -38)
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(.white.opacity(0.82))
                .offset(y: 20)
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

private struct GrainField: View {
    var opacity: Double = 0.28

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            for index in 0..<90 {
                let x = CGFloat((index * 47) % 101) / 100 * size.width
                let y = CGFloat((index * 73) % 97) / 96 * size.height
                let diameter = CGFloat(0.8 + Double((index * 11) % 9) / 8)
                let rect = CGRect(x: x, y: y, width: diameter, height: diameter)
                context.fill(Path(ellipseIn: rect),
                             with: .color(Palette.textPrimary.opacity(opacity)))
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ArtBadge: View {
    let symbol: String
    var tint: Color = Palette.onAccent
    var fill: Color = Palette.accent
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(fill, in: Circle())
    }
}

private struct ArtPill: View {
    let text: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
                .font(Typography.micro)
        }
        .foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Palette.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 0.5))
    }
}

// MARK: - 1. One layer, original untouched

private struct LayersArt: View {
    var body: some View {
        ZStack {
            MiniPhoto(corner: 14)
                .frame(width: 120, height: 150)
                .overlay(alignment: .bottomTrailing) {
                    ArtBadge(symbol: "lock.fill", size: 26)
                        .padding(7)
                }
                .rotationEffect(.degrees(-7))
                .shadow(color: Palette.shadow, radius: 8, x: 0, y: 5)
                .position(x: 105, y: 108)

            ZStack {
                MiniPhoto(corner: 14)
                GrainField(opacity: 0.24)
            }
            .frame(width: 120, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topTrailing) {
                ArtBadge(symbol: "plus", size: 26)
                    .padding(7)
            }
            .rotationEffect(.degrees(6))
            .shadow(color: Palette.shadow, radius: 8, x: 0, y: 5)
            .position(x: 255, y: 112)

            Image(systemName: "arrow.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Palette.accentText)
                .position(x: 180, y: 54)
        }
    }
}

// MARK: - 2. Photographic Styles, texture and grain

private struct StylesArt: View {
    private let swatches: [Color] = [Palette.thinking, Palette.running, Palette.accent]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 0.5)
                }
                .frame(width: 280, height: 158)
                .position(x: 180, y: 112)

            VStack(spacing: 14) {
                HStack(spacing: 22) {
                    ForEach(swatches.indices, id: \.self) { index in
                        ZStack {
                            Circle()
                                .fill(swatches[index])
                                .frame(width: 34, height: 34)
                            if index == 1 {
                                Circle()
                                    .strokeBorder(Palette.textPrimary, lineWidth: 2)
                                    .frame(width: 42, height: 42)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Palette.brandMilk)
                            }
                        }
                        .frame(width: 44, height: 44)
                    }
                }

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Palette.fillControl)
                        .frame(width: 210, height: 8)
                    Capsule()
                        .fill(Palette.accent)
                        .frame(width: 138, height: 8)
                    Circle()
                        .fill(Palette.surfaceElevated)
                        .overlay(Circle().strokeBorder(Palette.accent, lineWidth: 2))
                        .frame(width: 22, height: 22)
                        .offset(x: 127)
                }
                .frame(width: 210, height: 22)

                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.fillControl)
                    GrainField(opacity: 0.35)
                }
                .frame(width: 210, height: 22)
            }
            .position(x: 180, y: 112)

            ArtBadge(symbol: "camera.filters", size: 30)
                .position(x: 52, y: 52)
        }
    }
}

// MARK: - 3. Compatibility

private struct CompatibilityArt: View {
    var body: some View {
        ZStack {
            card(symbol: "photo", label: "HEIC", ok: true)
                .position(x: 72, y: 112)
            card(symbol: "livephoto", label: "LIVE", ok: true)
                .position(x: 180, y: 112)
            card(symbol: "doc", label: "RAW", ok: false)
                .position(x: 288, y: 112)
        }
    }

    private func card(symbol: String, label: String, ok: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(ok ? Palette.textPrimary : Palette.textTertiary)
            Text(label)
                .font(Typography.micro)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(width: 86, height: 112)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(ok ? Palette.hairline : Palette.error.opacity(0.35), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ok ? Palette.success : Palette.error)
                .padding(6)
        }
    }
}

// MARK: - 4. Pick photos and start

private struct PickerArt: View {
    private let positions: [CGPoint] = [
        CGPoint(x: 80, y: 62), CGPoint(x: 180, y: 62), CGPoint(x: 280, y: 62),
        CGPoint(x: 80, y: 128), CGPoint(x: 180, y: 128), CGPoint(x: 280, y: 128)
    ]

    var body: some View {
        ZStack {
            ForEach(positions.indices, id: \.self) { index in
                MiniPhoto(corner: 8)
                    .frame(width: 72, height: 52)
                    .overlay {
                        if index == 0 {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Palette.accent, lineWidth: 3)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if index == 0 {
                            ArtBadge(symbol: "checkmark", size: 20)
                                .padding(3)
                        }
                    }
                    .position(positions[index])
            }

            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                Text(String(localized: "添加纹理与颗粒"))
                    .font(Typography.micro)
            }
            .foregroundStyle(Palette.onAccent)
            .frame(width: 230, height: 34)
            .background(Palette.accent, in: Capsule())
            .position(x: 180, y: 190)
        }
    }
}

// MARK: - 5. Live Photo: one still, every frame, one slot

private struct LivePhotoArt: View {
    var body: some View {
        ZStack {
            ZStack {
                MiniPhoto(corner: 14)
                GrainField(opacity: 0.20)
            }
            .frame(width: 104, height: 132)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
                ArtBadge(symbol: "livephoto", size: 24)
                    .padding(5)
            }
            .position(x: 90, y: 92)

            ArtPill(text: String(localized: "tutorial.art.stillFrame", defaultValue: "主帧"),
                    symbol: "photo")
                .position(x: 90, y: 180)

            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    ZStack {
                        MiniPhoto(corner: 10)
                        GrainField(opacity: 0.24)
                    }
                    .frame(width: 118, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                    }
                    .rotationEffect(.degrees(Double(index - 1) * 4))
                    .offset(y: CGFloat(index - 1) * 14)
                }

                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.brandMilk)
                    .frame(width: 34, height: 34)
                    .background(Palette.brandInk.opacity(0.55), in: Circle())
            }
            .frame(width: 130, height: 150)
            .position(x: 270, y: 96)

            ArtPill(text: String(localized: "tutorial.art.allFrames", defaultValue: "全部帧"),
                    symbol: "film.stack")
                .position(x: 270, y: 184)

            Text("1")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(Palette.onAccent)
                .frame(width: 36, height: 36)
                .background(Palette.accent, in: Circle())
                .overlay(Circle().strokeBorder(Palette.surfaceElevated, lineWidth: 3))
                .position(x: 180, y: 92)

            Text("=")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .position(x: 180, y: 130)
        }
    }
}

// MARK: - 6. Where the new photo goes

private struct ResultArt: View {
    private let stages = [
        "doc.text.magnifyingglass",
        "sparkles",
        "checkmark.seal",
        "square.and.arrow.down"
    ]

    var body: some View {
        ZStack {
            Capsule()
                .fill(Palette.hairline)
                .frame(width: 280, height: 2)
                .position(x: 180, y: 54)

            ForEach(stages.indices, id: \.self) { index in
                Image(systemName: stages[index])
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(index == stages.count - 1 ? Palette.onAccent : Palette.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(index == stages.count - 1 ? Palette.accent : Palette.surface, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                    }
                    .position(x: 52 + CGFloat(index) * 76, y: 54)
            }

            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(Palette.accentText)
                .frame(width: 56, height: 56)
                .background(Palette.fillControl, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .position(x: 82, y: 154)

            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .position(x: 140, y: 154)

            ZStack(alignment: .bottomLeading) {
                MiniPhoto(corner: 12)
                GrainField(opacity: 0.20)
                Text("_Texel")
                    .font(Typography.monospaced)
                    .foregroundStyle(Palette.brandMilk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Palette.brandInk.opacity(0.55), in: Capsule())
                    .padding(6)
            }
            .frame(width: 132, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            }
            .position(x: 232, y: 154)

            ArtPill(text: String(localized: "tutorial.art.recents", defaultValue: "最近项目"),
                    symbol: "clock")
                .position(x: 232, y: 105)
        }
    }
}

// MARK: - 7. Edit the style afterwards

private struct EditArt: View {
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                ZStack {
                    MiniPhoto(corner: 0)
                    GrainField(opacity: 0.18)
                }
                .frame(width: 118, height: 132)
                .clipped()

                HStack(spacing: 18) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(Palette.accentText)
                    Image(systemName: "crop")
                    Image(systemName: "wand.and.stars")
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 118, height: 34)
                .background(Palette.surface)
            }
            .frame(width: 130, height: 180)
            .background(Palette.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            }
            .position(x: 88, y: 110)

            VStack(spacing: 10) {
                HStack(spacing: 14) {
                    ForEach(0..<3, id: \.self) { index in
                        ZStack {
                            Circle()
                                .fill(index == 1 ? Palette.accent : (index == 0 ? Palette.thinking.opacity(0.7) : Palette.running.opacity(0.7)))
                                .frame(width: 26, height: 26)
                            if index == 1 {
                                Circle()
                                    .strokeBorder(Palette.textPrimary, lineWidth: 1.5)
                                    .frame(width: 32, height: 32)
                            }
                        }
                    }
                }

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Palette.fillControl)
                        .frame(width: 140, height: 7)
                    Capsule()
                        .fill(Palette.accent)
                        .frame(width: 96, height: 7)
                    Circle()
                        .fill(Palette.surfaceElevated)
                        .overlay(Circle().strokeBorder(Palette.accent, lineWidth: 2))
                        .frame(width: 18, height: 18)
                        .offset(x: 87)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Palette.fillControl)
                    GrainField(opacity: 0.35)
                }
                .frame(width: 140, height: 20)
            }
            .padding(14)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            }
            .position(x: 268, y: 110)

            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .position(x: 177, y: 110)
        }
    }
}

// MARK: - 8. Why it can look unchanged

private struct InvisibleArt: View {
    var body: some View {
        ZStack {
            MiniPhoto(corner: 12)
                .frame(width: 92, height: 116)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                }
                .overlay(alignment: .bottomTrailing) {
                    ArtBadge(symbol: "eye.slash.fill",
                             tint: Palette.brandMilk,
                             fill: Palette.textTertiary,
                             size: 24)
                        .padding(5)
                }
                .position(x: 80, y: 108)

            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .position(x: 150, y: 108)

            ZStack {
                MiniPhoto(corner: 14)
                GrainField(opacity: 0.35)
            }
            .frame(width: 150, height: 156)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Palette.accent.opacity(0.5), lineWidth: 1.5)
            }
            .position(x: 258, y: 108)

            ZStack {
                Circle()
                    .fill(Palette.surfaceElevated.opacity(0.9))
                Circle()
                    .strokeBorder(Palette.accent, lineWidth: 3)
                GrainField(opacity: 0.70)
                    .clipShape(Circle())
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .offset(x: 18, y: 18)
            }
            .frame(width: 78, height: 78)
            .position(x: 258, y: 108)
        }
    }
}

// MARK: - 9. Quota and Pro

private struct QuotaArt: View {
    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { index in
                    Circle()
                        .fill(index < 2 ? Palette.accent : Palette.fillControl)
                        .frame(width: 36, height: 36)
                        .overlay {
                            if index < 2 {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Palette.onAccent)
                            }
                        }
                }
            }
            .position(x: 180, y: 52)

            ZStack {
                MiniPhoto(corner: 10)
                GrainField(opacity: 0.20)
            }
            .frame(width: 110, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
                ArtBadge(symbol: "livephoto", size: 22)
                    .padding(4)
            }
            .position(x: 78, y: 148)

            Text("=")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .position(x: 150, y: 148)

            Text("1")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Palette.onAccent)
                .frame(width: 40, height: 40)
                .background(Palette.accent, in: Circle())
                .position(x: 188, y: 148)

            HStack(spacing: 4) {
                Image(systemName: "infinity")
                    .font(.system(size: 12, weight: .semibold))
                Text("Pro")
                    .font(Typography.micro)
            }
            .foregroundStyle(Palette.accentText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Palette.accentSoft, in: Capsule())
            .position(x: 285, y: 148)
        }
    }
}
