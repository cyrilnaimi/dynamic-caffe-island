import Foundation

/// Type-erased wrapper for `any EventSource`. The registry stores one of
/// these per active profile so it can subscribe without opening the
/// existential at every call site.
public final class AnyEventSource: @unchecked Sendable {
    private let _stream: @Sendable () -> AsyncStream<AnyProfileState>
    private let _tearDown: @Sendable () -> Void

    public init<E: EventSource>(_ source: E) {
        self._stream = {
            let typedStream = source.stream()
            return AsyncStream { continuation in
                let task = Task {
                    for await value in typedStream {
                        continuation.yield(AnyProfileState.wrap(value))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
        self._tearDown = { source.tearDown() }
    }

    public func stream() -> AsyncStream<AnyProfileState> { _stream() }
    public func tearDown() { _tearDown() }
}
