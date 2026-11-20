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

    /// Registers a built-in profile by type; the registry creates and owns
    /// the instance.
    public func register(_ type: (some Profile).Type) throws {
        try register(instance: type.init())
    }

    /// Registers a built-in profile the caller already created, so the
    /// registry and the app share one instance (and one session manager,
    /// one preferences reader) instead of each having their own.
    public func register<P: Profile>(instance: P) throws {
        let type = P.self
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

    /// Conventional location for third-party profile bundles:
    /// `~/Library/Application Support/Caffe Island/Profiles`.
    public static var defaultBundleDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Caffe Island", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
    }

    /// Walks `directory` for `*.bundle` entries, verifies each one per the
    /// plugin trust model (see `BundleVerifier.swift`), asks `approve`, then
    /// loads its `NSPrincipalClass` and registers it. V1 callsites are
    /// opt-in (none in the default boot); T045a exercises this path.
    ///
    /// Never throws: a refused or broken bundle is skipped, logged, and
    /// reported in `BundleLoadResult.rejections` without affecting the
    /// others. A missing directory yields an empty result; an untrusted
    /// directory yields a single rejection for the directory itself.
    ///
    /// - Parameters:
    ///   - policy: signature policy; defaults to Developer ID from the app's
    ///     own team. `.anyValidSignature` is for tests/development only.
    ///   - approve: called with the verified signer before the bundle's code
    ///     is loaded; return true to load it. Defaults to deny. The caller
    ///     owns remembering approvals (e.g. keyed on `cdHash`).
    @discardableResult
    public func loadBundles(
        from directory: URL,
        policy: BundleTrustPolicy = .default,
        approve: @Sendable (BundleSignerInfo) async -> Bool = { _ in false }
    ) async -> BundleLoadResult {
        var result = BundleLoadResult()
        let verifier = BundleVerifier(policy: policy)

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir) else {
            logger.debug("profile bundle directory \(directory.path, privacy: .public) does not exist")
            return result
        }

        let root: URL
        do {
            root = try verifier.checkDirectory(directory)
        } catch {
            reject(directory, error, into: &result)
            return result
        }

        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            )
        } catch {
            reject(directory, BundleRejectionReason.loadFailed(error.localizedDescription), into: &result)
            return result
        }

        for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where url.pathExtension == "bundle" {
            do {
                let signer = try verifier.verify(bundleAt: url, in: root)
                guard await approve(signer) else {
                    throw BundleRejectionReason.notApprovedByUser(signer)
                }
                let id = try loadVerifiedBundle(at: signer.bundleURL)
                result.loaded.append(id)
                logger.info("loaded profile bundle \(url.path, privacy: .public) team=\(signer.teamIdentifier ?? "ad-hoc", privacy: .public)")
            } catch {
                reject(url, error, into: &result)
            }
        }
        return result
    }

    private func reject(_ url: URL, _ error: Error, into result: inout BundleLoadResult) {
        let reason = (error as? BundleRejectionReason) ?? .loadFailed(String(describing: error))
        logger.error("refused profile bundle \(url.path, privacy: .public): \(reason.description, privacy: .public)")
        result.rejections.append(BundleRejection(url: url, reason: reason))
    }

    /// Loads and registers a bundle that already passed verification and
    /// approval. Executes the bundle's code.
    private func loadVerifiedBundle(at url: URL) throws -> ProfileID {
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
        return cls.id
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
