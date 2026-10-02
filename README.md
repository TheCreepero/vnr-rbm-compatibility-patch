# VNR - RBM Compatibility Patch

Compatibility patch resolving graphical, tech tree, and interface conflicts between **Vanilla Navy Rework (VNR)** and **RBM's GFX Overhaul** for Hearts of Iron IV.

## Target Mods
- [RBM's GFX Overhaul](https://steamcommunity.com/sharedfiles/filedetails/?id=3496134789) (Workshop ID: `3496134789`)
- [Vanilla Navy Rework](https://steamcommunity.com/sharedfiles/filedetails/?id=2993766165) (Workshop ID: `2993766165`)
- [VNR RT56 Compatch](https://steamcommunity.com/sharedfiles/filedetails/?id=2993772731) (Workshop ID: `2993772731`)

## Overview

- **Game**: Hearts of Iron IV
- **Supported Version**: `1.19.*`
- **Mod Version**: `1.0`
- **Tags**: Graphics, Military, Historical

---

## Directory Architecture

This repository adheres to the standard single-root Hearts of Iron IV mod architecture:

```
C:\dev\vnr-rbm-compatibility-patch/
|-- .git/                           # Git repository root
|-- descriptor.mod                  # Clausewitz engine descriptor
|-- thumbnail.png                   # Steam Workshop thumbnail (512x512)
|-- build.ps1                       # Core build and lifecycle engine
|-- assets/                         # Raw graphics and master art assets
|-- artifacts/                      # Packaged release archives (git-ignored)
|-- common/                         # Game content and scripts (technologies, units, modules)
|-- interface/                      # GUI windows and GFX sprite definitions (.gui, .gfx)
|-- gfx/                            # Custom graphics, icons, and textures (.dds, .png)
|-- tests/                          # Automated Pester test suites
\-- wiki/                           # GitHub documentation wiki
```

---

## Development & Automation Commands

All lifecycle tasks are managed through `build.ps1`:

```powershell
# 1. Deploy mod to local Paradox Interactive Hearts of Iron IV mod folder
.\build.ps1 -Deploy

# 2. Configure zero-copy DevLink (instant hot-reload for live testing)
.\build.ps1 -DevLink

# 3. Validate syntax and bracket balance without deploying
.\build.ps1 -ValidateOnly

# 4. Run automated test suites (Pester)
.\build.ps1 -Test

# 5. Package clean release zip archive
.\build.ps1 -Package

# 6. Publish to Steam Workshop (Dry Run preview)
.\build.ps1 -PublishSteam -DryRun

# 7. Clean deployed mod files and temporary archives
.\build.ps1 -Clean
```

---

## Automated Testing

Unit tests are written with [Pester](https://pester.dev) and located in `tests/`. Execute tests using:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

---

## Author & License

- **Author**: TheCreepero