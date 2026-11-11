import SwiftUI

/// Three layout surfaces driven only by size classes and available width — never by device
/// model, idiom, or interface orientation. Standard phones and the Duo cover screen share the
/// compact column; the Duo inner display gets the regular two-pane layout.
enum DuoLayoutMode: String {
    case phone
    case cover
    case inner
}

private struct DuoLayoutModeKey: EnvironmentKey {
    static let defaultValue: DuoLayoutMode = .phone
}

extension EnvironmentValues {
    var duoLayout: DuoLayoutMode {
        get { self[DuoLayoutModeKey.self] }
        set { self[DuoLayoutModeKey.self] = newValue }
    }
}

/// Layout constants from the Duo handoff. They live here so the compact cover screen and the
/// regular inner display share one source of truth instead of scattering magic numbers.
enum DuoMetrics {
    static let coverMargin: CGFloat = 20
    static let coverBottom: CGFloat = 22
    static let coverButtonHeight: CGFloat = 52
    static let coverPreviewHeight: CGFloat = 252
    static let coverResultPreviewHeight: CGFloat = 204
    static let coverConvertingPreviewHeight: CGFloat = 196
    static let coverThumbnailSide: CGFloat = 64
    static let coverRailWidth: CGFloat = 44
    static let coverRailTop: CGFloat = 150
    static let coverRailTrailing: CGFloat = 8

    static let innerGap: CGFloat = 48
    static let innerLeadingPadding: CGFloat = 40
    static let innerTrailingPadding: CGFloat = 28
    static let innerRightPadding: CGFloat = 28
    static let innerBottom: CGFloat = 28
    static let innerQueueThumbnailSide: CGFloat = 88
    static let innerQueueSpacing: CGFloat = 8
    static let innerFormMaxWidth: CGFloat = 560
    static let proSheetMaxWidth: CGFloat = 520
    static let innerPickerMaxWidth: CGFloat = 300
}
