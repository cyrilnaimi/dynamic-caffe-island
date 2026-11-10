import Foundation

/// The single channel through which a profile communicates state changes to
/// the arbitrator. Per `contracts/event-source-contract.md`:
///
/// - E-1: `stream()` must yield the current state immediately on first iteration.
/// - E-2: ≤ 30 Hz sustained. Debounce inside the source.
/// - E-3: Cancellation releases OS resources within 100 ms.
/// - E-4: `stream()` itself returns in < 10 ms on the main actor.
/// - E-5: `tearDown()` is idempotent; after it, `stream()` returns a finished stream.
/// - E-6: `Sendable`; internal state guarded by an actor or serial queue.
/// - E-7: Recoverable errors yielded as state; non-recoverable use `preconditionFailure`.
public protocol EventSource: AnyObject, Sendable {
    associatedtype State: ProfileRuntimeState

    func stream() -> AsyncStream<State>
    func tearDown()
}

public extension EventSource {
    /// Type-erase *self* into an `AnyEventSource`. Callable on `any EventSource`
    /// values because the existential's `Self` is opened at the call site.
    func erased() -> AnyEventSource {
        AnyEventSource(self)
    }
}
