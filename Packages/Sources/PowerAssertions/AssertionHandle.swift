import Foundation
import IOKit.pwr_mgt
import OSLog

/// Live IOKit-backed implementation of `PowerAssertionClient`.
///
/// We request three assertion types so that caffeine prevents display sleep,
/// idle system sleep, AND screensaver (plan.md Phase 0, R-01):
///
///   `kIOPMAssertionTypePreventUserIdleDisplaySleep`
///   `kIOPMAssertionTypePreventUserIdleSystemSleep`
///   `kIOPMAssertionTypeUserIsActive`
///
/// Tokens are composed so that a single `release(token:)` can release all
/// three underlying assertions atomically.
public final class LivePowerAssertionClient: PowerAssertionClient, @unchecked Sendable {
    /// Display-sleep assertion alone prevents screensaver engagement
    /// (screensaver triggers via the display idle timer). System-sleep
    /// assertion covers idle-system sleep.
    public static let defaultAssertionTypes: [String] = [
        kIOPMAssertionTypePreventUserIdleDisplaySleep as String,
        kIOPMAssertionTypePreventUserIdleSystemSleep as String,
    ]

    private let lock = NSLock()
    // Outer token → list of IOKit assertion ids (one per assertion type)
    private var composite: [UInt32: [IOPMAssertionID]] = [:]
    private var nextToken: UInt32 = 1
    private let logger = Logger(subsystem: "ch.dynamic-caffe-island.powerassertions", category: "client")

    public init() {}

    public func acquire(name: String, types: [String]) throws -> UInt32 {
        lock.lock()
        let token = nextToken
        nextToken += 1
        lock.unlock()

        var ids: [IOPMAssertionID] = []
        for type in types {
            var assertionID: IOPMAssertionID = 0
            let kr = IOPMAssertionCreateWithName(
                type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                name as CFString,
                &assertionID
            )
            if kr != kIOReturnSuccess {
                for existing in ids {
                    IOPMAssertionRelease(existing)
                }
                logger.error("IOPMAssertionCreateWithName failed: \(kr)")
                throw PowerAssertionError.acquireFailed(kernReturn: kr)
            }
            ids.append(assertionID)
        }

        lock.lock()
        composite[token] = ids
        lock.unlock()

        logger.info("acquired assertion token=\(token) name=\(name, privacy: .public) types=\(types.count)")
        return token
    }

    public func release(token: UInt32) {
        lock.lock()
        let ids = composite.removeValue(forKey: token) ?? []
        lock.unlock()
        for id in ids {
            IOPMAssertionRelease(id)
        }
        if !ids.isEmpty {
            logger.info("released assertion token=\(token) count=\(ids.count)")
        }
    }
}

/// Owning-handle wrapper. `deinit` + atexit + SIGTERM/SIGINT release (FR-006).
public final class AssertionHandle: @unchecked Sendable {
    public let token: UInt32
    public let name: String
    private let client: any PowerAssertionClient
    private var released = false
    private let lock = NSLock()

    public init(name: String, client: any PowerAssertionClient = LivePowerAssertionClient(), types: [String] = LivePowerAssertionClient.defaultAssertionTypes) throws {
        self.name = name
        self.client = client
        self.token = try client.acquire(name: name, types: types)
        AssertionRegistry.shared.register(self)
    }

    public func release() {
        lock.lock()
        guard !released else {
            lock.unlock()
            return
        }
        released = true
        lock.unlock()
        client.release(token: token)
        AssertionRegistry.shared.unregister(self)
    }

    public var isReleased: Bool {
        lock.lock(); defer { lock.unlock() }
        return released
    }

    deinit {
        release()
    }
}
