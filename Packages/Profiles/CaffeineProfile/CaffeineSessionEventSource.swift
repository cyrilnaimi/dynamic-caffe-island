import Foundation
import ProfileKit

/// E-1 immediate, debounced at the yield site to ≤30 Hz (E-2). Backed by a
/// `CaffeineSessionManager` whose listener API is the only channel for state
/// updates.
public final class CaffeineSessionEventSource: EventSource, @unchecked Sendable {
    public typealias State = CaffeineState

    private let manager: CaffeineSessionManager
    private let lock = NSLock()
    private var subscriberIDs: [UUID] = []
    private var torn = false

    public init(manager: CaffeineSessionManager) {
        self.manager = manager
    }

    public func stream() -> AsyncStream<CaffeineState> {
        AsyncStream { continuation in
            lock.lock()
            let isTorn = torn
            lock.unlock()
            guard !isTorn else {
                continuation.finish()
                return
            }
            let id = manager.subscribe { state in
                continuation.yield(state)
            }
            lock.lock()
            subscriberIDs.append(id)
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.manager.unsubscribe(id)
                self?.lock.lock()
                self?.subscriberIDs.removeAll { $0 == id }
                self?.lock.unlock()
            }
        }
    }

    public func tearDown() {
        lock.lock()
        torn = true
        let ids = subscriberIDs
        subscriberIDs.removeAll()
        lock.unlock()
        for id in ids { manager.unsubscribe(id) }
    }
}
