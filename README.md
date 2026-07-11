# image-forge-gui

A native macOS app for **exploratory local image generation** — a thin SwiftUI
front-end that drives the [`image-forge`](https://github.com/nlink-jp/image-forge)
CLI's resident `serve` engine. Pick a model, write a prompt, generate single
images or batches, and browse the results in a gallery with live progress.

macOS 14+ (Apple silicon).

## What it does

- **Composer** (left): prompt / negative (resizable editors), a model picker
  showing each model's architecture and catalog content rating with a **Safe
  only** toggle (hide questionable / explicit), a **LoRA** section (stack
  installed LoRAs with per-LoRA weight sliders; only architecture-compatible ones
  are offered; **trigger words are shown and auto-inserted into the prompt**), an
  **Init image** section for
  **img2img** (drop or choose an image + a **strength** slider), a **ControlNet**
  section (pick an architecture-compatible ControlNet + a control image, with a
  **strength** slider and a **Canny** toggle — arch-filtered, so an SDXL base gets
  the SDXL ControlNet and an SD1.5 base the SD1.5 one), core parameters
  (seed with a random toggle, steps, CFG, width/height, hires), an **Advanced**
  section (sampler / scheduler / clip-skip overrides), and a batch **count**.
  A **License** section always shows the license of the base model, each LoRA, and
  the ControlNet in use, highlighting any with notable restrictions (non-commercial, no-derivatives,
  …); when a model requires attribution it also shows the **credit to include**
  (a copyable box) — the same text image-forge records in the image metadata.
  Press **Generate** — it turns into **Cancel** (⌘.) while running, which stops
  the batch immediately.
- **Gallery** (main): a grid of the active library's PNGs. Click to select
  (**⌘-click** to toggle, **⇧-click** for a range); a bottom inspector shows the
  prompt, seed, and size for a lone selection, or a batch bar (**Delete** to Trash
  / **Export** / **Move to Library**) for several. Double-click (or **View**) opens
  a **lightbox** with prev/next (←/→) and reveal. From the context menu,
  inspector, or lightbox you can **Reuse Prompt**, **Reuse All Parameters**
  ("make similar" — copies every setting, so a new seed yields a variation),
  **Use as Init Image** (send it to the Composer for img2img), **Upscale…**
  (ESRGAN ×4 into the current library), **Copy Prompt** / **Copy Negative
  Prompt**, and **Reveal in Finder**. A
  **library switcher** (folder menu) in the header row switches between named
  libraries, adds a new one (any folder), reveals it, or removes it from the list.
- **Manage Models** (View → Manage Models…, ⌘⇧M — or the "Get your first model…"
  button that replaces the model picker on a fresh install): browse the curated
  **catalog** (architecture, content rating, license, recommended RAM) and
  **install** a model with a live download progress bar, or **remove** an installed
  one to reclaim its multi-GB files. So a first-run user never has to touch the
  terminal to get started. Rated (questionable / explicit) models ask for
  confirmation before installing.
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
Model management uses the same one-shot pattern: `models list --json` (installed)
and `models list --catalog --json` (catalog) populate the pickers and the Manage
Models window; installing runs `models pull` (its stderr download progress is
streamed live into the progress bar) and removing runs `models rm --purge`. The
engine still owns the diffusion, the catalog, and the registry — the app only
drives the same subcommands a CLI user would.

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

A working txt2img **and img2img** app: Composer (single + batch, cancel, advanced
overrides, init image, LoRA stacking, ControlNet, License/credit panel) → Gallery
(lightbox, prompt / full-parameter reuse, use-as-init, ESRGAN upscale, switchable
libraries) with live progress, plus in-app **model management** (browse the
catalog, install with progress, remove — ADR-0001). Reuse works both for the
current session and for images reloaded from a library folder (reconstructed from
embedded metadata).

**Stays in the CLI:** inpaint, and the less-common model operations
(`quantize` / `import` / `gc`). This app drives the `serve` engine for txt2img /
img2img with LoRA + ControlNet, one-shot `upscale`, and catalog install/remove.

## Why Swift (native macOS)

Per the RFP: a Wails GUI was rejected (hard to debug); this is a native SwiftUI
app in the same family as `quick-translate` / `claude-usage-lens-gui`, talking to
image-forge over its stable `serve` protocol and `--json`. darwin/arm64 only, like
image-forge itself.

## License

MIT — see [LICENSE](LICENSE).
