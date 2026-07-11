import XCTest
@testable import ImageForgeGUI

/// Model management (ADR-0001): catalog decoding, pull-progress parsing, the arg
/// builders, and the streaming one-shot that surfaces `models pull` progress.
final class ManageModelsTests: XCTestCase {

    // MARK: - CatalogEntry decoding

    func testDecodeCatalogArray() throws {
        let json = """
        [
          {"name":"sd15-emaonly","arch":"sd15","prediction":"eps","rating":"safe",
           "license":"CreativeML OpenRAIL-M","min_ram_gb":8,"rec_ram_gb":16,
           "multi_component":false,"needs_opt_in":false,"installed":true,
           "notes":"Classic SD1.5."},
          {"name":"noobai-xl-vpred","arch":"sdxl","rating":"explicit",
           "needs_opt_in":true,"installed":false,"kind":""}
        ]
        """.data(using: .utf8)!
        let entries = try CatalogEntry.decodeCatalog(from: json)
        XCTAssertEqual(entries.count, 2)
        let sd15 = entries[0]
        XCTAssertEqual(sd15.name, "sd15-emaonly")
        XCTAssertEqual(sd15.recRAMGB, 16)
        XCTAssertTrue(sd15.isInstalled)
        XCTAssertFalse(sd15.requiresOptIn)
        XCTAssertTrue(sd15.isDiffusion)
        XCTAssertEqual(sd15.kindLabel, "SD15")

        let noob = entries[1]
        XCTAssertTrue(noob.requiresOptIn)
        XCTAssertFalse(noob.isInstalled)
    }

    func testDecodeCatalogWrapperFallback() throws {
        // `--all` wraps the catalog under a "catalog" key.
        let json = """
        {"installed":[],"catalog":[{"name":"x","arch":"sdxl"}]}
        """.data(using: .utf8)!
        let entries = try CatalogEntry.decodeCatalog(from: json)
        XCTAssertEqual(entries.map(\.name), ["x"])
    }

    // MARK: - Progress parsing

    func testParseProgressPercent() throws {
        try XCTAssertEqual(XCTUnwrap(AppModel.parseProgress("62%").fraction), 0.62, accuracy: 0.0001)
        try XCTAssertEqual(XCTUnwrap(AppModel.parseProgress("  7%").fraction), 0.07, accuracy: 0.0001)
        try XCTAssertEqual(XCTUnwrap(AppModel.parseProgress("100%").fraction), 1.0, accuracy: 0.0001)
        XCTAssertNil(AppModel.parseProgress("62%").status)
    }

    func testParseProgressStatus() {
        let p = AppModel.parseProgress("pulling animagine-xl-4.0.safetensors")
        XCTAssertNil(p.fraction)
        XCTAssertEqual(p.status, "pulling animagine-xl-4.0.safetensors")
        // A percentage embedded in a larger string is treated as status, not a bare %.
        XCTAssertNil(AppModel.parseProgress("done 100% complete").fraction)
    }

    func testParseProgressEmpty() {
        XCTAssertNil(AppModel.parseProgress("   ").fraction)
        XCTAssertNil(AppModel.parseProgress("   ").status)
    }

    // MARK: - ProgressBuffer (splits on \n and \r)

    func testProgressBufferSplitsOnNewlineAndCarriageReturn() {
        var buf = ProgressBuffer()
        // `\r`-updated percentages interleaved with `\n` status lines.
        let segs = buf.append("pulling foo\n\r  0%\r 50%\r100%\n".data(using: .utf8)!)
        XCTAssertEqual(segs, ["pulling foo", "0%", "50%", "100%"])
    }

    func testProgressBufferRetainsPartialSegment() {
        var buf = ProgressBuffer()
        XCTAssertEqual(buf.append("pul".data(using: .utf8)!), [])
        XCTAssertEqual(buf.append("ling\n".data(using: .utf8)!), ["pulling"])
    }

    // MARK: - Arg builders

    func testPullArgs() {
        XCTAssertEqual(ServeClient.pullArgs(name: "foo", allowNSFW: false), ["models", "pull", "foo"])
        XCTAssertEqual(ServeClient.pullArgs(name: "foo", allowNSFW: true),
                       ["models", "pull", "foo", "--allow-nsfw"])
    }

    func testRemoveArgs() {
        XCTAssertEqual(ServeClient.removeArgs(name: "foo", purge: false), ["models", "rm", "foo"])
        XCTAssertEqual(ServeClient.removeArgs(name: "foo", purge: true),
                       ["models", "rm", "foo", "--purge"])
    }

    // MARK: - runStreaming (live stderr segments)

    func testRunStreamingDeliversProgressSegments() async throws {
        // A stand-in "pull": prints a status line + `\r`-updated percentages to
        // stderr, and a final path to stdout. Mirrors image-forge's format.
        let script = #"printf 'pulling x\n' 1>&2; printf '\r 25%%\r 50%%\r100%%\n' 1>&2; echo /tmp/x.safetensors"#
        let box = SegmentBox()
        let data = try await ServeClient.runStreaming(
            binary: URL(fileURLWithPath: "/bin/sh"), args: ["-c", script]
        ) { seg in box.add(seg) }
        let out = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(out.contains("/tmp/x.safetensors"), "stdout not returned: \(out)")
        let segs = box.all()
        XCTAssertTrue(segs.contains("pulling x"), "missing status: \(segs)")
        XCTAssertTrue(segs.contains("100%"), "missing final percent: \(segs)")
    }

    func testRunStreamingNonzeroExitThrows() async {
        let script = "printf 'boom\\n' 1>&2; exit 4"
        do {
            _ = try await ServeClient.runStreaming(
                binary: URL(fileURLWithPath: "/bin/sh"), args: ["-c", script]) { _ in }
            XCTFail("expected a throw on nonzero exit")
        } catch {
            XCTAssertTrue("\(error)".contains("boom") || (error as? ServeClient.ServeError) != nil)
        }
    }
}

/// Thread-safe collector for `runStreaming`'s background-delivered segments.
private final class SegmentBox: @unchecked Sendable {
    private var segs: [String] = []
    private let lock = NSLock()
    func add(_ s: String) { lock.lock(); segs.append(s); lock.unlock() }
    func all() -> [String] { lock.lock(); defer { lock.unlock() }; return segs }
}
