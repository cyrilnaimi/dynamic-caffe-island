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
/// Thread-safe; callable from the main actor or any background queue.
///
/// - State lives under `lock`. Every change bumps `version`.
/// - Listeners are notified through `publishLatest()`, serialised by
///   `deliveryLock`, and always receive the manager's *current* state, so
///   two changes made on different threads can't reach listeners in the
///   reverse order (a stale `.inactive` after a newer `.active`).
/// - Expiry, the expiry dwell and process exit carry the id of the session
///   they were scheduled for and only end that session.
///
/// Listeners must not call back into `startSession` / `cancelSession`
/// synchronously (the event source only yields into an `AsyncStream`).
///
/// Injects a `PowerAssertionClient` so tests can swap in
/// `FakePowerAssertionClient`.
public final class CaffeineSessionManager: @unchecked Sendable {
    public typealias Listener = @Sendable (CaffeineState) -> Void

    /// How long `.expiring` lasts before the assertion is released, so the
    /// view can animate the end.
    static let expiryDwell: TimeInterval = 0.6

    private let lock = NSLock()
    /// Lock order: `deliveryLock` before `lock`, never the reverse.
    private let deliveryLock = NSLock()
    private let client: any PowerAssertionClient
    private let queue: DispatchQueue
    private let logger = Logger(subsystem: "ch.dynamic-caffe-island.caffeine", category: "session")

    private var state: CaffeineState = .inactive
    private var version: UInt64 = 0
    private var deliveredVersion: UInt64 = 0
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
        tearDownLocked()
        assertionHandle = handle
        setStateLocked(.active(session))

        // Schedule expiry for preset + untilClockTime.
        if let end = session.expectedEnd {
            scheduleExpiryLocked(sessionID: session.id, in: max(0, end.timeIntervalSince(now)))
        }

        // Event-driven process watch (kqueue NOTE_EXIT) — no polling.
        if let watched = session.watchedProcess {
            let source = DispatchSource.makeProcessSource(identifier: watched.pid, eventMask: .exit, queue: queue)
            source.setEventHandler { [weak self] in self?.processExited(sessionID: session.id) }
            source.resume()
            processWatch = source
        }
        lock.unlock()

        logger.info("started session id=\(session.id.uuidString.prefix(8), privacy: .public) duration=\(String(describing: duration), privacy: .public)")
        publishLatest()

        // The process may have exited between the check above and the
        // kqueue registration, in which case the source never fires.
        if let watched = session.watchedProcess, !Self.isProcessRunning(watched.pid) {
            processExited(sessionID: session.id)
        }
        return session
    }

    public func cancelSession(now _: Date = Date()) {
        endSession(reason: .cancelled, onlyIf: nil)
    }

    /// Call after the Mac wakes. The expiry timer runs on wall-clock time,
    /// so it already accounts for sleep; this ends a session whose end
    /// passed during sleep right away instead of waiting for timer
    /// coalescing, and re-arms the timer otherwise.
    public func systemDidWake(now: Date = Date()) {
        lock.lock()
        guard case let .active(session) = state, let end = session.expectedEnd else {
            lock.unlock()
            return
        }
        let left = end.timeIntervalSince(now)
        if left > 0 {
            scheduleExpiryLocked(sessionID: session.id, in: left)
            lock.unlock()
            return
        }
        lock.unlock()
        expire(sessionID: session.id)
    }

    // MARK: - Listener subscription (the EventSource uses this)

    public func subscribe(_ listener: @escaping Listener) -> UUID {
        let id = UUID()
        // Hold the delivery lock so no newer state can reach this listener
        // before its initial one.
        deliveryLock.lock()
        lock.lock()
        listeners[id] = listener
        let current = state
        lock.unlock()
        listener(current)                      // E-1 immediate yield
        deliveryLock.unlock()
        return id
    }

    public func unsubscribe(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        listeners.removeValue(forKey: id)
    }

    // MARK: - Internal (internal rather than private for unit tests)

    /// Ends the current session, or — when `sessionID` is given — only if
    /// that session is still the current one. The check and the teardown
    /// happen under one lock hold, so a session started in between is
    /// never ended by mistake.
    func endSession(reason: CaffeineEndReason, onlyIf sessionID: UUID?) {
        lock.lock()
        if let sessionID, state.session?.id != sessionID {
            lock.unlock()
            return
        }
        let hadSession = state.session != nil
        tearDownLocked()
        if hadSession { endReason = reason }
        setStateLocked(.inactive)
        lock.unlock()
        logger.info("ended session reason=\(String(describing: reason), privacy: .public)")
        publishLatest()
    }

    func expire(sessionID: UUID) {
        lock.lock()
        guard case let .active(session) = state, session.id == sessionID else {
            lock.unlock()
            return
        }
        expiryTimer?.cancel()
        expiryTimer = nil
        // Brief .expiring window before release. (The animation checkpoint's
        // expiry sequence lives in the view layer; this is the semantic state.)
        setStateLocked(.expiring(session))
        lock.unlock()
        publishLatest()

        // Only end *this* session: a new one started during the dwell wins.
        queue.asyncAfter(deadline: .now() + Self.expiryDwell) { [weak self] in
            self?.endSession(reason: .expired, onlyIf: sessionID)
        }
    }

    func processExited(sessionID: UUID) {
        lock.lock()
        let watched = state.session.flatMap { $0.id == sessionID ? $0.watchedProcess : nil }
        lock.unlock()
        guard let watched else { return }
        logger.info("watched process \(watched.pid) exited")
        endSession(reason: .processExited(name: watched.name), onlyIf: sessionID)
    }

    // MARK: - Private

    /// Caller holds `lock`.
    private func setStateLocked(_ new: CaffeineState) {
        state = new
        version &+= 1
    }

    /// Caller holds `lock`.
    private func tearDownLocked() {
        expiryTimer?.cancel()
        expiryTimer = nil
        processWatch?.cancel()
        processWatch = nil
        assertionHandle?.release()
        assertionHandle = nil
    }

    /// Wall-clock deadline: `DispatchTime` (mach absolute time) stops while
    /// the Mac sleeps, `DispatchWallTime` doesn't, so a session ends at the
    /// time the UI shows even if the lid was closed. Caller holds `lock`.
    private func scheduleExpiryLocked(sessionID: UUID, in interval: TimeInterval) {
        expiryTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(wallDeadline: .now() + interval, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.expire(sessionID: sessionID) }
        timer.resume()
        expiryTimer = timer
    }

    /// Sends the current state to every listener unless a newer delivery
    /// already did. Whichever call delivers last carries the newest state.
    private func publishLatest() {
        deliveryLock.lock()
        defer { deliveryLock.unlock() }
        lock.lock()
        let current = state
        let currentVersion = version
        let snapshot = Array(listeners.values)
        lock.unlock()
        guard currentVersion > deliveredVersion else { return }
        deliveredVersion = currentVersion
        for listener in snapshot { listener(current) }
    }
}
