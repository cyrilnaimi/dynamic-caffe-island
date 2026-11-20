import Foundation
import OSLog

/// Process-wide registry of live assertions. An `atexit` hook walks it to
/// release every outstanding assertion on a normal exit.
///
/// There is deliberately no SIGTERM / SIGINT handler: the kernel drops a
/// process's IOPM assertions when it dies, however it dies, so a signal
/// needs no cleanup. A handler would have to take locks and allocate, which
/// isn't async-signal-safe and could hang the app instead of ending it.
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

    /// Release every live assertion. Called from `atexit`; never from a
    /// signal handler (it takes locks).
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
    }
}
