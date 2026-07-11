import XCTest
import AppKit
@testable import ImageForgeGUI

/// MaskDrawing.renderPNG is the verifiable core of the inpaint mask editor: it must
/// produce a same-size grayscale PNG, white where painted (regenerate) and black
/// where kept, with erase and invert honored and the right top/bottom orientation.
final class MaskEditorTests: XCTestCase {
    /// White component (0=black … 1=white) at a pixel of a rendered PNG.
    /// NSBitmapImageRep is top-left origin (row 0 = top of the image).
    private func white(_ data: Data, _ x: Int, _ y: Int) throws -> CGFloat {
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
        let c = try XCTUnwrap(rep.colorAt(x: x, y: y)?.usingColorSpace(.genericGray))
        return c.whiteComponent
    }

    func testRenderSizeAndCenterPainted() throws {
        var d = MaskDrawing()
        d.add(MaskStamp(x: 0.5, y: 0.5, radius: 0.25, erase: false))
        let png = try XCTUnwrap(d.renderPNG(width: 80, height: 60))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(rep.pixelsWide, 80)
        XCTAssertEqual(rep.pixelsHigh, 60)
        try XCTAssertEqual(white(png, 40, 30), 1, accuracy: 0.05, "center painted = white")
        try XCTAssertEqual(white(png, 2, 2), 0, accuracy: 0.05, "corner kept = black")
    }

    func testOrientationTopPaintMapsToTop() throws {
        // Painting near the top of the displayed image (screen y small) must be
        // white at the top of the PNG (row near 0), not flipped to the bottom.
        var d = MaskDrawing()
        d.add(MaskStamp(x: 0.5, y: 0.12, radius: 0.15, erase: false))
        let png = try XCTUnwrap(d.renderPNG(width: 64, height: 64))
        try XCTAssertEqual(white(png, 32, 6), 1, accuracy: 0.05, "top region painted")
        try XCTAssertEqual(white(png, 32, 58), 0, accuracy: 0.05, "bottom region kept")
    }

    func testEraseRemovesPaint() throws {
        var d = MaskDrawing()
        d.add(MaskStamp(x: 0.5, y: 0.5, radius: 0.3, erase: false))
        d.add(MaskStamp(x: 0.5, y: 0.5, radius: 0.3, erase: true))
        let png = try XCTUnwrap(d.renderPNG(width: 64, height: 64))
        try XCTAssertEqual(white(png, 32, 32), 0, accuracy: 0.05, "erase paints the base back")
    }

    func testInvertSwaps() throws {
        var d = MaskDrawing()
        d.inverted = true
        d.add(MaskStamp(x: 0.5, y: 0.5, radius: 0.25, erase: false))
        let png = try XCTUnwrap(d.renderPNG(width: 64, height: 64))
        try XCTAssertEqual(white(png, 32, 32), 0, accuracy: 0.05, "inverted: painted → black")
        try XCTAssertEqual(white(png, 2, 2), 1, accuracy: 0.05, "inverted: base → white")
    }

    func testEmptyAndBadSize() {
        XCTAssertTrue(MaskDrawing().isEmpty)
        XCTAssertFalse(MaskDrawing(stamps: [MaskStamp(x: 0, y: 0, radius: 0.1, erase: false)]).isEmpty)
        XCTAssertNil(MaskDrawing().renderPNG(width: 0, height: 10))
        XCTAssertNil(MaskDrawing().renderPNG(width: 10, height: -1))
    }
}
