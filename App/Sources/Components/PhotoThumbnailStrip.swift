import SwiftUI

/// 68pt thumbnails, 10pt gaps, 2pt selection ring, a minus badge for photos that will be
/// skipped, and an explicit add tile. Swipe-free so it also works with VoiceOver and large type.
struct PhotoThumbnailStrip: View {
    let items: [PhotoItem]
    @Binding var selectedID: UUID?
    var onRemove: (PhotoItem) -> Void
    var onAdd: () -> Void
    var canAdd: Bool = true

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride
    private var reduceMotion: Bool { systemReduceMotion || reduceMotionOverride }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(items) { item in
                    thumbnail(for: item)
                }
                if canAdd {
                    addTile
                }
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)
        }
        .frame(height: Layout.thumbnailSide + Spacing.xs * 2)
        .scrollClipDisabled()
    }

    private func thumbnail(for item: PhotoItem) -> some View {
        let isSelected = item.id == selectedID
        return Button {
            if reduceMotion {
                selectedID = item.id
            } else {
                withAnimation(Motion.selection) { selectedID = item.id }
            }
        } label: {
            Image(uiImage: item.image)
                .resizable()
                .scaledToFill()
                .frame(width: Layout.thumbnailSide, height: Layout.thumbnailSide)
                .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous)
                        .strokeBorder(isSelected ? Palette.accent : Palette.hairline,
                                      lineWidth: isSelected ? 2 : 1)
                )
                .overlay(alignment: .topTrailing) {
                    if willSkip(item) {
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
            Button(role: .destructive) { onRemove(item) } label: {
                Label("移出队列", systemImage: "trash")
            }
        }
    }

    private var addTile: some View {
        Button(action: onAdd) {
            RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous)
                .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(width: Layout.thumbnailSide, height: Layout.thumbnailSide)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(.headline, design: .default, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("继续添加照片")
    }

    private func willSkip(_ item: PhotoItem) -> Bool {
        guard let verdict = item.verdict else { return false }
        return !verdict.isReady
    }
}
