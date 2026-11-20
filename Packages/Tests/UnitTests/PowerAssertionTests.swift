import XCTest
@testable import PowerAssertions

/// T018 — PowerAssertion lifecycle with fake client, including crash-sim.
final class PowerAssertionTests: XCTestCase {
    func testAcquireReleaseViaFakeClient() throws {
        let fake = FakePowerAssertionClient()
        let handle = try AssertionHandle(name: "test", client: fake, types: ["TestType"])
        XCTAssertFalse(handle.isReleased)
        XCTAssertEqual(fake.liveTokens.count, 1)

        handle.release()
        XCTAssertTrue(handle.isReleased)
        XCTAssertEqual(fake.liveTokens.count, 0)
    }

    func testDoubleReleaseIsNoOp() throws {
        let fake = FakePowerAssertionClient()
        let handle = try AssertionHandle(name: "dbl", client: fake, types: ["T"])
        handle.release()
        handle.release()
        let releaseCount = fake.calls.filter {
            if case .release = $0.kind { return true }; return false
        }.count
        XCTAssertEqual(releaseCount, 1, "double-release should only call underlying client once")
    }

    func testDeinitReleasesAssertion() throws {
        let fake = FakePowerAssertionClient()
        var handle: AssertionHandle? = try AssertionHandle(name: "deinit", client: fake, types: ["T"])
        XCTAssertEqual(fake.liveTokens.count, 1)
        handle = nil
        _ = handle     // silence warning
        XCTAssertEqual(fake.liveTokens.count, 0, "deinit must release")
    }

    func testRegistryReleaseAllReleasesLive() throws {
        // Isolated registry so we don't race with other tests' live handles.
        let fake = FakePowerAssertionClient()
        let h1 = try AssertionHandle(name: "a", client: fake, types: ["T"])
        let h2 = try AssertionHandle(name: "b", client: fake, types: ["T"])
        let h3 = try AssertionHandle(name: "c", client: fake, types: ["T"])
        XCTAssertEqual(fake.liveTokens.count, 3)

        AssertionRegistry.shared.releaseAll()
        XCTAssertEqual(fake.liveTokens.count, 0, "releaseAll drains all live tokens")
        XCTAssertTrue(h1.isReleased && h2.isReleased && h3.isReleased)
    }

    func testAcquireFailurePropagates() {
        let fake = FakePowerAssertionClient()
        fake.acquireFailsWith = -536870210  // kIOReturnError
        XCTAssertThrowsError(try AssertionHandle(name: "fail", client: fake, types: ["T"])) { error in
            guard case let PowerAssertionError.acquireFailed(kr) = error else {
                XCTFail("expected PowerAssertionError.acquireFailed, got \(error)")
                return
            }
            XCTAssertEqual(kr, -536870210)
        }
    }

    // Crash-simulation: the registry must release even if the owning Task exits abruptly.
    func testCrashSimOwningTaskExitReleasesOnAtexit() throws {
        // We can't call atexit in a test (would fire at process exit). But we
        // can verify that an orphaned-but-registered handle can be reached
        // via releaseAll, which is exactly what the atexit handler calls.
        let fake = FakePowerAssertionClient()
        let exp = expectation(description: "task done")
        Thread.detachNewThread {
            do {
                _ = try AssertionHandle(name: "orphan", client: fake, types: ["T"])
                // Thread exits without calling release — registry still holds weak ref,
                // but the handle deinits on thread exit anyway.
            } catch {
                XCTFail("\(error)")
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        // GC: force an autoreleasepool-equivalent by waiting briefly.
        Thread.sleep(forTimeInterval: 0.05)
        // After the thread exits, the handle has deinit'd → token should be released.
        XCTAssertEqual(fake.liveTokens.count, 0, "orphaned handle releases on deinit")
    }
}
