import SwiftUI
import LingXiKit

/// Splits a regular-width page into the handoff's 451 / 48 / 452 panes. Landscape uses
/// side-by-side columns; a tall regular surface stacks them without switching on orientation.
struct DuoInnerSplit<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        GeometryReader { proxy in
            let layout = proxy.size.width >= proxy.size.height
                ? AnyLayout(HStackLayout(spacing: DuoMetrics.innerGap))
                : AnyLayout(VStackLayout(spacing: Spacing.l))

            layout {
                leading
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                trailing
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// The compact cover screen keeps text buttons in the content column and moves pure icon
/// actions into the right-hand strip beside the camera island.
struct DuoCoverRail<Content: View>: View {
    @ViewBuilder var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: Spacing.s) {
            content
        }
        .padding(.top, DuoMetrics.coverRailTop)
        .padding(.trailing, DuoMetrics.coverRailTrailing)
    }
}

struct DuoRailButton: View {
    let systemImage: String
    let label: String
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: Layout.minimumTouchTarget, height: Layout.minimumTouchTarget)
                .background(Palette.fillControl, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier ?? "")
    }
}

struct DuoRailShareButton: View {
    let url: URL
    var label: String = String(localized: "分享这张 HEIC")

    var body: some View {
        ShareLink(item: url) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: Layout.minimumTouchTarget, height: Layout.minimumTouchTarget)
                .background(Palette.fillControl, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Compact Live Photo switch used on Duo layouts. The full radio group stays on standard
/// phones and in Settings; here a menu keeps the same temporary override without eating the
/// photo preview's height.
struct DuoLivePhotoModeRow: View {
    let selection: LivePhotoProcessingMode
    let onSelect: (LivePhotoProcessingMode) -> Void
    var showsQuotaNote: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "livephoto")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)

                Text(String(localized: "settings.livePhoto.section", defaultValue: "实况照片处理方式"))
                    .font(Typography.bodyEmphasized)
                    .foregroundStyle(Palette.textPrimary)

                Spacer(minLength: 0)

                Menu {
                    ForEach(LivePhotoProcessingMode.allCases, id: \.self) { mode in
                        Button {
                            onSelect(mode)
                        } label: {
                            if mode == selection {
                                Label(mode.title, systemImage: "checkmark")
                            } else {
                                Text(mode.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selection.title)
                            .font(Typography.captionEmphasized)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(Palette.accentText)
                    .padding(.horizontal, Spacing.s)
                    .frame(minHeight: 32)
                    .background(Palette.fillControl, in: Capsule())
                }
                .accessibilityLabel(String(localized: "settings.livePhoto.section", defaultValue: "实况照片处理方式"))
                .accessibilityValue(selection.title)
                .accessibilityIdentifier("livePhoto.mode.menu")
            }

            if showsQuotaNote {
                Text(LivePhotoProcessingMode.quotaNote)
                    .font(Typography.micro)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// Four-column queue used by the inner display. Four 88pt tiles fit the 383pt text column
/// without horizontal scrolling, so the left pane stays a true overview.
struct DuoQueueGrid: View {
    let items: [PhotoItem]
    @Binding var selectedID: UUID?
    var onRemove: (PhotoItem) -> Void
    var onAdd: () -> Void
    var canAdd: Bool = true

    private let columns = Array(
        repeating: GridItem(.fixed(DuoMetrics.innerQueueThumbnailSide), spacing: DuoMetrics.innerQueueSpacing),
        count: 4
    )

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: DuoMetrics.innerQueueSpacing) {
            ForEach(items) { item in
                PhotoThumbnailTile(
                    item: item,
                    side: DuoMetrics.innerQueueThumbnailSide,
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
                Button(action: onAdd) {
                    RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous)
                        .strokeBorder(Palette.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .frame(width: DuoMetrics.innerQueueThumbnailSide,
                               height: DuoMetrics.innerQueueThumbnailSide)
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
    }

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride
    private var reduceMotion: Bool { systemReduceMotion || reduceMotionOverride }
}

// MARK: - Sheet width

private struct DuoFormWidth: ViewModifier {
    @Environment(\.duoLayout) private var duoLayout
    var maxWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: duoLayout == .inner ? maxWidth : .infinity)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    /// Keeps regular-width sheets from stretching a single reading column across 951pt.
    func duoFormWidth(_ maxWidth: CGFloat = DuoMetrics.innerFormMaxWidth) -> some View {
        modifier(DuoFormWidth(maxWidth: maxWidth))
    }
}
