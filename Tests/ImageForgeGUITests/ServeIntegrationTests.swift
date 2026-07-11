import XCTest
@testable import ImageForgeGUI

/// Real end-to-end: drives a resident `image-forge serve` and generates one
/// image. Requires the real (cgo) image-forge binary and an installed model, so
/// it is skipped unless `IMAGE_FORGE_GUI_E2E=1` is set (not part of normal CI).
///
///   IMAGE_FORGE_GUI_E2E=1 swift test --filter ServeIntegrationTests
final class ServeIntegrationTests: XCTestCase {
    func testGenerateRoundTrip() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["IMAGE_FORGE_GUI_E2E"] != nil,
            "set IMAGE_FORGE_GUI_E2E=1 (and $IMAGE_FORGE_BIN or ~/bin/image-forge) to run")

        let client = try ServeClient()
        let stream = try client.start()
        defer { client.stop() }

        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("ifgui-e2e-\(UUID().uuidString).png").path
        var req = GenerationRequest(prompt: "a small red apple", output: out)
        req.model = "sd15-emaonly"
        req.steps = 6
        req.seed = 5
        try client.send(req)

        // Whichever finishes first: a matching `done`/`error`, the stream ending,
        // or a 200s timeout.
        let outcome = await withTaskGroup(of: String.self) { group -> String in
            group.addTask {
                for await ev in stream {
                    if ev.kind == .done, ev.output == out { return "done" }
                    if ev.kind == .error { return "error:\(ev.message ?? "")" }
                }
                return "stream-ended"
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 200_000_000_000)
                return "timeout"
            }
            let first = await group.next() ?? "none"
            group.cancelAll()
            return first
        }

        XCTAssertEqual(outcome, "done", "serve round-trip did not complete")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: out),
            "engine reported done but the PNG is missing at \(out)")
    }

    /// Real end-to-end for the Manage Models window (ADR-0001): the curated
    /// catalog decodes from the actual `models list --catalog --json` output.
    /// Read-only, so it only needs the binary (no model / no network).
    func testListCatalogDecodesFromRealBinary() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["IMAGE_FORGE_GUI_E2E"] != nil,
            "set IMAGE_FORGE_GUI_E2E=1 (and $IMAGE_FORGE_BIN or ~/bin/image-forge) to run")
        let client = try ServeClient()
        let catalog = try await client.listCatalog()
        XCTAssertFalse(catalog.isEmpty, "catalog should not be empty")
        // Every entry has a name; base diffusion models also carry an arch
        // (auxiliary kinds like upscalers legitimately have an empty arch).
        for e in catalog {
            XCTAssertFalse(e.name.isEmpty, "catalog entry with no name")
            if e.isDiffusion {
                XCTAssertFalse(e.arch.isEmpty, "diffusion model \(e.name) has no arch")
            }
        }
        // The classic smoke-test model is always in the catalog.
        XCTAssertTrue(catalog.contains { $0.name == "sd15-emaonly" },
                      "expected sd15-emaonly in the catalog")
    }
}
