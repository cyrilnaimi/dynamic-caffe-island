import Foundation

/// Pure computation over inputs from `SystemPreferencesReader`.
///
/// Honors FR-011 (caffeinated → `.suppressed`) and FR-007/008 (pick the next
/// sleep-like event and surface which one it is).
public enum SleepClock {
    public struct Inputs: Sendable, Equatable {
        public var displaySleepAfter: TimeInterval?
        public var screensaverAfter: TimeInterval?
        public var systemSleepAfter: TimeInterval?
        public var secondsSinceLastInput: TimeInterval
        public var caffeinationActive: Bool

        public init(
            displaySleepAfter: TimeInterval? = nil,
            screensaverAfter: TimeInterval? = nil,
            systemSleepAfter: TimeInterval? = nil,
            secondsSinceLastInput: TimeInterval = 0,
            caffeinationActive: Bool = false
        ) {
            self.displaySleepAfter = displaySleepAfter
            self.screensaverAfter = screensaverAfter
            self.systemSleepAfter = systemSleepAfter
            self.secondsSinceLastInput = secondsSinceLastInput
            self.caffeinationActive = caffeinationActive
        }
    }

    public enum NextEvent: Sendable, Equatable, ProfileRuntimeStateMarker {
        case displaySleep(TimeInterval)
        case screensaver(TimeInterval)
        case systemSleep(TimeInterval)
        case none                // all disabled
        case suppressed          // caffeinated

        public var remaining: TimeInterval? {
            switch self {
            case let .displaySleep(t), let .screensaver(t), let .systemSleep(t):
                return t
            case .none, .suppressed:
                return nil
            }
        }

        public var label: String {
            switch self {
            case .displaySleep: return "Display sleep"
            case .screensaver: return "Screensaver"
            case .systemSleep: return "System sleep"
            case .none: return "Sleep disabled"
            case .suppressed: return "Caffeinated"
            }
        }
    }

    /// Resolve inputs to the next-upcoming event. Pure; no system calls.
    public static func resolve(_ inputs: Inputs) -> NextEvent {
        // FR-011: caffeine suppresses sleep countdown.
        if inputs.caffeinationActive { return .suppressed }

        let candidates: [(NextEvent, TimeInterval)] = [
            inputs.displaySleepAfter.map { (NextEvent.displaySleep(max(0, $0 - inputs.secondsSinceLastInput)), $0) },
            inputs.screensaverAfter.map { (NextEvent.screensaver(max(0, $0 - inputs.secondsSinceLastInput)), $0) },
            inputs.systemSleepAfter.map { (NextEvent.systemSleep(max(0, $0 - inputs.secondsSinceLastInput)), $0) },
        ].compactMap { $0 }

        // FR-010: all disabled → distinct idle state
        if candidates.isEmpty { return .none }

        // Pick the one with smallest remaining time (closest event).
        let winner = candidates.min { lhs, rhs in
            lhs.0.remaining ?? .infinity < rhs.0.remaining ?? .infinity
        }
        return winner?.0 ?? .none
    }
}

/// Bridge protocol so we can mark types as `ProfileRuntimeState` without a
/// direct ProfileKit dependency. The actual conformance lives in the built-in
/// profile target (BuiltInProfiles depends on both SleepClock and ProfileKit).
public protocol ProfileRuntimeStateMarker: Sendable, Equatable {}
