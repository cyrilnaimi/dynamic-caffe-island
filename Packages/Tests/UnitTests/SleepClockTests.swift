import XCTest
@testable import SleepClock

/// T033 — resolves SleepClock.NextEvent across FR-007, FR-008, FR-010, FR-011.
final class SleepClockTests: XCTestCase {
    func testCaffeineSuppressesEverything() {
        // FR-011: while caffeinated, resolver returns .suppressed regardless.
        let inputs = SleepClock.Inputs(
            displaySleepAfter: 60,
            screensaverAfter: 120,
            systemSleepAfter: 300,
            secondsSinceLastInput: 5,
            caffeinationActive: true
        )
        XCTAssertEqual(SleepClock.resolve(inputs), .suppressed)
    }

    func testAllDisabledReturnsNone() {
        // FR-010
        let inputs = SleepClock.Inputs(
            displaySleepAfter: nil,
            screensaverAfter: nil,
            systemSleepAfter: nil,
            secondsSinceLastInput: 0,
            caffeinationActive: false
        )
        XCTAssertEqual(SleepClock.resolve(inputs), .none)
    }

    func testPicksEarliestEvent() {
        // FR-007/008: display 60s idle; screensaver 120; system 300
        // secondsSinceLastInput=10 → remaining: 50 / 110 / 290 → display wins.
        let inputs = SleepClock.Inputs(
            displaySleepAfter: 60,
            screensaverAfter: 120,
            systemSleepAfter: 300,
            secondsSinceLastInput: 10,
            caffeinationActive: false
        )
        let result = SleepClock.resolve(inputs)
        if case let .displaySleep(remaining) = result {
            XCTAssertEqual(remaining, 50, accuracy: 0.001)
        } else {
            XCTFail("expected .displaySleep, got \(result)")
        }
    }

    func testLabelsAreStable() {
        XCTAssertEqual(SleepClock.NextEvent.displaySleep(30).label, "Display sleep")
        XCTAssertEqual(SleepClock.NextEvent.screensaver(30).label, "Screensaver")
        XCTAssertEqual(SleepClock.NextEvent.systemSleep(30).label, "System sleep")
        XCTAssertEqual(SleepClock.NextEvent.none.label, "Sleep disabled")
        XCTAssertEqual(SleepClock.NextEvent.suppressed.label, "Caffeinated")
    }

    func testRemainingClampsAtZero() {
        let inputs = SleepClock.Inputs(
            displaySleepAfter: 10,
            screensaverAfter: nil,
            systemSleepAfter: nil,
            secondsSinceLastInput: 100,     // well past the idle threshold
            caffeinationActive: false
        )
        if case let .displaySleep(remaining) = SleepClock.resolve(inputs) {
            XCTAssertEqual(remaining, 0, "remaining must not go negative")
        } else {
            XCTFail()
        }
    }
}
