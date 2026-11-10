import ApplicationServices
import CoreGraphics
import Foundation

/// Wraps `CGEventSourceSecondsSinceLastEventType` — the authoritative
/// input-idle source for macOS (plan.md Phase 0 R-02). Tests swap in a
/// fake via the `Reader` protocol.
public struct IdleTimer {
    public protocol Reader: Sendable {
        func secondsSinceLastInput() -> TimeInterval
    }

    public struct SystemReader: Reader {
        public init() {}

        public func secondsSinceLastInput() -> TimeInterval {
            CGEventSource.secondsSinceLastEventType(
                .combinedSessionState,
                eventType: .init(rawValue: ~0)!
            )
        }
    }

    public static let live: Reader = SystemReader()
}
