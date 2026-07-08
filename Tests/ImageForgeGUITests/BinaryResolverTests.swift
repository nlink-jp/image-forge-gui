import XCTest
@testable import ImageForgeGUI

/// Resolution order for the image-forge binary:
///   bundled → $IMAGE_FORGE_BIN → ~/bin/image-forge → each dir on $PATH.
final class BinaryResolverTests: XCTestCase {
    private let home = "/Users/tester"
    private let bundled = "/Applications/ImageForgeGUI.app/Contents/Resources/image-forge"
    private let envBin = "/custom/image-forge"

    func testBundledPreferredOverEverything() {
        let got = BinaryResolver.resolvePath(
            env: ["IMAGE_FORGE_BIN": envBin, "PATH": "/usr/bin"],
            homeDir: home,
            bundled: bundled,
            isExecutable: { _ in true } // everything present ⇒ bundled must win
        )
        XCTAssertEqual(got, bundled)
    }

    func testEnvOverrideWhenNoBundle() {
        let got = BinaryResolver.resolvePath(
            env: ["IMAGE_FORGE_BIN": envBin],
            homeDir: home,
            bundled: nil,
            isExecutable: { $0 == envBin || $0 == home + "/bin/image-forge" }
        )
        XCTAssertEqual(got, envBin)
    }

    func testHomeBinFallback() {
        let homeBin = home + "/bin/image-forge"
        let got = BinaryResolver.resolvePath(
            env: [:],
            homeDir: home,
            bundled: bundled,
            isExecutable: { $0 == homeBin } // only ~/bin present
        )
        XCTAssertEqual(got, homeBin)
    }

    func testPathSearchLast() {
        let got = BinaryResolver.resolvePath(
            env: ["PATH": "/usr/bin:/opt/homebrew/bin"],
            homeDir: home,
            bundled: bundled,
            isExecutable: { $0 == "/opt/homebrew/bin/image-forge" }
        )
        XCTAssertEqual(got, "/opt/homebrew/bin/image-forge")
    }

    func testEmptyEnvValuesIgnored() {
        // An empty $IMAGE_FORGE_BIN must not resolve to "/image-forge" or block
        // the ~/bin fallback.
        let homeBin = home + "/bin/image-forge"
        let got = BinaryResolver.resolvePath(
            env: ["IMAGE_FORGE_BIN": "", "PATH": ""],
            homeDir: home,
            bundled: nil,
            isExecutable: { $0 == homeBin }
        )
        XCTAssertEqual(got, homeBin)
    }

    func testNilWhenNothingExecutable() {
        let got = BinaryResolver.resolvePath(
            env: ["IMAGE_FORGE_BIN": envBin, "PATH": "/usr/bin:/bin"],
            homeDir: home,
            bundled: bundled,
            isExecutable: { _ in false }
        )
        XCTAssertNil(got)
    }
}
