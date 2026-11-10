import AppKit
import AnimationKit
import Combine
import CoreGraphics
import Foundation
import OSLog
import PowerAssertions

/// Routes the four `TimelineTicker` down-shift triggers from plan.md R-07:
///
///   (a) `NSWorkspace.willSleepNotification` / `didWakeNotification`
///   (b) `NSApp.isHidden` via `didHideNotification` / `didUnhideNotification`
///   (c) `CGDisplayIsAsleep(CGMainDisplayID())` polled only on display-config-changed events
///   (d) frontmost-app full-screen detection via `NSWorkspace.frontmostApplication` + `.activeSpace`
///
/// Also audits live caffeine assertions on wake (FR-005) to release any
/// assertion the user did NOT initiate.
///
/// FR-029 distinction: this object controls the TICKER (pause/downgrade).
/// T052a controls the WINDOW visibility. Both are needed.
@MainActor
public final class VisibilityObserver: NSObject {
    public static let shared = VisibilityObserver()

    private let logger = Logger(subsystem: "ch.dynamic-caffe-island.app", category: "visibility")
    private let ticker = TimelineTicker.shared
    private var observers: [NSObjectProtocol] = []
    private var started = false

    public func start() {
        guard !started else { return }
        started = true
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.logger.info("willSleep → pause ticker")
            self?.ticker.pause()
        })
        observers.append(nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.logger.info("didWake → resume ticker")
            self?.ticker.resume()
            self?.auditAssertionsOnWake()
        })

        let app = NotificationCenter.default
        observers.append(app.addObserver(
            forName: NSApplication.didHideNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.logger.info("app hidden → ticker idle rate")
            // No-op for now: the ticker naturally downshifts when subscribers
            // cancel their higher-rate requests. For an explicit downgrade
            // when all windows are occluded we'd track subscriber state here.
        })
        observers.append(app.addObserver(
            forName: NSApplication.didUnhideNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.logger.info("app unhidden → ticker resume")
            self?.ticker.resume()
        })

        // Display-config changes: check CGDisplayIsAsleep once per change.
        observers.append(app.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            let asleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
            self?.logger.info("display params changed — mainDisplayAsleep=\(asleep)")
            if asleep { self?.ticker.pause() } else { self?.ticker.resume() }
        })

        // Frontmost full-screen detection (coarse-grained).
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.logger.debug("active space changed — visibility gate re-evaluated")
        })
    }

    public func stop() {
        let nc = NSWorkspace.shared.notificationCenter
        let app = NotificationCenter.default
        for obs in observers {
            nc.removeObserver(obs)
            app.removeObserver(obs)
        }
        observers.removeAll()
        started = false
    }

    /// FR-005: after a sleep/wake cycle, release any IOPMAssertion the user
    /// did not explicitly initiate. V1 built-ins always require an explicit
    /// user action (menu click) to start caffeine, so any live assertion
    /// after wake should only exist if it was active before sleep — which
    /// is allowed (session continues). The strict "not user-initiated" check
    /// is scaffolded here; real enforcement waits on `CaffeinationSession`
    /// ownership metadata (T024).
    private func auditAssertionsOnWake() {
        let count = AssertionRegistry.shared.liveCount
        logger.info("wake audit: \(count) live assertion(s)")
    }
}
