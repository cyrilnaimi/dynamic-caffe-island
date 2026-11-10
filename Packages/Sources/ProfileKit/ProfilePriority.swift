public struct ProfilePriority: Sendable, Comparable, Hashable {
    /// 0...100. Higher tier wins the primary slot. Checkpoint 03 Q-A1 mapping:
    /// 100 = Caffeine, 70 = Claude-future, 40 = Sleep-urgency, 10 = Sleep-idle.
    public let tier: Int

    /// Monotonic arrival timestamp from the event source; lower wins ties
    /// (earlier event gets the slot).
    public let tiebreak: UInt64

    public init(tier: Int, tiebreak: UInt64 = 0) {
        precondition((0...100).contains(tier), "priority tier must be in 0...100")
        self.tier = tier
        self.tiebreak = tiebreak
    }

    public static func < (lhs: ProfilePriority, rhs: ProfilePriority) -> Bool {
        // Higher tier wins → when ranking, we want `.max(by: <)` to return the
        // higher-priority one. So `<` is "lower-priority than".
        if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
        // Same tier: earlier arrival wins, so a larger tiebreak is "lower priority"
        return lhs.tiebreak > rhs.tiebreak
    }
}
