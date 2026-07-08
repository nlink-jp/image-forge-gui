import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

/// The app's view-model. Owns the resident `ServeClient`, the model list, the
/// session gallery, and live progress. All UI state is `@Published`; the whole
/// class is `@MainActor` so mutations are main-thread safe (serve events are
/// delivered onto the main actor by `start()`).
@MainActor
final class AppModel: ObservableObject {
    // Model list (Composer picker).
    @Published var models: [ModelInfo] = []

    // Session gallery (newest first) + selection (shared so File menu commands
    // can act on the selected image).
    @Published var results: [GeneratedImage] = []
    @Published var selectedID: GeneratedImage.ID?

    // Live status.
    @Published var isGenerating = false
    @Published var progress: Double = 0        // 0…1 for the current image
    @Published var statusMessage: String = "Starting engine…"
    @Published var errorMessage: String?

    // Bumped by the "New Generation" menu command; the Composer observes it to
    // clear + focus its fields.
    @Published var newGenerationTick = 0

    // Bumped to ask the Composer to load a gallery image's parameters (mirrors
    // newGenerationTick). `pendingReuse` carries what to load.
    @Published var reuseTick = 0
    private(set) var pendingReuse: (params: GenerationRequest, promptOnly: Bool)?

    /// Load a gallery image's parameters back into the Composer. `promptOnly`
    /// loads just the prompt + negative; otherwise every field (a "use these
    /// parameters" / "make a similar image" action — flip Random seed for a
    /// variation, keep it for an exact reproduction).
    func reuse(_ params: GenerationRequest, promptOnly: Bool) {
        pendingReuse = (params, promptOnly)
        reuseTick += 1
    }

    // Switchable libraries: the list + which one is active, mirrored from the
    // store so the Gallery's switcher can observe them. `activeLibraryURL` is
    // where new generations are written and existing PNGs are loaded from.
    @Published private(set) var libraries: [Library] = []
    @Published private(set) var activeLibraryID: Library.ID

    /// The currently-selected gallery image, if any.
    var selectedImage: GeneratedImage? { results.first { $0.id == selectedID } }

    /// The active library's folder, created on demand.
    var activeLibraryURL: URL {
        let url = URL(fileURLWithPath: libraryStore.active.path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The active library's display name (for the switcher label).
    var activeLibraryName: String { libraryStore.active.name }

    /// Whether the active library can be removed from the list (not Default/last).
    var canRemoveActiveLibrary: Bool { libraryStore.canRemove(activeLibraryID) }

    private let libraryStore: LibraryStore

    private var client: ServeClient?
    private var eventTask: Task<Void, Never>?
    // Bumped on each (re)launch so a previous client's late events / stream-end
    // (e.g. after a cancel terminates and restarts serve) are ignored.
    private var clientEpoch = 0

    // Monotonic token guarding async library loads: a switch bumps it so a slow
    // metadata parse from a previous library can't overwrite the new results.
    private var loadGeneration = 0

    // Batch bookkeeping: requests submitted but not yet completed, keyed by their
    // unique output path so a `done` event maps back to its request.
    private var pending = 0
    private var inFlight: [String: GenerationRequest] = [:]

    init() {
        let store = LibraryStore(
            fileURL: LibraryStore.defaultStoreURL(),
            defaultLibraryDir: Self.defaultLibraryDir())
        libraryStore = store
        libraries = store.libraries
        activeLibraryID = store.activeID
        loadActiveLibrary()
    }

    // MARK: - Engine lifecycle

    /// Start the resident serve engine (once) and begin consuming its events;
    /// also kick off the initial model load. Safe to call repeatedly.
    func start() {
        guard client == nil else { return }
        do {
            try launchClient()
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.client?.stop() }
            }
            loadModels()
        } catch {
            statusMessage = "Engine unavailable"
            errorMessage = error.localizedDescription
        }
    }

    /// (Re)create the serve client and begin consuming its events. Bumps
    /// `clientEpoch` so a previous client's late events / stream-end are ignored
    /// — `cancelGeneration` relies on this when it terminates and relaunches serve.
    private func launchClient() throws {
        clientEpoch += 1
        let epoch = clientEpoch
        let c = try ServeClient()
        client = c
        let stream = try c.start()
        eventTask = Task { @MainActor [weak self] in
            for await ev in stream {
                guard let self, self.clientEpoch == epoch else { continue }
                self.handle(ev)
            }
            if let self, self.clientEpoch == epoch { self.handleStreamEnded() }
        }
    }

