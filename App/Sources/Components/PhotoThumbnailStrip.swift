import SwiftUI

/// 68pt thumbnails, 2pt selection ring, and an explicit add tile. Swipe-free so it also works
/// with VoiceOver and large type.
struct PhotoThumbnailStrip: View {
    let items: [PhotoItem]
    @Binding var selectedID: UUID?
    var onRemove: (PhotoItem) -> Void
    var onAdd: () -> Void
    /// Hidden at the selection limit so the picker can never open on a guaranteed rejection.
    var canAdd: Bool = true

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
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
        .scrollClipDisabled()
    }

    private func thumbnail(for item: PhotoItem) -> some View {
        let isSelected = item.id == selectedID
        return Button {
            withAnimation(Motion.selection) { selectedID = item.id }
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
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(dotColor(for: item))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Palette.surface, lineWidth: 1.5))
                        .padding(5)
                }
                .opacity(isSelected ? 1 : 0.88)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.displayName)，\(item.accessibilityDescription)")
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

    private func dotColor(for item: PhotoItem) -> Color {
        if case .preparingFailed = item.phase { return Palette.error }
        switch item.verdict?.status {
        case .ready: return Palette.success
        case .alreadyEnhanced: return Palette.textSecondary
        case .unsupported: return Palette.warning
        case nil: return Palette.accent
        }
    }
}
