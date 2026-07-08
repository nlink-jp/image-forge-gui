import XCTest
@testable import ImageForgeGUI

/// Pure selection / file-placement helpers backing the gallery's multi-select
/// batch operations (⇧-click range selection, export/move collision-avoidance).
final class SelectionTests: XCTestCase {
    func testRangeIDsInclusiveEitherDirection() {
        let ids = (0..<5).map { _ in UUID() }
        XCTAssertEqual(AppModel.rangeIDs(from: ids[1], to: ids[3], in: ids), Array(ids[1...3]))
        // Reversed anchor/target yields the same slice in list order.
        XCTAssertEqual(AppModel.rangeIDs(from: ids[3], to: ids[1], in: ids), Array(ids[1...3]))
        // Same id → a single-element range.
        XCTAssertEqual(AppModel.rangeIDs(from: ids[2], to: ids[2], in: ids), [ids[2]])
    }

    func testRangeIDsNilWhenAbsent() {
        let ids = (0..<3).map { _ in UUID() }
        XCTAssertNil(AppModel.rangeIDs(from: UUID(), to: ids[0], in: ids))
        XCTAssertNil(AppModel.rangeIDs(from: ids[0], to: UUID(), in: ids))
    }

    func testUniqueDestinationAppendsSuffixOnCollision() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // No collision → the name is used as-is.
        let first = AppModel.uniqueDestination(dir: dir, name: "img.png")
        XCTAssertEqual(first.lastPathComponent, "img.png")

        // With that file present, the next placement bumps to "img 2.png", then "img 3.png".
        try Data().write(to: first)
        let second = AppModel.uniqueDestination(dir: dir, name: "img.png")
        XCTAssertEqual(second.lastPathComponent, "img 2.png")
        try Data().write(to: second)
        XCTAssertEqual(AppModel.uniqueDestination(dir: dir, name: "img.png").lastPathComponent, "img 3.png")
    }
}
