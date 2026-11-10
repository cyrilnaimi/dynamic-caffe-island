import XCTest
@testable import IslandCore
import ProfileKit

/// T046 — parameterized over all 5 failure modes from FR-025 / SC-007.
final class WatchdogTests: XCTestCase {
    private let profileID = ProfileID(raw: "test.profile")

    func testFailureMode_entrypointThrew() async throws {
        let w = Watchdog()
        w.profileActivated(profileID)
        let fired = expectation(description: "watchdog disables on 4th error")
        let task = Task { @Sendable in
            for await event in w.disableEvents {
                if event.profileID == self.profileID, case .entrypointThrew = event.reason {
                    fired.fulfill()
                }
                return
            }
        }
        for _ in 0..<4 {
            w.recordError(for: profileID)
        }
        await fulfillment(of: [fired], timeout: 1.0)
        task.cancel()
        XCTAssertTrue(w.isDisabled(profileID))
    }

    func testFailureMode_entrypointReturnedNil() async throws {
        let w = Watchdog()
        w.profileActivated(profileID)
        let fired = expectation(description: "disables on nil returns")
        let task = Task { @Sendable in
            for await event in w.disableEvents {
                if event.profileID == self.profileID, case .entrypointReturnedNil = event.reason {
                    fired.fulfill()
                }
                return
            }
        }
        for _ in 0..<4 { w.recordReturnedNil(for: profileID) }
        await fulfillment(of: [fired], timeout: 1.0)
        task.cancel()
    }

    func testFailureMode_entrypointHang() async throws {
        let w = Watchdog()
        w.profileActivated(profileID)
        let fired = expectation(description: "disables on frame-cost breach")
        let task = Task { @Sendable in
            for await event in w.disableEvents {
                if event.profileID == self.profileID, case .entrypointHang = event.reason {
                    fired.fulfill()
                }
                return
            }
        }
        // 60 frames at 20 ms each (well above the 10 ms average threshold).
        for _ in 0..<Watchdog.frameWindowSize {
            w.recordFrameCost(0.020, for: profileID)
        }
        await fulfillment(of: [fired], timeout: 1.0)
        task.cancel()
    }

    func testFailureMode_renderReentry() async throws {
        let w = Watchdog()
        w.profileActivated(profileID)
        let fired = expectation(description: "disables on re-entry")
        let task = Task { @Sendable in
            for await event in w.disableEvents {
                if event.profileID == self.profileID, case .renderReentry = event.reason {
                    fired.fulfill()
                }
                return
            }
        }
        w.recordRenderReentry(for: profileID)
        // Second call without renderExit → reentry.
        w.recordRenderReentry(for: profileID)
        await fulfillment(of: [fired], timeout: 1.0)
        task.cancel()
    }

    func testFailureMode_rssGrowthStorm() async throws {
        let w = Watchdog()
        let baseline: Int64 = 50 * 1024 * 1024
        w.profileActivated(profileID, rss: baseline)
        let fired = expectation(description: "disables on RSS growth")
        let task = Task { @Sendable in
            for await event in w.disableEvents {
                if event.profileID == self.profileID, case .rssGrowthStorm = event.reason {
                    fired.fulfill()
                }
                return
            }
        }
        // +25 MB within the window (> 20 MB threshold).
        w.recordRSS(baseline + 25 * 1024 * 1024, for: profileID)
        await fulfillment(of: [fired], timeout: 1.0)
        task.cancel()
    }

    func testBelowThresholdsDoesNotDisable() {
        let w = Watchdog()
        w.profileActivated(profileID)
        w.recordError(for: profileID)          // 1 error — below 3-per-60s threshold
        w.recordFrameCost(0.005, for: profileID) // 5 ms — below 10 ms threshold
        XCTAssertFalse(w.isDisabled(profileID))
    }

    func testDeactivationResetsMetrics() {
        let w = Watchdog()
        w.profileActivated(profileID)
        for _ in 0..<2 { w.recordError(for: profileID) }
        w.profileDeactivated(profileID)
        // Re-activate and record 2 more — should NOT trip since metrics reset.
        w.profileActivated(profileID)
        for _ in 0..<2 { w.recordError(for: profileID) }
        XCTAssertFalse(w.isDisabled(profileID))
    }
}
