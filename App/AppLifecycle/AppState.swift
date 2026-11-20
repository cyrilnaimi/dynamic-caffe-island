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

    /// A start failed while another session kept running. That session's
    /// state (and its Stop) stays as it is; the UI explains the failure
    /// with this message instead.
    public let startFailedWhileRunning = PassthroughSubject<String, Never>()

    /// The session manager's own state, current the moment a command
    /// returns. `caffeineState` mirrors it for SwiftUI but arrives a little
    /// later (through the event stream), so commands that must act on what
    /// just happened read this instead.
    public var liveCaffeineState: CaffeineState { caffeine.currentState }

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
            // Register the instances this object drives, not fresh copies:
            // a second SleepCountdownProfile would run pmset again and add
            // duplicate observers, and registry calls (tearDown, enable)
            // would act on profiles the UI never sees.
            try await ProfileRegistry.shared.register(instance: caffeine)
            try await ProfileRegistry.shared.register(instance: sleep)
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

    /// Returns the started session, or `nil` if it couldn't start. A failed
    /// start never hides a session that is still running.
    @discardableResult
    public func startCaffeine(duration: CaffeinationSession.Duration) -> CaffeinationSession? {
        do {
            return try caffeine.startSession(duration: duration)
        } catch {
            logger.error("startCaffeine failed: \(error.localizedDescription, privacy: .public)")
            let message: String
            if case .processNotRunning = error as? CaffeineSessionError {
                message = String(localized: "That process has already finished")
            } else {
                message = String(localized: "Couldn’t keep the Mac awake")
            }
            let live = caffeine.currentState
            if live.session != nil {
                caffeineState = live
                startFailedWhileRunning.send(message)
            } else {
                caffeineState = .error(message: message)
            }
            recomputeSlotState()
            return nil
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