    /// Stop an in-flight generation. sd.cpp renders are blocking C calls that
    /// can't be interrupted in place, so the only immediate stop is to terminate
    /// the serve process — which kills the current render and discards any queued
    /// batch items — then relaunch it fresh. The next generation reloads the model.
    func cancelGeneration() {
        guard isGenerating else { return }
        eventTask?.cancel()
        eventTask = nil
        client?.stop()
        client = nil
        pending = 0
        inFlight.removeAll()
        isGenerating = false
        progress = 0
        statusMessage = "Cancelled"
        do {
            try launchClient()   // epoch bump makes the old stream's end a no-op
        } catch {
            statusMessage = "Engine unavailable"
            errorMessage = "Couldn't restart the engine: \(error.localizedDescription)"
        }
    }

    /// Reload the installed-model list (View → Refresh Models, ⌘R).
    func loadModels() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let client = try self.client ?? ServeClient()
                self.models = try await client.listModels()
                if self.errorMessage != nil, !self.models.isEmpty { self.errorMessage = nil }
            } catch {
                self.errorMessage = "Couldn't list models: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Generation

    /// Submit `count` generations. Each gets a unique output path under the
    /// library dir. Seed: `randomSeed` → -1 (the engine randomizes per image and
    /// reports the seed back); otherwise the given seed, incremented per image
    /// (nil → the profile default).
    func generate(
        prompt: String,
        negative: String?,
        model: String?,
        seed: Int64?,
        randomSeed: Bool,
        steps: Int?,
        cfg: Double?,
        width: Int?,
        height: Int?,
        count: Int,
        hires: String?,
        sampler: String? = nil,
        scheduler: String? = nil,
        clipSkip: Int? = nil
    ) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isGenerating else { return }
        guard let client else {
            errorMessage = "The image-forge engine isn't running."
            return
        }

        let n = max(1, count)
        isGenerating = true
        progress = 0
        errorMessage = nil
        statusMessage = "Queued \(n) image\(n == 1 ? "" : "s")…"

        let dir = activeLibraryURL
        for i in 0..<n {
            let outURL = dir.appendingPathComponent(UUID().uuidString + ".png")
            let reqSeed: Int64?
            if randomSeed {
                reqSeed = -1
            } else if let seed {
                reqSeed = seed + Int64(i)
            } else {
                reqSeed = nil
            }

            let req = GenerationRequest(
                prompt: trimmed,
                negative: (negative?.isEmpty ?? true) ? nil : negative,
                model: model,
                seed: reqSeed,
                steps: steps,
                cfg: cfg,
                width: width,
                height: height,
                sampler: sampler,
                scheduler: scheduler,
                clipSkip: clipSkip,
                hires: hires,
                output: outURL.path
            )
            inFlight[outURL.path] = req
            pending += 1
            do {
                try client.send(req)
            } catch {
                pending -= 1
                inFlight[outURL.path] = nil
                errorMessage = "Failed to queue request: \(error.localizedDescription)"
            }
        }
        if pending == 0 { isGenerating = false }
    }

    // MARK: - Libraries

    /// Switch to a different library: point new generations at it and reload its
    /// existing PNGs into the gallery.
    func switchLibrary(to id: Library.ID) {
        guard id != activeLibraryID else { return }
        libraryStore.setActive(id)
        syncLibraries()
        loadActiveLibrary()
    }

    /// Add a library rooted at `url` (named after its folder), make it active, and
    /// load it.
    func addLibrary(url: URL) {
        let lib = libraryStore.add(name: url.lastPathComponent, url: url)
        libraryStore.setActive(lib.id)
        syncLibraries()
        loadActiveLibrary()
    }

    /// Remove a library from the list (Default/last are protected). If it was
    /// active, the Default becomes active and is loaded.
    func removeLibrary(_ id: Library.ID) {
        guard libraryStore.remove(id) else { return }
        syncLibraries()
        loadActiveLibrary()
    }

    private func syncLibraries() {
        libraries = libraryStore.libraries
        activeLibraryID = libraryStore.activeID
    }

    /// Replace the gallery with the active library's PNGs, newest first. Thumbnails
    /// appear immediately (file URLs only); prompt/seed/params are filled in from
    /// each PNG's embedded metadata on a background task so a large library doesn't
    /// block the main thread.
    func loadActiveLibrary() {
        loadGeneration &+= 1
        let token = loadGeneration
        let urls = Self.sortedPNGs(in: activeLibraryURL)

        results = urls.map { url in
            GeneratedImage(id: UUID(), url: url, prompt: "", seed: nil,
                           params: GenerationRequest(prompt: "", output: url.path))
        }
        selectedID = results.first?.id
        guard !urls.isEmpty else { return }

        Task.detached(priority: .utility) { [weak self] in
            var meta: [String: PngMetadata] = [:]
            for url in urls {
                if let m = PngMetadata.read(contentsOf: url) { meta[url.path] = m }
            }
            await self?.applyLibraryMetadata(meta, token: token)
        }
    }

    /// Merge parsed metadata into the current results, matched by file path. Guarded
    /// by `token` so a stale load (after a switch) is discarded, and applied by
    /// mapping (not reassigning) so images generated during the load survive.
    private func applyLibraryMetadata(_ meta: [String: PngMetadata], token: Int) {
        guard token == loadGeneration else { return }
        results = results.map { img in
            guard let m = meta[img.url.path] else { return img }
            var params = img.params
            params.prompt = m.prompt ?? params.prompt
            params.negative = m.negative
            params.seed = m.seed
            params.steps = m.steps
            params.cfg = m.cfg
            params.width = m.width
            params.height = m.height
            params.sampler = m.sampler
            params.scheduler = m.scheduler
            return GeneratedImage(
                id: img.id, url: img.url,
                prompt: m.prompt ?? img.prompt,
                seed: m.seed ?? img.seed,
                params: params)
        }
    }

    /// PNG files in `dir`, sorted by modification time descending (newest first).
    static func sortedPNGs(in dir: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        return urls
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                return l > r
            }
    }

    private func libraryStatus(count: Int) -> String {
        count == 0
            ? "\(activeLibraryName) — empty"
            : "\(activeLibraryName) — \(count) image\(count == 1 ? "" : "s")"
    }

    // MARK: - Event handling

    private func handle(_ ev: ServeEvent) {
        switch ev.kind {
        case .ready:
            statusMessage = "Engine ready"
        case .load:
            statusMessage = ev.message ?? "Loading model…"
        case .progress:
            if let p = ev.progress { progress = p }
            if let m = ev.message { statusMessage = m }
        case .done:
            if let out = ev.output { finishOne(outputPath: out, seed: ev.seed) }
        case .error:
            errorMessage = ev.message ?? "Generation failed."
            // An errored request won't emit `done`; free one slot so a batch
            // can still settle.
            pending = max(0, pending - 1)
            if pending == 0 { settle() }
        case .unknown:
            break
        }
    }

    private func finishOne(outputPath: String, seed: Int64?) {
        let req = inFlight.removeValue(forKey: outputPath)
        let image = GeneratedImage(
            id: UUID(),
            url: URL(fileURLWithPath: outputPath),
            prompt: req?.prompt ?? "",
            seed: seed ?? req?.seed,
            params: req ?? GenerationRequest(prompt: "", output: outputPath)
        )
        results.insert(image, at: 0)
        if selectedID == nil { selectedID = image.id }
        pending = max(0, pending - 1)
        progress = 0
        if pending == 0 { settle() }
    }

    private func settle() {
        isGenerating = false
        statusMessage = "Done — " + libraryStatus(count: results.count)
    }

    private func handleStreamEnded() {
        if isGenerating {
            isGenerating = false
            errorMessage = errorMessage ?? "The image-forge engine stopped unexpectedly."
        }
        statusMessage = "Engine stopped"
        client = nil
    }

    // MARK: - Menu-command actions

    /// File → New Generation (⌘N): signal the Composer to clear + focus.
    func requestNewGeneration() { newGenerationTick &+= 1 }

    /// File → Reveal Library in Finder (the active library).
    func revealLibrary() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: activeLibraryURL.path)
    }

    /// File → Export Selected… (⌘E): copy the selected PNG to a chosen location.
    func exportSelected() {
        guard let img = selectedImage else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = img.url.lastPathComponent
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: img.url, to: dest)
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    /// Help → ImageForgeGUI Help: open the bundled/dev README, else the repo.
    func openHelp() {
        if let url = Self.helpFileURL() {
            NSWorkspace.shared.open(url)
        } else {
            openImageForgeRepo()
        }
    }

    /// Help → image-forge on GitHub.
    func openImageForgeRepo() {
        if let url = URL(string: "https://github.com/nlink-jp/image-forge") {
            NSWorkspace.shared.open(url)
        }
    }

    /// App → About: a standard About panel populated with name/version/credits.
    /// The app icon comes from the bundle automatically.
    func showAboutPanel() {
        let credits = NSAttributedString(
            string: "A native macOS front-end that drives the image-forge serve engine.\n© 2026 nlink-jp — MIT License.")
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "ImageForgeGUI",
            .applicationVersion: Self.appVersion,
            .credits: credits,
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1.0"
    }

    // MARK: - Helpers

    static func defaultLibraryDir() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("image-forge-gui/library", isDirectory: true)
    }

    /// Best-effort README locator: the bundled copy (if a packaged .app later
    /// ships one), else walk up from the executable to find the source README
    /// (works under `swift run`). Returns nil if none is found.
    static func helpFileURL() -> URL? {
        if let url = Bundle.main.url(forResource: "README", withExtension: "md") { return url }
        var dir = Bundle.main.bundleURL.deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("README.md")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }
}
