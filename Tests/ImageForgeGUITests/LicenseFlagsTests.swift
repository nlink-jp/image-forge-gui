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
}
