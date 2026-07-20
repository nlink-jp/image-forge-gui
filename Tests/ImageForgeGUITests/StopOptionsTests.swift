import XCTest
@testable import ImageForgeGUI

/// The Cancel button's wording and the batch ceiling. The dialog only appears
/// when the two stop choices actually differ, so its message must always be able
/// to name a non-zero queue.
final class StopOptionsTests: XCTestCase {
    func testMessageSingularForOneQueuedImage() {
        let msg = ComposerView.stopDialogMessage(queued: 1)
        XCTAssertTrue(msg.hasPrefix("1 image still queued."), msg)
    }

    func testMessagePluralForSeveralQueuedImages() {
        let msg = ComposerView.stopDialogMessage(queued: 37)
        XCTAssertTrue(msg.hasPrefix("37 images still queued."), msg)
    }

    /// Both outcomes are spelled out — which image is kept and which is lost is
    /// the whole point of the dialog.
    func testMessageExplainsBothOutcomes() {
        let msg = ComposerView.stopDialogMessage(queued: 5)
        XCTAssertTrue(msg.contains("discards"), msg)
        XCTAssertTrue(msg.contains("keeps it"), msg)
    }

    func testMaxCountIsFifty() {
        XCTAssertEqual(ComposerView.maxCount, 50)
    }
}
