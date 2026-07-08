# CLAUDE.md — image-forge-gui

**Organization rules (mandatory): https://github.com/nlink-jp/.github/blob/main/CONVENTIONS.md**

## Project overview

A native macOS app (SwiftUI, normal `WindowGroup` — Dock icon + standard menu bar,
macOS 14+) for exploratory local image generation. It's a thin front-end that
drives the `image-forge` CLI's resident `serve` engine: Composer → Generate
(single/batch) → Gallery with live progress. image-forge owns the diffusion
engine, model management, and PNG metadata; this app spawns it and renders.

## Non-negotiable rules

- **Tests are mandatory** — write them with the implementation
- **Never build ad-hoc** — use `make build` / `make build-app`
- **Docs in sync** — update `README.md` and `README.ja.md` together
- **Small, typed commits** — `feat:`, `fix:`, `test:`, `chore:`, `docs:`, etc.
- **No secrets / PII committed** — the app runs a local subprocess only

## Build & test

```sh
make run          # swift run (debug)
make build-app    # signed .app (embeds the CLI)
make package      # notarized + stapled + zipped .app
make test
```

## Key decisions

- **Native SwiftUI** (RFP §3): a Wails GUI was rejected as hard to debug. Same
  family as `quick-translate` / `claude-usage-lens-gui`. darwin/arm64 only (like
  image-forge). **Normal windowed app**, not a menu-bar agent.
- **serve-driven** (RFP §3): image-forge's engine is `internal/` and can't be
  imported, so the app drives `image-forge serve` (a resident mode designed for a
  GUI front-end). One JSON request per line → JSON events per line.
- **Self-contained `.app`**: `make build-app` bundles the signed CLI into Resources
  (`--deep`). `BinaryResolver` prefers that bundled copy.

## Architecture

- `App.swift` — `@main`, `WindowGroup { ContentView }` + `AppCommands` (menus)
- `AppModel` — `@MainActor`; owns `ServeClient`, models, results, progress
- `ServeClient` — resident serve driver (spawn/send/stream), pure `LineBuffer`
- `BinaryResolver` — pure, tested binary resolution
- `Models` — `GenerationRequest` / `ServeEvent` / `ModelInfo` (match serve + `models list --json`)
- `ComposerView` / `GalleryView` / `ContentView` — the UI

## Design reference

- CLI (engine + serve protocol): https://github.com/nlink-jp/image-forge
