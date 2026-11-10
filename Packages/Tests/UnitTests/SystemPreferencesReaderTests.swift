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

    func testParseLatestBlockExtractsCorrectly() {
        let output = """
        Battery Power:
         displaysleep        2
         sleep               5
        AC Power:
         displaysleep        10
         sleep               20
        """
        let parsed = ProcessSource.parseLatestBlock(output)
        // Last values win (the AC block here).
        XCTAssertEqual(parsed.displayMinutes, 10)
        XCTAssertEqual(parsed.sleepMinutes, 20)
    }

    func testParseHandlesMissingKeys() {
        let output = "Nothing useful here"
        let parsed = ProcessSource.parseLatestBlock(output)
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
