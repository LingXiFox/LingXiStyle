import SwiftUI

/// Timings from the brief. Nothing here drives business state: animations only decorate
/// transitions that already happened. 1.5 removes every looping effect.
enum Motion {
    static let entrance = Animation.spring(response: 0.35, dampingFraction: 0.86)
    static let selection = Animation.spring(response: 0.28, dampingFraction: 0.80)
    static let stageChange = Animation.easeInOut(duration: 0.22)
    static let notice = Animation.easeOut(duration: 0.20)
    static let result = Animation.spring(response: 0.40, dampingFraction: 0.88)

    static func respectingReduceMotion(_ reduceMotion: Bool, _ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - Preview / UI-test hook

/// The system Reduce Motion value is read-only in SwiftUI, so the canvas and UI tests need a
/// separate switch to render that state. It defaults to false and never changes production behavior.
private struct ReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var reduceMotionOverride: Bool {
        get { self[ReduceMotionOverrideKey.self] }
        set { self[ReduceMotionOverrideKey.self] = newValue }
    }
}
