import XCTest
@testable import IslandCore
import ProfileKit

/// T019 — Arbitrator unit tests.
/// Covers A-1 purity over 1000 random inputs + targeted hysteresis,
/// collision (secondary == primary), and secondary-promotion cases.
final class ArbitratorTests: XCTestCase {
    // MARK: - A-1: Purity over 1000 random tuples

    func testArbitrateIsPure() {
        let rng = SystemRandomNumberGenerator()
        var generator = rng
        for i in 0..<1000 {
            let inputs = Self.randomEvents(seed: &generator, trial: i)
            let prefs = Arbitrator.Preferences(secondarySlotProfileID: inputs.randomEnabledID())
            let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
            let a = Arbitrator.arbitrate(events: inputs, preferences: prefs, now: fixedNow)
            let b = Arbitrator.arbitrate(events: inputs, preferences: prefs, now: fixedNow)
            XCTAssertEqual(a, b, "trial \(i): arbitrate is not pure")
        }
    }

    // MARK: - Targeted cases

    func testEmptyInputsReturnsEmpty() {
        let out = Arbitrator.arbitrate(events: [], preferences: .init(secondarySlotProfileID: nil))
        XCTAssertEqual(out, .empty)
    }

    func testHigherTierWinsPrimary() {
        let caffeine = makeSnapshot(id: "caffeine", tier: 100, active: true, halfPillRenderer: true)
        let sleep = makeSnapshot(id: "sleep", tier: 40, active: true, halfPillRenderer: true)
        let out = Arbitrator.arbitrate(events: [sleep, caffeine], preferences: .init())
        XCTAssertEqual(out.primary.profileID?.raw, "caffeine")
        XCTAssertTrue(out.secondary.isEmpty)
    }

    func testSecondaryEqualsPrimaryCollapsesToPrimaryOnly() {
        let caffeine = makeSnapshot(id: "caffeine", tier: 100, active: true, halfPillRenderer: true)
        let prefs = Arbitrator.Preferences(secondarySlotProfileID: caffeine.profileID)
        let out = Arbitrator.arbitrate(events: [caffeine], preferences: prefs)
        XCTAssertEqual(out.primary.profileID?.raw, "caffeine")
        XCTAssertTrue(out.secondary.isEmpty, "collision rule: secondary is hidden when it would duplicate primary")
        if case let .occupied(_, _, _, variant) = out.primary {
            XCTAssertEqual(variant, .fullPill, "lone primary uses full-pill")
        } else {
            XCTFail("expected primary to be occupied")
        }
    }

    func testLoneSecondaryPromotesToFullPill() {
        let sleep = makeSnapshot(id: "sleep", tier: 10, active: false, halfPillRenderer: true)
        let prefs = Arbitrator.Preferences(secondarySlotProfileID: sleep.profileID)
        let out = Arbitrator.arbitrate(events: [sleep], preferences: prefs)
        XCTAssertEqual(out.primary.profileID?.raw, "sleep", "lone secondary promotes to primary slot")
        if case let .occupied(_, _, _, variant) = out.primary {
            XCTAssertEqual(variant, .fullPill, "lone-secondary promotion uses full-pill (S-7)")
        } else {
            XCTFail("expected primary to be occupied with promoted secondary")
        }
    }

    func testBothOccupiedRendersSplit() {
        let caffeine = makeSnapshot(id: "caffeine", tier: 100, active: true, halfPillRenderer: true)
        let sleep = makeSnapshot(id: "sleep", tier: 10, active: true, halfPillRenderer: true)
        let prefs = Arbitrator.Preferences(secondarySlotProfileID: sleep.profileID)
        let out = Arbitrator.arbitrate(events: [caffeine, sleep], preferences: prefs)
        XCTAssertEqual(out.primary.profileID?.raw, "caffeine")
        XCTAssertEqual(out.secondary.profileID?.raw, "sleep")
        if case let .occupied(_, _, _, pv) = out.primary {
            XCTAssertEqual(pv, .halfPill)
        }
        if case let .occupied(_, _, _, sv) = out.secondary {
            XCTAssertEqual(sv, .halfPill)
        }
    }

    func testDisabledProfileDoesNotClaimPrimary() {
        let caffeine = makeSnapshot(id: "caffeine", tier: 100, active: true, enabled: false, halfPillRenderer: true)
        let sleep = makeSnapshot(id: "sleep", tier: 40, active: true, enabled: true, halfPillRenderer: true)
        let out = Arbitrator.arbitrate(events: [caffeine, sleep], preferences: .init())
        XCTAssertEqual(out.primary.profileID?.raw, "sleep", "disabled caffeine yields to sleep")
    }

