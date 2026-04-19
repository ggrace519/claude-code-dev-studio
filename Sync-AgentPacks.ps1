<#
.SYNOPSIS
    Activate Claude Code agent packs from the dev-studio library into a target project.

.DESCRIPTION
    The dev-studio at C:\coding-projects\claude-code-dev-studio\.claude\agents acts as
    the canonical library of all 105 agents. Most projects only need 1-3 packs.
    This script syncs a subset into a target project's .claude\agents directory, tracks
    what it owns via a manifest (.pack-manifest.json), and supports clean deactivation
    by re-running with a smaller pack list.

    Idempotent. Files managed by this script are tracked in the manifest; files not in
    the manifest are left untouched so manual additions are preserved.

.PARAMETER TargetProject
    Absolute path to the project root (the directory that contains or will contain .claude\).

.PARAMETER Packs
    Pack prefixes to activate (without trailing hyphen). E.g., 'saas','common'.
    Valid prefixes: game, saas, mobile, ai, dataplat, ecom, fintech, devtool, desktop,
    ext, embed, media, orch, infra, common.

.PARAMETER NoGeneralists
    Skip the 7 generalist agents. Default behavior includes them.

.PARAMETER Mode
    Copy   - write file copies (default; portable, no admin needed).
    Symlink - create symbolic links (requires Developer Mode or admin on Windows).

.PARAMETER DryRun
    Show what would happen without changing anything.

.PARAMETER WriteAdr
    Append an activation ADR to <TargetProject>\DECISIONS.md.

.PARAMETER LibraryRoot
    Override the library location. Default: C:\coding-projects\claude-code-dev-studio.

.PARAMETER AllowLibraryTarget
    Override the guard that refuses to run when TargetProject resolves to the same
    path as LibraryRoot. Not recommended — re-running later with a narrower -Packs
    list would remove files from the library itself based on the manifest created
    in the first run. See DECISIONS.md ADR-0004.

.EXAMPLE
    .\Sync-AgentPacks.ps1 -TargetProject D:\code\acme-saas -Packs saas,common -WriteAdr

.EXAMPLE
    # Re-run with a smaller list to deactivate a pack:
    .\Sync-AgentPacks.ps1 -TargetProject D:\code\acme-saas -Packs saas

.EXAMPLE
    # Preview only:
    .\Sync-AgentPacks.ps1 -TargetProject D:\code\game -Packs game,common -DryRun

.NOTES
    Writes BOM-less UTF-8 (manifest + ADR) to satisfy Claude Code's YAML parser
    convention codified in ADR-0001.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TargetProject,
    [Parameter(Mandatory)][string[]]$Packs,
    [switch]$NoGeneralists,
    [ValidateSet('Copy','Symlink')][string]$Mode = 'Copy',
    [switch]$DryRun,
    [switch]$WriteAdr,
    [string]$LibraryRoot = 'C:\coding-projects\claude-code-dev-studio',
    [switch]$AllowLibraryTarget
)

$ErrorActionPreference = 'Stop'

# --- Validate existence first (before Join-Path, which fails hard on missing drives)
if (-not (Test-Path -LiteralPath $TargetProject)) { throw "TargetProject does not exist: $TargetProject" }
if (-not (Test-Path -LiteralPath $LibraryRoot))   { throw "LibraryRoot does not exist: $LibraryRoot" }

# --- Paths
$LibAgents = Join-Path $LibraryRoot '.claude\agents'
$TgtClaude = Join-Path $TargetProject '.claude'
$TgtAgents = Join-Path $TgtClaude 'agents'
$Manifest  = Join-Path $TgtAgents '.pack-manifest.json'

if (-not (Test-Path -LiteralPath $LibAgents)) { throw "Library agents folder not found: $LibAgents" }

