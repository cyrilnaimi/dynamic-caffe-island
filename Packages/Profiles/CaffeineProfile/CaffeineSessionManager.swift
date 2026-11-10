import Foundation
import OSLog
import PowerAssertions

/// Owns the lifecycle of exactly one caffeine session at a time.
///
/// Thread-safe via an internal `NSLock`; callable from the main actor or any
/// background queue. State changes broadcast to every currently-subscribed
/// event-source stream.
///
/// Injects a `PowerAssertionClient` so tests can swap in
/// `FakePowerAssertionClient`.
public final class CaffeineSessionManager: @unchecked Sendable {
    public typealias Listener = @Sendable (CaffeineState) -> Void

    private let lock = NSLock()
    private let client: any PowerAssertionClient
    private let queue: DispatchQueue
    private let logger = Logger(subsystem: "ch.dynamic-caffe-island.caffeine", category: "session")

    private var state: CaffeineState = .inactive
    private var assertionHandle: AssertionHandle?
    private var expiryTimer: DispatchSourceTimer?
    private var listeners: [UUID: Listener] = [:]

    public init(client: any PowerAssertionClient = LivePowerAssertionClient(), queue: DispatchQueue = DispatchQueue(label: "ch.dynamic-caffe-island.caffeine.session")) {
        self.client = client
        self.queue = queue
    }

    // MARK: - Public state

    public var currentState: CaffeineState {
        lock.lock(); defer { lock.unlock() }
        return state
    }

    public var currentSession: CaffeinationSession? {
        currentState.session
    }

    // MARK: - Lifecycle

    @discardableResult
    public func startSession(duration: CaffeinationSession.Duration, now: Date = Date()) throws -> CaffeinationSession {
        let session = CaffeinationSession(startedAt: now, duration: duration)
        let handle = try AssertionHandle(
            name: "Dynamic Caffe Island — \(session.id.uuidString.prefix(8))",
            client: client
        )

        lock.lock()
        // Cancel any prior session atomically (last-write-wins).
        expiryTimer?.cancel()
        expiryTimer = nil
        assertionHandle?.release()
        assertionHandle = handle
        state = .active(session)

        // Schedule expiry for preset + untilClockTime.
        if let end = session.expectedEnd {
            let interval = max(0, end.timeIntervalSince(now))
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + interval)
            timer.setEventHandler { [weak self] in self?.expire() }
            timer.resume()
            expiryTimer = timer
        }
        let snapshot = listeners.values
        lock.unlock()

        logger.info("started session id=\(session.id.uuidString.prefix(8), privacy: .public) duration=\(String(describing: duration), privacy: .public)")
        for listener in snapshot { listener(.active(session)) }
        return session
    }

    public func cancelSession(now _: Date = Date()) {
        lock.lock()
        expiryTimer?.cancel()
        expiryTimer = nil
        assertionHandle?.release()
        assertionHandle = nil
        state = .inactive
        let snapshot = listeners.values
        lock.unlock()
        logger.info("cancelled session")
        for listener in snapshot { listener(.inactive) }
    }

    // MARK: - Listener subscription (the EventSource uses this)

    public func subscribe(_ listener: @escaping Listener) -> UUID {
        let id = UUID()
        lock.lock()
        listeners[id] = listener
        let current = state
        lock.unlock()
        listener(current)                      // E-1 immediate yield
        return id
    }

    public func unsubscribe(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        listeners.removeValue(forKey: id)
    }

    // MARK: - Internal

    private func expire() {
        lock.lock()
        guard let session = state.session else {
            lock.unlock()
            return
        }
        // Brief .expiring window before release. (The animation checkpoint's
        // expiry sequence lives in the view layer; this is the semantic state.)
        state = .expiring(session)
        let listenersSnapshot = listeners.values
        lock.unlock()

        for listener in listenersSnapshot { listener(.expiring(session)) }

        // Schedule release after a short dwell for the view to animate.
        queue.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.cancelSession()
        }
    }
}
