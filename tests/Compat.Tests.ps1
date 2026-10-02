BeforeDiscovery {
    . (Join-Path $PSScriptRoot "..\tools\UpstreamCommon.ps1")
    $manifest = Get-UpstreamManifest
    $script:ManifestFiles = @($manifest.files | ForEach-Object { @{ Path = $_.path; Source = $_.source } })
    $script:ScriptFiles = @($script:ManifestFiles | Where-Object { $_.Path -match '\.(gui|gfx|txt)$' }) +
        @(@{ Path = $manifest.generatedGfx; Source = 'generated' })

    # Upstream mods are only present on a machine subscribed to them; these checks are skipped on CI.
    $script:UpstreamMissing = -not (
        (Get-UpstreamModDir -Id $manifest.mods.vnr.id) -and (Get-UpstreamModDir -Id $manifest.mods.rbm.id)
    )
}

BeforeAll {
    . (Join-Path $PSScriptRoot "..\tools\UpstreamCommon.ps1")
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    $script:Manifest = Get-UpstreamManifest
    $script:GeneratedGfxPath = Join-Path $script:RepoRoot $script:Manifest.generatedGfx
    $script:VnrDir = Get-UpstreamModDir -Id $script:Manifest.mods.vnr.id
    $script:RbmDir = Get-UpstreamModDir -Id $script:Manifest.mods.rbm.id

    function Get-CleanScriptText {
        param([string]$Path)
        $lines = [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)
        return (@($lines | ForEach-Object { $_ -replace '#.*$', '' })) -join "`n"
    }
}

Describe "Upstream manifest" {
    It "lists each path only once" {
        $paths = @($script:Manifest.files | ForEach-Object { $_.path.ToLowerInvariant() })
        @($paths | Sort-Object -Unique).Count | Should -Be $paths.Count
    }

    It "<Path> exists in the patch" -ForEach $script:ManifestFiles {
        Test-Path -LiteralPath (Join-Path $script:RepoRoot $Path) | Should -Be $true
    }
}

Describe "Clausewitz script invariants" {
    It "<Path> has no BOM and balanced braces and quotes" -ForEach $script:ScriptFiles {
        $full = Join-Path $script:RepoRoot $Path
        $bytes = [System.IO.File]::ReadAllBytes($full)
        ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -Be $false

        $text = Get-CleanScriptText -Path $full
        ([regex]::Matches($text, '\{')).Count | Should -Be ([regex]::Matches($text, '\}')).Count
        (([regex]::Matches($text, '"')).Count % 2) | Should -Be 0
    }
}

Describe "Ship role icon strip" {
    It "<_> is re-declared with a frame count that divides its texture evenly" -ForEach @(
        'GFX_naval_equipment_role_icons', 'GFX_naval_equipment_role_icons_selected'
    ) {
        $blocks = Get-SpriteBlocks -ModRoot $script:RepoRoot
        $block = $blocks[$_.ToLowerInvariant()]
        $block | Should -Not -BeNullOrEmpty

        $textureMatch = [regex]::Match($block, 'texturefile\s*=\s*"([^"]+)"', 'IgnoreCase')
        $textureMatch.Success | Should -Be $true
        $texture = Join-Path $script:RepoRoot ($textureMatch.Groups[1].Value -replace '/', '\')
        Test-Path -LiteralPath $texture | Should -Be $true

        $framesMatch = [regex]::Match($block, 'noOfFrames\s*=\s*(\d+)', 'IgnoreCase')
        $framesMatch.Success | Should -Be $true
        $frames = [int]$framesMatch.Groups[1].Value
        $frames | Should -BeGreaterThan 8

        $size = Get-DdsSize -Path $texture
        ($size.Width % $frames) | Should -Be 0
    }
}

Describe "Upstream drift" {
    It "<Path> matches its <Source> source" -Skip:$script:UpstreamMissing -ForEach $script:ManifestFiles {
        $root = if ($Source -eq 'vnr') { $script:VnrDir } else { $script:RbmDir }
        $upstream = Join-Path $root ($Path -replace '/', '\')
        Test-Path -LiteralPath $upstream | Should -Be $true
        (Get-FileHash -LiteralPath (Join-Path $script:RepoRoot $Path) -Algorithm SHA256).Hash |
            Should -Be (Get-FileHash -LiteralPath $upstream -Algorithm SHA256).Hash
    }

    It "every file RBM and VNR both ship with different content is in the manifest" -Skip:$script:UpstreamMissing {
        $covered = @($script:Manifest.files | ForEach-Object { $_.path.ToLowerInvariant() })
        $ignored = @('descriptor.mod', 'thumbnail.png')

        $uncovered = @(Get-ChildItem -LiteralPath $script:VnrDir -Recurse -File | ForEach-Object {
            $relative = $_.FullName.Substring($script:VnrDir.Length + 1)
            $rbmFile = Join-Path $script:RbmDir $relative
            $key = ($relative -replace '\\', '/').ToLowerInvariant()
            if ($ignored -notcontains $key -and $covered -notcontains $key -and (Test-Path -LiteralPath $rbmFile)) {
                if ((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash -ne
                    (Get-FileHash -LiteralPath $rbmFile -Algorithm SHA256).Hash) { $key }
            }
        })

        $uncovered | Should -BeNullOrEmpty
    }

    It "the generated sprite file re-declares every sprite both mods define" -Skip:$script:UpstreamMissing {
        $expected = Get-CompatSpriteBlocks -VnrRoot $script:VnrDir -RbmRoot $script:RbmDir `
            -AlwaysRedeclare $script:Manifest.alwaysRedeclare
        $actual = Get-SpriteBlocks -ModRoot $script:RepoRoot

        foreach ($block in $expected) {
            $nameMatch = [regex]::Match($block, '\bname\s*=\s*"?([\w\-]+)"?')
            $nameMatch.Success | Should -Be $true
            $name = $nameMatch.Groups[1].Value
            $actual.Contains($name.ToLowerInvariant()) | Should -Be $true -Because "$name must be re-declared"
            ($actual[$name.ToLowerInvariant()] -replace '\s+', ' ') | Should -Be ($block -replace '\s+', ' ')
        }
    }
}
