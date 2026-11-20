import Foundation

/// Snapshot of the Mac's power source, as read from IOKit power sources.
public struct PowerSourceSnapshot: Sendable, Equatable {
    /// `false` on desktops (Mac mini, iMac, Mac Studio…).
    public var hasBattery: Bool
    /// Charge in percent (0…100). Meaningless when `hasBattery` is false.
    public var batteryPercent: Int
    /// On the power adapter.
    public var onACPower: Bool

    public init(hasBattery: Bool, batteryPercent: Int, onACPower: Bool) {
        self.hasBattery = hasBattery
        self.batteryPercent = batteryPercent
        self.onACPower = onACPower
    }

    public static let desktop = PowerSourceSnapshot(hasBattery: false, batteryPercent: 100, onACPower: true)
}

/// Decides when a keep-awake session must stop to protect the battery.
/// Pure logic: the app feeds it snapshots from IOKit notifications.
public struct BatteryGuard: Sendable, Equatable {
    public enum Verdict: Sendable, Equatable {
        case allow
        /// Battery at or below the threshold (and not charging).
        case batteryLow(percent: Int, threshold: Int)
        /// "Only keep awake on power adapter" and the Mac is on battery.
        case onBattery
    }

    /// Stop at or below this percentage. `0` disables the threshold.
    public var threshold: Int
    public var onlyOnPowerAdapter: Bool

    public init(threshold: Int = 0, onlyOnPowerAdapter: Bool = false) {
        self.threshold = threshold
        self.onlyOnPowerAdapter = onlyOnPowerAdapter
    }

    public var isEnabled: Bool { threshold > 0 || onlyOnPowerAdapter }

    public func verdict(for power: PowerSourceSnapshot) -> Verdict {
        // No battery → nothing to protect.
        guard power.hasBattery else { return .allow }
        if onlyOnPowerAdapter, !power.onACPower { return .onBattery }
        // Plugged in: the level only rises, keep going.
        if threshold > 0, !power.onACPower, power.batteryPercent <= threshold {
            return .batteryLow(percent: power.batteryPercent, threshold: threshold)
        }
        return .allow
    }
}