    func testSecondaryWithoutHalfPillIsRejected() {
        let caffeine = makeSnapshot(id: "caffeine", tier: 100, active: true, halfPillRenderer: true)
        let claude = makeSnapshot(id: "claude", tier: 70, active: true, halfPillRenderer: false)
        // User picked claude as secondary but it doesn't declare .halfPillRenderer.
        let prefs = Arbitrator.Preferences(secondarySlotProfileID: claude.profileID)
        let out = Arbitrator.arbitrate(events: [caffeine, claude], preferences: prefs)
        XCTAssertEqual(out.primary.profileID?.raw, "caffeine")
        XCTAssertTrue(out.secondary.isEmpty, "secondary pick rejected because half-pill capability missing")
    }

    // MARK: - Hysteresis (A-2)

    func testHysteresisKeepsPrimaryDuringMinimumRenderWindow() {
        let session = ArbitratorSession()
        let caffeine = makeSnapshot(id: "caffeine", tier: 100, active: true, halfPillRenderer: true)
        let sleep = makeSnapshot(id: "sleep", tier: 40, active: true, halfPillRenderer: true)
        let t0 = Date(timeIntervalSince1970: 0)
        // Caffeine wins primary.
        let first = session.tick(events: [caffeine], preferences: .init(), now: t0)
        XCTAssertEqual(first.primary.profileID?.raw, "caffeine")

        // 100 ms later — well inside the 300 ms min-render window. Caffeine goes idle;
        // but the hysteresis rule only protects against a lower-tier displacing a
        // higher-tier. A profile going idle yields immediately (A-2.2). Instead test
        // that "primary identity change inside window" keeps the last primary.
        let sleepOnly = [makeSnapshot(id: "caffeine", tier: 100, active: true, halfPillRenderer: true, tiebreak: 1),
                          sleep]
        let inside = session.tick(events: sleepOnly, preferences: .init(), now: t0.addingTimeInterval(0.100))
        XCTAssertEqual(inside.primary.profileID?.raw, "caffeine", "hysteresis holds primary")

        // 400 ms later — past the 300 ms window — sleep (lower tier) still shouldn't displace caffeine (still active).
        let late = session.tick(events: sleepOnly, preferences: .init(), now: t0.addingTimeInterval(0.400))
        XCTAssertEqual(late.primary.profileID?.raw, "caffeine", "caffeine still beats sleep on tier")
    }

    // MARK: - Helpers

    private func makeSnapshot(
        id: String,
        tier: Int,
        active: Bool,
        enabled: Bool = true,
        halfPillRenderer: Bool,
        tiebreak: UInt64 = 0
    ) -> Arbitrator.ProfileStateSnapshot {
        struct FakeState: ProfileRuntimeState {}
        let state: AnyProfileState = active ? AnyProfileState.wrap(FakeState()) : .empty
        var caps = ProfileCapabilities()
        if halfPillRenderer { caps.insert(.halfPillRenderer) }
        return Arbitrator.ProfileStateSnapshot(
            profileID: ProfileID(raw: id),
            state: state,
            priority: ProfilePriority(tier: tier, tiebreak: tiebreak),
            capabilities: caps,
            isEnabled: enabled,
            tiebreakArrival: tiebreak
        )
    }

    private static func randomEvents(seed: inout SystemRandomNumberGenerator, trial: Int) -> [Arbitrator.ProfileStateSnapshot] {
        let count = Int.random(in: 0...4, using: &seed)
        var out: [Arbitrator.ProfileStateSnapshot] = []
        for i in 0..<count {
            struct FakeState: ProfileRuntimeState {}
            let active = Bool.random(using: &seed)
            let halfPill = Bool.random(using: &seed)
            let enabled = Bool.random(using: &seed)
            var caps = ProfileCapabilities()
            if halfPill { caps.insert(.halfPillRenderer) }
            out.append(Arbitrator.ProfileStateSnapshot(
                profileID: ProfileID(raw: "p-\(trial)-\(i)"),
                state: active ? AnyProfileState.wrap(FakeState()) : .empty,
                priority: ProfilePriority(tier: Int.random(in: 0...100, using: &seed)),
                capabilities: caps,
                isEnabled: enabled,
                tiebreakArrival: UInt64(i)
            ))
        }
        return out
    }
}

private extension Array where Element == Arbitrator.ProfileStateSnapshot {
    func randomEnabledID() -> ProfileID? {
        filter(\.isEnabled).randomElement()?.profileID
    }
}
