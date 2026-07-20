import Foundation

/// Client-side queue for a batch generation.
///
/// `image-forge serve` renders strictly one request at a time (decode → render →
/// decode, see `internal/cli/serve.go`), so there is nothing to gain from dumping
/// a whole batch into its stdin up front — and one thing to lose: once a request
/// is in the engine's pipe the app can no longer take it back, which makes
/// "finish the current image, then stop" impossible. Holding the remainder here
/// and submitting one request at a time costs a stdin write per image (µs against
/// a render measured in seconds) and makes a graceful stop a matter of dropping
/// the queue — no process kill, no model reload.
///
/// Invariant: at most one request is in flight (`current`), so a `done`/`error`
/// event never has to be matched back to one of several outstanding requests.
///
/// Pure and value-typed: the batch bookkeeping is unit-testable without a running
/// engine.
struct BatchQueue: Equatable {
    /// The request handed to the engine and not yet settled.
    private(set) var current: GenerationRequest?
    /// Requests not yet submitted — what a graceful stop drops.
    private(set) var queued: [GenerationRequest] = []
    /// Images in this batch (submitted + queued) at the time it started, minus any
    /// dropped by a graceful stop, so `completed`/`total` stays truthful afterwards.
    private(set) var total = 0
    /// Images that have settled (rendered or failed).
    private(set) var completed = 0
    /// A "finish the current image, then stop" was requested.
    private(set) var isWindingDown = false

    /// Whether a batch is running: something in flight or still waiting.
    var isActive: Bool { current != nil || !queued.isEmpty }

    /// Images that a graceful stop would drop (excludes the in-flight one).
    var remaining: Int { queued.count }

    /// Whether "finish current, then stop" is a *distinct* choice from stopping
    /// now — it isn't once the queue is empty or already dropped.
    var canWindDown: Bool { current != nil && !queued.isEmpty && !isWindingDown }

    /// 1-based index of the image being rendered, for "Generating 3/50".
    var currentIndex: Int { min(completed + 1, max(total, 1)) }

    /// Overall batch progress, folding the in-flight image's own 0…1 progress into
    /// the completed count — a per-image bar is near-useless across 50 images.
    func overallProgress(imageProgress: Double) -> Double {
        guard total > 0 else { return 0 }
        return (Double(completed) + imageProgress.clamped01) / Double(total)
    }

    /// Begin a batch. Replaces any previous state.
    mutating func start(_ requests: [GenerationRequest]) {
        current = nil
        queued = requests
        total = requests.count
        completed = 0
        isWindingDown = false
    }

    /// Hand the next request to the engine, if any. Returns nil when the batch is
    /// exhausted (or wound down) — the caller then settles the batch.
    mutating func submitNext() -> GenerationRequest? {
        guard current == nil, !queued.isEmpty else { return nil }
        let next = queued.removeFirst()
        current = next
        return next
    }

    /// Settle the in-flight request (a `done` or `error` event). Returns it so the
    /// caller can build the gallery entry from the parameters it was sent with.
    /// `output` is the event's output path when it carried one; a mismatch means a
    /// stray event and is ignored.
    @discardableResult
    mutating func settleCurrent(output: String? = nil) -> GenerationRequest? {
        guard let req = current else { return nil }
        if let output, output != req.output { return nil }
        current = nil
        completed += 1
        return req
    }

    /// Let the in-flight image finish, then stop: drop the queue and shrink `total`
    /// so the status line doesn't keep counting toward images that will never run.
    mutating func windDown() {
        guard isActive else { return }
        queued.removeAll()
        isWindingDown = true
        total = completed + (current == nil ? 0 : 1)
    }

    /// Abandon everything (an immediate stop, or the engine dying).
    mutating func reset() {
        self = BatchQueue()
    }
}

private extension Double {
    /// Engine progress is nominally 0…1; clamp so a stray value can't push the
    /// overall bar backwards or past the end.
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}
