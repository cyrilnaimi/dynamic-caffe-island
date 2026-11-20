// MARK: - Plugin trust model
//
// Third-party profile bundles are arbitrary native code that runs inside the
// app process, so `ProfileRegistry.loadBundles(from:policy:approve:)` only
// loads a bundle when every rule below holds. Any failure skips that bundle
// (others still load), is logged via `os.Logger`, and is returned as a
// `BundleRejection` so the UI can explain it.
//
// 1. Scanned directory. It must be a real directory (not a symlink), owned
//    by the current user (`getuid()`), and neither group- nor world-writable.
//    The conventional location is `ProfileRegistry.defaultBundleDirectory`
//    (`~/Library/Application Support/Caffe Island/Profiles`).
// 2. Bundle paths. Every `*.bundle` entry, and every file inside it, must be
//    owned by the current user (or root) and not group- or world-writable.
//    A symlinked entry is followed only if its resolved target stays inside
//    the scanned directory.
// 3. Code signature. The bundle is checked with `SecStaticCodeCheckValidity`
//    (`kSecCSCheckAllArchitectures | kSecCSStrictValidate |
//    kSecCSCheckNestedCode`) against the `BundleTrustPolicy` requirement.
//    The default policy is Developer ID signed by the app's own team; an
//    unsigned, tampered or foreign-team bundle is refused.
//    `.anyValidSignature` (which also accepts ad-hoc signatures) exists for
//    tests and local development only.
// 4. User approval. The signer (team ID, signing identifier, cdhash) is
//    handed to an approval hook before the bundle is loaded. The hook
//    defaults to deny, so nothing loads unless the app asks the user.
//
// Defense in depth: the app keeps the hardened runtime with library
// validation ON, so `dlopen` re-checks the signature at load time and
// refuses code not signed by the app's team even if these checks were
// bypassed. Because the directory and bundles must be writable only by the
// user, the window between verification and `Bundle.load()` can only be
// exploited by code already running as that user.

import Foundation
import OSLog
import Security

// MARK: - Policy

/// Which code signatures `BundleVerifier` accepts for profile bundles.
public enum BundleTrustPolicy: Sendable, Equatable, Hashable {
    /// Developer ID Application signature issued by Apple to one of
    /// `teamIDs`. An empty set (or one holding only malformed IDs) accepts
    /// nothing. This is the production policy.
    case developerID(teamIDs: Set<String>)

    /// Any valid, untampered signature, including ad-hoc (`codesign -s -`).
    ///
    /// - Warning: For tests and local development only. It proves the bundle
    ///   was not modified after signing, not who signed it.
    case anyValidSignature

    /// The strict default: `.developerID` pinned to the team that signed the
    /// running app. If the host has no team ID (unsigned or ad-hoc builds),
    /// the set is empty and every bundle is refused.
    public static let `default`: BundleTrustPolicy = .developerID(
        teamIDs: BundleVerifier.hostTeamIdentifier.map { [$0] } ?? []
    )

    /// The code-signing requirement language string for this policy, or nil
    /// when the policy only needs a valid signature (`.anyValidSignature`)
    /// or cannot accept anything (no well-formed team ID).
    public var requirementString: String? {
        switch self {
        case .anyValidSignature:
            return nil
        case let .developerID(teamIDs):
            let clauses = teamIDs
                .filter(Self.isWellFormedTeamID)
                .sorted()
                .map { "certificate leaf[subject.OU] = \"\($0)\"" }
            guard !clauses.isEmpty else { return nil }
            // Apple's Developer ID designated-requirement shape: Apple root,
            // Developer ID intermediate, Developer ID Application leaf.
            return "anchor apple generic"
                + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
                + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
                + " and (" + clauses.joined(separator: " or ") + ")"
        }
    }

    /// Team IDs are 10 uppercase alphanumerics. Anything else is dropped so
    /// it cannot inject syntax into the requirement string.
    static func isWellFormedTeamID(_ id: String) -> Bool {
        id.count == 10 && id.allSatisfy { ("A"..."Z").contains($0) || ("0"..."9").contains($0) }
    }
}

// MARK: - Signer info

