import Foundation
import ProfileKit
import XCTest

/// Issue #16 — code-signature and path checks for third-party profile
/// bundles. Builds throwaway `.bundle`s around a copy of `/usr/bin/true`;
/// nothing is ever loaded or executed.
final class BundleVerifierTests: XCTestCase {
    private var tempDirs: [URL] = []

    override func tearDownWithError() throws {
        for dir in tempDirs {
            // Undo permission changes so cleanup always succeeds.
            _ = chmod(dir.path, 0o700)
            try? FileManager.default.removeItem(at: dir)
        }
        tempDirs.removeAll()
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    /// A fresh, user-owned, mode-0700 directory.
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundleVerifierTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        tempDirs.append(dir)
        // Canonicalize (/var -> /private/var) like `checkDirectory` does.
        // (`resolvingSymlinksInPath` maps /private/var back to /var, so use realpath.)
        let resolved = try XCTUnwrap(realpath(dir.path, nil))
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    /// Minimal bundle: Contents/Info.plist + Contents/MacOS/Plugin
    /// (an unsigned copy of /usr/bin/true).
    private func makeBundle(in dir: URL, name: String = "Plugin") throws -> URL {
        let bundle = dir.appendingPathComponent("\(name).bundle", isDirectory: true)
        let macOS = bundle.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "ch.dynamic-caffe-island.tests.\(name.lowercased())",
            "CFBundleExecutable": name,
            "CFBundleName": name,
            "CFBundlePackageType": "BNDL",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "1",
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        let exe = macOS.appendingPathComponent(name)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: exe)
        // The copy carries Apple's signature; strip it so the bundle is
        // genuinely unsigned until a test signs it.
        try run("/usr/bin/codesign", ["--remove-signature", exe.path])
        return bundle
    }

    private func adHocSign(_ bundle: URL) throws {
        try run("/usr/bin/codesign", ["-s", "-", "--force", bundle.path])
    }

