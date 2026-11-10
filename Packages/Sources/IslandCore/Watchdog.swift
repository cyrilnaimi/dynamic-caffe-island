import Foundation
import OSLog
import ProfileKit

/// Per-profile auto-disable watchdog. Monitors the five failure modes
/// enumerated in spec §FR-025 / §SC-007:
///
///   1. entrypoint throws
///   2. entrypoint returns nil where non-nil is required
///   3. entrypoint hangs past the 10 ms average wall-time watchdog
///   4. entrypoint re-enters the pill rendering path
///   5. process-wide RSS growth > 20 MB / 60 s after profile activation
///
/// Thresholds locked at checkpoint 03 §4.2 (Q-A3 "keep").
public final class Watchdog: @unchecked Sendable {
    // Thresholds per checkpoint 03 §4.2
    public static let errorsPerMinuteLimit = 3
    public static let errorWindow: TimeInterval = 60
    public static let frameBudgetAverage: TimeInterval = 0.010   // 10 ms
    public static let frameWindowSize = 60                        // 60-frame rolling window
    public static let rssGrowthBytes: Int64 = 20 * 1024 * 1024    // 20 MB
    public static let rssGrowthWindow: TimeInterval = 60

    public enum FailureMode: Sendable, Equatable, CustomStringConvertible {
        case entrypointThrew
        case entrypointReturnedNil
        case entrypointHang(averageMs: Double)
        case renderReentry
        case rssGrowthStorm(deltaBytes: Int64)

        public var description: String {
            switch self {
            case .entrypointThrew: return "entrypointThrew"
            case .entrypointReturnedNil: return "entrypointReturnedNil"
            case let .entrypointHang(avg): return "entrypointHang(avgMs=\(avg))"
            case .renderReentry: return "renderReentry"
            case let .rssGrowthStorm(delta): return "rssGrowthStorm(delta=\(delta))"
            }
        }
    }

    public struct DisableEvent: Sendable, Equatable {
        public let profileID: ProfileID
        public let reason: FailureMode
        public let at: Date
    }

    private struct ProfileMetrics {
        var errors: [Date] = []
        var frameCosts: [TimeInterval] = []
        var activatedAt: Date = Date()
        var baselineRSS: Int64 = 0
        var currentRSS: Int64 = 0
        var inRenderPath: Bool = false
        var disabled: Bool = false
    }

    private let lock = NSLock()
    private var metrics: [ProfileID: ProfileMetrics] = [:]
    private let disableContinuation: AsyncStream<DisableEvent>.Continuation
    public nonisolated let disableEvents: AsyncStream<DisableEvent>
    private let logger = Logger(subsystem: "ch.dynamic-caffe-island.islandcore", category: "watchdog")

    public init() {
        var cont: AsyncStream<DisableEvent>.Continuation!
        let stream = AsyncStream<DisableEvent> { c in cont = c }
        self.disableContinuation = cont
        self.disableEvents = stream
    }

    // MARK: - Activation / deactivation

    public func profileActivated(_ id: ProfileID, rss baselineRSS: Int64 = currentProcessRSS(), now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        var m = ProfileMetrics()
        m.activatedAt = now
        m.baselineRSS = baselineRSS
        m.currentRSS = baselineRSS
        metrics[id] = m
    }

    public func profileDeactivated(_ id: ProfileID) {
        lock.lock(); defer { lock.unlock() }
        metrics.removeValue(forKey: id)
    }

    // MARK: - Failure-mode reporting

    public func recordError(for id: ProfileID, mode: FailureMode = .entrypointThrew, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        guard var m = metrics[id], !m.disabled else { return }
        m.errors = m.errors.filter { now.timeIntervalSince($0) < Self.errorWindow }
        m.errors.append(now)
        metrics[id] = m
        if m.errors.count > Self.errorsPerMinuteLimit {
            disableLocked(id: id, reason: mode, now: now)
        } else {
            logger.warning("profile \(id.raw, privacy: .public) error #\(m.errors.count, privacy: .public): \(String(describing: mode), privacy: .public)")
        }
    }

    public func recordReturnedNil(for id: ProfileID, now: Date = Date()) {
        recordError(for: id, mode: .entrypointReturnedNil, now: now)
    }

    public func recordFrameCost(_ cost: TimeInterval, for id: ProfileID, now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        guard var m = metrics[id], !m.disabled else { return }
        m.frameCosts.append(cost)
        if m.frameCosts.count > Self.frameWindowSize {
            m.frameCosts.removeFirst(m.frameCosts.count - Self.frameWindowSize)
        }
        metrics[id] = m
        if m.frameCosts.count == Self.frameWindowSize {
            let avg = m.frameCosts.reduce(0, +) / Double(m.frameCosts.count)
            if avg > Self.frameBudgetAverage {
                disableLocked(id: id, reason: .entrypointHang(averageMs: avg * 1000), now: now)
            }
        }
    }

    public func recordRenderReentry(for id: ProfileID, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        guard var m = metrics[id], !m.disabled else { return }
        if m.inRenderPath {
            disableLocked(id: id, reason: .renderReentry, now: now)
            return
        }
        m.inRenderPath = true
        metrics[id] = m
    }

    public func renderExit(for id: ProfileID) {
        lock.lock(); defer { lock.unlock() }
        guard var m = metrics[id] else { return }
        m.inRenderPath = false
        metrics[id] = m
    }

    public func recordRSS(_ rss: Int64, for id: ProfileID, now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        guard var m = metrics[id], !m.disabled else { return }
        m.currentRSS = rss
        metrics[id] = m
        if now.timeIntervalSince(m.activatedAt) <= Self.rssGrowthWindow {
            let delta = rss - m.baselineRSS
            if delta > Self.rssGrowthBytes {
                disableLocked(id: id, reason: .rssGrowthStorm(deltaBytes: delta), now: now)
            }
        }
    }

    // MARK: - Query

    public func isDisabled(_ id: ProfileID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return metrics[id]?.disabled ?? false
    }

    // MARK: - Internals

    private func disableLocked(id: ProfileID, reason: FailureMode, now: Date) {
        guard var m = metrics[id], !m.disabled else { return }
        m.disabled = true
        metrics[id] = m
        logger.error("auto-disabled \(id.raw, privacy: .public) reason=\(String(describing: reason), privacy: .public)")
        disableContinuation.yield(DisableEvent(profileID: id, reason: reason, at: now))
    }
}

/// Whole-process resident set size via Mach `task_info` — same number
/// reported by `top -l N`. See plan.md Phase 0 R-09.
public func currentProcessRSS() -> Int64 {
    var info = mach_task_basic_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) { infoPtr -> kern_return_t in
        infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr -> kern_return_t in
            task_info(
                mach_task_self_,
                task_flavor_t(MACH_TASK_BASIC_INFO),
                ptr,
                &count
            )
        }
    }
    guard kr == KERN_SUCCESS else { return 0 }
    return Int64(info.resident_size)
}
