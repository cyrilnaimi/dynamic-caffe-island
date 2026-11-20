import XCTest
@testable import BuiltInProfiles
@testable import SleepClock

/// T037-adjacent — SystemPreferencesReader with a fake source.
final class SystemPreferencesReaderTests: XCTestCase {
    func testSnapshotHonorsZeroMeansDisabled() {
        let fake = FakePrefsSource(display: 0, sleep: 0, screensaver: 0)
        let reader = SystemPreferencesReader(source: fake)
        let s = reader.snapshot
        XCTAssertNil(s.displaySleepAfter, "pmset 0 means never → nil")
        XCTAssertNil(s.systemSleepAfter, "pmset 0 means never → nil")
        XCTAssertNil(s.screensaverAfter, "screensaver 0 means never → nil")
    }

    func testSnapshotConvertsMinutesToSeconds() {
        let fake = FakePrefsSource(display: 5, sleep: 20, screensaver: 600)
        let reader = SystemPreferencesReader(source: fake)
        let s = reader.snapshot
        XCTAssertEqual(s.displaySleepAfter, 300)
        XCTAssertEqual(s.systemSleepAfter, 1200)
        XCTAssertEqual(s.screensaverAfter, 600, "screensaver already in seconds")
    }

    func testInputsBuilderComposes() {
        let fake = FakePrefsSource(display: 5, sleep: 10, screensaver: 300)
        let reader = SystemPreferencesReader(source: fake)
        let inputs = reader.inputs(secondsSinceLastInput: 30, caffeinationActive: false)
        XCTAssertEqual(inputs.displaySleepAfter, 300)
        XCTAssertEqual(inputs.secondsSinceLastInput, 30)
        XCTAssertFalse(inputs.caffeinationActive)
    }

    private let laptopOutput = """
    Battery Power:
     Sleep On Power Button 1
     displaysleep         2
     sleep                5
     disksleep            10
    AC Power:
     Sleep On Power Button 1
     displaysleep         10
     sleep                20 (sleep prevented by caffeinate)
     disksleep            10
    """

    func testParseUsesBatteryBlockOnBattery() {
        let parsed = ProcessSource.parse(laptopOutput, powerSource: "Battery Power")
        XCTAssertEqual(parsed.displayMinutes, 2)
        XCTAssertEqual(parsed.sleepMinutes, 5)
    }

    func testParseUsesACBlockOnAC() {
        let parsed = ProcessSource.parse(laptopOutput, powerSource: "AC Power")
        XCTAssertEqual(parsed.displayMinutes, 10)
        XCTAssertEqual(parsed.sleepMinutes, 20)
    }

    func testParseDesktopWithOnlyACBlock() {
        let output = """
        AC Power:
         displaysleep         15
         sleep                0
        """
        let parsed = ProcessSource.parse(output, powerSource: nil)
        XCTAssertEqual(parsed.displayMinutes, 15)
        XCTAssertEqual(parsed.sleepMinutes, 0)
    }

    func testParseHandlesMissingKeys() {
        let output = "Nothing useful here"
        let parsed = ProcessSource.parse(output, powerSource: "AC Power")
        XCTAssertNil(parsed.displayMinutes)
        XCTAssertNil(parsed.sleepMinutes)
    }
}

struct FakePrefsSource: SystemPreferencesReader.Source {
    let display: Int?
    let sleep: Int?
    let screensaver: Int?

    init(display: Int?, sleep: Int?, screensaver: Int?) {
        self.display = display
        self.sleep = sleep
        self.screensaver = screensaver
    }

    func readPMSettings() -> (displayMinutes: Int?, sleepMinutes: Int?) {
        (display, sleep)
    }
    func readScreensaverSeconds() -> Int? { screensaver }
}
