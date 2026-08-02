import XCTest
@testable import ImageForgeGUI

/// A model whose weight files are gone (image-forge ADR-0008 `missing_files`) is
/// registered but cannot load — typically `models_dir` was re-pointed without
/// relocating the registry, or its volume isn't mounted. The GUI must decode that
/// signal and keep such a model out of every picker.
final class MissingModelTests: XCTestCase {
    func testDecodeMissingFiles() throws {
        let json = """
        [
          {"name":"animagine-xl-4","arch":"sdxl","in_catalog":true,
           "path":"/old/animagine-xl-4.safetensors",
           "missing_files":["/old/animagine-xl-4.safetensors"]},
          {"name":"realvisxl-v5","arch":"sdxl","in_catalog":true,
           "path":"/new/realvis.safetensors"}
        ]
        """
        let models = try ModelInfo.decodeInstalled(from: Data(json.utf8))
        XCTAssertEqual(models[0].missingFiles, ["/old/animagine-xl-4.safetensors"])
        XCTAssertTrue(models[0].isMissing)
        XCTAssertNil(models[1].missingFiles)
        XCTAssertFalse(models[1].isMissing, "a model with no missing_files key is healthy")
    }

    /// An older CLI omits the key entirely; that must read as healthy, not broken.
    func testAbsentKeyMeansHealthy() throws {
        let json = """
        [{"name":"legacy","arch":"sdxl","path":"/m/legacy.safetensors","in_catalog":false}]
        """
        let models = try ModelInfo.decodeInstalled(from: Data(json.utf8))
        XCTAssertFalse(models[0].isMissing)
    }

    /// An empty array is the same as absent — no false alarm.
    func testEmptyMissingFilesIsHealthy() throws {
        let json = """
        [{"name":"ok","arch":"sdxl","path":"/m/ok.safetensors","missing_files":[]}]
        """
        let models = try ModelInfo.decodeInstalled(from: Data(json.utf8))
        XCTAssertFalse(models[0].isMissing)
    }

    @MainActor
    func testPickersExcludeMissingModels() throws {
        let json = """
        [
          {"name":"base-ok","arch":"sdxl","in_catalog":true,"path":"/new/base.safetensors"},
          {"name":"base-gone","arch":"sdxl","in_catalog":true,"path":"/old/base.safetensors",
           "missing_files":["/old/base.safetensors"]},
          {"name":"lora-ok","kind":"lora","arch":"sdxl","path":"/new/l.safetensors"},
          {"name":"lora-gone","kind":"lora","arch":"sdxl","path":"/old/l2.safetensors",
           "missing_files":["/old/l2.safetensors"]},
          {"name":"cn-ok","kind":"controlnet","arch":"sdxl","path":"/new/cn.safetensors"},
          {"name":"cn-gone","kind":"controlnet","arch":"sdxl","path":"/old/cn.safetensors",
           "missing_files":["/old/cn.safetensors"]},
          {"name":"up-ok","kind":"upscaler","arch":"","path":"/new/up.pth"},
          {"name":"up-gone","kind":"upscaler","arch":"","path":"/old/up.pth",
           "missing_files":["/old/up.pth"]}
        ]
        """
        let app = AppModel()
        app.models = try ModelInfo.decodeInstalled(from: Data(json.utf8))

        XCTAssertEqual(app.missingModels.map(\.name).sorted(),
                       ["base-gone", "cn-gone", "lora-gone", "up-gone"])
        XCTAssertEqual(app.upscalerModels.map(\.name), ["up-ok"])
        XCTAssertEqual(app.loras(forArch: "sdxl").map(\.name), ["lora-ok"])
        XCTAssertEqual(app.controlNetModels(forArch: "sdxl").map(\.name), ["cn-ok"])
    }
}
