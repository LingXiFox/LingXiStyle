import SwiftUI

/// 68pt thumbnails, 10pt gaps, 2pt selection ring, a minus badge for photos that will be
/// skipped, and an explicit add tile. Swipe-free so it also works with VoiceOver and large type.
struct PhotoThumbnailStrip: View {
    let items: [PhotoItem]
    @Binding var selectedID: UUID?
    var onRemove: (PhotoItem) -> Void
    var onAdd: () -> Void
    var canAdd: Bool = true
    var side: CGFloat = Layout.thumbnailSide

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(items) { item in
                    PhotoThumbnailTile(
                        item: item,
                        side: side,
                        isSelected: item.id == selectedID,
                        onSelect: {
                            if reduceMotion {
                                selectedID = item.id
                            } else {
                                withAnimation(Motion.selection) { selectedID = item.id }
                            }
                        },
                        onRemove: { onRemove(item) }
                    )
                }
                if canAdd {
                    addTile
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)
        }
        .frame(height: side + Spacing.xs * 2)
        .scrollClipDisabled()
    }

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride
    private var reduceMotion: Bool { systemReduceMotion || reduceMotionOverride }

    private var addTile: some View {
        Button(action: onAdd) {
            RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous)
                .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(width: side, height: side)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(.headline, design: .default, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("继续添加照片")
    }
}

/// Shared square thumbnail used by the horizontal strip and the inner-display queue grid.
struct PhotoThumbnailTile: View {
    let item: PhotoItem
    var side: CGFloat = Layout.thumbnailSide
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Image(uiImage: item.image)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous)
                        .strokeBorder(isSelected ? Palette.accent : Palette.hairline,
                                      lineWidth: isSelected ? 2 : 1)
                )
                .overlay(alignment: .topTrailing) {
                    if willSkip {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: 18, height: 18)
                            .background(Palette.surfaceElevated, in: Circle())
                            .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 0.5))
                            .padding(5)
                    }
                }
                .opacity(isSelected ? 1 : 0.9)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "thumbnail.accessibilityLabel", defaultValue: "\(item.displayName)，\(item.accessibilityDescription)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button(role: .destructive, action: onRemove) {
                Label("移出队列", systemImage: "trash")
            }
        }
    }

    private var willSkip: Bool {
        guard let verdict = item.verdict else { return false }
        return !verdict.isReady
    }
}
