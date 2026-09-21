import XCTest
@testable import ImageForgeGUI

/// The Composer's ControlNet section: a single arch-compatible ControlNet + a
/// control image steer generation. Selection is by registry name; the payload
/// carries the resolved path (like LoRAs) so an older bundled CLI still works.
final class ControlNetTests: XCTestCase {
    private let models: [ModelInfo] = [
        ModelInfo(name: "sd15-emaonly", arch: "sd15", archTrusted: true, path: "/m/sd15.safetensors", kind: nil),
        ModelInfo(name: "juggernaut-xl", arch: "SDXL", archTrusted: true, path: "/m/jug.safetensors", kind: nil),
        ModelInfo(name: "flux-base", arch: "flux", archTrusted: true, path: "/m/flux.safetensors", kind: nil),
        ModelInfo(name: "controlnet-canny-sd15", arch: "sd15", archTrusted: true, path: "/m/cn15.safetensors", kind: "controlnet"),
        ModelInfo(name: "canny-sdxl", arch: "sdxl", archTrusted: true, path: "/m/cnxl.safetensors", kind: "controlnet"),
        ModelInfo(name: "lcm-lora-sd15", arch: "sd15", archTrusted: true, path: "/m/lcm15.safetensors", kind: "lora"),
    ]

    /// ControlNets are arch-bound like LoRAs — an SDXL base is offered only SDXL
    /// ControlNets, never the SD1.5 one (ADR-0006), when both arches are facts.
    /// This is `AppModel.controlNetModels(forBase:)` itself.
    @MainActor
    func testControlNetIsArchBoundLikeLoRA() {
        let app = AppModel()
        app.models = models
        XCTAssertEqual(app.controlNetModels(forBase: "sd15-emaonly").map(\.name), ["controlnet-canny-sd15"])
        XCTAssertEqual(app.controlNetModels(forBase: "juggernaut-xl").map(\.name), ["canny-sdxl"]) // case-insensitive
        XCTAssertTrue(app.controlNetModels(forBase: "flux-base").isEmpty)
        XCTAssertTrue(app.controlNetModels(forBase: nil).isEmpty)
    }

    func testControlNetPathResolvesSelectedName() {
        XCTAssertEqual(
            AppModel.controlNetPath(name: "controlnet-canny-sd15", models: models),
            "/m/cn15.safetensors")
    }

    /// nil name, unknown name, a non-ControlNet kind, or a path-less entry all
    /// resolve to nil — never a bogus path to the engine.
    func testControlNetPathSkipsInvalid() {
        let pathless = ModelInfo(name: "ghost-cn", arch: "sd15", path: nil, kind: "controlnet")
        let all = models + [pathless]
        XCTAssertNil(AppModel.controlNetPath(name: nil, models: all))
        XCTAssertNil(AppModel.controlNetPath(name: "no-such", models: all))
        XCTAssertNil(AppModel.controlNetPath(name: "lcm-lora-sd15", models: all)) // a LoRA
        XCTAssertNil(AppModel.controlNetPath(name: "juggernaut-xl", models: all)) // diffusion
        XCTAssertNil(AppModel.controlNetPath(name: "ghost-cn", models: all))      // no path
    }
}
