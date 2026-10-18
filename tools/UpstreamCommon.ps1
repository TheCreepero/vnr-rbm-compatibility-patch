# Shared helpers for Sync-Upstream.ps1 and tests/Compat.Tests.ps1. Dot-source this file.

function Get-UpstreamManifest {
    param([string]$Path = (Join-Path $PSScriptRoot "upstream-manifest.json"))
    return ([System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
}

# Resolves a Workshop mod's install folder from the launcher's ugc_<id>.mod file.
# Returns $null when the mod is not installed (e.g. on CI).
function Get-UpstreamModDir {
    param(
        [Parameter(Mandatory)][string]$Id,
        [string]$ModDir
    )

    if (-not $ModDir) {
        $docs = [Environment]::GetFolderPath('MyDocuments')
        if (-not $docs) { return $null }
        $ModDir = Join-Path $docs "Paradox Interactive\Hearts of Iron IV\mod"
    }

    $launcherFile = Join-Path $ModDir "ugc_$Id.mod"
    if (-not (Test-Path -LiteralPath $launcherFile)) { return $null }

    $raw = [System.IO.File]::ReadAllText($launcherFile, [System.Text.Encoding]::UTF8)
    if ($raw -notmatch '(?m)^\s*path\s*=\s*"([^"]+)"') { return $null }

    $dir = $matches[1] -replace '/', '\'
    if (Test-Path -LiteralPath $dir) { return $dir }
    return $null
}

# Parses every *spriteType block in a mod's interface/**/*.gfx files.
# Returns an ordered dictionary: lower-cased sprite name -> block text as written upstream.
# The last definition of a name wins, matching how the game resolves duplicates.
function Get-SpriteBlocks {
    param([Parameter(Mandatory)][string]$ModRoot)

    $blocks = [ordered]@{}
    $interfaceDir = Join-Path $ModRoot "interface"
    if (-not (Test-Path -LiteralPath $interfaceDir)) { return $blocks }

    $files = Get-ChildItem -LiteralPath $interfaceDir -Recurse -File -Filter *.gfx | Sort-Object FullName
    foreach ($file in $files) {
        $lines = [System.IO.File]::ReadAllLines($file.FullName, [System.Text.Encoding]::UTF8)
        $text = (@($lines | ForEach-Object { $_ -replace '#.*$', '' })) -join "`n"

        foreach ($m in [regex]::Matches($text, '\b\w*spriteType\s*=\s*\{', 'IgnoreCase')) {
            $depth = 1
            $i = $m.Index + $m.Length
            while ($i -lt $text.Length -and $depth -gt 0) {
                $ch = $text[$i]
                if ($ch -eq '{') { $depth++ } elseif ($ch -eq '}') { $depth-- }
                $i++
            }
            if ($depth -ne 0) { continue }

            $block = $text.Substring($m.Index, $i - $m.Index)
            if ($block -match '\bname\s*=\s*"?([\w\-]+)"?') {
                $key = $matches[1].ToLowerInvariant()
                if ($blocks.Contains($key)) { $blocks.Remove($key) }
                $blocks[$key] = $block
            }
        }
    }

    return $blocks
}

# Sprites the patch must re-declare with VNR's definition: every name RBM and VNR both define,
# plus the manifest's alwaysRedeclare list. Returns the VNR block texts, sorted by name.
function Get-CompatSpriteBlocks {
    param(
        [Parameter(Mandatory)][string]$VnrRoot,
        [Parameter(Mandatory)][string]$RbmRoot,
        [string[]]$AlwaysRedeclare = @()
    )

    $vnr = Get-SpriteBlocks -ModRoot $VnrRoot
    $rbm = Get-SpriteBlocks -ModRoot $RbmRoot

    $names = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($key in $vnr.Keys) {
        if ($rbm.Contains($key)) { [void]$names.Add($key) }
    }
    foreach ($name in $AlwaysRedeclare) {
        $key = $name.ToLowerInvariant()
        if (-not $vnr.Contains($key)) {
            throw "Sprite '$name' is listed in alwaysRedeclare but Vanilla Navy Rework no longer defines it."
        }
        [void]$names.Add($key)
    }

    return @($names | ForEach-Object { $vnr[$_] })
}

function Get-DdsSize {
    param([Parameter(Mandatory)][string]$Path)

    $stream = [System.IO.File]::OpenRead($Path)
    try {
        $header = New-Object byte[] 20
        [void]$stream.Read($header, 0, 20)
    }
    finally {
        $stream.Close()
    }

    return @{
        Height = [BitConverter]::ToInt32($header, 12)
        Width  = [BitConverter]::ToInt32($header, 16)
    }
}

# The installed version of a Workshop mod as Steam records it in appworkshop_394360.acf, next to the
# workshop content folder: the content manifest id and the day of the update. $null for a mod that is
# not a Workshop download.
function Get-UpstreamWorkshopVersion {
    param(
        [Parameter(Mandatory)][string]$InstallDir,
        [Parameter(Mandatory)][string]$Id
    )

    $acfPath = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $InstallDir))) "appworkshop_394360.acf"
    if (-not (Test-Path -LiteralPath $acfPath)) { return $null }

    $block = [regex]::Match([System.IO.File]::ReadAllText($acfPath), '"' + [regex]::Escape($Id) + '"\s*\{([^{}]*)\}')
    if (-not $block.Success) { return $null }
    $manifestMatch = [regex]::Match($block.Groups[1].Value, '"manifest"\s*"(\d+)"')
    if (-not $manifestMatch.Success) { return $null }
    $timeMatch = [regex]::Match($block.Groups[1].Value, '"timeupdated"\s*"(\d+)"')
    $updated = ""
    if ($timeMatch.Success) {
        $updated = [DateTimeOffset]::FromUnixTimeSeconds([long]$timeMatch.Groups[1].Value).UtcDateTime.ToString('yyyy-MM-dd')
    }
    return @{ Manifest = $manifestMatch.Groups[1].Value; TimeUpdated = $updated }
}

# Records what a sync was made from in tools/upstream-lock.json: each upstream mod's installed Workshop
# version and the SHA-256 of every file the manifest lists. The Modding Manager's Test-ModUpstream.ps1
# (and its Get-ModStatus.ps1 dashboard) compares the installed mods against it to report a stale patch.
function Save-UpstreamLock {
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][hashtable]$Roots,
        [string]$Path = (Join-Path $PSScriptRoot "upstream-lock.json")
    )

    $mods = [ordered]@{}
    foreach ($key in $Manifest.mods.PSObject.Properties.Name) {
        $id = [string]$Manifest.mods.$key.id
        $version = Get-UpstreamWorkshopVersion -InstallDir $Roots[$key] -Id $id
        $mods[$key] = [ordered]@{
            id          = $id
            manifest    = $(if ($version) { [string]$version.Manifest } else { "" })
            timeUpdated = $(if ($version) { [string]$version.TimeUpdated } else { "" })
        }
    }

    $files = [ordered]@{}
    foreach ($entry in $Manifest.files) {
        $source = Join-Path $Roots[$entry.source] ($entry.path -replace '/', '\')
        $hash = "missing"
        if (Test-Path -LiteralPath $source) {
            $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        $files[$entry.source + ':' + $entry.path] = $hash
    }

    [System.IO.File]::WriteAllText($Path, ([ordered]@{ mods = $mods; files = $files } | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
}
