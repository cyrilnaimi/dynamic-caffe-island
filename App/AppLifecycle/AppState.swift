import BuiltInProfiles
import Combine
import Foundation
import IslandCore
import OSLog
import ProfileKit
import SwiftUI

/// Owns the two v1 profiles, registers them, publishes mirrored states for
/// SwiftUI, and runs a local `ArbitratorSession` over those states to emit
/// a live `SlotState` the pill view subscribes to.
///
/// Not a singleton — instantiated once as a `@StateObject` in
/// `DynamicCaffeIslandApp`.
@MainActor
public final class AppState: ObservableObject {
    public let caffeine: CaffeineProfile
    public let sleep: SleepCountdownProfile

    @Published public private(set) var caffeineState: CaffeineState = .inactive
    @Published public private(set) var sleepState: SleepCountdownState = .idle(.none)
    @Published public private(set) var slotState: SlotState = .empty

    private let arbitrator = ArbitratorSession()
    private var arrivalCounter: UInt64 = 0
    private var caffeineTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private var bootstrapped = false
    private let logger = Logger(subsystem: "ch.dynamic-caffe-island.app", category: "state")

    public init() {
        self.caffeine = CaffeineProfile()
        let reader = SystemPreferencesReader()
        let caffeineRef = self.caffeine
        self.sleep = SleepCountdownProfile(
            reader: reader,
            caffeinationActive: { caffeineRef.currentState.isActive }
        )
    }

    public func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        do {
            try await ProfileRegistry.shared.register(CaffeineProfile.self)
            try await ProfileRegistry.shared.register(SleepCountdownProfile.self)
            logger.info("registered two built-in profiles")
        } catch {
            logger.error("profile registration failed: \(error.localizedDescription, privacy: .public)")
        }
        subscribe()
        VisibilityObserver.shared.start()
        recomputeSlotState()
    }

    private func subscribe() {
        let caffeineStream = caffeine.makeEventSource().erased()
        caffeineTask = Task { [weak self] in
            for await anyState in caffeineStream.stream() {
                guard let self else { return }
                if let state = anyState.unwrap(as: CaffeineState.self) {
                    await MainActor.run {
                        self.caffeineState = state
                        self.recomputeSlotState()
                    }
                }
            }
        }

        let sleepStream = sleep.makeEventSource().erased()
        sleepTask = Task { [weak self] in
            for await anyState in sleepStream.stream() {
                guard let self else { return }
                if let state = anyState.unwrap(as: SleepCountdownState.self) {
                    await MainActor.run {
                        self.sleepState = state
                        self.recomputeSlotState()
                    }
                }
            }
        }
    }

    // MARK: - Arbitration

    private func recomputeSlotState() {
        arrivalCounter += 1
        let caffeineSnapshot = Arbitrator.ProfileStateSnapshot(
            profileID: CaffeineProfile.id,
            state: caffeineState.isActive ? AnyProfileState.wrap(caffeineState) : .empty,
            priority: CaffeineProfile.priority,
            capabilities: CaffeineProfile.capabilities,
            isEnabled: true,
            tiebreakArrival: arrivalCounter
        )
        let sleepSnapshot = Arbitrator.ProfileStateSnapshot(
            profileID: SleepCountdownProfile.id,
            state: sleepState.isActive ? AnyProfileState.wrap(sleepState) : .empty,
            priority: ProfilePriority(tier: SleepCountdownProfile.tier(for: sleepState)),
            capabilities: SleepCountdownProfile.capabilities,
            isEnabled: true,
            tiebreakArrival: arrivalCounter
        )
        let events = [caffeineSnapshot, sleepSnapshot]
        let prefs = Arbitrator.Preferences(secondarySlotProfileID: nil)     // T050 will set this
        slotState = arbitrator.tick(events: events, preferences: prefs)
    }

    // MARK: - Commands (menu → profile)

    public func startCaffeine(duration: CaffeinationSession.Duration) {
        do {
            _ = try caffeine.startSession(duration: duration)
        } catch {
            logger.error("startCaffeine failed: \(error.localizedDescription, privacy: .public)")
            caffeineState = .error(message: "Couldn't start caffeine")
            recomputeSlotState()
        }
    }

    public func cancelCaffeine() {
        caffeine.cancelSession()
    }

    public func openSleepSettings() {
        sleep.performPrimaryInteraction(from: AnyProfileState.wrap(sleepState))
    }

    // MARK: - View rendering (used by IslandRootView)

    public func view(forProfileID id: ProfileID, state: AnyProfileState, variant: RenderVariant) -> AnyView? {
        let profile: any Profile
        if id == CaffeineProfile.id {
            profile = caffeine
        } else if id == SleepCountdownProfile.id {
            profile = sleep
        } else {
            return nil
        }
        switch variant {
        case .fullPill:
            return profile.makeFullPillView(state: state)
        case .halfPill:
            return profile.makeHalfPillView(state: state)
        }
    }

    public func performInteraction(for id: ProfileID?) {
        guard let id else { return }
        let profile: any Profile
        if id == CaffeineProfile.id {
            profile = caffeine
        } else if id == SleepCountdownProfile.id {
            profile = sleep
        } else {
            return
        }
        let state: AnyProfileState
        if id == CaffeineProfile.id {
            state = AnyProfileState.wrap(caffeineState)
        } else {
            state = AnyProfileState.wrap(sleepState)
        }
        profile.performPrimaryInteraction(from: state)
    }
}
