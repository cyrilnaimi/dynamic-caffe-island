import BuiltInProfiles
import XCTest

final class CaffeCommandTests: XCTestCase {
    private func cmd(_ s: String) -> CaffeCommand? { CaffeCommand.parse(URL(string: s)!) }

    func testStartVariants() {
        XCTAssertEqual(cmd("caffe://start?minutes=45"), .start(minutes: 45))
        XCTAssertEqual(cmd("caffe://start?m=5"), .start(minutes: 5))
        XCTAssertEqual(cmd("caffe://start/90"), .start(minutes: 90))
        XCTAssertEqual(cmd("caffe://20"), .start(minutes: 20))
        XCTAssertEqual(cmd("caffe://start"), .start(minutes: CaffeCommand.defaultMinutes))
    }

    func testStartRejectsBadMinutes() {
        XCTAssertNil(cmd("caffe://start?minutes=0"))
        XCTAssertNil(cmd("caffe://start?minutes=-5"))
        XCTAssertNil(cmd("caffe://start?minutes=abc"))
        XCTAssertNil(cmd("caffe://start?minutes=99999"))
    }

    func testSimpleCommands() {
        XCTAssertEqual(cmd("caffe://stop"), .stop)
        XCTAssertEqual(cmd("caffe://OFF"), .stop)
        XCTAssertEqual(cmd("caffe://toggle"), .toggle)
        XCTAssertEqual(cmd("caffe://indefinite"), .indefinite)
        XCTAssertEqual(cmd("caffe://peek"), .peek)
        XCTAssertEqual(cmd("caffe://pick"), .pickTime)
        XCTAssertNil(cmd("caffe://explode"))
        XCTAssertNil(cmd("https://start"))
    }

    func testWhileVariants() {
        XCTAssertEqual(cmd("caffe://while?pid=4242"), .whileProcess(pid: 4242))
        XCTAssertEqual(cmd("caffe://while/4242"), .whileProcess(pid: 4242))
        XCTAssertEqual(cmd("caffe://while?app=Xcode"), .whileApp("Xcode"))
        XCTAssertEqual(cmd("caffe://while?bundle=com.apple.dt.Xcode"), .whileApp("com.apple.dt.Xcode"))
        XCTAssertEqual(cmd("caffe://while?app=Final%20Cut%20Pro"), .whileApp("Final Cut Pro"))
    }

    func testWhileRejectsBadInput() {
        XCTAssertNil(cmd("caffe://while"))
        XCTAssertNil(cmd("caffe://while?pid=abc"))
        XCTAssertNil(cmd("caffe://while?pid=0"))
        XCTAssertNil(cmd("caffe://while?pid=1"), "launchd never exits")
        XCTAssertNil(cmd("caffe://while?pid=-3"))
        XCTAssertNil(cmd("caffe://while?app=%20"))
    }

    func testSettings() {
        XCTAssertEqual(cmd("caffe://settings"), .settings)
        XCTAssertEqual(cmd("caffe://preferences"), .settings)
    }

    func testUntilVariants() {
        XCTAssertEqual(cmd("caffe://until?time=19:45"), .until(hour: 19, minute: 45))
        XCTAssertEqual(cmd("caffe://until/1945"), .until(hour: 19, minute: 45))
        XCTAssertEqual(cmd("caffe://until/7"), .until(hour: 7, minute: 0))
        XCTAssertEqual(cmd("caffe://until?t=08h05"), .until(hour: 8, minute: 5))
        XCTAssertNil(cmd("caffe://until?time=25:00"))
        XCTAssertNil(cmd("caffe://until?time=12:61"))
        XCTAssertNil(cmd("caffe://until"))
    }

    func testNextOccurrenceLaterToday() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 18, minute: 0))!
        let target = CaffeCommand.nextOccurrence(hour: 19, minute: 45, after: now, calendar: cal)
        XCTAssertEqual(target, cal.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 19, minute: 45)))
    }

    func testNextOccurrenceRollsToTomorrow() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 23, minute: 0))!
        let target = CaffeCommand.nextOccurrence(hour: 8, minute: 0, after: now, calendar: cal)
        XCTAssertEqual(target, cal.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 8, minute: 0)))
    }

    func testNextOccurrenceSameMinuteRollsToTomorrow() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 9, minute: 30))!
        let target = CaffeCommand.nextOccurrence(hour: 9, minute: 30, after: now, calendar: cal)
        XCTAssertEqual(cal.component(.day, from: target), 11)
    }
}
