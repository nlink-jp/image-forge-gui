# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - unreleased

Initial project scaffold (Phase 1 Core).

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
- **Composer → Generate → Gallery** flow: model picker (diffusion only), prompt /
  negative, seed (fixed+increment or random `-1` per image), steps, CFG,
  width/height, hires (auto/on/off), batch count. `AppModel` submits N requests
  with unique output paths under the app library dir, consumes events, and appends
  finished PNGs to the session gallery with live progress.
- **Gallery**: `LazyVGrid` thumbnails, selection inspector (prompt + seed + copy),
  context menu with a functional **Reveal in Finder**.
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

### Stubbed (later phases)
- SwiftData history + prompt reuse, favorites / export polish, img2img (image drop
  + strength), gallery upscale (`image-forge upscale`) — marked TODO in the code.

[0.1.0]: https://github.com/nlink-jp/image-forge-gui/releases/tag/v0.1.0
