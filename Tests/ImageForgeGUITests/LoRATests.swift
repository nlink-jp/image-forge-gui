import XCTest
@testable import ImageForgeGUI

/// The Composer stacks LoRAs and sends serve a `loras: ["<path>:<weight>"]`
/// payload. Selections are made by registry name; the payload carries resolved
/// paths so an older bundled CLI (which can't resolve names) still works.
final class LoRATests: XCTestCase {
    private let models: [ModelInfo] = [
        ModelInfo(name: "animagine-xl-4", arch: "sdxl", path: "/m/anim.safetensors", kind: nil),
        ModelInfo(name: "lcm-lora-sdxl", arch: "sdxl", path: "/m/lcm-xl.safetensors", kind: "lora"),
        ModelInfo(name: "lcm-lora-sd15", arch: "sd15", path: "/m/lcm-15.safetensors", kind: "lora"),
        ModelInfo(name: "canny-sdxl", arch: "sdxl", path: "/m/canny.safetensors", kind: "controlnet"),
        ModelInfo(name: "realesrgan-x4plus", arch: "", path: "/m/esrgan.pth", kind: "upscaler"),
    ]

    func testKindPredicates() {
        XCTAssertTrue(models[0].isDiffusion)
        XCTAssertTrue(models[1].isLoRA)
        XCTAssertTrue(models[3].isControlNet)
        XCTAssertFalse(models[1].isDiffusion)
        XCTAssertFalse(models[4].isLoRA)
    }

    func testArchMatchIsCaseInsensitive() {
        XCTAssertTrue(models[1].matchesArch("SDXL"))
        XCTAssertTrue(models[1].matchesArch("sdxl"))
        XCTAssertFalse(models[1].matchesArch("sd15"))
    }

    func testPayloadUsesResolvedPathAndWeight() {
        let got = AppModel.loraPayload(
            selections: [(name: "lcm-lora-sdxl", weight: 0.8)], models: models)
        XCTAssertEqual(got, ["/m/lcm-xl.safetensors:0.8"])
    }

    /// A weight of 1.0 formats as "1", not "1.00" (%g), matching the CLI's parser.
    func testPayloadFormatsWeightCompactly() {
        let got = AppModel.loraPayload(
            selections: [(name: "lcm-lora-sdxl", weight: 1.0)], models: models)
        XCTAssertEqual(got, ["/m/lcm-xl.safetensors:1"])
    }

    func testPayloadStacksInOrder() {
        let got = AppModel.loraPayload(
            selections: [(name: "lcm-lora-sdxl", weight: 1.0),
                         (name: "lcm-lora-sd15", weight: 0.5)],
            models: models)
        XCTAssertEqual(got, ["/m/lcm-xl.safetensors:1", "/m/lcm-15.safetensors:0.5"])
    }

    /// Unknown names, non-LoRA kinds, and path-less entries are skipped, never
    /// sent to the engine as a bogus path.
    func testPayloadSkipsInvalidSelections() {
        let pathless = ModelInfo(name: "ghost-lora", arch: "sdxl", path: nil, kind: "lora")
        let all = models + [pathless]
        let got = AppModel.loraPayload(
            selections: [(name: "no-such", weight: 1.0),        // unknown
                         (name: "animagine-xl-4", weight: 1.0), // diffusion, not a LoRA
                         (name: "canny-sdxl", weight: 1.0),     // controlnet
                         (name: "ghost-lora", weight: 1.0)],    // no path
            models: all)
        XCTAssertEqual(got, [])
    }

    /// `loras` must reach the wire under the key serve expects, and be omitted
    /// entirely when unset.
    func testGenerationRequestEncodesLoras() throws {
        var req = GenerationRequest(prompt: "x", output: "/tmp/o.png")
        req.loras = ["/m/lcm-xl.safetensors:1"]
        let obj = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(req)) as? [String: Any])
        XCTAssertEqual(obj["loras"] as? [String], ["/m/lcm-xl.safetensors:1"])

        let bare = GenerationRequest(prompt: "x", output: "/tmp/o.png")
        let bareObj = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(bare)) as? [String: Any])
        XCTAssertNil(bareObj["loras"], "loras must be omitted when unset")
    }
}
