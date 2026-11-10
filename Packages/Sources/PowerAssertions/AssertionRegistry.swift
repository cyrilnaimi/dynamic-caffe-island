import Foundation
import OSLog

/// Process-wide registry of live assertions. `atexit` and signal handlers
/// walk this registry to release every outstanding assertion — that is how
/// FR-006 / SC-009 are guaranteed even under graceful-quit, SIGTERM, SIGINT,
/// uncaught-exception, and crash-without-deinit paths.
public final class AssertionRegistry: @unchecked Sendable {
    public static let shared = AssertionRegistry()

    private let lock = NSLock()
    private var live: NSHashTable<AssertionHandle> = NSHashTable.weakObjects()
    private var handlersInstalled = false
    private let logger = Logger(subsystem: "ch.dynamic-caffe-island.powerassertions", category: "registry")

    public init() {
        installProcessHandlers()
    }

    public func register(_ handle: AssertionHandle) {
        lock.lock(); defer { lock.unlock() }
        live.add(handle)
    }

    public func unregister(_ handle: AssertionHandle) {
        lock.lock(); defer { lock.unlock() }
        live.remove(handle)
    }

    /// Release every live assertion. Safe to call from atexit / signal
    /// handler contexts (uses only lock + synchronous IOKit release).
    public func releaseAll() {
        lock.lock()
        let snapshot = live.allObjects
        lock.unlock()
        for handle in snapshot {
            handle.release()
        }
        logger.info("releaseAll released \(snapshot.count) handle(s)")
    }

    public var liveCount: Int {
        lock.lock(); defer { lock.unlock() }
        return live.allObjects.count
    }

    // MARK: - Process-level handlers

    private func installProcessHandlers() {
        lock.lock()
        guard !handlersInstalled else {
            lock.unlock()
            return
        }
        handlersInstalled = true
        lock.unlock()

        atexit {
            AssertionRegistry.shared.releaseAll()
        }

        // SIGTERM/SIGINT handlers — release all, then default action.
        // We use sigaction with SA_RESETHAND so the default handler runs on
        // the second signal.
        Self.installSignalHandler(SIGTERM)
        Self.installSignalHandler(SIGINT)
    }

    private static func installSignalHandler(_ sig: Int32) {
        var action = sigaction()
        action.__sigaction_u.__sa_handler = { _ in
            AssertionRegistry.shared.releaseAll()
            // Re-raise with default disposition for the second signal.
            signal(SIGTERM, SIG_DFL)
            signal(SIGINT, SIG_DFL)
            _ = raise(SIGTERM)
        }
        action.sa_flags = Int32(SA_RESETHAND)
        sigaction(sig, &action, nil)
    }
}
