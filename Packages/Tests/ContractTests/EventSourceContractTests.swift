import XCTest
import ProfileKit

/// T017 — skeleton for E-1..E-5 contract tests.
/// Fills out as US1/US2 event sources land (T025, T039).
final class EventSourceContractTests: XCTestCase {
    func testE1_CurrentStateYieldedImmediatelyOnFirstIteration() async {
        let source = ImmediateSource(initial: .ready)
        let start = Date()
        var firstValue: ImmediateSource.State?
        for await value in source.stream() {
            firstValue = value
            break
        }
        let latency = Date().timeIntervalSince(start)
        XCTAssertEqual(firstValue, .ready)
        XCTAssertLessThan(latency, 0.050, "first yield must arrive within 50 ms")
    }

    func testE4_StreamReturnsFast() async {
        let source = ImmediateSource(initial: .ready)
        let start = Date()
        _ = source.stream()
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.010, "stream() must return in < 10 ms")
    }

    func testE5_TearDownProducesFinishedStreamOnNextCall() async {
        let source = ImmediateSource(initial: .ready)
        source.tearDown()
        var count = 0
        for await _ in source.stream() { count += 1 }
        XCTAssertEqual(count, 0, "after tearDown, stream() yields no values")
    }
}

private final class ImmediateSource: EventSource {
    enum State: String, ProfileRuntimeState { case ready, active }

    typealias S = State
    private let initial: State
    private var torn = false

    init(initial: State) {
        self.initial = initial
    }

    func stream() -> AsyncStream<State> {
        AsyncStream { continuation in
            if torn {
                continuation.finish()
                return
            }
            continuation.yield(initial)
        }
    }

    func tearDown() { torn = true }
}
