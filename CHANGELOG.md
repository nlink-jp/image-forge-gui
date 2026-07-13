# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.9.2] - 2026-07-14

### Changed
- **Bundled CLI updated to image-forge v0.24.0.** No app behaviour change — the
  new `models pull --kind/--arch/--trigger` overrides (for typing a non-catalog
  LoRA/ControlNet at pull time) are a CLI-only surface the GUI doesn't drive.
  Refreshed so the bundled CLI matches the standalone image-forge v0.24.0 release
  instead of shipping an older build.

## [0.9.1] - 2026-07-12

### Changed
- **Release archive renamed** from `ImageForgeGUI-vX.Y.Z-macos-arm64.zip` to
  `image-forge-gui-vX.Y.Z-darwin-arm64.zip`, aligning the tool name (kebab-case
  repo name) and OS token (`darwin`) with the org-wide Release Archive Standard
  (`nlink-jp/.github` CONVENTIONS.md). The archive still contains the notarized,
  stapled `ImageForgeGUI.app`. image-forge-gui is a native SwiftUI app and
  remains **darwin/arm64 only**.

No change to the app's behaviour — a packaging / release-naming change.

## [0.9.0] - 2026-07-12

### Added
- **Open a model's source page from Manage Models.** Every model row (installed and
  catalog) now has a compass/Safari button that opens the model's Civitai model page
  or Hugging Face repo in the browser, so you can read the model card without
  searching for it. The URL comes from the CLI's new `page_url` field in
  `models list --json` (image-forge ≥ v0.23.0), decoded onto `ModelInfo`/`CatalogEntry`.

### Changed
- **Bundled CLI updated to image-forge v0.23.0** (adds `models open` / `page_url`,
  which this feature relies on).

## [0.8.1] - 2026-07-12

### Changed
- **Bundled CLI updated to image-forge v0.22.0.** No app-code changes — this refresh
  brings the new catalog models into the app's model list (Manage Models / Composer):
  the Anima checkpoints `anima-yume` and `nova-anime-am` (Civitai DiT + shared Anima
  encoders/VAE) and the Illustrious SDXL checkpoints `akium-ijin` and `akium-lumen`.
  The CLI also gained the ability to source a multi-component model's DiT from Civitai
  (`civitai:<versionId>`), which is what the new Anima entries use.

## [0.8.0] - 2026-07-12

### Added
- **Inpaint: paint a mask on the init image** (#4). With an init image set, toggle
  "Inpaint: paint the area to regenerate" and paint directly on the image (brush /
  eraser, adjustable size, clear, invert). The painted area is shown as a uniform
  translucent red overlay, with a brush-size ring at the cursor; a legend and a
  live caption spell out that red = regenerated / unpainted = kept (Invert flips
  it). The mask is exported at the init image's exact pixel size (white = regenerate,
  black = keep) and sent as the serve `mask` field. Mask rendering is pure/unit-
  tested, and a gated integration test runs a real base → mask → inpaint round-trip.
  Inpaint is no longer CLI-only.
- The **model name** now shows in the gallery inspector and the lightbox (library-
  reloaded images read it from the embedded PNG metadata).

### Changed
- **Manage Models** moved from the View menu to the App menu (next to About) — it's
  an app-level, settings-y task and was hard to find in View.
- The bottom **status bar** has a fixed height, so it no longer jumps when the
  progress indicator appears/disappears.
- Bundles **image-forge v0.21.0** (load-time `--wtype` quantization).

## [0.7.0] - 2026-07-11

### Added
- **Rename a library** from the switcher (folder menu → Rename…). Changes the
  display label only — the folder on disk is never renamed or moved. The Default
  library can be renamed too and keeps its protected first position.

### Changed
- The batch **Count** control is now a slider (1–16) instead of a stepper — easier
  to read and set at a glance. Same 1–16 range and behavior.
- Bundles **image-forge v0.20.0** (Flux/SD3.5 guidance controls in the CLI).

## [0.6.2] - 2026-07-11

### Changed
- Bundles **image-forge v0.19.0**: **FLUX.1-dev** and **SD3.5-Large** are now in the
  catalog, so they can be browsed and installed from the Manage Models window. No
  GUI code change.

## [0.6.1] - 2026-07-11

### Changed
- **Manage Models "Remove" now passes `--confirmed-by-frontend`** to `models rm
  --purge`. image-forge v0.18.1 gates destructive deletes behind an interactive
  "yes" and refuses from a non-TTY subprocess; the app already confirms with the
  user in its own "Delete X and its files?" dialog, so it asserts that confirmation
  to the CLI. Requires the bundled **image-forge v0.18.1** (older CLIs don't know
  the flag).

