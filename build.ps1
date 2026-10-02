[CmdletBinding(DefaultParameterSetName = 'Deploy')]
param(
    [Parameter(ParameterSetName = 'Deploy')]
    [switch]$Deploy,

    [Parameter(ParameterSetName = 'DevLink')]
    [switch]$DevLink,

    [Parameter(ParameterSetName = 'Package')]
    [switch]$Package,

    [Parameter(ParameterSetName = 'PublishSteam')]
    [switch]$PublishSteam,

    [Parameter(ParameterSetName = 'InstallSteamCmd')]
    [switch]$InstallSteamCmd,

    [Parameter(ParameterSetName = 'ValidateOnly')]
    [switch]$ValidateOnly,

    [Parameter(ParameterSetName = 'Test')]
    [switch]$Test,

    [switch]$Validate,
    [switch]$NoValidate,
    [switch]$Clean,

    [string]$Hoi4InstallDir,
    [string]$ModDir,
    [string]$ZipOutput,
    [string]$SteamUser,
    [string]$ChangeNote,
    [string]$SteamCmdPath,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

$RepoDir = $PSScriptRoot
$DescriptorPath = Join-Path $RepoDir "descriptor.mod"
$ModFolderName = Split-Path -Leaf $RepoDir
$ModZipArchiveName = "vnr-rbm-compatibility-patch.zip"
$ArtifactsDir = Join-Path $RepoDir "artifacts"

if (-not $ModDir) {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $ModDir = Join-Path $docs "Paradox Interactive\Hearts of Iron IV\mod"
}

function Write-Step { param([string]$msg) Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Info { param([string]$msg) Write-Host "  [INFO] $msg" -ForegroundColor Gray }
function Write-Warn { param([string]$msg) Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$msg) Write-Host "  [ERROR] $msg" -ForegroundColor Red }

function Get-ModMetadata {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "Descriptor file not found: $Path"
    }

    $raw = Get-Content $Path -Raw -Encoding UTF8
    $metadata = @{
        Raw = $raw
        Version = $null
        SupportedVersion = $null
        Name = $null
        RemoteFileId = $null
        Tags = @()
    }

    if ($raw -match 'version\s*=\s*"([^"]+)"') { $metadata.Version = $matches[1] }
    if ($raw -match 'supported_version\s*=\s*"([^"]+)"') { $metadata.SupportedVersion = $matches[1] }
    if ($raw -match 'name\s*=\s*"([^"]+)"') { $metadata.Name = $matches[1] }
    if ($raw -match 'remote_file_id\s*=\s*"([^"]+)"') { $metadata.RemoteFileId = $matches[1] }

    return $metadata
}

function New-LauncherModContent {
    param(
        [string]$DescriptorPath,
        [string]$TargetModPath
    )

    $rawLines = Get-Content $DescriptorPath -Encoding UTF8
    $normalizedPath = ($TargetModPath -replace '\\', '/')

    $lines = [System.Collections.Generic.List[string]]::new()
    $insertedPath = $false

    foreach ($line in $rawLines) {
        if ($line -match '^\s*path\s*=') { continue }

        if (-not $insertedPath -and ($line -match '^\s*remote_file_id\s*=')) {
            $lines.Add('path="' + $normalizedPath + '"')
            $insertedPath = $true
        }

        $lines.Add($line)
    }

    if (-not $insertedPath) {
        $lines.Add('path="' + $normalizedPath + '"')
    }

    return ($lines -join "`r`n")
}

