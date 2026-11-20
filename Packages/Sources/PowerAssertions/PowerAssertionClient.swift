import Foundation

/// Wraps the IOKit calls the Caffeine profile needs, so tests can fake them.
/// Only two calls are required: creating an assertion and releasing it.
public protocol PowerAssertionClient: AnyObject, Sendable {
    /// Acquire an assertion. Returns a raw token the caller owns.
    /// Throws on any underlying failure (kern_return != KERN_SUCCESS).
    func acquire(name: String, types: [String]) throws -> UInt32

    /// Release a previously-acquired assertion. Double-release is a no-op.
    func release(token: UInt32)
}

/// Production client — wraps `IOPMAssertionCreateWithName` / `IOPMAssertionRelease`.
/// Lives in `AssertionHandle.swift` since it depends on the IOKit import.
public enum PowerAssertionError: Error, Equatable {
    case acquireFailed(kernReturn: Int32)
}

/// In-memory fake used by tests. Thread-safe via an internal NSLock.
public final class FakePowerAssertionClient: PowerAssertionClient, @unchecked Sendable {
    public struct Call: Equatable, Sendable {
        public enum Kind: Equatable, Sendable { case acquire(name: String), release(token: UInt32) }
        public let kind: Kind
    }

    private let lock = NSLock()
    private var nextToken: UInt32 = 1
    private(set) public var liveTokens: Set<UInt32> = []
    public private(set) var calls: [Call] = []

    /// Configure to fail the next `acquire` call with the given kern_return.
    public var acquireFailsWith: Int32?

    public init() {}

    public func acquire(name: String, types: [String]) throws -> UInt32 {
        lock.lock(); defer { lock.unlock() }
        if let kr = acquireFailsWith {
            acquireFailsWith = nil
            calls.append(Call(kind: .acquire(name: name)))
            throw PowerAssertionError.acquireFailed(kernReturn: kr)
        }
        let token = nextToken
        nextToken += 1
        liveTokens.insert(token)
        calls.append(Call(kind: .acquire(name: name)))
        return token
    }

    public func release(token: UInt32) {
        lock.lock(); defer { lock.unlock() }
        liveTokens.remove(token)
        calls.append(Call(kind: .release(token: token)))
    }
}
