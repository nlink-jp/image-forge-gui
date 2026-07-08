# RFP: image-forge-gui

> Generated: 2026-07-07
> Status: Draft

## 1. Problem Statement

image-forge's CLI is powerful, but the **exploratory workflow — trying many
prompts, picking and saving the good results, and reusing past settings — is
cumbersome in a terminal.** `image-forge-gui` is a **native macOS (Swift/SwiftUI)
frontend** that drives image-forge's resident engine (`serve`) to provide
**batch prompt generation, gallery selection/saving, and reuse from generation
history.** Target users are local image-generation users of image-forge (mainly
the author / nlink-jp).

## 2. Functional Specification

### Views / UI surface
- **Composer**: prompt/negative, model picker (`models list --json`), core
  parameters (seed, steps, cfg, size, sampler/scheduler — profile fills defaults),
  batch controls (count N; seed mode fixed-increment or random), hires on/off,
  img2img (drop an init image + strength). "Generate" enqueues.
- **Queue / progress**: batch queue, live progress from serve events, cancel.
- **Gallery**: grid of results, select/favorite, right-click to save, reuse
  parameters, delete, upscale (`image-forge upscale`).
- **History**: list of past generations (prompt + params + thumbnail), click to
  restore into the Composer, search.
- **Inspector**: full parameters of a selected image, copy prompt, reuse.

### Input / Output
- **Backend**: spawn a resident `image-forge serve`; one generation = one JSON
  request line on stdin, `ready`/`load`/`progress`/`done`/`error` events on
  stdout. The model list comes from `image-forge models list --json` (one-shot).
- **Output**: generated PNGs are auto-saved into an app-managed library folder
  (each PNG carries image-forge's v0.12.0 metadata — the A1111-compatible
  `parameters` chunk plus the `image-forge` JSON — so images are
  self-describing). Export copies selected images to a chosen folder + "Reveal in
  Finder."

### Configuration
- Bundled image-forge binary (used from the .app's Resources by default), library
  (output) folder, default model. App settings via UserDefaults.

### External Dependencies
- The **bundled image-forge binary** (darwin/arm64, signed). No network services.

## 3. Design Decisions

- **Native macOS Swift/SwiftUI.** Wails was rejected (the author finds it
  hard to debug / unreliable). Same family as `claude-usage-lens-gui` /
  `quick-translate` (a thin Swift frontend that drives the CLI).
- **Drive `image-forge serve` as a subprocess.** image-forge's engine lives in
  `internal/` packages and cannot be imported from another module, so driving the
  subprocess is the only — and best — path; `serve` is the resident mode built for
  a GUI frontend.
- **Bundle the signed image-forge binary in the .app** (self-contained). **History
  in SwiftData** (native SwiftUI integration, macOS 14+).
- **Complements** the image-forge CLI.
- **The app icon is generated with image-forge itself (dogfooding).** Chosen:
  realvisxl-v5 rendering an "anvil + hammer + rainbow sparks = forging images"
  (`assets/app-icon-source.png`, seed 1001; the prompt/seed are embedded in the
  PNG metadata, so it's reproducible). `.icns` packaging is Phase 3.
- **Out of scope**: inpaint / ControlNet (Phase 2+), model pull/quantize (stays in
  the CLI; the GUI only lists + generates), training, Windows/Linux (darwin/arm64
  only, like image-forge).

## 4. Development Plan

### Phase 1: Core
Swift app scaffold + the **serve driver** (spawn, JSON send/receive, event
parsing, error handling) + model list + Composer + txt2img single/batch + Gallery
+ live progress. Unit tests (JSON encoding / event parsing / the serve protocol
designed to be mockable).

### Phase 2: Features
SwiftData history + prompt reuse + favorites/export + img2img (image drop +
strength) + hires toggle + upscale (gallery right-click).

### Phase 3: Release
Polish + docs (README ja/en) + **app icon (build the `.icns` from the generated
art)** + Developer ID signing + notarization (.app, .dmg if needed) + release.

Each phase is independently reviewable.

## 5. Required API Scopes / Permissions

**None** (no external services; local subprocess only). **Non-sandboxed Developer
ID direct distribution** (it spawns a subprocess and writes files; not App Store,
same as the other util-series Swift apps).

## 6. Series Placement

Series: **util-series**
Reason: image-forge itself is util-series; its GUI belongs here too, like the
other util-series GUIs (`claude-usage-lens-gui`, `csv-editor`, `mail-analyzer-gui`).

## 7. External Platform Constraints

**None** (no external platform). Technical: **darwin/arm64 only** (the bundled
image-forge is arm64/Metal); **macOS 14+** (SwiftData requirement).

---

## Discussion Log

- **Problem/name**: name `image-forge-gui` (matches the `*-gui` convention).
  Problem statement fixed as "the exploratory workflow, in a GUI."
- **Tech stack**: Wails rejected by the author (unreliable / hard to debug) →
  native Swift/SwiftUI (same family as the existing Swift apps).
- **Architecture**: the engine is `internal` and un-importable → driving
  `image-forge serve` as a subprocess is the only path (serve was built for this).
- **Binary acquisition**: options (reference PATH/~/bin + setting vs. bundle in
  the .app) → **bundle in the .app** (self-contained).
- **History storage**: SwiftData / SQLite(GRDB) / JSON → **SwiftData** (native
  SwiftUI integration).
- **MVP scope**: txt2img+hires / +upscale / +img2img → **include img2img in v1**
  (txt2img batch + hires + img2img + upscale; inpaint/ControlNet in Phase 2).
- **App icon**: generated three candidates with image-forge itself; chose the
  realvisxl-v5 "anvil + rainbow sparks" (candidate A). Dogfooded; reproducible via
  the embedded v0.12.0 metadata.
