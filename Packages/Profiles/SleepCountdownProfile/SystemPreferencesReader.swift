import Foundation
import IOKit.ps
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
/// Both are called only on launch, on preference-change notifications and
/// when the power source changes (FR-030). `pmset -g custom` lists one block
/// per power source ("Battery Power", "AC Power", "UPS Power"); we read the
/// block for the source the Mac is drawing from right now.
public struct ProcessSource: SystemPreferencesReader.Source {
    public init() {}

    public func readPMSettings() -> (displayMinutes: Int?, sleepMinutes: Int?) {
        guard let output = Self.runProcess(path: "/usr/bin/pmset", args: ["-g", "custom"]) else {
            return (nil, nil)
        }
        return Self.parse(output, powerSource: Self.providingPowerSource())
    }

    /// "AC Power", "Battery Power" or "UPS Power" — the same names `pmset`
    /// uses for its block headers. `nil` if IOKit can't tell.
    static func providingPowerSource() -> String? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }
        return IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
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

    /// Values from the block for `powerSource`. Falls back to the last block
    /// (a desktop only has "AC Power") when there is no such block.
    static func parse(_ output: String, powerSource: String?) -> (displayMinutes: Int?, sleepMinutes: Int?) {
        var blocks: [(name: String, display: Int?, sleep: Int?)] = []
        for line in output.split(separator: "\n") {
            let raw = String(line)
            if !raw.hasPrefix(" "), !raw.hasPrefix("\t"), raw.hasSuffix(":") {
                blocks.append((String(raw.dropLast()).trimmingCharacters(in: .whitespaces), nil, nil))
                continue
            }
            let parts = raw.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2 else { continue }
            if blocks.isEmpty { blocks.append(("", nil, nil)) }
            switch parts[0] {
            case "displaysleep": blocks[blocks.count - 1].display = Int(parts[1])
            case "sleep": blocks[blocks.count - 1].sleep = Int(parts[1])
            default: break
            }
        }
        let block = blocks.last { $0.name == powerSource } ?? blocks.last
        return (block?.display, block?.sleep)
    }
}
