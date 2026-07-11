import XCTest
@testable import ImageForgeGUI

/// `runOneShot` drives a short-lived subcommand (e.g. `image-forge upscale`). It
/// must drain stdout and stderr concurrently — `upscale` streams progress to
/// stderr throughout, so reading stdout to EOF first would let a >64 KiB stderr
/// stream fill the pipe buffer and deadlock (#1). /bin/sh stands in for a chatty
/// subcommand; 256 KiB is well past the pipe buffer, so a regression hangs here.
final class RunOneShotTests: XCTestCase {
    func testLargeStderrDoesNotDeadlock() async throws {
        let script = "yes x | head -c 262144 1>&2; echo OUTPUT_LINE"
        let data = try await ServeClient.runOneShot(
            binary: URL(fileURLWithPath: "/bin/sh"), args: ["-c", script])
        let out = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(out.contains("OUTPUT_LINE"), "stdout not returned: \(out.prefix(80))")
    }

    /// A nonzero exit surfaces the (large) stderr as the error — still no deadlock.
    func testNonzeroExitSurfacesLargeStderr() async {
        let script = "yes E | head -c 262144 1>&2; exit 3"
        do {
            _ = try await ServeClient.runOneShot(
                binary: URL(fileURLWithPath: "/bin/sh"), args: ["-c", script])
            XCTFail("expected a runFailed error on nonzero exit")
        } catch let ServeClient.ServeError.runFailed(stderr) {
            XCTAssertFalse(stderr.isEmpty, "stderr should be captured on failure")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
