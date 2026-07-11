import Foundation

/// Accumulates raw stdout bytes and yields complete newline-terminated lines,
/// buffering any partial trailing line until the next chunk arrives. Pure and
/// synchronous so it can be unit-tested against arbitrary read boundaries.
struct LineBuffer {
    private var buffer = Data()

    /// Append a chunk and return every *complete* line it completed (empty lines
    /// omitted). A trailing partial line is retained for the next call.
    mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)
        guard let lastNL = buffer.lastIndex(of: 0x0A) else { return [] }
        let complete = buffer[buffer.startIndex...lastNL]
        buffer.removeSubrange(buffer.startIndex...lastNL)
        let slices: [Data.SubSequence] = complete.split(
            separator: UInt8(0x0A), omittingEmptySubsequences: true)
        return slices.map { Data($0) }
    }
}

/// Splits a byte stream into progress "segments" on either newline or carriage
/// return — `image-forge models pull` rewrites its percentage in place with `\r`
/// (`\r  62%`) and prints status lines with `\n`. Pure and synchronous so it can
/// be unit-tested; a trailing partial segment is retained for the next chunk.
struct ProgressBuffer {
    private var buffer = Data()

    /// Append a chunk and return each completed, non-empty, whitespace-trimmed
    /// segment (a `\r`-updated percentage or a `\n` status line).
    mutating func append(_ data: Data) -> [String] {
        buffer.append(data)
        var out: [String] = []
        while let idx = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let seg = Data(buffer[buffer.startIndex..<idx])
            buffer.removeSubrange(buffer.startIndex...idx)
            if let s = String(data: seg, encoding: .utf8) {
                let t = s.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { out.append(t) }
            }
        }
        return out
    }
}

/// Drives a resident `image-forge serve` process: one JSON request per line on
/// stdin, a stream of JSON events on stdout. The process is kept alive so the
/// model load + Metal init is paid once, not per generation.
///
/// Robustness: stdout is buffered until newlines (partial reads are fine) and
/// each line is decoded leniently — stable-diffusion.cpp occasionally prints
/// stray non-JSON text to stdout, so undecodable lines are simply skipped;
/// serve's own events are always JSON. stderr is drained to the app's log.
final class ServeClient: @unchecked Sendable {
    enum ServeError: LocalizedError {
        case notStarted
        case launchFailed(String)
        case runFailed(String)

        var errorDescription: String? {
            switch self {
            case .notStarted:
                return "The image-forge engine isn't running."
            case .launchFailed(let d):
                return "Couldn't start image-forge: \(d)"
            case .runFailed(let d):
                return d.isEmpty ? "image-forge exited with an error." : d
            }
        }
    }

    private let binary: URL
    private var process: Process?
    private var stdin: FileHandle?
    private var continuation: AsyncStream<ServeEvent>.Continuation?
    private var lineBuffer = LineBuffer()
    private let lock = NSLock()

    init(binary: URL) { self.binary = binary }

    /// Convenience initializer that resolves the bundled/installed binary.
    convenience init() throws {
        self.init(binary: try BinaryResolver.resolve())
    }

    /// Launch `image-forge serve` and return a stream of its events. The first
    /// event is normally `{"kind":"ready"}`. The stream finishes when the
    /// process exits (or `stop()` is called).
    @discardableResult
    func start() throws -> AsyncStream<ServeEvent> {
        let proc = Process()
        proc.executableURL = binary
        proc.arguments = ["serve"]
        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        let stream = AsyncStream<ServeEvent> { cont in
            self.continuation = cont
        }

        // stderr → app log (drain to avoid the pipe filling and blocking serve).
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let d = handle.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            FileHandle.standardError.write(Data("[image-forge serve] \(s)".utf8))
        }

