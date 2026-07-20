import XCTest
@testable import ImageForgeGUI

/// `BatchQueue` holds the images a batch still owes the engine. It exists so a
/// batch can be stopped *gracefully* (finish the in-flight image, drop the rest),
/// which is only possible while the remainder is here rather than in the engine's
/// stdin — so these tests pin both the one-at-a-time submission invariant and the
/// two stop paths.
final class BatchQueueTests: XCTestCase {
    private func requests(_ n: Int) -> [GenerationRequest] {
        (0..<n).map { GenerationRequest(prompt: "p\($0)", output: "/tmp/\($0).png") }
    }

    // MARK: - Submission

    func testEmptyQueueIsInactive() {
        var q = BatchQueue()
        XCTAssertFalse(q.isActive)
        XCTAssertNil(q.submitNext())
        XCTAssertFalse(q.canWindDown)
    }

    func testSubmitsOneAtATime() {
        var q = BatchQueue()
        q.start(requests(3))
        XCTAssertEqual(q.total, 3)
        XCTAssertEqual(q.remaining, 3)

        XCTAssertEqual(q.submitNext()?.output, "/tmp/0.png")
        XCTAssertEqual(q.remaining, 2)
        // The invariant: nothing else goes out until the current one settles.
        XCTAssertNil(q.submitNext())
        XCTAssertEqual(q.remaining, 2)

        q.settleCurrent(output: "/tmp/0.png")
        XCTAssertEqual(q.submitNext()?.output, "/tmp/1.png")
    }

    func testRunsToCompletionInOrder() {
        var q = BatchQueue()
        q.start(requests(3))
        var order: [String] = []
        while let req = q.submitNext() {
            order.append(req.output)
            q.settleCurrent(output: req.output)
        }
        XCTAssertEqual(order, ["/tmp/0.png", "/tmp/1.png", "/tmp/2.png"])
        XCTAssertEqual(q.completed, 3)
        XCTAssertFalse(q.isActive)
        XCTAssertFalse(q.isWindingDown)
    }

    // MARK: - Settling

    func testSettleReturnsTheRequestItWasSentWith() {
        var q = BatchQueue()
        q.start(requests(1))
        _ = q.submitNext()
        XCTAssertEqual(q.settleCurrent(output: "/tmp/0.png")?.prompt, "p0")
        XCTAssertNil(q.current)
        XCTAssertEqual(q.completed, 1)
    }

    /// An error event may carry no output (e.g. a malformed request): settle the
    /// in-flight one anyway, or the batch would stall forever.
    func testSettleWithoutOutputSettlesTheInFlightRequest() {
        var q = BatchQueue()
        q.start(requests(2))
        _ = q.submitNext()
        XCTAssertEqual(q.settleCurrent()?.output, "/tmp/0.png")
        XCTAssertEqual(q.completed, 1)
    }

    /// A stray event from a previous engine (a late `done` after a restart) must
    /// not settle the image currently rendering.
    func testSettleIgnoresMismatchedOutput() {
        var q = BatchQueue()
        q.start(requests(2))
        _ = q.submitNext()
        XCTAssertNil(q.settleCurrent(output: "/tmp/stale.png"))
        XCTAssertEqual(q.completed, 0)
        XCTAssertEqual(q.current?.output, "/tmp/0.png")
    }

    func testSettleWithNothingInFlightIsANoOp() {
        var q = BatchQueue()
        q.start(requests(1))
        XCTAssertNil(q.settleCurrent(output: "/tmp/0.png"))
        XCTAssertEqual(q.completed, 0)
    }

    // MARK: - Graceful stop

    func testWindDownKeepsCurrentAndDropsQueue() {
        var q = BatchQueue()
        q.start(requests(10))
        _ = q.submitNext()
        q.settleCurrent(output: "/tmp/0.png")
        let inFlight = q.submitNext()          // image 2 of 10 is rendering
        q.windDown()

        XCTAssertEqual(q.remaining, 0)
        XCTAssertTrue(q.isWindingDown)
        XCTAssertEqual(q.current?.output, inFlight?.output, "the in-flight image survives")
        // total shrinks to what will actually be produced: 1 done + 1 rendering.
        XCTAssertEqual(q.total, 2)
        XCTAssertEqual(q.currentIndex, 2)

        q.settleCurrent(output: inFlight!.output)
        XCTAssertNil(q.submitNext(), "nothing follows a wound-down batch")
        XCTAssertFalse(q.isActive)
        XCTAssertEqual(q.completed, 2)
    }

    func testCanWindDownOnlyWhileImagesAreStillQueued() {
        var q = BatchQueue()
        q.start(requests(2))
        XCTAssertFalse(q.canWindDown, "nothing in flight yet")

        _ = q.submitNext()
        XCTAssertTrue(q.canWindDown)

        q.windDown()
        XCTAssertFalse(q.canWindDown, "already winding down")

        // Last image of a batch: stopping gracefully is the same as doing nothing.
        var single = BatchQueue()
        single.start(requests(1))
        _ = single.submitNext()
        XCTAssertFalse(single.canWindDown)
    }

    func testWindDownOnAnIdleQueueIsANoOp() {
        var q = BatchQueue()
        q.windDown()
        XCTAssertFalse(q.isWindingDown)
        XCTAssertEqual(q.total, 0)
    }

    // MARK: - Immediate stop

    func testResetAbandonsEverything() {
        var q = BatchQueue()
        q.start(requests(5))
        _ = q.submitNext()
        q.reset()
        XCTAssertEqual(q, BatchQueue())
        XCTAssertFalse(q.isActive)
    }

    // MARK: - Progress

    func testOverallProgressFoldsInTheCurrentImage() {
        var q = BatchQueue()
        q.start(requests(4))
        _ = q.submitNext()
        XCTAssertEqual(q.overallProgress(imageProgress: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(q.overallProgress(imageProgress: 0.5), 0.125, accuracy: 0.0001)

        q.settleCurrent(output: "/tmp/0.png")
        _ = q.submitNext()
        XCTAssertEqual(q.overallProgress(imageProgress: 0.5), 0.375, accuracy: 0.0001)
    }

    func testOverallProgressClampsStrayEngineValues() {
        var q = BatchQueue()
        q.start(requests(2))
        _ = q.submitNext()
        XCTAssertEqual(q.overallProgress(imageProgress: 5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(q.overallProgress(imageProgress: -1), 0, accuracy: 0.0001)
    }

    func testOverallProgressOnAnEmptyQueueIsZero() {
        XCTAssertEqual(BatchQueue().overallProgress(imageProgress: 0.5), 0, accuracy: 0.0001)
    }

    /// The status line reads "3/50"; the index must never run past the total, even
    /// on the last settled image before the batch finishes.
    func testCurrentIndexIsOneBasedAndBounded() {
        var q = BatchQueue()
        q.start(requests(2))
        XCTAssertEqual(q.currentIndex, 1)
        _ = q.submitNext()
        q.settleCurrent(output: "/tmp/0.png")
        XCTAssertEqual(q.currentIndex, 2)
        _ = q.submitNext()
        q.settleCurrent(output: "/tmp/1.png")
        XCTAssertEqual(q.currentIndex, 2, "does not overshoot the total")
    }
}
