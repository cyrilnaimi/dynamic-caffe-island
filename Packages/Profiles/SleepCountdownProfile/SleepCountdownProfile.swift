import AppKit
import Foundation
import ProfileKit
import SleepClock
import SwiftUI

/// FR-007..FR-011. Tier mapping per checkpoint 03 Q-A1:
///
///   - idle countdown → tier 10 (Sleep-idle)
///   - remaining < 10 s → tier 40 (Sleep-urgency)
///
/// The static `Profile.priority` here returns the maximum (urgency) — the
/// per-snapshot priority in the arbitrator is computed per-tick.
public final class SleepCountdownProfile: Profile {
    public static let id = ProfileID(raw: "ch.dynamic-caffe-island.sleep-countdown")

    public static let metadata = ProfileMetadata(
        displayName: "Sleep Countdown",
        iconSystemName: "moon.zzz.fill",
        summary: "Shows the time remaining until the next display sleep, screensaver, or system sleep."
    )

    public static let capabilities: ProfileCapabilities = [
        .halfPillRenderer,
        .keyboardActivation,
        .userConfigurable,
    ]

    /// Maximum priority — the arbitrator uses this as an upper bound and
    /// reads the per-snapshot tier from the event-source output for the
    /// actual arbitration decision.
    public static let priority = ProfilePriority(tier: 40)

    public let reader: SystemPreferencesReader
    public let eventSource: SleepCountdownEventSource

    public required init() {
        self.reader = SystemPreferencesReader()
        // Default caffeinationActive provider returns false; AppState will
        // construct a wired instance via init(reader:caffeinationActive:) instead.
        self.eventSource = SleepCountdownEventSource(
            reader: reader,
            caffeinationActive: { false }
        )
    }

    public init(reader: SystemPreferencesReader, caffeinationActive: @escaping @Sendable () -> Bool) {
        self.reader = reader
        self.eventSource = SleepCountdownEventSource(
            reader: reader,
            caffeinationActive: caffeinationActive
        )
    }

    public func makeEventSource() -> any EventSource {
        eventSource
    }

    public func makeFullPillView(state: AnyProfileState) -> AnyView {
        let sleepState = state.unwrap(as: SleepCountdownState.self) ?? .idle(.none)
        return AnyView(SleepCountdownFullPillView(state: sleepState))
    }

    public func makeHalfPillView(state: AnyProfileState) -> AnyView? {
        let sleepState = state.unwrap(as: SleepCountdownState.self) ?? .idle(.none)
        return AnyView(SleepCountdownHalfPillView(state: sleepState))
    }

    public func performPrimaryInteraction(from _: AnyProfileState) {
        // T044 — open System Settings → Displays & Lock Screen
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.displays") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    public func tearDown() {
        eventSource.tearDown()
    }

    /// Per-snapshot priority helper for the arbitration coordinator.
    /// See Q-A1 resolution in checkpoint 03.
    public static func tier(for state: SleepCountdownState) -> Int {
        state.isUrgent ? 40 : 10
    }
}
