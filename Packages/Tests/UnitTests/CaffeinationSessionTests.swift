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

    // MARK: - While a process runs

    private func spawn(_ path: String, _ args: [String]) throws -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try p.run()
        return p
    }

    func testWhileProcessEndsWhenProcessExits() throws {
        let fake = FakePowerAssertionClient()
        let mgr = CaffeineSessionManager(client: fake)
        let child = try spawn("/bin/sleep", ["0.3"])
        let session = try mgr.startSession(duration: .whileProcess(pid: child.processIdentifier, name: "sleep"))
        XCTAssertNil(session.expectedEnd)
        XCTAssertEqual(fake.liveTokens.count, 1)

        let ended = expectation(description: "session ends after process exit")
        let id = mgr.subscribe { if case .inactive = $0 { ended.fulfill() } }
        // Acceptance: assertion released within 2 s of the process exiting.
        wait(for: [ended], timeout: 2.3)
        mgr.unsubscribe(id)
        XCTAssertEqual(fake.liveTokens.count, 0)
        XCTAssertEqual(mgr.lastEndReason, .processExited(name: "sleep"))
    }

    func testWhileProcessAlreadyGoneThrows() throws {
        let fake = FakePowerAssertionClient()
        let mgr = CaffeineSessionManager(client: fake)
        let child = try spawn("/usr/bin/true", [])
        child.waitUntilExit()
        XCTAssertThrowsError(try mgr.startSession(duration: .whileProcess(pid: child.processIdentifier, name: "true"))) {
            XCTAssertEqual($0 as? CaffeineSessionError, .processNotRunning(pid: child.processIdentifier))
        }
        XCTAssertEqual(fake.liveTokens.count, 0)
    }

    func testCancelRecordsReason() throws {
        let mgr = CaffeineSessionManager(client: FakePowerAssertionClient())
        _ = try mgr.startSession(duration: .indefinite)
        mgr.cancelSession()
        XCTAssertEqual(mgr.lastEndReason, .cancelled)
    }

    // MARK: - Ending only the session a timer or watch was set up for (#26)

    func testStaleExpiryDoesNotEndNewSession() throws {
        let fake = FakePowerAssertionClient()
        let mgr = CaffeineSessionManager(client: fake)
        let old = try mgr.startSession(duration: .preset(60))
        let new = try mgr.startSession(duration: .indefinite)
        mgr.expire(sessionID: old.id)                      // stale timer handler
        XCTAssertEqual(mgr.currentState, .active(new))
        XCTAssertEqual(fake.liveTokens.count, 1)
    }

    func testStaleDwellDoesNotEndNewSession() throws {
        let fake = FakePowerAssertionClient()
        let mgr = CaffeineSessionManager(client: fake)
        let old = try mgr.startSession(duration: .preset(60))
        mgr.expire(sessionID: old.id)
        XCTAssertEqual(mgr.currentState, .expiring(old))
        let new = try mgr.startSession(duration: .indefinite)
        mgr.endSession(reason: .expired, onlyIf: old.id)   // dwell block fires late
        XCTAssertEqual(mgr.currentState, .active(new))
        XCTAssertEqual(fake.liveTokens.count, 1)

        // And the real dwell block, once it runs, leaves it alone too.
        let settled = expectation(description: "dwell passed")
        DispatchQueue.global().asyncAfter(deadline: .now() + CaffeineSessionManager.expiryDwell + 0.3) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        XCTAssertEqual(mgr.currentState, .active(new))
    }

    func testStaleProcessExitDoesNotEndNewSession() throws {
        let fake = FakePowerAssertionClient()
        let mgr = CaffeineSessionManager(client: fake)
        let child = try spawn("/bin/sleep", ["5"])
        defer { child.terminate() }
        let old = try mgr.startSession(duration: .whileProcess(pid: child.processIdentifier, name: "sleep"))
        let new = try mgr.startSession(duration: .indefinite)
        mgr.processExited(sessionID: old.id)
        XCTAssertEqual(mgr.currentState, .active(new))
        XCTAssertEqual(fake.liveTokens.count, 1)
    }

    func testExpiryEndsSessionAfterDwell() throws {
        let fake = FakePowerAssertionClient()
        let mgr = CaffeineSessionManager(client: fake)
        _ = try mgr.startSession(duration: .preset(0.05))
        let ended = expectation(description: "expired")
        let id = mgr.subscribe { if case .inactive = $0 { ended.fulfill() } }
        wait(for: [ended], timeout: 2)
        mgr.unsubscribe(id)
        XCTAssertEqual(mgr.lastEndReason, .expired)
        XCTAssertEqual(fake.liveTokens.count, 0)
    }

    // MARK: - Sleep and wake (#29)

    func testWakePastEndExpiresAtOnce() throws {
        let fake = FakePowerAssertionClient()
        let mgr = CaffeineSessionManager(client: fake)
        let session = try mgr.startSession(duration: .preset(3600))
        mgr.systemDidWake(now: Date(timeIntervalSinceNow: 3700))
        XCTAssertEqual(mgr.currentState, .expiring(session))
    }

    func testWakeBeforeEndKeepsSession() throws {
        let fake = FakePowerAssertionClient()
        let mgr = CaffeineSessionManager(client: fake)
        let session = try mgr.startSession(duration: .preset(3600))
        mgr.systemDidWake(now: Date(timeIntervalSinceNow: 1800))
        XCTAssertEqual(mgr.currentState, .active(session))
    }

    // MARK: - Listener ordering (#27)

    func testConcurrentChangesConvergeOnCurrentState() throws {
        let fake = FakePowerAssertionClient()
        let mgr = CaffeineSessionManager(client: fake)
        let lastSeen = Locked<CaffeineState>(.inactive)
        let id = mgr.subscribe { lastSeen.set($0) }
        defer { mgr.unsubscribe(id) }

        for round in 0 ..< 200 {
            DispatchQueue.concurrentPerform(iterations: 8) { i in
                if (i + round) % 3 == 0 {
                    mgr.cancelSession()
                } else {
                    _ = try? mgr.startSession(duration: i % 2 == 0 ? .indefinite : .preset(60))
                }
            }
            XCTAssertEqual(lastSeen.get(), mgr.currentState, "round \(round)")
            XCTAssertEqual(fake.liveTokens.count, mgr.currentState.session == nil ? 0 : 1, "round \(round)")
        }
        mgr.cancelSession()
    }
}

private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ new: Value) { lock.lock(); value = new; lock.unlock() }
}
