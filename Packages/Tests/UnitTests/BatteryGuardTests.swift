import PowerAssertions
import XCTest

final class BatteryGuardTests: XCTestCase {
    private func power(_ percent: Int, ac: Bool) -> PowerSourceSnapshot {
        PowerSourceSnapshot(hasBattery: true, batteryPercent: percent, onACPower: ac)
    }

    func testDisabledAlwaysAllows() {
        let guardOff = BatteryGuard()
        XCTAssertFalse(guardOff.isEnabled)
        XCTAssertEqual(guardOff.verdict(for: power(3, ac: false)), .allow)
    }

    func testThresholdStopsOnBattery() {
        let g = BatteryGuard(threshold: 20)
        XCTAssertEqual(g.verdict(for: power(21, ac: false)), .allow)
        XCTAssertEqual(g.verdict(for: power(20, ac: false)), .batteryLow(percent: 20, threshold: 20))
        XCTAssertEqual(g.verdict(for: power(5, ac: false)), .batteryLow(percent: 5, threshold: 20))
    }

    func testThresholdIgnoredWhileCharging() {
        XCTAssertEqual(BatteryGuard(threshold: 30).verdict(for: power(10, ac: true)), .allow)
    }

    func testOnlyOnPowerAdapter() {
        let g = BatteryGuard(onlyOnPowerAdapter: true)
        XCTAssertEqual(g.verdict(for: power(100, ac: false)), .onBattery)
        XCTAssertEqual(g.verdict(for: power(100, ac: true)), .allow)
    }

    func testDesktopWithoutBatteryUnaffected() {
        let g = BatteryGuard(threshold: 30, onlyOnPowerAdapter: true)
        XCTAssertEqual(g.verdict(for: .desktop), .allow)
        XCTAssertEqual(g.verdict(for: PowerSourceSnapshot(hasBattery: false, batteryPercent: 0, onACPower: false)), .allow)
    }
}
