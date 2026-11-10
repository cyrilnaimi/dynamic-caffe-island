import Foundation
import ProfileKit

/// A single "keep the Mac awake" window. Owned by the Caffeine profile.
/// The `AssertionHandle` is opaque to this type — session equality is by id.
public struct CaffeinationSession: Sendable, Equatable {
    public enum Duration: Sendable, Equatable, Codable {
        case preset(TimeInterval)
        case untilClockTime(Date)
        case indefinite
    }

    public let id: UUID
    public let startedAt: Date
    public let duration: Duration
    /// `nil` for `.indefinite`.
    public let expectedEnd: Date?

    public init(id: UUID = UUID(), startedAt: Date = Date(), duration: Duration) {
        self.id = id
        self.startedAt = startedAt
        self.duration = duration
        switch duration {
        case let .preset(seconds):
            self.expectedEnd = startedAt.addingTimeInterval(seconds)
        case let .untilClockTime(date):
            // Clamp to >=1 minute in the future.
            let min = startedAt.addingTimeInterval(60)
            self.expectedEnd = max(date, min)
        case .indefinite:
            self.expectedEnd = nil
        }
    }

    public func remaining(now: Date = Date()) -> TimeInterval? {
        guard let end = expectedEnd else { return nil }
        return max(0, end.timeIntervalSince(now))
    }

    /// Monotonically-increasing timestamp for `ProfilePriority.tiebreak` at the
    /// moment this session was started. Callers pass this to the arbitrator.
    public var tiebreakArrival: UInt64 {
        UInt64(startedAt.timeIntervalSince1970 * 1000)
    }
}

public enum CaffeineState: Sendable, Equatable, ProfileRuntimeState {
    case inactive
    case active(CaffeinationSession)
    case expiring(CaffeinationSession)
    case error(message: String)

    public var session: CaffeinationSession? {
        switch self {
        case let .active(s), let .expiring(s): return s
        case .inactive, .error: return nil
        }
    }

    public var isActive: Bool {
        if case .active = self { return true }
        return false
    }
}