function Invoke-Validation {
    Write-Step "Validating mod syntax, descriptor, and structure..."
    $hasErrors = $false

    if (-not (Test-Path $DescriptorPath)) {
        Write-Err "descriptor.mod is missing!"
        $hasErrors = $true
    } else {
        $meta = Get-ModMetadata -Path $DescriptorPath
        if (-not $meta.Name) { Write-Err "descriptor.mod: missing 'name' attribute"; $hasErrors = $true }
        if (-not $meta.SupportedVersion) { Write-Err "descriptor.mod: missing 'supported_version' attribute"; $hasErrors = $true }
        if (-not $hasErrors) {
            Write-Ok "descriptor.mod valid (Mod: '$($meta.Name)', Game Version: $($meta.SupportedVersion))"
        }
    }

    $thumbPath = Join-Path $RepoDir "thumbnail.png"
    if (Test-Path $thumbPath) {
        Write-Ok "thumbnail.png verified"
    } else {
        Write-Err "thumbnail.png missing from root directory!"
        $hasErrors = $true
    }

    $clausewitzFiles = @(Get-ChildItem -Path $RepoDir -Recurse -File | Where-Object {
        ($_.Extension -eq '.txt' -or $_.Extension -eq '.gui' -or $_.Extension -eq '.gfx') -and
        $_.FullName -notmatch '[\\/](\.git|\.github|\.vscode|tests|tools|wiki)[\\/]'
    })

    $checkedCount = 0
    foreach ($file in $clausewitzFiles) {
        $fileHasError = $false
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            Write-Err "$($file.Name): UTF-8 BOM detected! Files must be saved as UTF-8 without BOM."
            $fileHasError = $true
        }

        $lines = [System.IO.File]::ReadAllLines($file.FullName, [System.Text.Encoding]::UTF8)
        $cleanLines = @($lines | ForEach-Object { $_ -replace '#.*$', '' })
        $cleanText = $cleanLines -join "`n"

        $openCount  = ([regex]::Matches($cleanText, '\{')).Count
        $closeCount = ([regex]::Matches($cleanText, '\}')).Count
        if ($openCount -ne $closeCount) {
            Write-Err "$($file.Name): Bracket mismatch (Open: $openCount, Close: $closeCount)"
            $fileHasError = $true
        }

        $quoteCount = ([regex]::Matches($cleanText, '"')).Count
        if ($quoteCount % 2 -ne 0) {
            Write-Err "$($file.Name): Unbalanced double quotes ($quoteCount quotes found)"
            $fileHasError = $true
        }

        if ($fileHasError) {
            $hasErrors = $true
        } else {
            $checkedCount++
        }
    }

    if (-not $hasErrors) {
        Write-Ok "All $checkedCount content files passed syntax and structure validation."
    }

    return (-not $hasErrors)
}

function Find-SteamCmd {
    param([string]$CustomPath)
    if ($CustomPath -and (Test-Path $CustomPath)) { return $CustomPath }
    if (Get-Command 'steamcmd' -ErrorAction SilentlyContinue) {
        return (Get-Command 'steamcmd').Source
    }
    $candidates = @(
        "C:\steamcmd\steamcmd.exe",
        "C:\Program Files (x86)\SteamCMD\steamcmd.exe",
        (Join-Path $env:LOCALAPPDATA "Programs\steamcmd\steamcmd.exe")
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    return $null
}

function Install-SteamCmd {
    $destDir = "C:\steamcmd"
    Write-Step "Installing SteamCMD to $destDir..."
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    $zipPath = Join-Path $destDir "steamcmd.zip"
    Invoke-WebRequest -Uri "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip" -OutFile $zipPath
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $destDir)
    Remove-Item -Force $zipPath
    Write-Ok "SteamCMD installed successfully at $destDir\steamcmd.exe"
    return (Join-Path $destDir "steamcmd.exe")
}

if ($InstallSteamCmd) {
    $installed = Install-SteamCmd
    Write-Host "`nSteamCMD ready at: $installed" -ForegroundColor Green
    $stopwatch.Stop()
    exit 0
}

$shouldValidate = $Validate -or (-not $NoValidate -and -not $Clean -and -not $Test)
if ($ValidateOnly) {
    $ok = Invoke-Validation
    $stopwatch.Stop()
    if ($ok) {
        Write-Host "`nValidation succeeded in $($stopwatch.Elapsed.TotalSeconds.ToString('0.00'))s" -ForegroundColor Green
        exit 0
    } else {
        Write-Host "`nValidation failed!" -ForegroundColor Red
        exit 1
    }
}

if ($Test) {
    $testRunner = Join-Path $RepoDir "tests\Run-Tests.ps1"
    if (-not (Test-Path $testRunner)) {
        Write-Err "Test runner not found at: $testRunner"
        exit 1
    }
    & $testRunner
    $rc = $LASTEXITCODE
    $stopwatch.Stop()
    exit $rc
}

if ($shouldValidate) {
    $valid = Invoke-Validation
    if (-not $valid) {
        Write-Err "Pre-flight validation failed. Aborting."
        exit 1
    }
}

if ($Clean) {
    Write-Step "Cleaning build artifacts and deployed mod..."
    $deployedFolder = Join-Path $ModDir $ModFolderName
    $deployedModFile = Join-Path $ModDir "$ModFolderName.mod"
    $zipFile = if ($ZipOutput) { $ZipOutput } else { Join-Path $ArtifactsDir $ModZipArchiveName }

    if (Test-Path $deployedFolder) {
        Remove-Item -Recurse -Force $deployedFolder
        Write-Ok "Removed deployed folder: $deployedFolder"
    }
    if (Test-Path $deployedModFile) {
        Remove-Item -Force $deployedModFile
        Write-Ok "Removed deployed mod file: $deployedModFile"
    }
    if (Test-Path $zipFile) {
        Remove-Item -Force $zipFile
        Write-Ok "Removed archive: $zipFile"
    }

    Write-Host "`nClean complete." -ForegroundColor Green
    exit 0
}

