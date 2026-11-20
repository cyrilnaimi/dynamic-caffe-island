import XCTest
@testable import SleepClock

/// T034 — IdleTimer with a fake reader.
final class IdleTimerTests: XCTestCase {
    func testFakeReaderReturnsConfiguredValue() {
        let fake = FakeIdleReader(seconds: 42)
        XCTAssertEqual(fake.secondsSinceLastInput(), 42, accuracy: 0.001)
    }

    func testResolveSeesUpdatedIdleTime() {
        let fake = FakeIdleReader(seconds: 0)
        let inputs1 = SleepClock.Inputs(
            displaySleepAfter: 60,
            systemSleepAfter: 120,
            secondsSinceLastInput: fake.secondsSinceLastInput()
        )
        if case let .displaySleep(r) = SleepClock.resolve(inputs1) {
            XCTAssertEqual(r, 60, accuracy: 0.001)
        } else {
            XCTFail()
        }
        fake.seconds = 45
        let inputs2 = SleepClock.Inputs(
            displaySleepAfter: 60,
            systemSleepAfter: 120,
            secondsSinceLastInput: fake.secondsSinceLastInput()
        )
        if case let .displaySleep(r) = SleepClock.resolve(inputs2) {
            XCTAssertEqual(r, 15, accuracy: 0.001, "remaining shrinks with idle time")
        } else {
            XCTFail()
        }
    }
}

final class FakeIdleReader: IdleTimer.Reader, @unchecked Sendable {
    var seconds: TimeInterval
    init(seconds: TimeInterval) { self.seconds = seconds }
    func secondsSinceLastInput() -> TimeInterval { seconds }
}
