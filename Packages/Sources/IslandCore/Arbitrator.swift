import Foundation
import ProfileKit

/// Pure arbitration function. Per `contracts/island-slot-contract.md` A-1:
/// same `(events, preferences)` → same `(primary, secondary)`, no hidden state.
///
/// Stateful hysteresis lives in `ArbitratorSession` (A-2 / A-3).
public enum Arbitrator {
    public struct ProfileStateSnapshot: Sendable, Equatable {
        public let profileID: ProfileID
        public let state: AnyProfileState
        public let priority: ProfilePriority
        public let capabilities: ProfileCapabilities
        public let isEnabled: Bool
        public let tiebreakArrival: UInt64

        public init(
            profileID: ProfileID,
            state: AnyProfileState,
            priority: ProfilePriority,
            capabilities: ProfileCapabilities,
            isEnabled: Bool,
            tiebreakArrival: UInt64
        ) {
            self.profileID = profileID
            self.state = state
            self.priority = priority
            self.capabilities = capabilities
            self.isEnabled = isEnabled
            self.tiebreakArrival = tiebreakArrival
        }

        /// A profile is "active" iff it has a non-empty state.
        public var isActive: Bool {
            if case .empty = state { return false }
            return isEnabled
        }
    }

    public struct Preferences: Sendable, Equatable {
        public var secondarySlotProfileID: ProfileID?

        public init(secondarySlotProfileID: ProfileID? = nil) {
            self.secondarySlotProfileID = secondarySlotProfileID
        }
    }

    /// Arbitrate a set of profile states + user preferences into a slot assignment.
    public static func arbitrate(
        events: [ProfileStateSnapshot],
        preferences: Preferences,
        now: Date = Date()
    ) -> SlotState {
        let byID = Dictionary(uniqueKeysWithValues: events.map { ($0.profileID, $0) })

        // Primary: highest-priority profile with non-idle state.
        let primaryCandidate = events
            .filter(\.isActive)
            .max { a, b in
                // ProfilePriority.< defined such that lhs < rhs means lhs is *lower* priority.
                a.priority < b.priority
            }

        // Secondary: user pick filtered by (registered ∧ enabled ∧ .halfPillRenderer ∧ not primary).
        let secondaryCandidate = preferences.secondarySlotProfileID
            .flatMap { id in byID[id] }
            .flatMap { snapshot -> ProfileStateSnapshot? in
                guard snapshot.isEnabled,
                      snapshot.capabilities.contains(.halfPillRenderer)
                else { return nil }
                // Collision rule: if the secondary pick is also the primary, secondary is hidden.
                if snapshot.profileID == primaryCandidate?.profileID { return nil }
                return snapshot
            }

        let p = primaryCandidate
        let s = secondaryCandidate

        switch (p, s) {
        case (nil, nil):
            return .empty

        case let (nil, .some(sec)):
            // Secondary promoted to full-pill (§S-7: lone secondary renders full).
            return SlotState(
                primary: .occupied(
                    profileID: sec.profileID,
                    state: sec.state,
                    enteredAt: now,
                    variant: .fullPill
                ),
                secondary: .empty
            )

        case let (.some(pri), nil):
            return SlotState(
                primary: .occupied(
                    profileID: pri.profileID,
                    state: pri.state,
                    enteredAt: now,
                    variant: .fullPill
                ),
                secondary: .empty
            )

        case let (.some(pri), .some(sec)):
            // Both occupied → split layout.
            return SlotState(
                primary: .occupied(
                    profileID: pri.profileID,
                    state: pri.state,
                    enteredAt: now,
                    variant: .halfPill
                ),
                secondary: .occupied(
                    profileID: sec.profileID,
                    state: sec.state,
                    enteredAt: now,
                    variant: .halfPill
                )
            )
        }
    }
}

/// Stateful wrapper that applies A-2 minimum-render-window hysteresis.
///
/// Per checkpoint 03 §3.2 (Q-A2 resolution): minimum render window is
/// **300 ms** (tightened from the original 500 ms draft).
public final class ArbitratorSession: @unchecked Sendable {
    public static let minimumRenderWindow: TimeInterval = 0.300
    public static let queueCoalesceWindow: TimeInterval = 0.200

    private let lock = NSLock()
    private var lastOutput: SlotState = .empty
    private var lastPrimaryEnteredAt: Date?

    public init() {}

    public func tick(
        events: [Arbitrator.ProfileStateSnapshot],
        preferences: Arbitrator.Preferences,
        now: Date = Date()
    ) -> SlotState {
        let desired = Arbitrator.arbitrate(events: events, preferences: preferences, now: now)

        lock.lock(); defer { lock.unlock() }

        // A-2: a primary that just entered holds the slot for minimumRenderWindow.
        if let enteredAt = lastPrimaryEnteredAt,
           now.timeIntervalSince(enteredAt) < Self.minimumRenderWindow,
           let lastPrimaryID = lastOutput.primary.profileID,
           desired.primary.profileID != lastPrimaryID
        {
            // Keep last primary; allow secondary to update.
            return SlotState(primary: lastOutput.primary, secondary: desired.secondary)
        }

        // A-2 satisfied (or first render): adopt desired.
        if desired.primary.profileID != lastOutput.primary.profileID {
            lastPrimaryEnteredAt = now
        }
        lastOutput = desired
        return desired
    }

    public var current: SlotState {
        lock.lock(); defer { lock.unlock() }
        return lastOutput
    }
}
