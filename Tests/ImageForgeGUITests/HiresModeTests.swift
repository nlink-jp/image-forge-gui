import XCTest
@testable import ImageForgeGUI

/// `HiresMode` backs the Composer's Hires picker and the gallery "Reuse All
/// Parameters" path: a request's stored `hires` string must map back to the same
/// mode it was sent as.
final class HiresModeTests: XCTestCase {
    func testValueForEachMode() {
        XCTAssertNil(HiresMode.standard.value)
        XCTAssertEqual(HiresMode.off.value, "off")
        XCTAssertEqual(HiresMode.auto.value, "auto")
        XCTAssertEqual(HiresMode.on.value, "on")
    }

    func testInitFromStoredValue() {
        XCTAssertEqual(HiresMode(value: "off"), .off)
        XCTAssertEqual(HiresMode(value: "auto"), .auto)
        XCTAssertEqual(HiresMode(value: "on"), .on)
    }

    func testInitDefaultsToStandardForNilOrUnknown() {
        XCTAssertEqual(HiresMode(value: nil), .standard)
        XCTAssertEqual(HiresMode(value: ""), .standard)
        XCTAssertEqual(HiresMode(value: "garbage"), .standard)
    }

    /// Round-trip: a mode's `value` re-parses to the same mode (the reuse path).
    func testRoundTrip() {
        for mode in HiresMode.allCases {
            XCTAssertEqual(HiresMode(value: mode.value), mode, "\(mode) did not round-trip")
        }
    }
}
