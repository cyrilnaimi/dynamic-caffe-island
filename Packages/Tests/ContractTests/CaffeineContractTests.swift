import XCTest
@testable import BuiltInProfiles
import ProfileKit
import PowerAssertions

/// T020 — Caffeine profile conforms to the Profile contract.
/// Uses FakePowerAssertionClient so we don't acquire real IOPMAssertions.
final class CaffeineContractTests: XCTestCase {
    private func makeProfile() -> CaffeineProfile {
        CaffeineProfile(client: FakePowerAssertionClient())
    }

    func testIdentityAndPriorityMatchCheckpoint() {
        XCTAssertEqual(CaffeineProfile.id.raw, "ch.dynamic-caffe-island.caffeine")
        XCTAssertEqual(CaffeineProfile.priority.tier, 100)
    }

    func testCapabilitiesIncludeHalfPillRenderer() {
        XCTAssertTrue(CaffeineProfile.capabilities.contains(.halfPillRenderer))
        XCTAssertTrue(CaffeineProfile.capabilities.contains(.keyboardActivation))
        XCTAssertTrue(CaffeineProfile.capabilities.contains(.userConfigurable))
    }

    func testHalfPillViewNonNilWhenCapabilityDeclared() {
        let profile = makeProfile()
        XCTAssertNotNil(profile.makeHalfPillView(state: .empty))
    }

    func testFullPillViewHandlesEveryState() throws {
        let profile = makeProfile()
        let states: [CaffeineState] = [
            .inactive,
            .active(CaffeinationSession(duration: .preset(60))),
            .expiring(CaffeinationSession(duration: .preset(60))),
            .error(message: "test"),
        ]
        for state in states {
            let view = profile.makeFullPillView(state: AnyProfileState.wrap(state))
            _ = view      // just exercising makeFullPillView without throwing
        }
    }

    func testPerformPrimaryInteractionOnActiveDeactivates() throws {
        let fake = FakePowerAssertionClient()
        let profile = CaffeineProfile(client: fake)
        let session = try profile.startSession(duration: .preset(60))
        XCTAssertTrue(profile.currentState.isActive)
        profile.performPrimaryInteraction(from: AnyProfileState.wrap(CaffeineState.active(session)))
        XCTAssertFalse(profile.currentState.isActive)
    }
}