    private func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "BundleVerifierTests", code: Int(p.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "\(tool) \(args.joined(separator: " ")) failed: \(output)",
            ])
        }
    }

    private func expectRejection(
        _ body: () throws -> Any,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ check: (BundleRejectionReason) -> Bool
    ) {
        do {
            let value = try body()
            XCTFail("expected a rejection, got \(value)", file: file, line: line)
        } catch let reason as BundleRejectionReason {
            XCTAssertTrue(check(reason), "unexpected reason: \(reason)", file: file, line: line)
        } catch {
            XCTFail("unexpected error type: \(error)", file: file, line: line)
        }
    }

    // MARK: - Signature

    func testUnsignedBundleIsRefused() throws {
        let dir = try makeTempDir()
        let bundle = try makeBundle(in: dir)
        let verifier = BundleVerifier(policy: .anyValidSignature)
        expectRejection({ try verifier.verify(bundleAt: bundle, in: dir) }) { reason in
            if case .unsigned = reason { return true }
            return false
        }
    }

    func testAdHocSignedBundlePassesUnderAnyValidSignature() throws {
        let dir = try makeTempDir()
        let bundle = try makeBundle(in: dir)
        try adHocSign(bundle)
        let signer = try BundleVerifier(policy: .anyValidSignature).verify(bundleAt: bundle, in: dir)
        XCTAssertTrue(signer.isAdHoc)
        XCTAssertNil(signer.teamIdentifier)
        XCTAssertEqual(signer.signingIdentifier, "ch.dynamic-caffe-island.tests.plugin")
        XCTAssertEqual(signer.bundleIdentifier, "ch.dynamic-caffe-island.tests.plugin")
        XCTAssertEqual(signer.bundleURL.standardizedFileURL.path, bundle.standardizedFileURL.path)
        XCTAssertEqual(signer.cdHash?.count, 40, "SHA-1-length hex cdhash expected")
    }

    func testTamperedExecutableIsRefused() throws {
        let dir = try makeTempDir()
        let bundle = try makeBundle(in: dir)
        try adHocSign(bundle)
        let exe = bundle.appendingPathComponent("Contents/MacOS/Plugin")
        let handle = try FileHandle(forWritingTo: exe)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("tampered".utf8))
        try handle.close()

        let verifier = BundleVerifier(policy: .anyValidSignature)
        expectRejection({ try verifier.verify(bundleAt: bundle, in: dir) }) { reason in
            if case .invalidSignature = reason { return true }
            return false
        }
    }

    func testTamperedResourceIsRefused() throws {
        let dir = try makeTempDir()
        let bundle = try makeBundle(in: dir)
        try adHocSign(bundle)
        try Data("<plist/>".utf8).write(to: bundle.appendingPathComponent("Contents/Info.plist"))

        let verifier = BundleVerifier(policy: .anyValidSignature)
        expectRejection({ try verifier.verify(bundleAt: bundle, in: dir) }) { reason in
            if case .invalidSignature = reason { return true }
            return false
        }
    }

    func testAdHocSignedBundleIsRefusedUnderDefaultPolicy() throws {
        let dir = try makeTempDir()
        let bundle = try makeBundle(in: dir)
        try adHocSign(bundle)

        // The default pins the host's team (or nothing); either way ad-hoc fails.
        guard case .developerID = BundleTrustPolicy.default else {
            return XCTFail("default policy must be .developerID")
        }
        XCTAssertEqual(BundleVerifier().policy, .default)
        expectRejection({ try BundleVerifier().verify(bundleAt: bundle, in: dir) }) { reason in
            switch reason {
            case .policyNotSatisfied, .noTrustedSigners: return true
            default: return false
            }
        }
    }

    func testAdHocSignedBundleFailsDeveloperIDRequirement() throws {
        let dir = try makeTempDir()
        let bundle = try makeBundle(in: dir)
        try adHocSign(bundle)
        let verifier = BundleVerifier(policy: .developerID(teamIDs: ["ABCDE12345"]))
        expectRejection({ try verifier.verify(bundleAt: bundle, in: dir) }) { reason in
            if case .policyNotSatisfied = reason { return true }
            return false
        }
    }

    func testDeveloperIDRequirementString() {
        let req = BundleTrustPolicy.developerID(teamIDs: ["ZZZZZ99999", "ABCDE12345"]).requirementString
        XCTAssertEqual(
            req,
            "anchor apple generic"
                + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
                + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
                + " and (certificate leaf[subject.OU] = \"ABCDE12345\" or certificate leaf[subject.OU] = \"ZZZZZ99999\")"
        )
        // Malformed IDs are dropped (no requirement-language injection).
        XCTAssertNil(BundleTrustPolicy.developerID(teamIDs: ["X\" or anchor trusted"]).requirementString)
        XCTAssertNil(BundleTrustPolicy.developerID(teamIDs: []).requirementString)
        XCTAssertNil(BundleTrustPolicy.anyValidSignature.requirementString)
    }

    func testEmptyTeamSetAcceptsNothing() throws {
        let dir = try makeTempDir()
        let bundle = try makeBundle(in: dir)
        try adHocSign(bundle)
        let verifier = BundleVerifier(policy: .developerID(teamIDs: []))
        expectRejection({ try verifier.verify(bundleAt: bundle, in: dir) }) { $0 == .noTrustedSigners }
    }

    // MARK: - Paths

    func testWorldWritableDirectoryIsRefused() throws {
        let dir = try makeTempDir()
        XCTAssertEqual(chmod(dir.path, 0o777), 0)
        expectRejection({ try BundleVerifier().checkDirectory(dir) }) { reason in
            if case .writableByOthers = reason { return true }
            return false
        }
    }

    func testGroupWritableDirectoryIsRefused() throws {
        let dir = try makeTempDir()
        XCTAssertEqual(chmod(dir.path, 0o770), 0)
        expectRejection({ try BundleVerifier().checkDirectory(dir) }) { reason in
            if case .writableByOthers = reason { return true }
            return false
        }
    }

    func testUserOwnedPrivateDirectoryIsAccepted() throws {
        let dir = try makeTempDir()
        let root = try BundleVerifier().checkDirectory(dir)
        XCTAssertEqual(root.path, dir.path)
    }

    func testSymlinkedDirectoryIsRefused() throws {
        let dir = try makeTempDir()
        let real = dir.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: false)
        let link = dir.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        expectRejection({ try BundleVerifier().checkDirectory(link) }) { reason in
            if case .directoryIsSymlink = reason { return true }
            return false
        }
    }

    func testWorldWritableBundleIsRefused() throws {
        let dir = try makeTempDir()
        let bundle = try makeBundle(in: dir)
        try adHocSign(bundle)
        let exe = bundle.appendingPathComponent("Contents/MacOS/Plugin")
        XCTAssertEqual(chmod(exe.path, 0o777), 0)
        let verifier = BundleVerifier(policy: .anyValidSignature)
        expectRejection({ try verifier.verify(bundleAt: bundle, in: dir) }) { reason in
            if case let .writableByOthers(path, _) = reason { return path.hasSuffix("Contents/MacOS/Plugin") }
            return false
        }
    }

    func testSymlinkEscapingDirectoryIsRefused() throws {
        let dir = try makeTempDir()
        let outside = try makeTempDir()
        let target = try makeBundle(in: outside)
        try adHocSign(target)
        let link = dir.appendingPathComponent("Evil.bundle")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let verifier = BundleVerifier(policy: .anyValidSignature)
        expectRejection({ try verifier.verify(bundleAt: link, in: dir) }) { reason in
            if case let .symlinkEscapesDirectory(_, resolved) = reason { return resolved == target.path }
            return false
        }
    }

    func testSymlinkInsideDirectoryIsFollowed() throws {
        let dir = try makeTempDir()
        let real = try makeBundle(in: dir, name: "Real")
        try adHocSign(real)
        let link = dir.appendingPathComponent("Alias.bundle")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let signer = try BundleVerifier(policy: .anyValidSignature).verify(bundleAt: link, in: dir)
        XCTAssertEqual(signer.bundleURL.standardizedFileURL.path, real.standardizedFileURL.path)
    }

    func testDefaultBundleDirectory() {
        let path = ProfileRegistry.defaultBundleDirectory.path
        XCTAssertTrue(path.hasSuffix("Library/Application Support/Caffe Island/Profiles"), path)
    }

    // MARK: - Registry integration (verification only; nothing is loaded)

    func testLoadBundlesSkipsBadBundlesAndAsksApproval() async throws {
        let dir = try makeTempDir()
        _ = try makeBundle(in: dir, name: "Unsigned")
        let good = try makeBundle(in: dir, name: "Signed")
        try adHocSign(good)

        let asked = SignerLog()
        let registry = ProfileRegistry()
        let result = await registry.loadBundles(from: dir, policy: .anyValidSignature) { signer in
            await asked.append(signer)
            return false
        }

        XCTAssertTrue(result.loaded.isEmpty)
        XCTAssertEqual(result.rejections.count, 2)
        let byName = Dictionary(uniqueKeysWithValues: result.rejections.map { ($0.url.lastPathComponent, $0.reason) })
        XCTAssertEqual(byName["Unsigned.bundle"], .unsigned)
        guard case let .notApprovedByUser(signer)? = byName["Signed.bundle"] else {
            return XCTFail("signed bundle should reach the approval hook: \(result.rejections)")
        }
        XCTAssertEqual(signer.signingIdentifier, "ch.dynamic-caffe-island.tests.signed")
        let seen = await asked.all
        XCTAssertEqual(seen.map(\.signingIdentifier), ["ch.dynamic-caffe-island.tests.signed"])
        let registered = await registry.registeredProfiles
        XCTAssertTrue(registered.isEmpty)
    }

    func testLoadBundlesDefaultsToDeny() async throws {
        let dir = try makeTempDir()
        let good = try makeBundle(in: dir)
        try adHocSign(good)
        let result = await ProfileRegistry().loadBundles(from: dir, policy: .anyValidSignature)
        XCTAssertTrue(result.loaded.isEmpty)
        guard case .notApprovedByUser? = result.rejections.first?.reason else {
            return XCTFail("expected default deny, got \(result.rejections)")
        }
    }

    func testLoadBundlesRejectsUntrustedDirectory() async throws {
        let dir = try makeTempDir()
        let good = try makeBundle(in: dir)
        try adHocSign(good)
        XCTAssertEqual(chmod(dir.path, 0o777), 0)
        let result = await ProfileRegistry().loadBundles(from: dir, policy: .anyValidSignature) { _ in true }
        XCTAssertTrue(result.loaded.isEmpty)
        XCTAssertEqual(result.rejections.count, 1)
        XCTAssertEqual(result.rejections.first?.url, dir)
    }

    func testLoadBundlesMissingDirectoryIsEmpty() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundleVerifierTests-missing-\(UUID().uuidString)")
        let result = await ProfileRegistry().loadBundles(from: missing)
        XCTAssertEqual(result, BundleLoadResult())
    }
}

private actor SignerLog {
    private(set) var all: [BundleSignerInfo] = []
    func append(_ s: BundleSignerInfo) { all.append(s) }
}
