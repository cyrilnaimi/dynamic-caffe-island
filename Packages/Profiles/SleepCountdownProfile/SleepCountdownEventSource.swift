import AnimationKit
import Foundation
import OSLog
import ProfileKit
import SleepClock

/// Ticker-driven countdown source. Subscribes to `TimelineTicker` at idle
/// rate (1 Hz), reads `IdleTimer` + `SystemPreferencesReader`, applies the
/// `caffeinationActive` signal, runs `SleepClock.resolve`, and yields
/// `SleepCountdownState` changes.
///
/// E-2: never yields faster than 1 Hz here; transitions up to 30 Hz only
/// when remaining < 10 s (urgency) via `requestRate(.transitioning, for:)`.
public final class SleepCountdownEventSource: EventSource, @unchecked Sendable {
    public typealias State = SleepCountdownState

    public typealias CaffeinationProvider = @Sendable () -> Bool

    private let ticker: TimelineTicker
    private let reader: SystemPreferencesReader
    private let idleReader: IdleTimer.Reader
    private let caffeinationActive: CaffeinationProvider
    private let logger = Logger(subsystem: "ch.dynamic-caffe-island.sleepclock", category: "event-source")

    private let lock = NSLock()
    private var lastYielded: SleepCountdownState = .idle(.none)
    private var continuations: [UUID: AsyncStream<SleepCountdownState>.Continuation] = [:]
    private var tickerSub: TimelineTicker.Subscription?
    private var urgencyBump: TimelineTicker.Subscription?
    private var torn = false

    public init(
        ticker: TimelineTicker = .shared,
        reader: SystemPreferencesReader,
        idleReader: IdleTimer.Reader = IdleTimer.live,
        caffeinationActive: @escaping CaffeinationProvider
    ) {
        self.ticker = ticker
        self.reader = reader
        self.idleReader = idleReader
        self.caffeinationActive = caffeinationActive
    }

    public func stream() -> AsyncStream<SleepCountdownState> {
        AsyncStream { continuation in
            lock.lock()
            if torn {
                lock.unlock()
                continuation.finish()
                return
            }
            let id = UUID()
            continuations[id] = continuation
            let needsTickerSub = tickerSub == nil
            if needsTickerSub {
                let sub = ticker.subscribe(rate: .idle) { [weak self] in self?.tick() }
                tickerSub = sub
            }
            lock.unlock()

            // E-1 immediate yield.
            continuation.yield(computeState())

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations.removeValue(forKey: id)
                if self.continuations.isEmpty {
                    self.tickerSub?.cancel()
                    self.tickerSub = nil
                    self.urgencyBump?.cancel()
                    self.urgencyBump = nil
                }
                self.lock.unlock()
            }
        }
    }

    public func tearDown() {
        lock.lock()
        torn = true
        let conts = continuations
        continuations.removeAll()
        tickerSub?.cancel()
        tickerSub = nil
        urgencyBump?.cancel()
        urgencyBump = nil
        lock.unlock()
        for (_, c) in conts { c.finish() }
    }

    // MARK: - Internals

    private func tick() {
        let new = computeState()
        lock.lock()
        let changed = new != lastYielded
        lastYielded = new
        let snapshot = continuations.values
        // If entering urgency (< 10 s), bump the ticker to transitioning for 10 s.
        if new.isUrgent, urgencyBump == nil {
            urgencyBump = ticker.requestRate(.transitioning, for: 10.0)
        } else if !new.isUrgent, let bump = urgencyBump {
            bump.cancel()
            urgencyBump = nil
        }
        lock.unlock()
        guard changed else { return }
        for c in snapshot { c.yield(new) }
    }

    private func computeState() -> SleepCountdownState {
        let isCaffeinated = caffeinationActive()
        let idle = idleReader.secondsSinceLastInput()
        let inputs = reader.inputs(secondsSinceLastInput: idle, caffeinationActive: isCaffeinated)
        let event = SleepClock.resolve(inputs)
        if case .suppressed = event { return .suppressed }
        return .idle(event)
    }
}