## [0.6.0] - 2026-07-11

### Added
- **In-app model management** (#3, ADR-0001). A fresh install no longer dead-ends
  into the terminal: a dedicated **Manage Models** window (View → Manage Models…,
  ⌘⇧M, or the "Get your first model…" button that replaces the Composer's empty
  picker) browses the curated catalog (`models list --catalog --json`), **installs**
  a model with a live download progress bar (`models pull`, its stderr progress
  streamed via a new `runStreaming` one-shot), and **removes** an installed model to
  reclaim its files (`models rm --purge`). Rated (questionable / explicit) models
  require a confirmation before install. `quantize` / `import` / `gc` stay in the CLI.

### Changed
- Bundles **image-forge v0.18.0** (opt-in flash attention + tiled VAE decoding for
  16 GB machines, and `models gc` / `rm --purge` disk reclamation — the latter now
  driven by the Manage Models window's Remove).

## [0.5.2] - 2026-07-11

### Fixed
- **`runOneShot` no longer risks a deadlock on large upscales** (#1). It drained
  stdout to EOF before reading stderr, so a chatty `upscale` (progress streams to
  stderr) could fill the ~64 KiB pipe buffer and hang the app. stdout and stderr
  are now drained concurrently.
- **Error events no longer leak in-flight entries** (#2). A serve `error` freed a
  `pending` slot but never removed the request from `inFlight` (it had no key). The
  bundled serve now sends the failing request's `output`, which the GUI uses to
  remove the exact entry; `settle()` and the engine-stopped path also reconcile
  `inFlight` so it always tracks `pending`.
- Bundles **image-forge v0.17.1** (batch-seed, in-flight-cancel, and
  sampler/scheduler-validation fixes).

## [0.5.1] - 2026-07-11

### Fixed
- Bundles **image-forge v0.17.0**, which makes **SDXL ControlNet** work
  (`controlnet-canny-sdxl`). The Composer's ControlNet section already arch-filters,
  so once you `models pull controlnet-canny-sdxl` it's offered for SDXL bases — no UI
  change. (v0.5.0 bundled v0.16.0, where SDXL ControlNet couldn't load.)

## [0.5.0] - 2026-07-11

### Added
- **ControlNet section in the Composer.** Steer generation by a control image's
  structure: pick an **architecture-compatible ControlNet** (arch-filtered to the
  base model, like LoRAs — an SDXL base is never offered an SD1.5 ControlNet),
  drop or choose a **control image**, set a **strength**, and toggle **Canny edge
  preprocessing**. The control model's license/credit shows in the License section
  like any other model, and a note flags that switching the ControlNet reloads the
  base model. Only **SD1.5** ControlNet ships today (`controlnet-canny-sd15`); the
  section is empty for a base with no compatible ControlNet and points at
  `models pull`. Sent over the existing serve protocol (`control_net` / `control` /
  `control_strength` / `canny`) — the fields go out only as a complete set.
- Bundles **image-forge v0.16.0** (the first ControlNet catalog entry).

## [0.4.1] - 2026-07-11

### Fixed
- Bundles **image-forge v0.15.1**, which corrects **`z-image-turbo`'s license**:
  it is **Apache-2.0** (permissive), not the `review-license` shown in v0.4.0. The
  License section now reflects that — no spurious restriction warning for it.

## [0.4.0] - 2026-07-11

### Added
- **LoRA trigger words in the Composer.** A LoRA usually only takes effect when
  specific tokens are in the prompt — miss them and it loads and silently does
  nothing. Each LoRA row shows its trigger words, and the section gathers the
  selected LoRAs' triggers (de-duplicated) into one place:
  - a **read-only, selectable box with a Copy button** holds just the trigger
    words, so they're easy to paste in;
  - **Add trigger words automatically** (default on) merges them into the prompt
    **only at generation** — the prompt field is never edited, so switching or
    removing LoRAs can't pile up stale tokens. Turn it off to place them by hand.
- **License section in the Composer.** Always shows the license of the base model
  and every LoRA in use. Models with **notable restrictions** (non-commercial,
  no-derivatives, attribution, share-alike) are highlighted in orange with flag
  chips, and the section header gets a ⚠️ when any restricted model is selected —
  so you notice before sharing or selling the output. Driven by the CLI's
  structured `license_flags`, not by parsing license prose.
- **Credit to include, in the License section.** When a model in use requires
  attribution, the section shows the exact credit to give — a read-only,
  selectable box with a one-click **Copy** — combining the base model and every
  LoRA's attribution (de-duplicated). It matches the `credit` image-forge writes
  into the PNG metadata, so it's a record you can also paste wherever you share
  the image. Nothing is ever burned into the pixels.
- Bundles **image-forge v0.15.0** — a much larger curated LoRA catalog (few-step
  LCM / Lightning / DMD2, plus 12 verified Civitai style LoRAs across SDXL and the
  new **Anima** base), the `trigger_words`, and the `license_flags` / `attribution`
  these consume.

## [0.3.0] - 2026-07-09

### Added
- **LoRA support in the Composer.** A new **LoRA** section stacks any number of
  installed LoRAs, each with its own **weight** slider. The picker offers only
  LoRAs whose architecture matches the selected base model (an SDXL LoRA is never
  offered for an SD1.5 base), and switching base models drops the ones that no
  longer apply. Sent as serve's `loras: ["<path>:<weight>"]` — applied per render,
  so no model reload. When nothing compatible is installed, the section says so
  and shows how to get one (`image-forge models pull lcm-lora-sdxl`).
- Bundles **image-forge v0.13.1**, which:
  - makes LoRA / ControlNet first-class registry kinds (so the GUI can enumerate
    and arch-filter them);
  - **fixes a crash where using any LoRA killed the engine** — which, for this
    app's resident `serve` process, would have taken generation down with it;
  - **stops embedding filesystem paths in generated PNGs.** Images written by this
    app previously carried absolute paths — including
    `img2img.init: /Users/<you>/…` — which leaked your username to anyone the
    image was shared with. Models are now recorded by name. Images generated
    before this keep their old metadata; re-generate to clean them.

## [0.2.0] - 2026-07-09

Completes the two features left stubbed in v0.1.0 (img2img and gallery upscale)
and adds multi-select batch operations.

### Added
- **img2img**: an **Init image** section in the Composer — drop an image (from
  Finder or the gallery) or pick one, with a **strength** slider (engine default
  0.6); a set init image makes the next generation img2img (`init` + `strength`
  on the serve request; strength is only sent alongside an init image). A gallery
  **Use as Init Image (img2img)** action (context menu / inspector / lightbox)
  sends a picked image straight to the Composer as the init image. Reuse-all and
  New Generation clear / restore it (restored only if the file still exists).
- **Upscale**: the gallery **Upscale…** action (context menu / inspector /
  lightbox) opens a sheet to pick an installed ESRGAN model; it runs a one-shot
  `image-forge upscale` (separate from the resident engine), writes the result
  into the active library, and prepends it to the gallery. Real-ESRGAN upscales
  by its native factor (×4), so there's no scale control. A one-shot upscale is
  mutually exclusive with generation (blocked while either runs) to avoid two
  concurrent Metal loads on the 16 GB baseline; the status bar shows a spinner.
- **Multi-select gallery + batch actions**: click selects, **⌘-click** toggles,
  **⇧-click** extends a range, and a click on the empty area **deselects**. With a
  selection you can **Delete** (to the Trash,
  after a confirmation dialog), **Export** (a save panel for one, a folder picker
  for several), and **Move to Library** (relocate the files into another library's
  folder) — from a selection bar at the bottom, the right-click menu, and the File
  menu (Export ⌘E, Delete ⌘⌫).
- Tests: `ServeClient.upscaleArgs`, ⇧-click range selection, export/move collision
  suffixing.

### Fixed
- The gallery now shows each image's **actual pixel dimensions** (read from the
  PNG `IHDR` chunk) instead of the *requested* width/height from the embedded
  text metadata. The two diverge after hires or upscale — an upscaled image was
  showing its source size (e.g. 1536² for a 6144² file).
- **Upscaled images keep their prompt** on library reload: the bundled CLI is now
  **image-forge v0.12.1**, whose `upscale` carries the source's generation
  metadata (prompt / seed / params) into the output PNG. (Images upscaled before
  this — with an older CLI — have no embedded prompt and won't gain one
  retroactively; re-upscale to embed it.)
- Clicking a thumbnail now highlights it **instantly**. The single-tap selection
  was delayed while SwiftUI waited to rule out a double-tap; selection and the
  double-tap-to-lightbox are now independent gestures.

## [0.1.0] - 2026-07-08

Initial release: a working txt2img app driving the `image-forge serve` engine —
Composer (single + batch) → Gallery with live progress, prompt / full-parameter
reuse, and switchable libraries.

### Added
- SwiftPM app (macOS 14+, normal windowed app — Dock icon + standard menu bar),
  Makefile (`build` / `build-app` / `package` / `test`), Developer ID signing +
  notarization scripts (mirrors `claude-usage-lens-gui` / `quick-translate`),
  MIT license, docs.
- **serve driver** (`ServeClient`): spawns and keeps `image-forge serve` resident;
  writes one JSON request per line to stdin; reads stdout **line-by-line** (a pure,
  tested `LineBuffer` handles partial reads) and exposes decoded events as an
  `AsyncStream<ServeEvent>`; decodes leniently (skips stray non-JSON stdout);
  drains stderr to the log; surfaces process exit. One-shot `listModels()` runs
  `image-forge models list --json`.
- **Binary resolution** (`BinaryResolver`, pure + tested): bundled Resources →
  `$IMAGE_FORGE_BIN` → `~/bin/image-forge` → `PATH`.
- **Composer → Generate → Gallery** flow: model picker showing each model's
  architecture + catalog content rating with a **Safe only** toggle (hide
  questionable / explicit; diffusion models only), resizable prompt / negative
  editors, seed (fixed+increment or random `-1` per image), steps, CFG,
  width/height, hires (auto/on/off), batch count, and an **Advanced** section
  (sampler / scheduler / clip-skip overrides). `AppModel` submits N requests with
  unique output paths under the app library dir, consumes events, and appends
  finished PNGs to the session gallery with live progress.
- **Cancel generation**: while a batch runs, Generate becomes **Cancel** (⌘.). It
  terminates and relaunches the serve process (sd.cpp renders are blocking and
  can't be interrupted in place) — killing the current render and discarding queued
  items; an epoch guard keeps the old event stream from clobbering state.
- **Gallery**: `LazyVGrid` thumbnails; a selection inspector (prompt / seed / size);
  a full-size **lightbox** (double-click or View, prev/next via ←/→, reveal, Esc to
  close). **Reuse Prompt** / **Reuse All Parameters** ("make similar") and **Copy
  Prompt** / **Copy Negative Prompt** / **Reveal in Finder** from the context menu,
  inspector, and lightbox — reuse loads a gallery image's parameters back into the
  Composer (session images and library-reloaded images alike).
- **Switchable libraries**: several named library folders the user switches between
  (`LibraryStore` — ordered list + active id persisted to `libraries.json`; seeds a
  **Default** pointing at the original fixed library dir for migration). Switching
  repoints new generations and loads that folder's existing PNGs into the gallery,
  reconstructing prompt / seed / size from each PNG's embedded metadata
  (`PngMetadata`, a pure `tEXt` / `iTXt` chunk parser preferring the `image-forge`
  JSON, else the AUTOMATIC1111 `parameters` string; metadata parsing runs on a
  background task). A folder-menu **library switcher** sits atop the gallery
  (switch / New Library… / Reveal / Remove from List).
- Standard macOS menu bar with app-specific items: custom **About**, File →
  **New Generation** (⌘N) / **Export Selected…** (⌘E) / **Reveal Library in
  Finder**, View → **Refresh Models** (⌘R), Help → docs + upstream repo.
- Unit tests: `GenerationRequest` → JSON encoding (key names + nil omission),
  `ServeEvent` decoding (ready/load/progress/done/error + unknown), `LineBuffer`
  partial-read buffering, `models list --json` decoding (bare array + `--all`
  wrapper + upscaler kind), `BinaryResolver` order, `PngMetadata` chunk parsing
  (tEXt JSON + iTXt UTF-8 round-trip + A1111 fallback + no-metadata nil), and
  `LibraryStore` (seed/migration, add/switch/remove round-trip, Default/last
  protection).

### Not yet implemented
- img2img (image drop + strength) and gallery **Upscale…** (`image-forge upscale`)
  are stubbed in the UI (marked TODO in the code). inpaint / ControlNet and model
  management stay in the CLI.

[0.3.0]: https://github.com/nlink-jp/image-forge-gui/releases/tag/v0.3.0
[0.2.0]: https://github.com/nlink-jp/image-forge-gui/releases/tag/v0.2.0
[0.1.0]: https://github.com/nlink-jp/image-forge-gui/releases/tag/v0.1.0