if ($DevLink) {
    Write-Step "Configuring DevLink (Zero-Copy Live Development)..."

    if (-not (Test-Path $ModDir)) {
        New-Item -ItemType Directory -Path $ModDir -Force | Out-Null
    }

    $targetDir = Join-Path $ModDir $ModFolderName
    if (Test-Path $targetDir) {
        Write-Warn "A physical deployed folder exists at: $targetDir"
        Write-Warn "Removing or renaming it is recommended so the launcher does not conflict with DevLink."
    }

    $launcherModContent = New-LauncherModContent -DescriptorPath $DescriptorPath -TargetModPath $RepoDir
    $targetModFile = Join-Path $ModDir "$ModFolderName.mod"
    [System.IO.File]::WriteAllText($targetModFile, $launcherModContent, [System.Text.UTF8Encoding]::new($false))

    $localModFile = Join-Path $RepoDir "$ModFolderName.mod"
    [System.IO.File]::WriteAllText($localModFile, $launcherModContent, [System.Text.UTF8Encoding]::new($false))

    Write-Ok "DevLink configured successfully!"
    Write-Info "Launcher mod file: $targetModFile"
    Write-Info "Points directly to: $RepoDir"
    $stopwatch.Stop()
    exit 0
}

if ($Package) {
    Write-Step "Packaging mod release archive..."
    if (-not (Test-Path $ArtifactsDir)) {
        New-Item -ItemType Directory -Path $ArtifactsDir -Force | Out-Null
    }
    $zipTarget = if ($ZipOutput) { $ZipOutput } else { Join-Path $ArtifactsDir $ModZipArchiveName }

    if (Test-Path $zipTarget) {
        Remove-Item -Force $zipTarget
    }

    $tempStage = Join-Path ([System.IO.Path]::GetTempPath()) "mod_pkg_$([System.Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $tempStage -Force | Out-Null

    try {
        $excludeDirs = @('.git', '.github', '.vscode', '.agents', '.agent', 'tests', 'tools', 'wiki', 'assets', 'artifacts', 'scratch', 'Files', 'docs')
        $excludeFiles = @('.gitattributes', '.gitignore', 'build.ps1', 'build.bat', 'build_and_deploy.bat', '.steam_username')

        $items = Get-ChildItem -Path $RepoDir
        foreach ($item in $items) {
            if ($item.PSIsContainer) {
                if ($excludeDirs -contains $item.Name) { continue }
                Copy-Item -Path $item.FullName -Destination (Join-Path $tempStage $item.Name) -Recurse -Force
            } else {
                if ($excludeFiles -contains $item.Name) { continue }
                if ($item.Extension -eq '.zip' -or $item.Extension -eq '.md') { continue }
                Copy-Item -Path $item.FullName -Destination (Join-Path $tempStage $item.Name) -Force
            }
        }

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($tempStage, $zipTarget)
        Write-Ok "Package created successfully: $zipTarget"
    }
    finally {
        if (Test-Path $tempStage) {
            Remove-Item -Recurse -Force $tempStage
        }
    }

    $stopwatch.Stop()
    exit 0
}