/// Who signed a bundle, read via `SecCodeCopySigningInformation`. Handed to
/// the approval hook so the app can show it to the user.
public struct BundleSignerInfo: Sendable, Equatable, Hashable {
    /// Bundle location that was verified (symlinks resolved).
    public let bundleURL: URL
    /// `CFBundleIdentifier` from the bundle's Info.plist, if present.
    public let bundleIdentifier: String?
    /// Code-signing identifier (usually equal to the bundle identifier).
    public let signingIdentifier: String?
    /// Apple Developer Team ID; nil for ad-hoc signatures.
    public let teamIdentifier: String?
    /// True for ad-hoc (`codesign -s -`) signatures.
    public let isAdHoc: Bool
    /// Hex code-directory hash; identifies this exact build of the bundle,
    /// e.g. to remember an approval.
    public let cdHash: String?

    public init(
        bundleURL: URL,
        bundleIdentifier: String?,
        signingIdentifier: String?,
        teamIdentifier: String?,
        isAdHoc: Bool,
        cdHash: String?
    ) {
        self.bundleURL = bundleURL
        self.bundleIdentifier = bundleIdentifier
        self.signingIdentifier = signingIdentifier
        self.teamIdentifier = teamIdentifier
        self.isAdHoc = isAdHoc
        self.cdHash = cdHash
    }
}

// MARK: - Rejections

/// Why a bundle (or the scanned directory) was refused.
public enum BundleRejectionReason: Error, Sendable, Equatable, CustomStringConvertible {
    /// The path is missing or not a directory (bundles must be directories).
    case notADirectory(path: String)
    /// The scanned directory itself is a symlink.
    case directoryIsSymlink(path: String)
    /// Owned by another user. The directory must be owned by the current
    /// user; bundle contents may also be owned by root.
    case notOwnedByCurrentUser(path: String, ownerUID: UInt32)
    /// Group- or world-writable.
    case writableByOthers(path: String, mode: UInt16)
    /// A symlinked entry resolves outside the scanned directory.
    case symlinkEscapesDirectory(path: String, target: String)
    /// No code signature at all.
    case unsigned
    /// The signature is broken: contents modified after signing, malformed,
    /// or failed strict validation.
    case invalidSignature(status: Int32, message: String)
    /// Valid signature that does not satisfy the trust policy (wrong team,
    /// not Developer ID, ad-hoc under the default policy…).
    case policyNotSatisfied(requirement: String)
    /// The policy cannot accept anything (e.g. `.developerID` with no
    /// well-formed team ID).
    case noTrustedSigners
    /// The approval hook declined this signer.
    case notApprovedByUser(BundleSignerInfo)
    /// Passed verification but failed to load or register.
    case loadFailed(String)

    public var description: String {
        switch self {
        case let .notADirectory(path):
            return "\(path) is not a directory"
        case let .directoryIsSymlink(path):
            return "\(path) is a symlink; the profiles directory must be a real directory"
        case let .notOwnedByCurrentUser(path, uid):
            return "\(path) is owned by uid \(uid), not the current user"
        case let .writableByOthers(path, mode):
            return "\(path) is group- or world-writable (mode \(String(mode & 0o7777, radix: 8)))"
        case let .symlinkEscapesDirectory(path, target):
            return "\(path) is a symlink to \(target), outside the profiles directory"
        case .unsigned:
            return "bundle is not code-signed"
        case let .invalidSignature(status, message):
            return "code signature is invalid or the bundle was modified (\(status): \(message))"
        case let .policyNotSatisfied(requirement):
            return "code signature does not satisfy the trust policy (\(requirement))"
        case .noTrustedSigners:
            return "no trusted signer configured; the policy accepts no bundle"
        case let .notApprovedByUser(signer):
            return "not approved by the user (signer \(signer.teamIdentifier ?? "ad-hoc"), id \(signer.signingIdentifier ?? "?"))"
        case let .loadFailed(reason):
            return "failed to load: \(reason)"
        }
    }
}

/// A refused bundle or directory, surfaced to the UI.
public struct BundleRejection: Sendable, Equatable {
    public let url: URL
    public let reason: BundleRejectionReason

