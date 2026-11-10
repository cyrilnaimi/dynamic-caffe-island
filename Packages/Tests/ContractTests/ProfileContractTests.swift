import XCTest
import ProfileKit

/// T017 — skeleton for the Profile protocol contract tests (B-1..B-8).
///
/// Parameterizes over `ProfileRegistry.shared.registeredProfiles` at setUp.
/// Real assertions populate when US1/US2 profiles register (T026, T040).
final class ProfileContractTests: XCTestCase {
    static var registeredProfiles: [any Profile] = []

    override class func setUp() {
        super.setUp()
        Task { @MainActor in
            registeredProfiles = await ProfileRegistry.shared.registeredProfiles
        }
    }

    func testB1_DuplicateRegistrationThrows() async throws {
        // Use an isolated registry instance for this assertion.
        let registry = ProfileRegistry()
        try await registry.register(DummyProfile.self)
        do {
            try await registry.register(DummyProfile.self)
            XCTFail("expected RegistrationError.duplicate")
        } catch let error as RegistrationError {
            if case let .duplicate(id) = error {
                XCTAssertEqual(id, DummyProfile.id)
            } else {
                XCTFail("unexpected error case: \(error)")
            }
        }
    }

    func testB6_PriorityTiersInRange() async {
        let profiles = await ProfileRegistry.shared.registeredProfiles
        for p in profiles {
            let tier = type(of: p).priority.tier
            XCTAssertTrue((0...100).contains(tier), "\(type(of: p).id): tier \(tier) out of 0...100")
        }
    }

    func testB2_CapabilitiesHonesty() async {
        let profiles = await ProfileRegistry.shared.registeredProfiles
        for p in profiles {
            let caps = type(of: p).capabilities
            // Half-pill view must be nil iff capability is absent.
            let view = p.makeHalfPillView(state: .empty)
            if caps.contains(.halfPillRenderer) {
                XCTAssertNotNil(view, "\(type(of: p).id): declared .halfPillRenderer must return non-nil half-pill view")
            } else {
                XCTAssertNil(view, "\(type(of: p).id): no .halfPillRenderer capability must return nil half-pill view")
            }
        }
    }
}

// MARK: - DummyProfile used to validate duplicate-registration behavior

import SwiftUI

private final class DummyProfile: Profile {
    static let id = ProfileID(raw: "dummy.contract.test")
    static let metadata = ProfileMetadata(
        displayName: "Dummy",
        iconSystemName: "circle",
        summary: "Fixture for contract tests"
    )
    static let capabilities: ProfileCapabilities = []
    static let priority = ProfilePriority(tier: 50)

    init() {}
    func makeEventSource() -> any EventSource { DummyEventSource() }
    func makeFullPillView(state: AnyProfileState) -> AnyView { AnyView(EmptyView()) }
    func makeHalfPillView(state: AnyProfileState) -> AnyView? { nil }
    func performPrimaryInteraction(from state: AnyProfileState) {}
}

private final class DummyEventSource: EventSource {
    struct State: ProfileRuntimeState { let tick: Int }
    typealias S = State
    func stream() -> AsyncStream<State> { AsyncStream { $0.finish() } }
    func tearDown() {}
}