if ($PublishSteam) {
    Write-Step "Preparing Steam Workshop publication..."
    $steamCmd = Find-SteamCmd -CustomPath $SteamCmdPath
    if (-not $steamCmd -and -not $DryRun) {
        Write-Err "SteamCMD not found! Run with -InstallSteamCmd to install it automatically."
        exit 1
    }

    $meta = Get-ModMetadata -Path $DescriptorPath
    if (-not $meta.RemoteFileId) {
        Write-Warn "No remote_file_id found in descriptor.mod. Steam Workshop will create a NEW item."
    }

    $userFile = Join-Path $RepoDir ".steam_username"
    if (-not $SteamUser -and (Test-Path $userFile)) {
        $SteamUser = (Get-Content $userFile -Raw).Trim()
    }

    if (-not $SteamUser -and -not $DryRun) {
        $SteamUser = Read-Host "Enter your Steam account username"
        if ($SteamUser) {
            Set-Content -Path $userFile -Value $SteamUser -Force
        }
    }

    $stageDir = Join-Path ([System.IO.Path]::GetTempPath()) "steam_stage_$([System.Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

    try {
        $excludeDirs = @('.git', '.github', '.vscode', '.agents', '.agent', 'tests', 'tools', 'wiki', 'assets', 'artifacts', 'scratch', 'Files', 'docs')
        $excludeFiles = @('.gitattributes', '.gitignore', 'build.ps1', 'build.bat', 'build_and_deploy.bat', '.steam_username')

        $items = Get-ChildItem -Path $RepoDir
        foreach ($item in $items) {
            if ($item.PSIsContainer) {
                if ($excludeDirs -contains $item.Name) { continue }
                Copy-Item -Path $item.FullName -Destination (Join-Path $stageDir $item.Name) -Recurse -Force
            } else {
                if ($excludeFiles -contains $item.Name) { continue }
                if ($item.Extension -eq '.zip' -or $item.Extension -eq '.md') { continue }
                Copy-Item -Path $item.FullName -Destination (Join-Path $stageDir $item.Name) -Force
            }
        }

        $vdfPath = Join-Path $stageDir "workshop_build.vdf"
        $vdfLines = @(
            '"workshopitem"',
            '{',
            '    "appid"             "394360"',
            ('    "publishedfileid"   "' + $meta.RemoteFileId + '"'),
            ('    "contentfolder"     "' + ($stageDir -replace '\\', '/') + '"'),
            ('    "previewfile"       "' + ((Join-Path $stageDir 'thumbnail.png') -replace '\\', '/') + '"'),
            '    "visibility"        "0"',
            ('    "title"             "' + $meta.Name + '"'),
            ('    "changenote"        "' + $ChangeNote + '"'),
            '}'
        )
        $vdfContent = $vdfLines -join "`r`n"
        [System.IO.File]::WriteAllText($vdfPath, $vdfContent, [System.Text.UTF8Encoding]::new($false))

        Write-Info "Staged content at: $stageDir"
        Write-Info "VDF Path: $vdfPath"

        if ($DryRun) {
            Write-Ok "[DRY RUN] Would execute SteamCMD with VDF content:`n$vdfContent"
            $stopwatch.Stop()
            exit 0
        }

        $steamArgs = '+login ' + $SteamUser + ' +workshop_build_item "' + $vdfPath + '" +quit'
        Write-Step "Executing SteamCMD..."
        $proc = Start-Process -FilePath $steamCmd -ArgumentList $steamArgs -NoNewWindow -PassThru -Wait
        if ($proc.ExitCode -ne 0) {
            Write-Err "SteamCMD exited with error code $($proc.ExitCode)"
            exit $proc.ExitCode
        }
        Write-Ok "Steam Workshop upload completed successfully!"
    }
    finally {
        if (-not $DryRun -and (Test-Path $stageDir)) {
            Remove-Item -Recurse -Force $stageDir
        }
    }

    $stopwatch.Stop()
    exit 0
}

Write-Step "Deploying mod to Paradox Interactive HOI4 mod directory..."

if (-not (Test-Path $ModDir)) {
    New-Item -ItemType Directory -Path $ModDir -Force | Out-Null
}

$targetFolder = Join-Path $ModDir $ModFolderName
if (-not (Test-Path $targetFolder)) {
    New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
}

$excludeDirs = @('.git', '.github', '.vscode', '.agents', '.agent', 'tests', 'tools', 'wiki', 'assets', 'artifacts', 'scratch', 'Files', 'docs')
$excludeFiles = @('.gitattributes', '.gitignore', 'build.ps1', 'build.bat', 'build_and_deploy.bat', '.steam_username')

$items = Get-ChildItem -Path $RepoDir
foreach ($item in $items) {
    if ($item.PSIsContainer) {
        if ($excludeDirs -contains $item.Name) { continue }
        Copy-Item -Path $item.FullName -Destination (Join-Path $targetFolder $item.Name) -Recurse -Force
    } else {
        if ($excludeFiles -contains $item.Name) { continue }
        if ($item.Extension -eq '.zip' -or $item.Extension -eq '.md') { continue }
        Copy-Item -Path $item.FullName -Destination (Join-Path $targetFolder $item.Name) -Force
    }
}

$launcherModContent = New-LauncherModContent -DescriptorPath $DescriptorPath -TargetModPath $targetFolder
$targetModFile = Join-Path $ModDir "$ModFolderName.mod"
[System.IO.File]::WriteAllText($targetModFile, $launcherModContent, [System.Text.UTF8Encoding]::new($false))

Write-Ok "Mod successfully deployed to: $targetFolder"
Write-Ok "Launcher descriptor generated at: $targetModFile"
$stopwatch.Stop()
Write-Info "Deployment completed in $($stopwatch.Elapsed.TotalSeconds.ToString('0.00'))s"
exit 0