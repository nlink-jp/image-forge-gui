import XCTest
@testable import ImageForgeGUI

/// The Composer's ControlNet section: a single arch-compatible ControlNet + a
/// control image steer generation. Selection is by registry name; the payload
/// carries the resolved path (like LoRAs) so an older bundled CLI still works.
final class ControlNetTests: XCTestCase {
    private let models: [ModelInfo] = [
        ModelInfo(name: "sd15-emaonly", arch: "sd15", path: "/m/sd15.safetensors", kind: nil),
        ModelInfo(name: "juggernaut-xl", arch: "sdxl", path: "/m/jug.safetensors", kind: nil),
        ModelInfo(name: "controlnet-canny-sd15", arch: "sd15", path: "/m/cn15.safetensors", kind: "controlnet"),
        ModelInfo(name: "canny-sdxl", arch: "sdxl", path: "/m/cnxl.safetensors", kind: "controlnet"),
        ModelInfo(name: "lcm-lora-sd15", arch: "sd15", path: "/m/lcm15.safetensors", kind: "lora"),
    ]

    /// ControlNets are arch-bound like LoRAs — an SDXL base is offered only SDXL
    /// ControlNets, never the SD1.5 one (ADR-0006). This is the exact predicate
    /// `AppModel.controlNetModels(forArch:)` filters on.
    func testControlNetIsArchBoundLikeLoRA() {
        func controlNets(forArch a: String) -> [String] {
            models.filter { $0.isControlNet && $0.matchesArch(a) }.map(\.name)
        }
        XCTAssertEqual(controlNets(forArch: "sd15"), ["controlnet-canny-sd15"])
        XCTAssertEqual(controlNets(forArch: "SDXL"), ["canny-sdxl"]) // case-insensitive
        XCTAssertTrue(controlNets(forArch: "flux").isEmpty)
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
