# image-forge-gui

A native macOS app for **exploratory local image generation** — a thin SwiftUI
front-end that drives the [`image-forge`](https://github.com/nlink-jp/image-forge)
CLI's resident `serve` engine. Pick a model, write a prompt, generate single
images or batches, and browse the results in a gallery with live progress.

macOS 14+ (Apple silicon).

## What it does

- **Composer** (left): prompt / negative (resizable editors), a model picker
  showing each model's architecture and catalog content rating with a **Safe
  only** toggle (hide questionable / explicit), core parameters (seed with a
  random toggle, steps, CFG, width/height, hires), an **Advanced** section
  (sampler / scheduler / clip-skip overrides), and a batch **count**. Press
  **Generate** — it turns into **Cancel** (⌘.) while running, which stops the
  batch immediately.
- **Gallery** (main): a grid of the active library's PNGs. Click to select (a
  bottom inspector shows the prompt, seed, and size); double-click (or **View**)
  opens a **lightbox** with prev/next (←/→) and reveal. From the context menu,
  inspector, or lightbox you can **Reuse Prompt**, **Reuse All Parameters**
  ("make similar" — copies every setting, so a new seed yields a variation),
  **Copy Prompt** / **Copy Negative Prompt**, and **Reveal in Finder**. A
  **library switcher** (folder menu) in the header row switches between named
  libraries, adds a new one (any folder), reveals it, or removes it from the list.
- **Status bar**: a live progress bar and status message driven by the engine's
  `ready` / `load` / `progress` / `done` / `error` events; errors surface inline.

## Libraries

New generations are written to the **active library** folder; the first-run
**Default** library is `~/Library/Application Support/image-forge-gui/library/`
(so pre-existing images keep working). Switching a library repoints new
generations *and* loads that folder's existing PNGs into the gallery — image-forge
embeds each image's parameters (A1111-compatible + `image-forge` JSON metadata),
so prompt / seed / size are reconstructed from the files themselves. The library
list and active selection are persisted in
`~/Library/Application Support/image-forge-gui/libraries.json`.

## How it works

The app spawns **`image-forge serve`** once and keeps it resident (the model load
and Metal init are paid once, not per image). Each generation is a single JSON
line written to the engine's stdin; the engine streams back JSON events on stdout,
which the app decodes line-by-line to update progress and append finished images.
The model list comes from a one-shot `image-forge models list --json`.

This mirrors the `claude-usage-lens-gui` / `quick-translate` pattern: a native
Swift shell over a Go CLI that owns the real work.

## Requirements

The `image-forge` CLI (darwin/arm64, Metal). It's resolved in this order:

1. the **bundled** copy in `Contents/Resources` (Developer-ID signed + notarized —
   the trust anchor; `make build-app` embeds it)
2. `$IMAGE_FORGE_BIN`
3. `~/bin/image-forge`
4. `image-forge` on your `PATH`

## Build

```sh
make run                 # build + run (debug)
make build               # release binary → .build/release/
make build-app           # signed .app bundle → dist/ (embeds the CLI)
make package             # build-app + notarize + staple + zip (release)
make test
```

`make build-app` bundles the CLI from `CLI_BIN` (default
`../image-forge/dist/image-forge`); override it:
`make build-app CLI_BIN=/path/to/image-forge`.

## Status

v0.1.0 — a working txt2img app: Composer (single + batch, cancel, advanced
overrides) → Gallery (lightbox, prompt / full-parameter reuse, switchable
libraries) with live progress. Reuse works both for the current session and for
images reloaded from a library folder (reconstructed from embedded metadata).

**Not yet implemented:** img2img (image drop + strength) and gallery upscale
(`image-forge upscale`) are stubbed in the UI. inpaint / ControlNet and model
management stay in the CLI.

## Why Swift (native macOS)

Per the RFP: a Wails GUI was rejected (hard to debug); this is a native SwiftUI
app in the same family as `quick-translate` / `claude-usage-lens-gui`, talking to
image-forge over its stable `serve` protocol and `--json`. darwin/arm64 only, like
image-forge itself.

## License

MIT — see [LICENSE](LICENSE).
