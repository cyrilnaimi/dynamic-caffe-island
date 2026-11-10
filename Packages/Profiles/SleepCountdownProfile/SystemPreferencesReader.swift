import Foundation
import OSLog
import SleepClock

/// Reads the three sleep-related OS settings that drive the Sleep Countdown
/// profile: `displaysleep`, `sleep` (system sleep), and screensaver
/// `idleTime`. Re-reads on `com.apple.powerManagementPreferencesChanged`
/// and `com.apple.screensaver.didchange` distributed notifications — NEVER
/// in a polling loop (FR-030).
///
/// Exposes the current values via a `snapshot` struct that the event source
/// reads each tick. Tests swap in a fake via the `Source` protocol.
public final class SystemPreferencesReader: @unchecked Sendable {
    public struct Snapshot: Sendable, Equatable {
        public var displaySleepAfter: TimeInterval?
        public var screensaverAfter: TimeInterval?
        public var systemSleepAfter: TimeInterval?

        public init(
            displaySleepAfter: TimeInterval? = nil,
            screensaverAfter: TimeInterval? = nil,
            systemSleepAfter: TimeInterval? = nil
        ) {
            self.displaySleepAfter = displaySleepAfter
            self.screensaverAfter = screensaverAfter
            self.systemSleepAfter = systemSleepAfter
        }
    }

    public protocol Source: Sendable {
        func readPMSettings() -> (displayMinutes: Int?, sleepMinutes: Int?)
        func readScreensaverSeconds() -> Int?
    }

    private let source: Source
    private let lock = NSLock()
    private var current: Snapshot = Snapshot()
    private var observers: [UUID: @Sendable (Snapshot) -> Void] = [:]
    private let logger = Logger(subsystem: "ch.dynamic-caffe-island.sleepclock", category: "prefs-reader")
    private var notificationObservers: [NSObjectProtocol] = []
    private let center = DistributedNotificationCenter.default()
    private let queue = OperationQueue.main

    public init(source: Source = ProcessSource()) {
        self.source = source
        refresh()
        installObservers()
    }

    deinit {
        for obs in notificationObservers {
            center.removeObserver(obs)
        }
    }

    public var snapshot: Snapshot {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    @discardableResult
    public func subscribe(_ listener: @escaping @Sendable (Snapshot) -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        observers[id] = listener
        let c = current
        lock.unlock()
        listener(c)                          // yield current on subscribe
        return id
    }

    public func unsubscribe(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        observers.removeValue(forKey: id)
    }

    public func refresh() {
        let pm = source.readPMSettings()
        let ss = source.readScreensaverSeconds()
        let new = Snapshot(
            displaySleepAfter: pm.displayMinutes.map { $0 == 0 ? nil : TimeInterval($0 * 60) } ?? nil,
            screensaverAfter: ss.map { $0 == 0 ? nil : TimeInterval($0) } ?? nil,
            systemSleepAfter: pm.sleepMinutes.map { $0 == 0 ? nil : TimeInterval($0 * 60) } ?? nil
        )
        lock.lock()
        let changed = current != new
        current = new
        let snapshot = observers.values
        lock.unlock()
        if changed {
            logger.info("prefs changed — display=\(pm.displayMinutes.map(String.init) ?? "nil", privacy: .public) sleep=\(pm.sleepMinutes.map(String.init) ?? "nil", privacy: .public) screensaver=\(ss.map(String.init) ?? "nil", privacy: .public)")
            for listener in snapshot { listener(new) }
        }
    }

    private func installObservers() {
        notificationObservers.append(center.addObserver(
            forName: Notification.Name("com.apple.powerManagementPreferencesChanged"),
            object: nil, queue: queue
        ) { [weak self] _ in self?.refresh() })
        notificationObservers.append(center.addObserver(
            forName: Notification.Name("com.apple.screensaver.didchange"),
            object: nil, queue: queue
        ) { [weak self] _ in self?.refresh() })
    }

    /// Inputs shaped for `SleepClock.resolve`. Caller provides the dynamic
    /// fields (idle seconds and caffeine flag).
    public func inputs(secondsSinceLastInput: TimeInterval, caffeinationActive: Bool) -> SleepClock.Inputs {
        let s = snapshot
        return SleepClock.Inputs(
            displaySleepAfter: s.displaySleepAfter,
            screensaverAfter: s.screensaverAfter,
            systemSleepAfter: s.systemSleepAfter,
            secondsSinceLastInput: secondsSinceLastInput,
            caffeinationActive: caffeinationActive
        )
    }
}

// MARK: - Default source (production)

/// Live source — shells out to `pmset` and `defaults -currentHost`.
/// Both are called only on launch + notification (FR-030). The shell-out is
/// acceptable because the alternative (`IOPMCopyPMPreferences`) returns
/// per-profile settings and requires matching against the active power-source
/// name, which adds complexity; `pmset -g custom` produces the currently-in-
/// effect values directly.
public struct ProcessSource: SystemPreferencesReader.Source {
    public init() {}

    public func readPMSettings() -> (displayMinutes: Int?, sleepMinutes: Int?) {
        guard let output = Self.runProcess(path: "/usr/bin/pmset", args: ["-g", "custom"]) else {
            return (nil, nil)
        }
        // Walk the active profile's block — on most systems pmset -g custom
        // prints both "Battery Power" and "AC Power" blocks; the active one
        // is preceded by `*` or ends with `(current)`. As a safe default we
        // take the last block (typically the currently-active one on Macs
        // that prefer the connected source when plugged in).
        return Self.parseLatestBlock(output)
    }

    public func readScreensaverSeconds() -> Int? {
        guard let output = Self.runProcess(path: "/usr/bin/defaults", args: ["-currentHost", "read", "com.apple.screensaver", "idleTime"]),
              let value = Int(output.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return nil
        }
        return value
    }

    // MARK: - Helpers

    static func runProcess(path: String, args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            return nil
        }
        // Drain stdout *before* waiting: a child that fills the pipe buffer
        // would otherwise block forever on write while we block on exit.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func parseLatestBlock(_ output: String) -> (displayMinutes: Int?, sleepMinutes: Int?) {
        var display: Int?
        var sleep: Int?
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2 else { continue }
            switch parts[0] {
            case "displaysleep":
                display = Int(parts[1])
            case "sleep":
                sleep = Int(parts[1])
            default:
                break
            }
        }
        return (display, sleep)
    }
}
