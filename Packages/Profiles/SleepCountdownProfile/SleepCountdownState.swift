import Foundation
import ProfileKit
import SleepClock

/// Profile-facing runtime state. Wraps `SleepClock.NextEvent` (which lives in
/// the SleepClock module and is agnostic of ProfileKit) and conforms to
/// `ProfileRuntimeState`.
public enum SleepCountdownState: Sendable, Equatable, ProfileRuntimeState {
    case idle(SleepClock.NextEvent)          // countdown or .none sentinel
    case suppressed                           // caffeinated — Sleep profile yields primary slot

    public var nextEvent: SleepClock.NextEvent? {
        switch self {
        case let .idle(event): return event
        case .suppressed: return nil
        }
    }

    /// Sleep is presentable whenever not suppressed by caffeine — the
    /// sentinel `.idle(.none)` state is still *shown* (moon.slash + "Sleep
    /// disabled" label) per FR-010.
    public var isActive: Bool {
        switch self {
        case .suppressed: return false
        case .idle: return true
        }
    }

    public var isUrgent: Bool {
        guard case let .idle(event) = self,
              let remaining = event.remaining
        else {
            return false
        }
        return remaining < 10
    }
}
