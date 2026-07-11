# ADR-0001: Bring model management into the GUI

- Status: Accepted
- Date: 2026-07-11

## Context

The RFP (docs/en/image-forge-gui-rfp.md §3) deliberately kept **model management
in the CLI**: "the GUI only lists + generates." The app drives `image-forge serve`
for generation and calls `image-forge models list --json` once to populate the
Composer's model picker — nothing more.

That draws the boundary in the wrong place for a **first run**. A fresh install has
no models, and the app dead-ends the user into the terminal:

- `ComposerView` shows an empty picker and disables Generate when
  `diffusionModels.isEmpty`.
- The LoRA section literally instructs the user to run
  `image-forge models pull lcm-lora-sdxl`.
- `ServeClient.listModels()` only decodes **installed** models; the curated catalog
  the CLI already exposes (`models list --catalog --json`) is never surfaced.

For an app whose whole premise is "no technical knowledge needed," making the very
first action a CLI command is the single biggest UX gap (GUI issue #3).

The CLI already provides everything needed as one-shot subcommands — the engine
does not have to change:

- `models list --catalog --json` — the curated catalog (arch, rating, license,
  RAM tier, `needs_opt_in`, `installed`).
- `models pull <name> [--allow-nsfw]` — downloads + registers, **streaming
  progress on stderr** (resumable/retrying).
- `models rm <name> [--purge]` — removes the registry entry, and with `--purge`
  reclaims the multi-GB weight files (keeping shared / out-of-dir files).

## Decision

**Revisit the RFP boundary: model acquisition and removal move into the GUI**,
driven by the existing CLI one-shots. The diffusion engine, the catalog, and the
registry stay owned by image-forge — the GUI only *drives* the same subcommands a
CLI user would run, exactly as it already drives `serve` and `upscale`.

Concretely:

- A dedicated **Manage Models** window (menu + a "Get your first model…" button
  that replaces the Composer's dead-end empty state). A window (not a modal sheet)
  so it can stay open beside the Composer.
- **Browse** the catalog via `models list --catalog --json`, showing arch, rating,
  license, RAM tier, and an installed badge.
- **Install** via `models pull` with **live progress**. This needs a *streaming*
  one-shot (the existing `runOneShot` only returns stdout at exit); we add
  `runStreaming(args:onLine:)` that surfaces stderr progress lines as they arrive,
  reusing the concurrent-drain discipline that fixed the two-pipe deadlock.
- **Remove** via `models rm --purge` to actually reclaim disk (a GUI user has no
  other way to free the multi-GB files).
- Respect the **NSFW opt-in**: a `needs_opt_in` catalog entry requires an explicit
  confirmation before `--allow-nsfw` is passed.

Out of scope for now (kept in the CLI): `quantize`, `import`, `models gc`, and
disk-usage reporting. `gc` and disk usage are the natural next increment.

## Consequences

- The GUI delivers on "no technical knowledge needed" on first run.
- New CLI coupling: three more subcommand shapes the GUI depends on
  (`list --catalog --json`, `pull`, `rm --purge`). These are stable, name-based,
  and already how a CLI user manages models; `pull`'s stderr progress text is
  best-effort (parsed leniently, never fatal).
- The trust boundary is unchanged: the GUI still runs only the bundled, signed
  `image-forge` binary (`BinaryResolver`), now for management as well as rendering.
- The RFP's "GUI only lists + generates" statement is superseded by this ADR.
