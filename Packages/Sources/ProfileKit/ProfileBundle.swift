import Foundation

public struct SemanticVersion: Sendable, Equatable, Hashable, Comparable, CustomStringConvertible, Codable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    /// SemVer-compatible: same major, `other.minor,patch >= self.minor,patch`.
    public func isCompatible(with other: SemanticVersion) -> Bool {
        major == other.major && (minor, patch) <= (other.minor, other.patch)
    }
}

public struct ProfileBundle: Sendable, Equatable {
    public enum Origin: Sendable, Equatable {
        case builtIn
        case userBundle(URL)
    }

    public let id: ProfileID
    public let version: SemanticVersion
    public let contractVersion: SemanticVersion
    public let origin: Origin
    /// Type to instantiate when the registry activates this bundle.
    /// Non-codable; set at bundle-load time.
    public let principalType: (any Profile.Type)?

    public init(
        id: ProfileID,
        version: SemanticVersion,
        contractVersion: SemanticVersion,
        origin: Origin,
        principalType: (any Profile.Type)? = nil
    ) {
        self.id = id
        self.version = version
        self.contractVersion = contractVersion
        self.origin = origin
        self.principalType = principalType
    }

    public static func == (lhs: ProfileBundle, rhs: ProfileBundle) -> Bool {
        lhs.id == rhs.id
            && lhs.version == rhs.version
            && lhs.contractVersion == rhs.contractVersion
            && lhs.origin == rhs.origin
        // principalType is intentionally excluded from equality (metatypes aren't Equatable).
    }
}

public enum ContractVersion {
    /// The ProfileKit contract version this build of the framework exposes.
    /// Bump major on breaking changes; bump minor on additive changes.
    public static let current = SemanticVersion(1, 0, 0)

    /// Bundles whose `contractVersion` falls outside this range are rejected.
    public static let supportedRange: ClosedRange<SemanticVersion> =
        SemanticVersion(1, 0, 0)...SemanticVersion(1, 999, 999)
}
