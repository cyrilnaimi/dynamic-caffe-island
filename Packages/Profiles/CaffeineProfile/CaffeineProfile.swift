import Foundation
import ProfileKit
import PowerAssertions
import SwiftUI

/// FR-001..FR-006. Tier 100 per checkpoint 03 Q-A1 resolution.
///
/// Profiles must have a no-arg `init()` per B-1; we also expose an
/// `init(client:)` overload so tests can inject `FakePowerAssertionClient`
/// without ceremony.
public final class CaffeineProfile: Profile {
    public static let id = ProfileID(raw: "ch.dynamic-caffe-island.caffeine")

    public static let metadata = ProfileMetadata(
        displayName: "Caffeine",
        iconSystemName: "cup.and.saucer.fill",
        summary: "Keep the Mac awake for a chosen duration."
    )

    public static let capabilities: ProfileCapabilities = [
        .halfPillRenderer,
        .keyboardActivation,
        .userConfigurable,
    ]

    public static let priority = ProfilePriority(tier: 100)

    public let sessionManager: CaffeineSessionManager

    public required init() {
        self.sessionManager = CaffeineSessionManager(client: LivePowerAssertionClient())
    }

    public init(client: any PowerAssertionClient) {
        self.sessionManager = CaffeineSessionManager(client: client)
    }

    // MARK: - Profile protocol

    public func makeEventSource() -> any EventSource {
        CaffeineSessionEventSource(manager: sessionManager)
    }

    public func makeFullPillView(state: AnyProfileState) -> AnyView {
        let caffeineState = state.unwrap(as: CaffeineState.self) ?? .inactive
        return AnyView(CaffeineFullPillView(state: caffeineState))
    }

    public func makeHalfPillView(state: AnyProfileState) -> AnyView? {
        let caffeineState = state.unwrap(as: CaffeineState.self) ?? .inactive
        return AnyView(CaffeineHalfPillView(state: caffeineState))
    }

    public func performPrimaryInteraction(from state: AnyProfileState) {
        // FR-004 one-action cancel: clicking the pill while caffeine is active deactivates.
        let caffeineState = state.unwrap(as: CaffeineState.self) ?? .inactive
        if caffeineState.isActive {
            sessionManager.cancelSession()
        }
    }

    public func tearDown() {
        sessionManager.cancelSession()
    }

    // MARK: - External commands (invoked by the menu)

    @discardableResult
    public func startSession(duration: CaffeinationSession.Duration) throws -> CaffeinationSession {
        try sessionManager.startSession(duration: duration)
    }

    public func cancelSession() {
        sessionManager.cancelSession()
    }

    public var currentState: CaffeineState {
        sessionManager.currentState
    }
}
