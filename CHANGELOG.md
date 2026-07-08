# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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

[0.2.0]: https://github.com/nlink-jp/image-forge-gui/releases/tag/v0.2.0
[0.1.0]: https://github.com/nlink-jp/image-forge-gui/releases/tag/v0.1.0
