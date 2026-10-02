# VNR - RBM Compatibility Patch - Development & Agent Rules

## 1. Mod Architecture & Workspace Layout
- This project is a compatibility patch resolving graphical, tech tree, and interface conflicts between:
  - **Vanilla Navy Rework (VNR)** (Steam ID: `2993766165`)
  - **RBM's GFX Overhaul** (Steam ID: `3496134789`)
  - **VNR RT56 Compatch** (Steam ID: `2993772731`)
- This project follows a unified single-root mod layout:
  - **Workspace & Git root**: `C:\dev\vnr-rbm-compatibility-patch` (Git repository root containing `.git/`)
  - All mod descriptors (`descriptor.mod`), build tools (`build.ps1`), content (`common/`, `interface/`, `gfx/`), tests (`tests/`), and agent configurations (`GEMINI.md`) reside at the project root.
  - Release archives (`artifacts/`) and scratch scripts (`scratch/`) are git-ignored.

## 2. Clausewitz File Format & Syntax Invariants
- **UTF-8 Without BOM**: All Clausewitz script files (`.mod`, `.txt`, `.gui`, `.gfx`) must be saved in UTF-8 without BOM. Never use standard Windows PowerShell `Set-Content -Encoding UTF8` because it writes a BOM (`\ufeff`). Always write text files using:
  `[System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))`
- **Key-Value Syntax**: `descriptor.mod` must strictly follow `key="value"` without spaces around the `=` operator.
- **Bracket Balance**: Curly braces `{}` and double quotes `""` must always be strictly balanced.
- **No Empty Blocks**: Avoid empty blocks such as `unique = { }` or `ordered = { }`.

## 3. Build & Automation Protocol
- Always run pre-flight syntax and descriptor checks before declaring work complete:
  `powershell -File .\build.ps1 -ValidateOnly`
- Run the full automated Pester test suite:
  `powershell -File .\build.ps1 -Test`
- Use `.\build.ps1 -DevLink` for zero-copy live editing directly from the repository.
- Use `.\build.ps1 -Package` to verify that release packaging strictly excludes `.git`, `.github`, `.vscode`, `tests`, `wiki`, and developer scripts.

- Files under `gfx/` and `interface/` are copies from the upstream mods, listed in `tools/upstream-manifest.json`. Never hand-edit them or `interface/zzz_vnr_rbm_compat.gfx`; change the manifest and run `.\tools\Sync-Upstream.ps1`.

## 4. Git & Commit Guidelines
- Do not commit to the Git repository unless explicitly instructed by the user. The user prefers to review changes before committing.
- **Git Verification Invariant**: After completing changes, always verify `git status` to ensure the working tree reflects expected changes.