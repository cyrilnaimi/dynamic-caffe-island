import Darwin
import Foundation
import OSLog
import PowerAssertions

/// Why the last session ended. Lets the UI explain an automatic stop
/// ("make finished") instead of a generic "coffee's over".
public enum CaffeineEndReason: Sendable, Equatable {
    case cancelled
    case expired
    case processExited(name: String)
}

public enum CaffeineSessionError: Error, Equatable, LocalizedError {
    /// `.whileProcess` was asked for a process that is not running.
    case processNotRunning(pid: Int32)

    public var errorDescription: String? {
        switch self {
        case let .processNotRunning(pid): return "process \(pid) is not running"
        }
    }
}

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
    private var processWatch: DispatchSourceProcess?
    private var endReason: CaffeineEndReason?
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

    /// Why the most recent session ended (`nil` before any session ended).
    /// Set before listeners are told about `.inactive`.
    public var lastEndReason: CaffeineEndReason? {
        lock.lock(); defer { lock.unlock() }
        return endReason
    }

    /// `true` while `pid` exists. `EPERM` means it exists but belongs to
    /// another user, which still counts as running.
    public static func isProcessRunning(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    // MARK: - Lifecycle

    @discardableResult
    public func startSession(duration: CaffeinationSession.Duration, now: Date = Date()) throws -> CaffeinationSession {
        let session = CaffeinationSession(startedAt: now, duration: duration)
        if let watched = session.watchedProcess, !Self.isProcessRunning(watched.pid) {
            throw CaffeineSessionError.processNotRunning(pid: watched.pid)
        }
        let handle = try AssertionHandle(
            name: "Caffe Island — \(session.id.uuidString.prefix(8))",
            client: client
        )

        lock.lock()
        // Cancel any prior session atomically (last-write-wins).
        expiryTimer?.cancel()
        expiryTimer = nil
        processWatch?.cancel()
        processWatch = nil
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

        // Event-driven process watch (kqueue NOTE_EXIT) — no polling.
        if let watched = session.watchedProcess {
            let source = DispatchSource.makeProcessSource(identifier: watched.pid, eventMask: .exit, queue: queue)
            source.setEventHandler { [weak self] in self?.processExited(sessionID: session.id) }
            source.resume()
            processWatch = source
        }
        let snapshot = listeners.values
        lock.unlock()

        // The process may have exited between the check above and the
        // kqueue registration, in which case the source never fires.
        if let watched = session.watchedProcess, !Self.isProcessRunning(watched.pid) {
            processExited(sessionID: session.id)
        }

        logger.info("started session id=\(session.id.uuidString.prefix(8), privacy: .public) duration=\(String(describing: duration), privacy: .public)")
        for listener in snapshot { listener(.active(session)) }
        return session
    }

    public func cancelSession(now _: Date = Date()) {
        endSession(reason: .cancelled)
    }

    private func endSession(reason: CaffeineEndReason) {
        lock.lock()
        let hadSession = state.session != nil
        expiryTimer?.cancel()
        expiryTimer = nil
        processWatch?.cancel()
        processWatch = nil
        assertionHandle?.release()
        assertionHandle = nil
        state = .inactive
        if hadSession { endReason = reason }
        let snapshot = listeners.values
        lock.unlock()
        logger.info("ended session reason=\(String(describing: reason), privacy: .public)")
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
        // Only end *this* session: a new one started during the dwell wins.
        queue.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.currentSession?.id == session.id else { return }
            self.endSession(reason: .expired)
        }
    }

    private func processExited(sessionID: UUID) {
        lock.lock()
        guard let session = state.session, session.id == sessionID, let watched = session.watchedProcess else {
            lock.unlock()
            return
        }
        lock.unlock()
        logger.info("watched process \(watched.pid) exited")
        endSession(reason: .processExited(name: watched.name))
    }
}
