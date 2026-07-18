import XCTest
@testable import ImageForgeGUI

/// The batch delete/trash kernel that backs "Move to Trash" and its
/// permanent-delete fallback. On a volume with no Trash (e.g. an SMB share)
/// `trashItem` throws; those ids must be partitioned out so the gallery can raise
/// an explicit permanent-delete confirmation instead of stranding the files.
final class DeleteFallbackTests: XCTestCase {
    private struct NoTrashOnVolume: Error {}

    private func items(_ n: Int) -> [(id: UUID, url: URL)] {
        (0..<n).map { (id: UUID(), url: URL(fileURLWithPath: "/vol/img\($0).png")) }
    }

    func testAllSucceedReportsNoFailures() {
        let batch = items(3)
        let outcome = AppModel.applyBatch(batch) { _ in /* trashed */ }
        XCTAssertEqual(outcome.ok, Set(batch.map(\.id)))
        XCTAssertTrue(outcome.failed.isEmpty)
    }

    func testAllFailArePartitionedForFallback() {
        let batch = items(3)
        let outcome = AppModel.applyBatch(batch) { _ in throw NoTrashOnVolume() }
        XCTAssertTrue(outcome.ok.isEmpty)
        // Every id is queued for the permanent-delete confirmation, carrying its URL.
        XCTAssertEqual(Set(outcome.failed.map(\.id)), Set(batch.map(\.id)))
        XCTAssertEqual(Set(outcome.failed.map(\.url)), Set(batch.map(\.url)))
    }

    /// A mixed selection (some files on a Trash-capable volume, some not) splits
    /// cleanly: the trashable ones are removed, the rest escalate to permanent delete.
    func testMixedSelectionSplitsSuccessAndFailure() {
        let batch = items(4)
        let strandedURLs: Set<URL> = [batch[1].url, batch[3].url]
        let outcome = AppModel.applyBatch(batch) { url in
            if strandedURLs.contains(url) { throw NoTrashOnVolume() }
        }
        XCTAssertEqual(outcome.ok, [batch[0].id, batch[2].id])
        XCTAssertEqual(Set(outcome.failed.map(\.id)), [batch[1].id, batch[3].id])
    }

    /// The fallback op is a real `removeItem`: prove it wires through, using an
    /// isolated temp directory (never touching real user data).
    func testPermanentDeleteOpRemovesRealFiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        var batch: [(id: UUID, url: URL)] = []
        for i in 0..<3 {
            let url = dir.appendingPathComponent("img\(i).png")
            try Data([0x89]).write(to: url)
            batch.append((id: UUID(), url: url))
        }
        // One file is already gone → removeItem throws only for that one.
        try FileManager.default.removeItem(at: batch[1].url)

        let outcome = AppModel.applyBatch(batch) {
            try FileManager.default.removeItem(at: $0)
        }
        XCTAssertEqual(outcome.ok, [batch[0].id, batch[2].id])
        XCTAssertEqual(outcome.failed.map(\.id), [batch[1].id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: batch[0].url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: batch[2].url.path))
    }
}
