BeforeAll {
    $script:RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
    $script:BuildScriptPath = Join-Path $script:RepoRoot "build.ps1"
    $script:BuildContent = [System.IO.File]::ReadAllText($script:BuildScriptPath, [System.Text.Encoding]::UTF8)

    $metaFuncMatch = [regex]::Match($script:BuildContent, '(?s)(function Get-ModMetadata\s*\{.*?\n\})')
    $launcherFuncMatch = [regex]::Match($script:BuildContent, '(?s)(function New-LauncherModContent\s*\{.*?\n\})')

    if ($metaFuncMatch.Success) {
        . ([ScriptBlock]::Create($metaFuncMatch.Groups[1].Value))
    }
    if ($launcherFuncMatch.Success) {
        . ([ScriptBlock]::Create($launcherFuncMatch.Groups[1].Value))
    }

    $script:PowerShellExe = (Get-Process -Id $PID).Path

    function New-TempDirectory {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) "mod_test_$([System.Guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        return $path
    }

    function Get-RelativeFileList {
        param([string]$Root)

        $rootPath = (Resolve-Path $Root).Path.TrimEnd('\', '/')
        return @(Get-ChildItem -Path $rootPath -Recurse -Force -File |
            ForEach-Object { $_.FullName.Substring($rootPath.Length + 1) -replace '\\', '/' } |
            Sort-Object)
    }

    function Get-NestedFolderList {
        param([string]$Root)

        return @(Get-ChildItem -Path $Root -Recurse -Force -Directory |
            Where-Object { $_.Name -eq $_.Parent.Name } |
            ForEach-Object { $_.FullName })
    }

    function Get-ExpectedModFileList {
        $expected = @('descriptor.mod', 'thumbnail.png')
        foreach ($folder in @('interface', 'gfx')) {
            $expected += Get-RelativeFileList -Root (Join-Path $script:RepoRoot $folder) | ForEach-Object { "$folder/$_" }
        }
        return @($expected | Sort-Object)
    }
}

Describe "build.ps1 Helper: Get-ModMetadata" {
    It "Parses mod metadata correctly from descriptor file" {
        $tempFile = [System.IO.Path]::GetTempFileName()
        try {
            $sampleLines = @(
                'version="1.0.0"',
                'tags={',
                "`t`"Historical`"",
                "`t`"Military`"",
                '}',
                'name="VNR - RBM Compatibility Patch"',
                'supported_version="1.19.*"',
                'remote_file_id="1234567890"'
            )
            $sampleDescriptor = $sampleLines -join "`r`n"
            [System.IO.File]::WriteAllText($tempFile, $sampleDescriptor, [System.Text.Encoding]::UTF8)

            $meta = Get-ModMetadata -Path $tempFile
            $meta.Version | Should -Be "1.0.0"
            $meta.Name | Should -Be "VNR - RBM Compatibility Patch"
            $meta.SupportedVersion | Should -Be "1.19.*"
            $meta.RemoteFileId | Should -Be "1234567890"
        }
        finally {
            if (Test-Path $tempFile) { Remove-Item -Force $tempFile }
        }
    }
}

Describe "build.ps1 Helper: New-LauncherModContent" {
    It "Normalizes backslashes to forward slashes in target mod path" {
        $tempFile = [System.IO.Path]::GetTempFileName()
        try {
            $sampleLines = @(
                'version="1.0"',
                'name="VNR - RBM Compatibility Patch"',
                'supported_version="1.19.*"'
            )
            $sampleDescriptor = $sampleLines -join "`r`n"
            [System.IO.File]::WriteAllText($tempFile, $sampleDescriptor, [System.Text.Encoding]::UTF8)

            $result = New-LauncherModContent -DescriptorPath $tempFile -TargetModPath "C:\Games\Hearts of Iron IV\mod\vnr-rbm-compatibility-patch"
            $result | Should -Match 'path="C:/Games/Hearts of Iron IV/mod/vnr-rbm-compatibility-patch"'
            $result | Should -Not -Match '\\\\'
        }
        finally {
            if (Test-Path $tempFile) { Remove-Item -Force $tempFile }
        }
    }
}

Describe "build.ps1 Content Copy" {
    It "Deploying twice into the same mod folder does not nest content folders" {
        $modDir = New-TempDirectory
        try {
            foreach ($run in 1..2) {
                & $script:PowerShellExe -NoProfile -ExecutionPolicy Bypass -File $script:BuildScriptPath -Deploy -NoValidate -ModDir $modDir | Out-Null
                $LASTEXITCODE | Should -Be 0
            }

            $deployed = Join-Path $modDir (Split-Path -Leaf $script:RepoRoot)
            Get-NestedFolderList -Root $deployed | Should -BeNullOrEmpty
            Get-RelativeFileList -Root $deployed | Should -Be (Get-ExpectedModFileList)
        }
        finally {
            Remove-Item -Recurse -Force $modDir
        }
    }

    It "Publish dry run stages only the mod content" {
        $output = & $script:PowerShellExe -NoProfile -ExecutionPolicy Bypass -File $script:BuildScriptPath -PublishSteam -DryRun -NoValidate
        $LASTEXITCODE | Should -Be 0

        $stagedLine = @($output | Where-Object { $_ -match 'Staged content at:\s*(.+)$' })[0]
        $stagedLine | Should -Not -BeNullOrEmpty
        $null = $stagedLine -match 'Staged content at:\s*(.+)$'
        $contentDir = $matches[1].Trim()
        try {
            Get-NestedFolderList -Root $contentDir | Should -BeNullOrEmpty
            Get-RelativeFileList -Root $contentDir | Should -Be (Get-ExpectedModFileList)
        }
        finally {
            Remove-Item -Recurse -Force (Split-Path -Parent $contentDir)
        }
    }

    It "Package archive contains only the mod content" {
        $zipDir = New-TempDirectory
        try {
            $zipPath = Join-Path $zipDir "package.zip"
            & $script:PowerShellExe -NoProfile -ExecutionPolicy Bypass -File $script:BuildScriptPath -Package -NoValidate -ZipOutput $zipPath | Out-Null
            $LASTEXITCODE | Should -Be 0

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
            try {
                $entries = @($zip.Entries | Where-Object { $_.Name } | ForEach-Object { $_.FullName -replace '\\', '/' } | Sort-Object)
            }
            finally {
                $zip.Dispose()
            }
            $entries | Should -Be (Get-ExpectedModFileList)
        }
        finally {
            Remove-Item -Recurse -Force $zipDir
        }
    }
}

Describe "build.ps1 Packaging & Staging Exclusions" {
    It "Build script must exclude tests directory from packages and deployment" {
        $script:BuildContent | Should -Match "excludeDirs\s*=\s*@\([^)]*['`"]tests['`"]"
    }

    It "Build script must exclude wiki directory from packages and deployment" {
        $script:BuildContent | Should -Match "excludeDirs\s*=\s*@\([^)]*['`"]wiki['`"]"
    }

    It "Build script must exclude .git and dev tools from packaging" {
        $script:BuildContent | Should -Match "excludeDirs\s*=\s*@\([^)]*['`"]\.git['`"]"
        $script:BuildContent | Should -Match "excludeDirs\s*=\s*@\([^)]*['`"]\.github['`"]"
    }
}