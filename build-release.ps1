#Requires -Version 5.1
<#
.SYNOPSIS
    Build a Claude Code Dev Studio release ZIP + SHA256 sidecar.

.DESCRIPTION
    Stages an installed-layout tree under .\dist\stage\ccds-<version>\,
    zips it to .\dist\ccds-<version>.zip, and writes a matching
    .sha256 sidecar.

    Installed layout (inside the ZIP):
      bin/                 -- dispatcher scripts (ccds.{ps1,sh})
      scripts/             -- Sync-AgentPacks, Verify-Agents, jit-claude.md
      agents/              -- 105 agent .md files (all generalists + pack agents flat)
      catalog.json         -- agent index with name/pack/model/description
      README.md            -- installer reference
      version.txt          -- the release version tag

    After extraction to ~/.claude/playbook/ the installer:
      - Copies 7 generalist agents to ~/.claude/agents/
      - Injects the JIT protocol block into ~/.claude/CLAUDE.md (marker-based, idempotent)

.PARAMETER Version
    Release version tag. Required. Example: 'v0.4.0-rc1'.

.PARAMETER OutputDir
    Destination directory for the ZIP and sidecar. Default: '.\dist'.

.EXAMPLE
    .\build-release.ps1 -Version v0.4.0-rc1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^v\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$')]
    [string]$Version,

    [string]$OutputDir = (Join-Path $PSScriptRoot 'dist')
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# Preflight: required source files
# ---------------------------------------------------------------------------
$required = @(
    'bin\ccds.ps1'
    'bin\ccds.sh'
    'Sync-AgentPacks.ps1'
    'Verify-Agents.ps1'
    'Sync-AgentPacks.sh'
    'verify-agents.sh'
    'catalog.json'
    'scripts\jit-claude.md'
    'scripts\ccds-user-setup.sh'
    'README.md'
    '.claude\agents'
)
$missing = @()
foreach ($rel in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $rel))) { $missing += $rel }
}
if ($missing.Count -gt 0) {
    throw "Missing required source(s): $($missing -join ', ')"
}

# ---------------------------------------------------------------------------
# Prepare output and stage directories
# ---------------------------------------------------------------------------
$pkgName  = "ccds-$Version"
$stageDir = Join-Path $OutputDir "stage\$pkgName"
$zipPath  = Join-Path $OutputDir "$pkgName.zip"
$shaPath  = "$zipPath.sha256"

if (Test-Path -LiteralPath (Join-Path $OutputDir 'stage')) {
    Write-Step "Cleaning previous stage: $(Join-Path $OutputDir 'stage')"
    Remove-Item -LiteralPath (Join-Path $OutputDir 'stage') -Recurse -Force
}
New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

# ---------------------------------------------------------------------------
# Copy map: source (repo-relative) -> destination (stage-relative)
# ---------------------------------------------------------------------------
$copyMap = @(
    @{ Src = 'bin\ccds.ps1' ; Dst = 'bin\ccds.ps1' }
    @{ Src = 'bin\ccds.sh'  ; Dst = 'bin\ccds.sh' }
    @{ Src = 'Sync-AgentPacks.ps1'     ; Dst = 'scripts\Sync-AgentPacks.ps1' }
    @{ Src = 'Verify-Agents.ps1'       ; Dst = 'scripts\Verify-Agents.ps1' }
    @{ Src = 'Sync-AgentPacks.sh'      ; Dst = 'scripts\Sync-AgentPacks.sh' }
    @{ Src = 'verify-agents.sh'        ; Dst = 'scripts\verify-agents.sh' }
    @{ Src = 'scripts\jit-claude.md'        ; Dst = 'scripts\jit-claude.md' }
    @{ Src = 'scripts\ccds-user-setup.sh'  ; Dst = 'scripts\ccds-user-setup.sh' }
    @{ Src = 'catalog.json'            ; Dst = 'catalog.json' }
    @{ Src = 'README.md'               ; Dst = 'README.md' }
)

