import Foundation
import XCTest
@testable import Ansomnia

/// Static checks on .github/workflows/*.yml and the release packaging:
/// every action is pinned to a commit SHA with its version alongside, no job
/// runs with the default token permissions, release.yml publishes a DMG for
/// each new version in Resources/Info.plist, and the files the in-app
/// updater downloads are the ones the workflow uploads. Plain text checks;
/// the files are small and have no YAML anchors.
final class ReleaseWorkflowTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private var workflowsDir: URL { repoRoot.appendingPathComponent(".github/workflows", isDirectory: true) }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
    }

    private func workflows() throws -> [(name: String, text: String)] {
        let names = try FileManager.default.contentsOfDirectory(atPath: workflowsDir.path).filter { $0.hasSuffix(".yml") }.sorted()
        XCTAssertTrue(names.contains("release.yml"), "\(names)")
        return try names.map { ($0, try String(contentsOf: workflowsDir.appendingPathComponent($0), encoding: .utf8)) }
    }

    private func lines(_ text: String) -> [String] { text.components(separatedBy: "\n") }

    private func releaseWorkflow() throws -> String { try read(".github/workflows/release.yml") }

    func testEveryActionIsPinnedToACommitSHAWithItsVersionNoted() throws {
        let pinned = try NSRegularExpression(pattern: #"^\s*-?\s*uses:\s*[\w.-]+/[\w./-]+@[0-9a-f]{40}\s+#\s*v\d+(\.\d+)*\s*$"#)
        for (name, text) in try workflows() {
            let uses = lines(text).filter { $0.range(of: #"^\s*-?\s*uses:"#, options: .regularExpression) != nil }
            XCTAssertFalse(uses.isEmpty, "\(name) uses no actions?")
            for line in uses {
                XCTAssertNotNil(pinned.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                                "\(name): not pinned to a full commit SHA with a version comment: \(line)")
            }
        }
    }

    /// The top level grants at most `contents: read`, and a job that needs
    /// more declares its own block.
    func testEveryJobDeclaresItsOwnPermissions() throws {
        for (name, text) in try workflows() {
            let ls = lines(text)
            let top = try XCTUnwrap(ls.firstIndex { $0.hasPrefix("permissions:") }, "\(name): no top-level permissions")
            var topScopes: [String] = []
            if ls[top] != "permissions: {}" {
                for line in ls[(top + 1)...] {
                    guard line.hasPrefix("  "), !line.trimmingCharacters(in: .whitespaces).isEmpty else { break }
                    topScopes.append(line.trimmingCharacters(in: .whitespaces))
                }
            }
            XCTAssertTrue(topScopes.isEmpty || topScopes == ["contents: read"], "\(name): top-level permissions grant more than contents: read: \(topScopes)")
        }
        let release = try releaseWorkflow()
        XCTAssertTrue(release.contains("    permissions:\n      contents: write\n"), "only the release job may write, and only contents")
        XCTAssertFalse(release.contains("pull_request"), "never runs for pull requests")
    }

    /// Every push to main builds and publishes a release when the version
    /// in Info.plist has no tag yet, and does nothing otherwise.
    func testThePushToMainPublishesEachNewVersionAsADMG() throws {
        let text = try releaseWorkflow()
        XCTAssertTrue(text.contains("on:\n  push:\n    branches: [main]\n  workflow_dispatch:\n"), "runs on pushes to main and by hand")
        XCTAssertTrue(text.contains("runs-on: macos-26"), "built on an Apple Silicon macOS 26 runner")
        XCTAssertTrue(text.contains("plutil -extract CFBundleShortVersionString raw -o - Resources/Info.plist"), "the version comes from Info.plist")
        XCTAssertTrue(text.contains(#"git ls-remote --exit-code --tags origin "refs/tags/v$version""#), "a version that has a tag is skipped")
        XCTAssertTrue(text.contains("scripts/make-dmg.sh --output dist"), "built with the DMG script")
        XCTAssertTrue(text.contains(#""dist/Ansomnia-$VERSION.dmg" dist/Ansomnia.dmg dist/SHA256SUMS"#), "the versioned DMG, the fixed-name DMG and the checksums are uploaded")
        XCTAssertTrue(text.contains("--latest"), "a new version is marked Latest")
        XCTAssertTrue(text.contains("--target \"$GITHUB_SHA\""), "the tag is made on the built commit")
        for absent in ["--clobber", "gh release delete", "gh release edit", "git push", "--prerelease"] {
            XCTAssertFalse(text.contains(absent), "release.yml contains \(absent)")
        }
    }

    /// What the workflow uploads is what the updater and the README fetch.
    func testTheUpdaterAndTheReadmeFetchWhatTheWorkflowUploads() throws {
        let version = try XCTUnwrap(SemanticVersion("0.5.0"))
        XCTAssertEqual(UpdateAsset.dmgName(version), "Ansomnia-0.5.0.dmg")
        XCTAssertEqual(UpdateAsset.downloadURL(version, file: "SHA256SUMS").absoluteString,
                       "https://github.com/AImunich20/Ansomnia/releases/download/v0.5.0/SHA256SUMS")
        XCTAssertEqual(GitHubReleaseFetcher.latestEndpoint.absoluteString, "https://api.github.com/repos/\(UpdateAsset.repository)/releases/latest")
        let script = try read("scripts/make-dmg.sh")
        XCTAssertTrue(script.contains(#"DMG="$OUTPUT/Ansomnia-$VERSION.dmg""#))
        XCTAssertTrue(script.contains(#"shasum -a 256 "Ansomnia-$VERSION.dmg" "Ansomnia.dmg" > SHA256SUMS"#) || script.contains(#""$SHASUM" -a 256 "Ansomnia-$VERSION.dmg" "Ansomnia.dmg" > SHA256SUMS"#))
        XCTAssertTrue(script.contains(#""$CP" "$ROOT/scripts/install.sh" "$ROOT/scripts/uninstall.sh" "$VOLUME/""#), "the DMG carries the installer the updater runs")
        XCTAssertTrue(try readmeInstallSection().contains("https://github.com/AImunich20/Ansomnia/releases/latest/download/Ansomnia.dmg"), "the README links the current DMG")
    }

    func testTheUpdaterReadsShasumListingsAndFollowsOnlyGitHubRedirects() {
        let hex = String(repeating: "ab", count: 32)
        let listing = "\(hex)  Ansomnia-0.5.0.dmg\n\(String(repeating: "cd", count: 32)) *Ansomnia.dmg\n"
        XCTAssertEqual(UpdateAsset.checksum(for: "Ansomnia-0.5.0.dmg", in: listing), hex)
        XCTAssertEqual(UpdateAsset.checksum(for: "Ansomnia.dmg", in: listing), String(repeating: "cd", count: 32))
        XCTAssertNil(UpdateAsset.checksum(for: "Other.dmg", in: listing))
        XCTAssertNil(UpdateAsset.checksum(for: "x.dmg", in: "nothex  x.dmg\n"))
        XCTAssertEqual(UpdateAsset.sha256(of: Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

        XCTAssertTrue(UpdateAsset.isTrustedRedirect(URL(string: "https://release-assets.githubusercontent.com/x")))
        XCTAssertTrue(UpdateAsset.isTrustedRedirect(URL(string: "https://github.com/AImunich20/Ansomnia/releases")))
        XCTAssertFalse(UpdateAsset.isTrustedRedirect(URL(string: "http://objects.githubusercontent.com/x")), "not over plain HTTP")
        XCTAssertFalse(UpdateAsset.isTrustedRedirect(URL(string: "https://githubusercontent.com.example.org/x")))
        XCTAssertFalse(UpdateAsset.isTrustedRedirect(URL(string: "https://example.org/x")))
    }

    func testTheInstallScriptQuotesTheDMGPathAndRunsTheDMGsInstaller() throws {
        let version = try XCTUnwrap(SemanticVersion("1.2.3"))
        let script = UpdateAsset.installScript(dmg: URL(fileURLWithPath: "/Users/o'neil/Caches/Ansomnia-1.2.3.dmg"), version: version)
        XCTAssertTrue(script.hasPrefix("#!/bin/bash\n"))
        XCTAssertTrue(script.contains(#"DMG='/Users/o'\''neil/Caches/Ansomnia-1.2.3.dmg'"#), script)
        XCTAssertTrue(script.contains(#"/usr/bin/hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$MNT" "$DMG""#))
        XCTAssertTrue(script.contains(#"/bin/bash "$MNT/install.sh" --allow-unverified-origin --app "$MNT/Ansomnia.app""#))
    }

    /// The release is ad-hoc signed: no signing or notarization step that
    /// could let a bundle skip --allow-unverified-origin.
    func testTheReleaseIsAdHocSignedWithNoSigningOrNotarizationStep() throws {
        let text = try releaseWorkflow()
        for absent in ["secrets.", "security ", "create-keychain", "notarytool", "stapler"] {
            XCTAssertFalse(text.contains(absent), "release.yml contains \(absent)")
        }
        let build = try read("scripts/build-app.sh")
        for absent in ["ANSOMNIA_SIGN_IDENTITY", "--options", "--timestamp"] {
            XCTAssertFalse(build.contains(absent), "build-app.sh contains \(absent)")
        }
        XCTAssertTrue(build.contains(#""$CODESIGN" --force --sign - "$APP""#), "build-app.sh signs ad-hoc")
        let install = try read("scripts/install.sh")
        for absent in ["spctl", "SPCTL", "EXPECTED_TEAM_ID", "TeamIdentifier"] {
            XCTAssertFalse(install.contains(absent), "install.sh contains \(absent)")
        }
    }

    /// Release bundles are arm64 only, so the notes and the README's
    /// Install section say a release needs an Apple Silicon Mac.
    func testTheNotesAndTheReadmeStateTheAppleSiliconRequirement() throws {
        XCTAssertTrue(try releaseWorkflow().contains(#"echo "Ansomnia $VERSION for Apple Silicon Macs with macOS 26 or later.""#))
        XCTAssertTrue(try readmeInstallSection().contains("Apple Silicon"), "the README's Install section")
    }

    /// The scripts the DMG carries sit at its top level. They take sibling
    /// scripts from their own folder only.
    func testTheDMGsScriptsTakeNothingFromTheFolderAboveTheirOwn() throws {
        for path in ["scripts/install.sh", "scripts/uninstall.sh"] {
            let script = try read(path)
            XCTAssertFalse(script.contains(#"BASH_SOURCE[0]}")/.."#), "\(path) resolves a path from the parent of its folder")
            XCTAssertTrue(script.contains(#"SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)""#), "\(path) has no SCRIPT_DIR")
        }
    }

    private func readmeInstallSection() throws -> String {
        let readme = try read("README.md")
        let install = try XCTUnwrap(readme.range(of: "\n## Install\n"), "README has no Install section")
        let end = readme.range(of: "\n## ", range: install.upperBound..<readme.endIndex)?.lowerBound ?? readme.endIndex
        return String(readme[install.upperBound..<end])
    }
}