        // stdout → line buffer → decoded events.
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let d = handle.availableData
            if d.isEmpty { return } // EOF is handled by terminationHandler.
            self?.ingest(d)
        }

        proc.terminationHandler = { [weak self] _ in
            self?.finish()
        }

        do {
            try proc.run()
        } catch {
            continuation?.finish()
            continuation = nil
            throw ServeError.launchFailed(error.localizedDescription)
        }
        self.process = proc
        self.stdin = inPipe.fileHandleForWriting
        return stream
    }

    /// Split incoming bytes into lines and yield a `ServeEvent` for each
    /// decodable one; skip stray non-JSON lines.
    private func ingest(_ data: Data) {
        lock.lock()
        let lines = lineBuffer.append(data)
        lock.unlock()
        let dec = JSONDecoder()
        for line in lines {
            if let ev = try? dec.decode(ServeEvent.self, from: line) {
                continuation?.yield(ev)
            }
        }
    }

    /// Queue one generation: write its JSON line + newline to the engine's stdin.
    func send(_ req: GenerationRequest) throws {
        guard let stdin else { throw ServeError.notStarted }
        var data = try JSONEncoder().encode(req)
        data.append(0x0A)
        try stdin.write(contentsOf: data)
    }

    /// Terminate the engine: close stdin (serve exits on EOF) and terminate.
    func stop() {
        try? stdin?.close()
        stdin = nil
        if let p = process, p.isRunning { p.terminate() }
    }

    private func finish() {
        continuation?.finish()
        continuation = nil
    }

    // MARK: - One-shot

    /// One-shot: run `image-forge models list --json` and decode the installed
    /// models. Runs a separate short-lived process (not the resident engine).
    func listModels() async throws -> [ModelInfo] {
        let data = try await Self.runOneShot(binary: binary, args: ["models", "list", "--json"])
        return try ModelInfo.decodeInstalled(from: data)
    }

    /// One-shot: `image-forge models list --catalog --json` → the curated catalog.
    func listCatalog() async throws -> [CatalogEntry] {
        let data = try await Self.runOneShot(
            binary: binary, args: ["models", "list", "--catalog", "--json"])
        return try CatalogEntry.decodeCatalog(from: data)
    }

    /// Install a catalog model: `image-forge models pull <name> [--allow-nsfw]`,
    /// surfacing download progress live via `onProgress` (each stderr segment — a
    /// `\r`-updated percentage or a status line). Throws `.runFailed` on failure.
    func pull(name: String, allowNSFW: Bool,
              onProgress: @escaping @Sendable (String) -> Void) async throws {
        _ = try await Self.runStreaming(
            binary: binary,
            args: Self.pullArgs(name: name, allowNSFW: allowNSFW),
            onLine: onProgress)
    }

    /// Remove an installed model: `image-forge models rm <name> [--purge]`. With
    /// `purge` the weight files are deleted too (shared / out-of-dir files kept).
    func remove(name: String, purge: Bool) async throws {
        _ = try await Self.runOneShot(
            binary: binary, args: Self.removeArgs(name: name, purge: purge))
    }

    /// Pure arg builder for `models pull` (injectable for tests).
    static func pullArgs(name: String, allowNSFW: Bool) -> [String] {
        var args = ["models", "pull", name]
        if allowNSFW { args.append("--allow-nsfw") }
        return args
    }

    /// Pure arg builder for `models rm` (injectable for tests). When purging, the
    /// app has already confirmed the deletion with the user via its own dialog, so
    /// it passes `--confirmed-by-frontend`: the CLI otherwise requires a "yes" at an
    /// interactive terminal (which this non-TTY subprocess can't provide) before it
    /// will delete weight files.
    static func removeArgs(name: String, purge: Bool) -> [String] {
        var args = ["models", "rm", name]
        if purge { args += ["--purge", "--confirmed-by-frontend"] }
        return args
    }

    /// One-shot: `image-forge upscale <input> -o <output> [--model <name>]`, run
    /// as a separate short-lived process (not the resident engine). The output
    /// factor is the ESRGAN model's native one (typically ×4) — image-forge
    /// ignores a requested `--scale` for Real-ESRGAN, so we don't pass it. On
    /// success the CLI prints the output path to stdout; progress goes to the
    /// child's stderr (drained). Throws `.runFailed` on a nonzero exit.
    func upscale(input: URL, output: URL, model: String) async throws {
        _ = try await Self.runOneShot(
            binary: binary,
            args: Self.upscaleArgs(input: input.path, output: output.path, model: model))
    }

    /// Pure arg builder for `image-forge upscale` (injectable for tests). An empty
    /// `model` omits `--model`, letting the CLI use its configured default.
    static func upscaleArgs(input: String, output: String, model: String) -> [String] {
        var args = ["upscale", input, "-o", output]
        if !model.isEmpty { args += ["--model", model] }
        return args
    }

    /// Run a short-lived `image-forge` subcommand to completion and return its
    /// stdout, throwing `.runFailed` on a nonzero exit.
    static func runOneShot(binary: URL, args: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = binary
                proc.arguments = args
                let out = Pipe()
                let err = Pipe()
                proc.standardOutput = out
                proc.standardError = err
                do {
                    try proc.run()
                } catch {
                    cont.resume(throwing: ServeError.launchFailed(error.localizedDescription))
                    return
                }
                // Drain stderr concurrently with stdout. `upscale` streams progress
                // to stderr throughout the run; reading stdout to EOF first would let
                // a >64 KiB stderr stream fill the pipe buffer and block the child
                // while we block on stdout — the classic two-pipe deadlock.
                let group = DispatchGroup()
                var errData = Data()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                group.wait() // stderr read finishes when the child closes the pipe on exit
                if proc.terminationStatus != 0 {
                    let stderr = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    cont.resume(throwing: ServeError.runFailed(stderr))
                    return
                }
                cont.resume(returning: data)
            }
        }
    }

    /// Like `runOneShot`, but delivers each stderr *segment* to `onLine` as it
    /// arrives — used by `pull` to show live download progress (`\r`-updated
    /// percentages + status lines). stdout is returned at exit; a nonzero exit
    /// throws `.runFailed` with the tail of stderr.
    static func runStreaming(
        binary: URL, args: [String], onLine: @escaping @Sendable (String) -> Void
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = binary
                proc.arguments = args
                let out = Pipe()
                let err = Pipe()
                proc.standardOutput = out
                proc.standardError = err

                // stderr → live progress segments (buffered by \n or \r). A
                // lock-guarded collector keeps the last few segments for error text.
                let collector = StreamCollector()
                err.fileHandleForReading.readabilityHandler = { h in
                    let d = h.availableData
                    if d.isEmpty { return }
                    for seg in collector.ingest(d) { onLine(seg) }
                }
                do {
                    try proc.run()
                } catch {
                    err.fileHandleForReading.readabilityHandler = nil
                    cont.resume(throwing: ServeError.launchFailed(error.localizedDescription))
                    return
                }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                err.fileHandleForReading.readabilityHandler = nil
                // Flush any stderr left in the pipe after exit (the final status /
                // error line the live handler may not have seen).
                let rest = err.fileHandleForReading.readDataToEndOfFile()
                if !rest.isEmpty { for seg in collector.ingest(rest) { onLine(seg) } }
                if proc.terminationStatus != 0 {
                    cont.resume(throwing: ServeError.runFailed(collector.tail()))
                    return
                }
                cont.resume(returning: data)
            }
        }
    }
}

/// Lock-guarded accumulator for `runStreaming`'s stderr: splits bytes into
/// progress segments and retains the last few for error reporting. `@unchecked
/// Sendable` because all mutable state is guarded by the lock.
private final class StreamCollector: @unchecked Sendable {
    private var buffer = ProgressBuffer()
    private var recent: [String] = []
    private let lock = NSLock()

    func ingest(_ data: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        let segs = buffer.append(data)
        recent.append(contentsOf: segs)
        if recent.count > 12 { recent.removeFirst(recent.count - 12) }
        return segs
    }

    /// The last few segments, joined — used as the error message on nonzero exit.
    func tail() -> String {
        lock.lock(); defer { lock.unlock() }
        return recent.suffix(4).joined(separator: "\n")
    }
}
