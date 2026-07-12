import XCTest
@testable import ImageForgeGUI

final class ModelInfoTests: XCTestCase {
    /// The default `models list --json` output is a bare array of installed
    /// models (matches image-forge's installedView; extra keys are ignored).
    func testDecodeBareInstalledArray() throws {
        let json = """
        [
          {"name":"realvisxl-v5","arch":"sdxl","rating":"safe",
           "license":"CreativeML Open RAIL++-M","path":"/m/realvis.safetensors",
           "vae_path":"/m/sdxl.vae.safetensors","multi_component":false,"in_catalog":true},
          {"name":"flux1-schnell","arch":"flux","rating":"safe","license":"Apache-2.0",
           "multi_component":true,"in_catalog":true}
        ]
        """
        let models = try ModelInfo.decodeInstalled(from: Data(json.utf8))
        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(models[0].name, "realvisxl-v5")
        XCTAssertEqual(models[0].arch, "sdxl")
        XCTAssertEqual(models[0].path, "/m/realvis.safetensors")
        XCTAssertEqual(models[0].inCatalog, true)
        XCTAssertEqual(models[0].id, "realvisxl-v5")
        XCTAssertTrue(models[0].isDiffusion)
        XCTAssertNil(models[1].path) // flux has no single-file path
    }

    /// `--all` wraps the arrays; decodeInstalled must accept that shape too and
    /// return just the installed models.
    func testDecodeWrappedAllOutput() throws {
        let json = """
        {"installed":[{"name":"illustrious-xl-v1.1","arch":"sdxl","multi_component":false,"in_catalog":true}],
         "catalog":[{"name":"some-catalog-only","arch":"sdxl"}]}
        """
        let models = try ModelInfo.decodeInstalled(from: Data(json.utf8))
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0].name, "illustrious-xl-v1.1")
    }

    /// An upscaler carries kind="upscaler" and must be excluded from the
    /// diffusion picker.
    func testUpscalerKindNotDiffusion() throws {
        let json = """
        [{"name":"realesrgan-x4plus","kind":"upscaler","arch":"","in_catalog":true}]
        """
        let models = try ModelInfo.decodeInstalled(from: Data(json.utf8))
        XCTAssertEqual(models[0].kind, "upscaler")
        XCTAssertFalse(models[0].isDiffusion)
    }

    func testEmptyArray() throws {
        let models = try ModelInfo.decodeInstalled(from: Data("[]".utf8))
        XCTAssertTrue(models.isEmpty)
    }

    /// page_url (the model's Civitai / HF page) decodes into pageURL and pageLink,
    /// which the "open model page" link uses. A model without it yields no link.
    func testPageURLDecodesForInstalledAndCatalog() throws {
        let json = """
        [
          {"name":"anima-yume","arch":"anima","in_catalog":true,
           "page_url":"https://civitai.com/model-versions/3065644"},
          {"name":"my-local","arch":"sdxl","in_catalog":false}
        ]
        """
        let models = try ModelInfo.decodeInstalled(from: Data(json.utf8))
        XCTAssertEqual(models[0].pageURL, "https://civitai.com/model-versions/3065644")
        XCTAssertEqual(models[0].pageLink?.host, "civitai.com")
        XCTAssertNil(models[1].pageURL)
        XCTAssertNil(models[1].pageLink) // a local model has no page link

        let catJSON = """
        [{"name":"flux1-schnell","arch":"flux","kind":"",
          "page_url":"https://huggingface.co/leejet/FLUX.1-schnell-gguf"}]
        """
        let cat = try CatalogEntry.decodeCatalog(from: Data(catJSON.utf8))
        XCTAssertEqual(cat[0].pageLink?.host, "huggingface.co")
    }
}
