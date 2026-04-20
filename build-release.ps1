#Requires -Version 5.1
<#
.SYNOPSIS
    Build a Claude Playbook release ZIP + SHA256 sidecar.

.DESCRIPTION
    Stages an installed-layout tree under .\dist\stage\claude-playbook-<version>\,
    zips it to .\dist\claude-playbook-<version>.zip, and writes a matching
    .sha256 sidecar.

    Installed layout (inside the ZIP):
      bin/                 -- dispatcher scripts (claude-playbook.{ps1,sh})
      scripts/             -- Sync-AgentPacks + Verify-Agents (ps1 + sh)
      .claude/agents/      -- 105 agent markdown files (the library)
      CLAUDE.md            -- playbook reference
      README.md            -- installer reference
      version.txt          -- the release version tag

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
    'bin\claude-playbook.ps1'
    'bin\claude-playbook.sh'
    'Sync-AgentPacks.ps1'
    'Verify-Agents.ps1'
    'Sync-AgentPacks.sh'
    'verify-agents.sh'
    'CLAUDE.md'
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
$pkgName  = "claude-playbook-$Version"
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
    @{ Src = 'bin\claude-playbook.ps1' ; Dst = 'bin\claude-playbook.ps1' }
    @{ Src = 'bin\claude-playbook.sh'  ; Dst = 'bin\claude-playbook.sh' }
    @{ Src = 'Sync-AgentPacks.ps1'     ; Dst = 'scripts\Sync-AgentPacks.ps1' }
    @{ Src = 'Verify-Agents.ps1'       ; Dst = 'scripts\Verify-Agents.ps1' }
    @{ Src = 'Sync-AgentPacks.sh'      ; Dst = 'scripts\Sync-AgentPacks.sh' }
    @{ Src = 'verify-agents.sh'        ; Dst = 'scripts\verify-agents.sh' }
    @{ Src = 'CLAUDE.md'               ; Dst = 'CLAUDE.md' }
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

# Copy the agents library (preserve .md files only — skip manifest + any cruft)
$agentsSrc = Join-Path $repoRoot '.claude\agents'
$agentsDst = Join-Path $stageDir '.claude\agents'
New-Item -ItemType Directory -Path $agentsDst -Force | Out-Null
$agentFiles = Get-ChildItem -LiteralPath $agentsSrc -Filter '*.md' -File
foreach ($file in $agentFiles) {
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $agentsDst $file.Name) -Force
}
Write-Step "Copied $($agentFiles.Count) agent files"

# ---------------------------------------------------------------------------
# Write version.txt (no BOM, trimmed)
# ---------------------------------------------------------------------------
$versionFile = Join-Path $stageDir 'version.txt'
[System.IO.File]::WriteAllText($versionFile, $Version, [System.Text.UTF8Encoding]::new($false))
Write-Step "Wrote version.txt: $Version"

# ---------------------------------------------------------------------------
# Build ZIP
# ---------------------------------------------------------------------------
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Write-Step "Creating ZIP: $zipPath"
Compress-Archive -Path (Join-Path $stageDir '*') -DestinationPath $zipPath -Force

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
Write-Host "Agents    : $($agentFiles.Count)"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Inspect: Expand-Archive -Path '$zipPath' -DestinationPath .\dist\verify -Force"
Write-Host "  2. Tag    : git tag $Version && git push origin $Version"
Write-Host "  3. Release: gh release create $Version '$zipPath' '$shaPath' --notes-file CHANGELOG.md"
