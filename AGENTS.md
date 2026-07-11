# AGENTS.md — image-forge-gui

## What this is

A **normal windowed** macOS app (SwiftUI, `WindowGroup`, Dock icon + standard menu
bar) that drives the `image-forge` CLI's resident `serve` engine for exploratory
local image generation: Composer → Generate (single/batch) → Gallery with live
progress. A thin native front-end — image-forge owns the diffusion engine, model
management, and metadata; this app spawns it and renders. macOS 14+, Apple silicon.

## Build & test

```sh
make run        # swift run (debug)
make build      # swift build -c release
make build-app  # signed .app (embeds the CLI from $CLI_BIN into Resources)
make package    # build-app + notarize + staple + zip
make test       # swift test
```

## Structure

```
Sources/ImageForgeGUI/
  App.swift            @main; WindowGroup { ContentView } + a second Window
                       ("manage-models") { ManageModelsView } + AppCommands (menu bar)
  ContentView.swift    HSplitView: Composer | Gallery, + bottom StatusBar;
                       onChange(manageModelsTick) → openWindow("manage-models")
  ComposerView.swift   prompt/negative/model/LoRA/init-image/ControlNet/params/advanced/License/count/hires + Generate
                       (empty-state "Get your first model…" → requestManageModels)
  GalleryView.swift    library switcher header + LazyVGrid thumbnails +
                       selection InspectorBar + context menu + lightbox
  ManageModelsView.swift  Manage Models window (ADR-0001): Installed (Remove→rm --purge)
                       + Available (Install→pull, live progress, NSFW opt-in confirm)
  AppModel.swift       @MainActor ObservableObject: ServeClient owner, models,
                       catalog + installs (model mgmt), results, progress, LibraryStore
                       owner; generate(); load/install/removeModel; menu actions
  ServeClient.swift    resident `serve` driver + pure LineBuffer/ProgressBuffer;
                       one-shots: listModels / listCatalog / pull(runStreaming) / remove / upscale
  BinaryResolver.swift pure, tested binary resolution
  LibraryStore.swift   pure, tested: named libraries + active id, JSON-persisted
  PngMetadata.swift    pure, tested: PNG tEXt/iTXt chunk parser (recover prompt/seed)
  Models.swift         GenerationRequest / ServeEvent / ModelInfo / CatalogEntry / GeneratedImage
Tests/ImageForgeGUITests/
  GenerationRequestTests / ServeEventTests (+ LineBufferTests) / ManageModelsTests /
  ModelInfoTests / BinaryResolverTests / PngMetadataTests / LibraryStoreTests
Info.plist             normal app (NO LSUIElement); graphics-design category
scripts/               codesign-darwin-app.sh, notarize-darwin-app.sh, make-icns.sh
assets/                AppIcon-1024.png (→ AppIcon.icns at build)
```

## Gotchas / conventions

- **serve driver.** The app drives **`image-forge serve`**: spawn once, keep
  resident, write one JSON request per line to stdin, read JSON events from stdout.
  Request/event schemas track image-forge `internal/cli/serve.go` (`serveRequest`)
  and `internal/engine/engine.go` (`engine.Event`) — if those change, update
  `Models.swift`. Events: `ready` / `load` / `progress` / `done` (carries `output`
  + `seed`) / `error`.
- **Decode leniently.** stable-diffusion.cpp occasionally prints stray non-JSON
  text to stdout; serve's own events are always JSON lines. `ServeClient` buffers
  stdout to newlines (`LineBuffer`, pure/tested for partial reads) and **skips**
  any line that doesn't decode as a `ServeEvent`. Unknown event kinds decode to
  `.unknown` rather than throwing.
- **Binary resolution** (`BinaryResolver.resolvePath`, pure + tested): bundled
  Resources first (signed/notarized trust anchor), then `$IMAGE_FORGE_BIN`,
  `~/bin/image-forge`, then each `$PATH` dir. `make build-app` bundles the CLI so
  the `.app` is self-contained.
