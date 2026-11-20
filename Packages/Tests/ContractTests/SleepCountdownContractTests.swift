import XCTest
@testable import BuiltInProfiles
import ProfileKit

/// T035 — SleepCountdownProfile conforms to Profile.
final class SleepCountdownContractTests: XCTestCase {
    func testIdentityAndStaticPriorityMatchCheckpoint() {
        XCTAssertEqual(SleepCountdownProfile.id.raw, "ch.dynamic-caffe-island.sleep-countdown")
        XCTAssertEqual(SleepCountdownProfile.priority.tier, 40)
    }

    func testCapabilities() {
        XCTAssertTrue(SleepCountdownProfile.capabilities.contains(.halfPillRenderer))
        XCTAssertTrue(SleepCountdownProfile.capabilities.contains(.keyboardActivation))
        XCTAssertTrue(SleepCountdownProfile.capabilities.contains(.userConfigurable))
    }

    func testHalfPillViewNonNilWhenCapabilityDeclared() {
        let profile = makeProfile()
        XCTAssertNotNil(profile.makeHalfPillView(state: .empty))
    }

    func testTierComputation() {
        // Below 10 s remaining → urgency tier 40
        XCTAssertEqual(SleepCountdownProfile.tier(for: .idle(.displaySleep(5))), 40)
        // Above 10 s → idle tier 10
        XCTAssertEqual(SleepCountdownProfile.tier(for: .idle(.displaySleep(60))), 10)
        // Suppressed → still idle tier (shouldn't reach arbitration anyway)
        XCTAssertEqual(SleepCountdownProfile.tier(for: .suppressed), 10)
        // None (disabled) → idle tier
        XCTAssertEqual(SleepCountdownProfile.tier(for: .idle(.none)), 10)
    }

    func testFullPillViewHandlesEveryEvent() {
        let profile = makeProfile()
        let states: [SleepCountdownState] = [
            .idle(.none),
            .idle(.displaySleep(120)),
            .idle(.screensaver(60)),
            .idle(.systemSleep(600)),
            .idle(.displaySleep(5)),       // urgent
            .suppressed,
        ]
        for s in states {
            _ = profile.makeFullPillView(state: AnyProfileState.wrap(s))
        }
    }

    private func makeProfile() -> SleepCountdownProfile {
        SleepCountdownProfile(
            reader: SystemPreferencesReader(source: InlinePrefsSource()),
            caffeinationActive: { false }
        )
    }
}

private struct InlinePrefsSource: SystemPreferencesReader.Source {
    func readPMSettings() -> (displayMinutes: Int?, sleepMinutes: Int?) {
        (5, 30)
    }
    func readScreensaverSeconds() -> Int? { 600 }
}
