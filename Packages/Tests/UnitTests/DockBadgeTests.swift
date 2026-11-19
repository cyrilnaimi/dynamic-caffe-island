import BuiltInProfiles
import XCTest

final class DockBadgeTests: XCTestCase {
    func testOpenEndedSessionsShowInfinity() {
        XCTAssertEqual(DockBadge.text(remaining: nil), "∞")
    }

    func testMinutesRoundUp() {
        XCTAssertEqual(DockBadge.text(remaining: 0), "1m")
        XCTAssertEqual(DockBadge.text(remaining: 1), "1m")
        XCTAssertEqual(DockBadge.text(remaining: 60), "1m")
        XCTAssertEqual(DockBadge.text(remaining: 61), "2m")
        XCTAssertEqual(DockBadge.text(remaining: 25 * 60 - 30), "25m")
        XCTAssertEqual(DockBadge.text(remaining: 59 * 60), "59m")
    }

    func testHoursUseHourMinuteFormat() {
        XCTAssertEqual(DockBadge.text(remaining: 60 * 60), "1h00")
        XCTAssertEqual(DockBadge.text(remaining: 65 * 60), "1h05")
        XCTAssertEqual(DockBadge.text(remaining: 64 * 60 + 1), "1h05")
        XCTAssertEqual(DockBadge.text(remaining: 5 * 3600), "5h00")
    }

    func testNextChangeIsOnTheMinute() throws {
        XCTAssertNil(DockBadge.secondsUntilChange(remaining: nil))
        XCTAssertNil(DockBadge.secondsUntilChange(remaining: 45))
        let delay = try XCTUnwrap(DockBadge.secondsUntilChange(remaining: 150))
        XCTAssertEqual(delay, 30.05, accuracy: 0.001)
        // Right on a minute boundary: the text changes a full minute later.
        XCTAssertEqual(try XCTUnwrap(DockBadge.secondsUntilChange(remaining: 120)), 60.05, accuracy: 0.001)
        // After waiting, the badge reads the next value.
        XCTAssertEqual(DockBadge.text(remaining: 150), "3m")
        XCTAssertEqual(DockBadge.text(remaining: 150 - delay), "2m")
    }
}
