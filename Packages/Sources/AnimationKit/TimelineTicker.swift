import Foundation
import OSLog

/// Shared adaptive-rate frame scheduler. Three rates per research R-07:
///
///   - `.idle`         → 1 Hz (sleep countdown heartbeat; minimal power).
///   - `.transitioning`→ 30 Hz (during a profile state transition).
///   - `.active`       → 60 Hz (during a matched-geometry animation).
///
/// The ticker coalesces requests from subscribers; the effective rate is the
/// max requested. One `Timer`-equivalent in the whole app (per the plan's
/// "no raw Timer" guidance).
public final class TimelineTicker: @unchecked Sendable {
    public static let shared = TimelineTicker()

    public enum Rate: Int, Sendable, Comparable {
        case paused = 0
        case idle = 1
        case transitioning = 30
        case active = 60

        public static func < (lhs: Rate, rhs: Rate) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        public var interval: TimeInterval? {
            switch self {
            case .paused: return nil
            case .idle: return 1.0
            case .transitioning: return 1.0 / 30.0
            case .active: return 1.0 / 60.0
            }
        }
    }

    public struct Subscription: Sendable {
        public let id: UUID
        private let _cancel: @Sendable () -> Void

        init(id: UUID, cancel: @escaping @Sendable () -> Void) {
            self.id = id
            self._cancel = cancel
        }

        public func cancel() { _cancel() }
    }

    private struct Entry {
        let id: UUID
        let requestedRate: Rate
        let callback: @Sendable () -> Void
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var timer: DispatchSourceTimer?
    private var currentRate: Rate = .paused
    private let queue = DispatchQueue(label: "ch.dynamic-caffe-island.animationkit.ticker")
    private let logger = Logger(subsystem: "ch.dynamic-caffe-island.animationkit", category: "ticker")
    /// Last time a tick fired — used for latency probes (T063a).
    public private(set) var lastFrameAt: Date?

    public init() {}

    @discardableResult
    public func subscribe(rate: Rate = .idle, _ callback: @escaping @Sendable () -> Void) -> Subscription {
        let id = UUID()
        lock.lock()
        entries.append(Entry(id: id, requestedRate: rate, callback: callback))
        reconfigureLocked()
        lock.unlock()
        return Subscription(id: id, cancel: { [weak self] in self?.cancel(id: id) })
    }

    public func cancel(id: UUID) {
        lock.lock()
        entries.removeAll { $0.id == id }
        reconfigureLocked()
        lock.unlock()
    }

    public func cancelAll() {
        lock.lock()
        entries.removeAll()
        reconfigureLocked()
        lock.unlock()
    }

    public func pause() {
        lock.lock()
        timer?.cancel()
        timer = nil
        currentRate = .paused
        lock.unlock()
    }

    public func resume() {
        lock.lock()
        reconfigureLocked()
        lock.unlock()
    }

    /// Bumps effective rate upward for the duration of a transition. Used by
    /// slot-split/rejoin animations.
    public func requestRate(_ rate: Rate, for duration: TimeInterval) -> Subscription {
        let sub = subscribe(rate: rate) { /* rate-only request */ }
        let id = sub.id
        queue.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.cancel(id: id)
        }
        return sub
    }

    // MARK: - Internals

    private func reconfigureLocked() {
        let desired = entries.map(\.requestedRate).max() ?? .paused
        guard desired != currentRate else { return }
        timer?.cancel()
        timer = nil
        currentRate = desired
        guard let interval = desired.interval else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in self?.fire() }
        t.resume()
        timer = t
    }

    private func fire() {
        lock.lock()
        lastFrameAt = Date()
        let snapshot = entries
        lock.unlock()
        for entry in snapshot {
            entry.callback()
        }
    }
}