- **Model management (ADR-0001)** drives one-shot subcommands, not `serve`:
  `models list --catalog --json` (→ `CatalogEntry`), `models pull` (install),
  `models rm --purge` (remove). `pull` rewrites its percentage with `\r` (`\r 62%`)
  and prints status with `\n`, so progress uses `ProgressBuffer` (splits on **both**
  `\n` and `\r`, pure/tested) via `runStreaming` (delivers stderr segments live),
  not `LineBuffer`. `AppModel.parseProgress` turns a bare `"62%"` segment into a
  fraction. The Manage Models window is opened via the `manageModelsTick`
  → `openWindow("manage-models")` pattern (Commands can't call `openWindow`
  directly; ContentView observes the tick), mirroring `newGenerationTick`.
- **Seed batching.** Random-seed batches send `seed = -1` per image (the engine
  randomizes and reports the seed back on `done`); a fixed seed increments per
  image. Each request gets a unique `output` path under
  `~/Library/Application Support/image-forge-gui/library/`; a `done` event maps
  back to its request by that path.
- **Main-actor model.** `AppModel` is `@MainActor`; the event-consuming Task is
  `@MainActor` too, so `@Published` mutations are main-thread safe. The engine is
  stopped on `NSApplication.willTerminate` (serve exits on stdin EOF).
- **Switchable libraries.** `AppModel` owns a `LibraryStore` (ordered `[Library]`
  + active id, persisted to `libraries.json`; seeds a **Default** at the original
  fixed `library/` dir for migration). `generate()` writes to `activeLibraryURL`;
  `loadActiveLibrary()` lists the active folder's `*.png` (newest-first by mtime),
  shows thumbnails immediately, then fills prompt/seed/params from each PNG's
  embedded metadata (`PngMetadata.read`) on a **detached** task. A monotonic
  `loadGeneration` token discards a stale load after a switch, and the parsed
  metadata is *merged* into `results` (mapped by URL, not reassigned) so images
  generated during the load survive. Default/last libraries are never removable.
- **PNG metadata parser.** `PngMetadata` walks `tEXt` (Latin-1) / `iTXt` (UTF-8)
  chunks, preferring the `image-forge` JSON (shape = `internal/cli/metadata.go`
  `imgforgeMeta`), else the A1111 `parameters` string. It mirrors the writer in
  image-forge `internal/engine/pngmeta.go` — if that chunk format changes, update
  it. CRC bytes are skipped, not verified (tests build chunks with a real CRC-32).
- **Normal app, not menu-bar.** Unlike the `claude-usage-lens-gui` template, this
  is a regular `WindowGroup` app (Dock icon, full Apple/File/Edit/View/Window/Help
  menu bar). Only the build system + the CLIRunner Process/resolution pattern were
  reused from that template — not its `MenuBarExtra` UI.
- **Signing**: `--deep` signs the bundled CLI too. Pure SwiftUI/AppKit needs no
  entitlements (Hardened Runtime alone). Notarize + staple the `.app`.

## Status

Working txt2img + **img2img** app: Composer (single/batch, **cancel** via
terminate+relaunch serve, **Advanced** sampler/scheduler/clip-skip overrides,
model arch + rating with **Safe only**, **LoRA** stacking with per-LoRA weights
filtered to the base model's arch, **Init image** drop/pick + strength,
**ControlNet** arch-filtered pick + control image + strength + Canny, **License**
panel showing the base/LoRA/ControlNet license + the attribution credit) →
Gallery (**lightbox**, **multi-select** ⌘/⇧-click with batch **Delete (Trash) /
Export / Move to Library**, **switchable named libraries** persisted + reloaded
via embedded metadata, **Reuse Prompt / Reuse All Parameters / Use as Init Image
/ Upscale…** + Copy Prompt/Negative from context menu, inspector, and lightbox)
with live progress. Selection is a `Set<id>` (anchor for ⇧-range); single-tap
select + a *simultaneous* double-tap lightbox avoids selection lag. **img2img** =
`init` + `strength` on the serve request;
**Upscale…** runs one-shot `image-forge upscale` (native ×4, mutually exclusive
with generation). inpaint + model management stay in the CLI.

## Design reference

- The CLI (engine + serve protocol): https://github.com/nlink-jp/image-forge
