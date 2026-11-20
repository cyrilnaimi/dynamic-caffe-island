import Foundation

/// Text for the Dock icon badge while a session runs: "25m", "1h05", "∞".
/// Whole minutes only, rounded up, so the badge changes at most once a
/// minute and never reads "0m" while the Mac is still being kept awake.
public enum DockBadge {
    /// `remaining == nil` is an open-ended session (indefinite, or while a
    /// process runs).
    public static func text(remaining: TimeInterval?) -> String {
        guard let remaining else { return "∞" }
        let minutes = max(1, Int((remaining / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes)m" }
        return String(format: "%dh%02d", minutes / 60, minutes % 60)
    }

    /// Seconds until `text(remaining:)` next changes, so the badge can be
    /// refreshed exactly then instead of polling. `nil` when it never will.
    public static func secondsUntilChange(remaining: TimeInterval?) -> TimeInterval? {
        guard let remaining, remaining > 60 else { return nil }
        // The text shows ceil(remaining / 60), so it changes the moment
        // `remaining` drops to the next whole minute: `intoMinute` seconds
        // from now, or a full minute when already exactly on one.
        let intoMinute = remaining.truncatingRemainder(dividingBy: 60)
        // Leave a little slack so the next read lands on the new minute.
        return (intoMinute == 0 ? 60 : intoMinute) + 0.05
    }
}
