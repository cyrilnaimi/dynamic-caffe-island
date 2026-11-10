import Foundation
import OSLog

/// The registry is the single owner of all loaded profiles. Per
/// `contracts/profile-contract.md`, it is responsible for: (a) registering
/// built-in and bundle profiles, (b) enable/disable (FR-026), (c) guarded
/// invocation of every profile entrypoint (B-7), and (d) dispatching
/// `ProfileDisabled` events when the watchdog fires.
public actor ProfileRegistry {
    public static let shared = ProfileRegistry()

    private struct Entry {
        let bundle: ProfileBundle
        let instance: any Profile
        var isEnabled: Bool
    }

    private var entries: [ProfileID: Entry] = [:]
    private var disabledByWatchdogSet: Set<ProfileID> = []
    private let disabledEventContinuation: AsyncStream<ProfileID>.Continuation
    private nonisolated let _disabledEventStream: AsyncStream<ProfileID>
    private let logger = Logger(subsystem: "ch.dynamic-caffe-island.profilekit", category: "registry")

    public init() {
        var cont: AsyncStream<ProfileID>.Continuation!
        let stream = AsyncStream<ProfileID> { c in cont = c }
        self.disabledEventContinuation = cont
        self._disabledEventStream = stream
    }

    // MARK: - Registration

    public func register(_ type: (some Profile).Type) throws {
        let id = type.id
        if entries[id] != nil {
            logger.error("duplicate registration attempt for \(id.raw, privacy: .public)")
            throw RegistrationError.duplicate(id)
        }
        let bundle = ProfileBundle(
            id: id,
            version: SemanticVersion(1, 0, 0),
            contractVersion: ContractVersion.current,
            origin: .builtIn,
            principalType: type
        )
        let instance = type.init()
        entries[id] = Entry(bundle: bundle, instance: instance, isEnabled: true)
        logger.info("registered \(id.raw, privacy: .public) (built-in)")
    }

    public func register(bundle: ProfileBundle) throws {
        guard ContractVersion.supportedRange.contains(bundle.contractVersion) else {
            throw RegistrationError.incompatibleContractVersion(bundle.id, bundle.contractVersion)
        }
        if entries[bundle.id] != nil {
            throw RegistrationError.duplicate(bundle.id)
        }
        guard let type = bundle.principalType else {
            throw RegistrationError.bundleInvalid(URL(fileURLWithPath: "/"), reason: "no principalType")
        }
        let instance = type.init()
        entries[bundle.id] = Entry(bundle: bundle, instance: instance, isEnabled: true)
        logger.info("registered \(bundle.id.raw, privacy: .public) (\(String(describing: bundle.origin)))")
    }

    /// V1: walks `directory` for `*.bundle` subdirectories, loads their
    /// `NSPrincipalClass`, and registers. V1 callsites are opt-in (none in
    /// the default boot); T045a exercises this path end-to-end.
    ///
    /// SECURITY: this executes code from disk. Before wiring it into the
    /// default boot, verify each bundle's code signature
    /// (`SecStaticCodeCheckValidity` against a team requirement) and only
    /// scan a directory the user owns. Hardened runtime library validation
    /// already blocks unsigned bundles in Release builds.
    public func loadBundles(from directory: URL) throws {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        for url in contents where url.pathExtension == "bundle" {
            guard let bundle = Bundle(url: url) else {
                throw RegistrationError.bundleInvalid(url, reason: "not a loadable bundle")
            }
            try bundle.loadAndCheck()
            guard let cls = bundle.principalClass as? any Profile.Type else {
                throw RegistrationError.bundleInvalid(url, reason: "principalClass is not a Profile")
            }
            let contractVersionString = bundle.infoDictionary?["ProfileKitContractVersion"] as? String ?? "1.0.0"
            let contractVersion = SemanticVersion.parse(contractVersionString) ?? SemanticVersion(1, 0, 0)
            let versionString = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
            let version = SemanticVersion.parse(versionString) ?? SemanticVersion(1, 0, 0)
            let profileBundle = ProfileBundle(
                id: cls.id,
                version: version,
                contractVersion: contractVersion,
                origin: .userBundle(url),
                principalType: cls
            )
            try register(bundle: profileBundle)
        }
    }

    // MARK: - Enable/disable (FR-026)

    public func setEnabled(_ id: ProfileID, _ enabled: Bool, byWatchdog: Bool = false) {
        guard var entry = entries[id] else { return }
        let wasEnabled = entry.isEnabled
        entry.isEnabled = enabled
        entries[id] = entry
        if !enabled && byWatchdog {
            disabledByWatchdogSet.insert(id)
            disabledEventContinuation.yield(id)
        } else if enabled {
            disabledByWatchdogSet.remove(id)
        }
        if wasEnabled != enabled {
            logger.info("profile \(id.raw, privacy: .public) enabled=\(enabled)")
        }
    }

    public func isEnabled(_ id: ProfileID) -> Bool {
        entries[id]?.isEnabled ?? false
    }

    // MARK: - Introspection

    public var registeredProfiles: [any Profile] {
        entries.values.map { $0.instance }
    }

    public var enabledProfiles: [any Profile] {
        entries.values.filter(\.isEnabled).map { $0.instance }
    }

    public var disabledByWatchdog: Set<ProfileID> {
        disabledByWatchdogSet
    }

    public nonisolated var profileDisabledEvents: AsyncStream<ProfileID> {
        _disabledEventStream
    }

    // MARK: - Guarded invocation (B-7)

    /// Wraps a closure that calls into a profile with do/catch; returns the
    /// fallback on any thrown error. Caller increments the watchdog.
    public func guardedCall<T>(
        profile id: ProfileID,
        op: String,
        fallback: T,
        _ body: () throws -> T
    ) -> T {
        do {
            return try body()
        } catch {
            logger.error("profile \(id.raw, privacy: .public) op=\(op, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            return fallback
        }
    }

    // MARK: - Teardown

    public func tearDown() {
        for (id, entry) in entries {
            entry.instance.tearDown()
            logger.info("tore down \(id.raw, privacy: .public)")
        }
        entries.removeAll()
        disabledEventContinuation.finish()
    }
}

// MARK: - Helpers

private extension Bundle {
    func loadAndCheck() throws {
        if !isLoaded {
            guard load() else {
                throw RegistrationError.bundleInvalid(bundleURL, reason: "load() returned false")
            }
        }
    }
}

public extension SemanticVersion {
    static func parse(_ s: String) -> SemanticVersion? {
        let parts = s.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 3 else { return nil }
        return SemanticVersion(parts[0], parts[1], parts[2])
    }
}
