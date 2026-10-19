# VNR - RBM Compatibility Patch - Agent Rules

Shared rules for every mod in this tree (file encodings, build commands, engine knowledge, git) are in the Modding Manager's `../../AGENTS.md`; `CLAUDE.md` and `GEMINI.md` import this file.

## What this mod is
- A compatibility patch for the graphical, tech-tree and interface conflicts between Vanilla Navy Rework (`2993766165`), RBM's GFX Overhaul (`3496134789`) and the VNR RT56 Compatch (`2993772731`); not yet on the Workshop. Its content is `interface/` and `gfx/`.

## Mod invariants
- Files under `gfx/` and `interface/` are copies from the upstream mods listed in `tools/upstream-manifest.json`. Never hand-edit them or `interface/zzz_vnr_rbm_compat.gfx`: change the manifest and run `.\tools\Sync-Upstream.ps1`, which also writes `tools/upstream-lock.json`.
- `tests/Compat.Tests.ps1` pins the manifest against the files; the Manager's `Scripts\Test-ModUpstream.ps1` reports when an installed upstream mod moved on (`-Acknowledge` records the installed versions).

## Commands beyond build.ps1
- `.\tools\Sync-Upstream.ps1`: refresh the upstream copies from the installed Workshop mods.

## Read when
| Task | Read |
|---|---|
| An upstream mod updated | the Manager's `Scripts\Test-ModUpstream.ps1`, then the `hoi4-mod-update-review` skill |
| What the patch copies and why | `tools/upstream-manifest.json`, `README.md` |

## Engine Knowledge
- Engine facts live in the Modding Manager's register, reached through the user-level `hoi4-modding-knowledge` skill: search it before a new kind of file and before asking for a game launch, cite ids here, never write a fact into this repository.
- Topics this mod leans on: `loading-and-overrides`, `gui-sprites-and-fonts`, `gui-widgets`, `encoding-and-syntax`.
- `tests/Knowledge.Tests.ps1` runs the register's audit for this repository; it is a copy the Manager keeps current.