# --- Self-target guard (ADR-0004)
# Refuse to sync the library onto itself: a later re-run with a narrower -Packs
# list would remove files from the library based on the manifest created here.
$resolvedTarget  = (Resolve-Path -LiteralPath $TargetProject).Path.TrimEnd('\','/')
$resolvedLibrary = (Resolve-Path -LiteralPath $LibraryRoot).Path.TrimEnd('\','/')
if ($resolvedTarget -ieq $resolvedLibrary) {
    if (-not $AllowLibraryTarget) {
        throw @"
TargetProject resolves to LibraryRoot ($resolvedTarget).
Refusing to sync the library onto itself -- a later re-run with a narrower
-Packs list would delete library files based on the manifest written here.

If you really need this (e.g., the library IS your working project),
pass -AllowLibraryTarget. Not recommended.
"@
    } else {
        Write-Warning "Self-target override active (-AllowLibraryTarget). Library at '$resolvedLibrary' will be treated as a consumer project."
    }
}

$KnownPrefixes = @(
    'game','saas','mobile','ai','dataplat','ecom','fintech','devtool',
    'desktop','ext','embed','media','orch','infra','common'
)

$invalid = @($Packs | Where-Object { $_ -notin $KnownPrefixes })
if ($invalid.Count -gt 0) {
    throw "Unknown pack(s): $($invalid -join ', '). Valid: $($KnownPrefixes -join ', ')"
}

$LibFiles = Get-ChildItem $LibAgents -Filter *.md -File | Sort-Object Name

# Generalists = library files not starting with any known pack prefix
$Generalists = @(
    $LibFiles | Where-Object {
        $base = $_.BaseName
        -not ($KnownPrefixes | Where-Object { $base.StartsWith("$_-") })
    } | ForEach-Object { $_.Name }
)

# --- Compute desired set
$desired = New-Object 'System.Collections.Generic.HashSet[string]'
if (-not $NoGeneralists) { foreach ($g in $Generalists) { [void]$desired.Add($g) } }
foreach ($p in $Packs) {
    $LibFiles | Where-Object { $_.BaseName -like "$p-*" } | ForEach-Object {
        [void]$desired.Add($_.Name)
    }
}

# --- Ensure target dirs (unless dry run)
if (-not $DryRun) {
    if (-not (Test-Path $TgtClaude)) { New-Item -ItemType Directory -Path $TgtClaude | Out-Null }
    if (-not (Test-Path $TgtAgents)) { New-Item -ItemType Directory -Path $TgtAgents | Out-Null }
}

# --- Load existing manifest
$prevSet = New-Object 'System.Collections.Generic.HashSet[string]'
if (Test-Path $Manifest) {
    try {
        $prev = Get-Content $Manifest -Raw | ConvertFrom-Json
        foreach ($f in $prev.managedFiles) { [void]$prevSet.Add($f) }
    } catch {
        Write-Warning "Manifest unreadable; treating as empty: $_"
    }
}

# --- Compute deltas
$toAdd    = @($desired | Where-Object { -not $prevSet.Contains($_) } | Sort-Object)
$toRemove = @($prevSet | Where-Object { -not $desired.Contains($_) } | Sort-Object)
$toKeep   = @($desired | Where-Object {      $prevSet.Contains($_) })

# --- Plan output
Write-Host ""
$header = "=== Sync plan  [Mode=$Mode$(if ($DryRun) { ', DRY RUN' })]"
Write-Host $header -ForegroundColor Cyan
Write-Host ("Library : {0}" -f $LibAgents)
Write-Host ("Target  : {0}" -f $TgtAgents)
Write-Host ("Packs   : {0}{1}" -f ($Packs -join ', '),
                                  $(if ($NoGeneralists) { ' (no generalists)' } else { ' + generalists' }))
Write-Host ""
Write-Host ("  + Add    : {0}" -f $toAdd.Count)    -ForegroundColor Green
Write-Host ("  - Remove : {0}" -f $toRemove.Count) -ForegroundColor Yellow
Write-Host ("  = Keep   : {0}" -f $toKeep.Count)   -ForegroundColor DarkGray

if ($toAdd.Count    -gt 0) { Write-Host "  Adding:";   $toAdd    | ForEach-Object { Write-Host "    + $_" -ForegroundColor Green  } }
if ($toRemove.Count -gt 0) { Write-Host "  Removing:"; $toRemove | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow } }

if ($DryRun) {
    Write-Host ""
    Write-Host "DRY RUN - no changes made." -ForegroundColor Magenta
    return
}

# --- Apply removes (only files previously managed by this script)
foreach ($f in $toRemove) {
    $tgt = Join-Path $TgtAgents $f
    if (Test-Path $tgt) { Remove-Item $tgt -Force }
}

# --- Apply adds
foreach ($f in $toAdd) {
    $src = Join-Path $LibAgents $f
    $tgt = Join-Path $TgtAgents $f
    if (Test-Path $tgt) { Remove-Item $tgt -Force }  # replace shadowing copy if present
    switch ($Mode) {
        'Copy' {
            Copy-Item -Path $src -Destination $tgt -Force
        }
        'Symlink' {
            try {
                New-Item -ItemType SymbolicLink -Path $tgt -Target $src -ErrorAction Stop | Out-Null
            } catch {
                throw "Symlink failed for $f. On Windows, enable Developer Mode (Settings > Privacy & security > For developers) or run elevated. Underlying: $_"
            }
        }
    }
}

# --- Write manifest (BOM-less UTF-8)
$manifestObj = [pscustomobject]@{
    schema       = 1
    updated      = (Get-Date).ToString('o')
    libraryRoot  = $LibraryRoot
    mode         = $Mode
    packs        = $Packs
    generalists  = -not $NoGeneralists
    managedFiles = @($desired | Sort-Object)
}
$json = $manifestObj | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($Manifest, $json, [System.Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host ("OK Sync complete. {0} agents installed; manifest: {1}" -f $desired.Count, $Manifest) -ForegroundColor Green

# --- Optional ADR (BOM-less append)
if ($WriteAdr) {
    $decisions = Join-Path $TargetProject 'DECISIONS.md'
    $today     = (Get-Date).ToString('yyyy-MM-dd')
    $packList  = ($Packs | ForEach-Object { "``$_-``" }) -join ', '
    $genNote   = if ($NoGeneralists) { '' } else { ' (plus generalists)' }

    $adr = @"

---

## ADR - Activate agent packs ($today)

**Date:** $today
**Status:** Accepted
**Phase:** Initialize

### Context
Project requires archetype-specific agent specialists in addition to the seven generalists shipped by the playbook. Library at ``$LibraryRoot`` provides 105 reusable agents; this project does not need all of them.

### Decision
Activate the following packs: $packList$genNote.

Sync mechanism: $Mode (managed by ``Sync-AgentPacks.ps1``; see ``.claude\agents\.pack-manifest.json``).

### Consequences
- $($desired.Count) agent files installed under ``.claude\agents\``.
- Re-running the script with a different pack list adds/removes agents accordingly; files not listed in the manifest are left untouched.
- Library updates are picked up by re-running the sync (Copy mode) or automatically (Symlink mode).
"@

    $existing = if (Test-Path $decisions) { [System.IO.File]::ReadAllText($decisions) } else { '' }
    [System.IO.File]::WriteAllText($decisions, $existing + $adr, [System.Text.UTF8Encoding]::new($false))
    Write-Host ("OK ADR appended to {0}" -f $decisions) -ForegroundColor Green
}
