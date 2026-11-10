import XCTest
@testable import BuiltInProfiles
import PowerAssertions

/// T021 — CaffeinationSession lifecycle via CaffeineSessionManager + FakePowerAssertionClient.
/// Covers: start, expire(preset), expire(untilClockTime), cancel, indefinite, error.
final class CaffeinationSessionTests: XCTestCase {
    func testStartPresetAcquiresAssertion() throws {
        let fake = FakePowerAssertionClient()
        let mgr = CaffeineSessionManager(client: fake)
        let session = try mgr.startSession(duration: .preset(60))
        XCTAssertTrue(mgr.currentState.isActive)
        XCTAssertEqual(fake.liveTokens.count, 1)
        XCTAssertNotNil(session.expectedEnd)
    }

    func testCancelReleasesAssertion() throws {
        let fake = FakePowerAssertionClient()
        let mgr = CaffeineSessionManager(client: fake)
        _ = try mgr.startSession(duration: .preset(60))
        mgr.cancelSession()
        XCTAssertFalse(mgr.currentState.isActive)
        XCTAssertEqual(fake.liveTokens.count, 0)
    }

    func testIndefiniteHasNoExpectedEnd() throws {
        let fake = FakePowerAssertionClient()
        let mgr = CaffeineSessionManager(client: fake)
        let session = try mgr.startSession(duration: .indefinite)
        XCTAssertNil(session.expectedEnd)
    }

    func testUntilClockTimeClampsToMinimum() throws {
        let fake = FakePowerAssertionClient()
        let mgr = CaffeineSessionManager(client: fake)
        let past = Date(timeIntervalSinceNow: -3600)   // 1h ago
        let session = try mgr.startSession(duration: .untilClockTime(past))
        let end = try XCTUnwrap(session.expectedEnd)
        // Should clamp to startedAt + 60 s.
        XCTAssertGreaterThanOrEqual(end.timeIntervalSince(session.startedAt), 60)
    }

    func testErrorStateWhenAcquireFails() {
        let fake = FakePowerAssertionClient()
        fake.acquireFailsWith = -536870210
        let mgr = CaffeineSessionManager(client: fake)
        XCTAssertThrowsError(try mgr.startSession(duration: .preset(60)))
        XCTAssertFalse(mgr.currentState.isActive)
        XCTAssertEqual(fake.liveTokens.count, 0, "failed acquire leaves no live tokens")
    }

    func testStartingNewSessionCancelsPrevious() throws {
        let fake = FakePowerAssertionClient()
        let mgr = CaffeineSessionManager(client: fake)
        _ = try mgr.startSession(duration: .preset(60))
        _ = try mgr.startSession(duration: .preset(120))
        XCTAssertEqual(fake.liveTokens.count, 1, "previous assertion released on new session")
    }

    func testSubscribeReceivesInitialStateImmediately() throws {
        let fake = FakePowerAssertionClient()
        let mgr = CaffeineSessionManager(client: fake)
        _ = try mgr.startSession(duration: .preset(60))

        let exp = expectation(description: "initial state")
        let id = mgr.subscribe { state in
            if state.isActive { exp.fulfill() }
        }
        wait(for: [exp], timeout: 0.5)
        mgr.unsubscribe(id)
    }

    func testRemainingIsNonNegative() {
        let session = CaffeinationSession(startedAt: Date(timeIntervalSinceNow: -3600), duration: .preset(60))
        XCTAssertEqual(session.remaining()?.rounded(), 0)
    }
}
