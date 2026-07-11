import XCTest
@testable import ImageForgeGUI

/// The GUI highlights license restrictions from the CLI's license_flags; these
/// pin the decode + the hasLicenseFlags convenience the License section uses.
final class LicenseFlagsTests: XCTestCase {
    func testDecodesLicenseFlags() throws {
        let json = """
        [{"name":"dmd2","arch":"sdxl","kind":"lora","license":"CC BY-NC 4.0",
          "license_flags":["non-commercial","attribution"]},
         {"name":"mythic","arch":"sdxl","kind":"lora","license":"permissive"}]
        """.data(using: .utf8)!
        let m = try ModelInfo.decodeInstalled(from: json)
        XCTAssertEqual(m[0].licenseFlags, ["non-commercial", "attribution"])
        XCTAssertTrue(m[0].hasLicenseFlags)
        XCTAssertNil(m[1].licenseFlags)
        XCTAssertFalse(m[1].hasLicenseFlags, "a model with no flags is permissive")
    }

    func testDecodesAttribution() throws {
        let json = """
        [{"name":"illustrious","arch":"sdxl","license_flags":["attribution"],
          "attribution":"Illustrious XL by ONOMAAI (Civitai)"},
         {"name":"free","arch":"sdxl"}]
        """.data(using: .utf8)!
        let m = try ModelInfo.decodeInstalled(from: json)
        XCTAssertEqual(m[0].creditText, "Illustrious XL by ONOMAAI (Civitai)")
        XCTAssertNil(m[1].creditText, "no attribution → no credit text")
    }

    /// combinedCredit gathers the attribution of every model in use, de-duplicated,
    /// joined the same way image-forge writes it into the PNG metadata.
    func testCombinedCredit() {
        func info(_ name: String, _ credit: String?) -> ModelInfo {
            var m = ModelInfo(name: name, arch: "sdxl")
            m.attribution = credit
            return m
        }
        // Base + LoRA both crediting → both, in order.
        XCTAssertEqual(
            AppModel.combinedCredit(forModels: [
                info("base", "Base by A"), info("lora", "LoRA by B"),
            ]),
            "Base by A · LoRA by B")
        // Duplicate credit text collapses to one.
        XCTAssertEqual(
            AppModel.combinedCredit(forModels: [
                info("base", "Same Studio"), info("lora", "Same Studio"),
            ]),
            "Same Studio")
        // Permissive models contribute nothing.
        XCTAssertEqual(
            AppModel.combinedCredit(forModels: [info("base", nil), info("lora", nil)]),
            "")
    }
}
