import Foundation

/// A single conversion pass over an ordered queue. It owns the session token and the queue
/// cursor, so a cancelled or replaced pass can never advance a newer pass's items.
///
/// The type is deliberately UI-free: AppModel maps PhotoItem state into it, and the engine
/// never sees it. That also makes cancellation and retry behaviour testable on macOS.
public struct ConversionRun: Sendable, Equatable {
    public enum ItemState: String, Sendable, Equatable {
        /// Needs conversion in this pass.
        case pending
        /// Already saved by an earlier pass; never convert it again.
        case saved
        /// Deliberately skipped (already has texture, unsupported container, ...).
        case skipped
        /// The last attempt failed. A retry pass starts it as pending again.
        case failed
        /// Cancelled before any conversion work started.
        case cancelled
        /// Known unsupported; the app should record the real verdict issue.
        case unsupported
        /// No usable original file (prepare failed or the item was removed).
        case unavailable
        /// Deliberately left for a later pass, without recording a user-visible outcome.
        /// Used when a free user asks to convert only the remaining daily allowance.
        case deferred
    }

    public enum Step: Sendable, Equatable {
        case convert(UUID)
        case skip(UUID)
        case cancel(UUID)
        case finished
    }

    public let id: UUID
    private var order: [UUID]
    private var states: [UUID: ItemState]
    private var cursor: Int
    public private(set) var isCancelling: Bool

    public init(id: UUID = UUID(), entries: [(id: UUID, state: ItemState)]) {
        self.id = id
        self.order = []
        self.states = [:]
        self.cursor = 0
        self.isCancelling = false
        for entry in entries {
            if self.states[entry.id] == nil {
                self.order.append(entry.id)
            }
            self.states[entry.id] = entry.state
        }
    }

    public func accepts(sessionID: UUID) -> Bool {
        sessionID == id
    }

    public func state(of itemID: UUID) -> ItemState? {
        states[itemID]
    }

    public var hasSaved: Bool {
        states.values.contains(.saved)
    }

    public var pendingCount: Int {
        states.values.filter { $0 == .pending }.count
    }

    public var isFinished: Bool {
        !states.values.contains { $0 == .pending }
    }

    public mutating func requestCancel() {
        isCancelling = true
    }

    /// Records the outcome of the item that was handed out by next(). Only pending items can
    /// complete; a stale callback from an older pass therefore cannot mark a new pass saved.
    public mutating func complete(_ itemID: UUID, state: ItemState) {
        guard states[itemID] == .pending else { return }
        states[itemID] = state
    }

    /// Returns the next action. A pending item stays pending until complete() is called, so a
    /// caller that awaits conversion will see the same item again only if it never completed it.
    public mutating func next() -> Step {
        while cursor < order.count {
            let itemID = order[cursor]
            guard let state = states[itemID] else {
                cursor += 1
                continue
            }
            switch state {
            case .pending:
                if isCancelling {
                    states[itemID] = .cancelled
                    cursor += 1
                    return .cancel(itemID)
                }
                return .convert(itemID)
            case .unsupported:
                cursor += 1
                return .skip(itemID)
            case .unavailable:
                states[itemID] = .cancelled
                cursor += 1
                return .cancel(itemID)
            case .saved, .skipped, .failed, .cancelled, .deferred:
                cursor += 1
            }
        }
        return .finished
    }
}