    public init(url: URL, reason: BundleRejectionReason) {
        self.url = url
        self.reason = reason
    }
}

/// Outcome of `ProfileRegistry.loadBundles(from:policy:approve:)`.
public struct BundleLoadResult: Sendable, Equatable {
    /// Profiles that were loaded and registered.
    public var loaded: [ProfileID]
    /// Bundles (or the directory) that were refused, in scan order.
    public var rejections: [BundleRejection]

    public init(loaded: [ProfileID] = [], rejections: [BundleRejection] = []) {
        self.loaded = loaded
        self.rejections = rejections
    }
}

// MARK: - Verifier

/// Performs the path and code-signature checks described in the plugin
/// trust model at the top of this file. Stateless; does not load code.
public struct BundleVerifier: Sendable {
    public let policy: BundleTrustPolicy

    private static let logger = Logger(subsystem: "ch.dynamic-caffe-island.profilekit", category: "bundle-trust")

    /// Flags required by the trust model for `SecStaticCodeCheckValidity`.
    static let validityFlags = SecCSFlags(
        rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode
    )

    public init(policy: BundleTrustPolicy = .default) {
        self.policy = policy
    }

    /// Team ID of the running process's signature, if any.
    public static let hostTeamIdentifier: String? = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }()

    // MARK: Path checks

    /// Checks the directory to scan and returns its canonical path.
    /// - Throws: `BundleRejectionReason`.
    public func checkDirectory(_ directory: URL) throws -> URL {
        let path = directory.path
        let st = try Self.lstat(path)
        if (st.st_mode & S_IFMT) == S_IFLNK {
            throw BundleRejectionReason.directoryIsSymlink(path: path)
        }
        guard (st.st_mode & S_IFMT) == S_IFDIR else {
            throw BundleRejectionReason.notADirectory(path: path)
        }
        guard st.st_uid == getuid() else {
            throw BundleRejectionReason.notOwnedByCurrentUser(path: path, ownerUID: st.st_uid)
        }
        try Self.checkNotWritableByOthers(path: path, mode: st.st_mode)
        return URL(fileURLWithPath: try Self.realpath(path), isDirectory: true)
    }

    /// Checks one `*.bundle` entry of `directory` (as returned by
    /// `checkDirectory`) and returns the location to verify and load:
    /// the entry itself, or its symlink target if that stays inside
    /// `directory`. Every file inside the bundle is checked too.
    /// - Throws: `BundleRejectionReason`.
    public func checkBundlePath(_ bundleURL: URL, in directory: URL) throws -> URL {
        let path = bundleURL.path
        let rootPath = try Self.realpath(directory.path)
        let entry = try Self.lstat(path)

        var resolvedPath = path
        if (entry.st_mode & S_IFMT) == S_IFLNK {
            guard let target = try? Self.realpath(path) else {
                throw BundleRejectionReason.symlinkEscapesDirectory(path: path, target: "<unresolvable>")
            }
            guard target.hasPrefix(rootPath + "/") else {
                throw BundleRejectionReason.symlinkEscapesDirectory(path: path, target: target)
            }
            resolvedPath = target
        } else {
            // A non-symlink entry may still sit under a symlinked parent;
            // compare canonical paths.
            let canonical = try Self.realpath(path)
            guard canonical.hasPrefix(rootPath + "/") else {
                throw BundleRejectionReason.symlinkEscapesDirectory(path: path, target: canonical)
            }
            resolvedPath = canonical
        }

        let st = try Self.lstat(resolvedPath)
        guard (st.st_mode & S_IFMT) == S_IFDIR else {
            throw BundleRejectionReason.notADirectory(path: resolvedPath)
        }
        try Self.checkOwnerAndMode(path: resolvedPath, stat: st)

        // Every file inside the bundle (symlinks are not followed; the code
        // signature seals them and strict validation rejects ones escaping
        // the bundle).
        let fm = FileManager.default
        if let enumerator = fm.enumerator(atPath: resolvedPath) {
            for case let relative as String in enumerator {
                let child = (resolvedPath as NSString).appendingPathComponent(relative)
                try Self.checkOwnerAndMode(path: child, stat: try Self.lstat(child))
            }
        }
        return URL(fileURLWithPath: resolvedPath, isDirectory: true)
    }

    // MARK: Signature checks

    /// Verifies the code signature of the bundle at `bundleURL` against
    /// `policy` and returns its signer.
    /// - Throws: `BundleRejectionReason`.
    public func verifySignature(of bundleURL: URL) throws -> BundleSignerInfo {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            throw Self.reason(for: createStatus, requirement: nil)
        }

        var requirement: SecRequirement?
        let requirementText = policy.requirementString
        switch policy {
        case .anyValidSignature:
            break
        case .developerID:
            guard let requirementText else { throw BundleRejectionReason.noTrustedSigners }
            let status = SecRequirementCreateWithString(requirementText as CFString, [], &requirement)
            guard status == errSecSuccess, requirement != nil else {
                Self.logger.fault("cannot compile requirement \(requirementText, privacy: .public): \(status)")
                throw BundleRejectionReason.noTrustedSigners
            }
        }

        let status = SecStaticCodeCheckValidity(staticCode, Self.validityFlags, requirement)
        guard status == errSecSuccess else {
            throw Self.reason(for: status, requirement: requirementText)
        }
        return try Self.signerInfo(for: staticCode, bundleURL: bundleURL)
    }

    /// Path checks followed by signature verification.
    /// - Parameter directory: canonical directory from `checkDirectory`.
    /// - Throws: `BundleRejectionReason`.
    public func verify(bundleAt bundleURL: URL, in directory: URL) throws -> BundleSignerInfo {
        let resolved = try checkBundlePath(bundleURL, in: directory)
        return try verifySignature(of: resolved)
    }

    // MARK: Helpers

    private static func signerInfo(for code: SecStaticCode, bundleURL: URL) throws -> BundleSignerInfo {
        var info: CFDictionary?
        let status = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        guard status == errSecSuccess, let dict = info as? [String: Any] else {
            throw reason(for: status, requirement: nil)
        }
        let flags = (dict[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let cdHash = (dict[kSecCodeInfoUnique as String] as? Data)?
            .map { String(format: "%02x", $0) }
            .joined()
        let plist = dict[kSecCodeInfoPList as String] as? [String: Any]
        return BundleSignerInfo(
            bundleURL: bundleURL,
            bundleIdentifier: plist?["CFBundleIdentifier"] as? String,
            signingIdentifier: dict[kSecCodeInfoIdentifier as String] as? String,
            teamIdentifier: dict[kSecCodeInfoTeamIdentifier as String] as? String,
            isAdHoc: flags & SecCodeSignatureFlags.adhoc.rawValue != 0,
            cdHash: cdHash
        )
    }

    private static func reason(for status: OSStatus, requirement: String?) -> BundleRejectionReason {
        switch status {
        case errSecCSUnsigned:
            return .unsigned
        case errSecCSReqFailed:
            return .policyNotSatisfied(requirement: requirement ?? "")
        default:
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
            return .invalidSignature(status: status, message: message)
        }
    }

    private static func checkOwnerAndMode(path: String, stat st: stat) throws {
        guard st.st_uid == getuid() || st.st_uid == 0 else {
            throw BundleRejectionReason.notOwnedByCurrentUser(path: path, ownerUID: st.st_uid)
        }
        try checkNotWritableByOthers(path: path, mode: st.st_mode)
    }

    private static func checkNotWritableByOthers(path: String, mode: mode_t) throws {
        // Symlink permission bits are meaningless on macOS; their targets
        // are checked separately (or sealed by the signature).
        guard (mode & S_IFMT) != S_IFLNK else { return }
        if mode & (S_IWGRP | S_IWOTH) != 0 {
            throw BundleRejectionReason.writableByOthers(path: path, mode: UInt16(mode))
        }
    }

    private static func lstat(_ path: String) throws -> stat {
        var st = stat()
        guard Darwin.lstat(path, &st) == 0 else {
            throw BundleRejectionReason.notADirectory(path: path)
        }
        return st
    }

    private static func realpath(_ path: String) throws -> String {
        guard let resolved = Darwin.realpath(path, nil) else {
            throw BundleRejectionReason.notADirectory(path: path)
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
