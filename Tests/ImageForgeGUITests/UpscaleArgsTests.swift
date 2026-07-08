import XCTest
@testable import ImageForgeGUI

/// The gallery Upscale action runs a one-shot `image-forge upscale`; its argument
/// vector is built by a pure helper so we can test it without spawning a process.
final class UpscaleArgsTests: XCTestCase {
    func testBuildsUpscaleWithModel() {
        let args = ServeClient.upscaleArgs(
            input: "/lib/in.png", output: "/lib/out.png", model: "realesrgan-x4plus")
        XCTAssertEqual(args, ["upscale", "/lib/in.png", "-o", "/lib/out.png",
                              "--model", "realesrgan-x4plus"])
    }

    /// An empty model name omits `--model` so the CLI uses its configured default.
    func testOmitsModelWhenEmpty() {
        let args = ServeClient.upscaleArgs(input: "/a.png", output: "/b.png", model: "")
        XCTAssertEqual(args, ["upscale", "/a.png", "-o", "/b.png"])
        XCTAssertFalse(args.contains("--model"))
    }

    /// No `--scale` is ever passed (Real-ESRGAN ignores it; native factor governs).
    func testNeverPassesScale() {
        let args = ServeClient.upscaleArgs(input: "/a.png", output: "/b.png", model: "m")
        XCTAssertFalse(args.contains("--scale"))
    }
}