Write-Step "Staging files to $stageDir"
foreach ($entry in $copyMap) {
    $srcFull = Join-Path $repoRoot $entry.Src
    $dstFull = Join-Path $stageDir $entry.Dst
    $dstDir  = Split-Path -Parent $dstFull
    if (-not (Test-Path -LiteralPath $dstDir)) {
        New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $srcFull -Destination $dstFull -Force
}

# Copy the agents library flat to agents/ (all 105 .md files; installer decides what goes where)
$agentsSrc = Join-Path $repoRoot '.claude\agents'
$agentsDst = Join-Path $stageDir 'agents'
New-Item -ItemType Directory -Path $agentsDst -Force | Out-Null
$agentFiles = Get-ChildItem -LiteralPath $agentsSrc -Filter '*.md' -File
foreach ($file in $agentFiles) {
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $agentsDst $file.Name) -Force
}
Write-Step "Staged $($agentFiles.Count) agent files to agents\"

# ---------------------------------------------------------------------------
# Preflight: reject staged scripts containing null bytes (U+0000)
#
# A trailing line of null bytes is invisible in most editors and survives
# Copy-Item unchanged, but causes PowerShell to throw CommandNotFoundException
# at the end of every script run — even after a successful execution.
# Catching this here prevents a corrupt release from shipping.
# ---------------------------------------------------------------------------
Write-Step "Checking staged scripts for null bytes"
$scriptFiles = Get-ChildItem -LiteralPath $stageDir -Recurse -File -Include '*.ps1', '*.sh'
$nullByteFiles = @()
foreach ($f in $scriptFiles) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    if ([System.Array]::IndexOf($bytes, [byte]0) -ge 0) {
        $nullByteFiles += $f.FullName.Substring($stageDir.Length).TrimStart('\', '/')
    }
}
if ($nullByteFiles.Count -gt 0) {
    throw "Null bytes (U+0000) found in staged script(s) — fix source files before releasing:`n  $($nullByteFiles -join "`n  ")"
}
Write-Step "OK — no null bytes in $($scriptFiles.Count) staged script(s)"

# ---------------------------------------------------------------------------
# Write version.txt (no BOM, trimmed)
# ---------------------------------------------------------------------------
$versionFile = Join-Path $stageDir 'version.txt'
[System.IO.File]::WriteAllText($versionFile, $Version, [System.Text.UTF8Encoding]::new($false))
Write-Step "Wrote version.txt: $Version"

# ---------------------------------------------------------------------------
# Build ZIP (POSIX paths — forward slashes in entry names)
# ---------------------------------------------------------------------------
# Compress-Archive writes backslash separators on Windows, causing 'unzip'
# warnings on Linux. We use System.IO.Compression.ZipArchive directly and
# normalise every entry name to forward slashes. This is safe on all platforms
# and required for cross-platform install compatibility.
# ---------------------------------------------------------------------------
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Write-Step "Creating ZIP (POSIX paths): $zipPath"

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$zipStream = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
$archive   = New-Object System.IO.Compression.ZipArchive($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem -LiteralPath $stageDir -Recurse -File | ForEach-Object {
        # Strip the stageDir prefix and normalise separators to forward slashes
        $entryName = $_.FullName.Substring($stageDir.Length).TrimStart('\', '/').Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $_.FullName, $entryName,
            [System.IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
    }
} finally {
    $archive.Dispose()
    $zipStream.Dispose()
}

# ---------------------------------------------------------------------------
# Compute SHA256 sidecar
# ---------------------------------------------------------------------------
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLower()
$sidecar = "$hash  $pkgName.zip"
[System.IO.File]::WriteAllText($shaPath, $sidecar, [System.Text.UTF8Encoding]::new($false))
Write-Step "Wrote SHA256 sidecar: $shaPath"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
$zipSize = (Get-Item -LiteralPath $zipPath).Length
$zipSizeKb = [math]::Round($zipSize / 1KB, 1)

Write-Host ""
Write-Host "=== Build summary ===" -ForegroundColor Green
Write-Host "Version   : $Version"
Write-Host "ZIP       : $zipPath"
Write-Host "Size      : $zipSizeKb KB"
Write-Host "SHA256    : $hash"
Write-Host "Sidecar   : $shaPath"
