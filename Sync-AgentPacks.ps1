<#
.SYNOPSIS
    Stage Claude Code Dev Studio domain skills from the library into a target project.

.DESCRIPTION
    Under ADR-0007 the 19 agents (14 <pack>-architect domain agents + 5 core) are
    always-on and installed globally in ~/.claude/agents/. This script no longer copies
    agents -- it stages the per-project, JIT skill layer.

    The library at ~/.claude/playbook/skills/ holds one directory per skill, each with a
    SKILL.md. This script copies the project-scoped domain skills (directories named
    <pack>-*) for the requested packs into a target project's .claude\skills\ directory,
    tracks what it owns via a manifest (.skill-manifest.json), and supports clean
    deactivation by re-running with a smaller pack list or with -Clean.

    Cross-cutting skills (common-*, playbook-conventions, sync-agents, api-design,
    ux-design, security-checklist, code-review-checklist) are GLOBAL (~/.claude/skills)
    and are never staged per project. Selecting by <pack>- prefix naturally excludes them.

    Idempotent. Skills managed by this script are tracked in the manifest; directories not
    in the manifest are left untouched so manual additions are preserved.

.PARAMETER TargetProject
    Absolute path to the project root (the directory that contains or will contain .claude\).

.PARAMETER Packs
    Domain pack prefixes to activate (without trailing hyphen). E.g., 'saas','ai'.
    Valid prefixes: game, saas, mobile, ai, dataplat, ecom, fintech, devtool, desktop,
    ext, embed, media, orch, infra. (No 'common' -- common is cross-cutting/global only.)

.PARAMETER Clean
    Remove all skills staged by a previous sync (per the manifest) and delete the manifest.

.PARAMETER DryRun
    Show what would happen without changing anything.

.PARAMETER WriteAdr
    Append an activation ADR to <TargetProject>\DECISIONS.md.

.PARAMETER LibraryRoot
    Override the library location. Default: %USERPROFILE%\.claude\playbook (set by installer).

.PARAMETER AllowLibraryTarget
    Override the guard that refuses to run when TargetProject resolves to the same
    path as LibraryRoot. Not recommended -- re-running later with a narrower -Packs
    list would remove skills from the library itself based on the manifest created
    in the first run. See DECISIONS.md ADR-0004.

.EXAMPLE
    .\Sync-AgentPacks.ps1 -TargetProject D:\code\acme-saas -Packs saas -WriteAdr

.EXAMPLE
    # Activate more than one pack:
    .\Sync-AgentPacks.ps1 -TargetProject D:\code\app -Packs ai,saas

.EXAMPLE
    # Re-run with a smaller list to deactivate a pack:
    .\Sync-AgentPacks.ps1 -TargetProject D:\code\acme-saas -Packs saas

.EXAMPLE
    # Remove all staged skills:
    .\Sync-AgentPacks.ps1 -TargetProject D:\code\app -Clean

.EXAMPLE
    # Preview only:
    .\Sync-AgentPacks.ps1 -TargetProject D:\code\game -Packs game -DryRun

.NOTES
    Writes BOM-less UTF-8 (manifest + ADR) to satisfy Claude Code's YAML parser
    convention codified in ADR-0001. Canonical rationale: ADR-0004 (mechanism) +
    ADR-0007 (skills model).
#>
[CmdletBinding(DefaultParameterSetName = 'Activate')]
param(
    [Parameter(Mandatory)][string]$TargetProject,
    [Parameter(Mandatory, ParameterSetName = 'Activate')][string[]]$Packs,
    [Parameter(Mandatory, ParameterSetName = 'Clean')][switch]$Clean,
    [switch]$DryRun,
    [switch]$WriteAdr,
    [switch]$NoGates,
    [string]$LibraryRoot = (Join-Path $env:USERPROFILE '.claude\playbook'),
    [switch]$AllowLibraryTarget
)

$ErrorActionPreference = 'Stop'

$SchemaVersion = 3

# --- Gate staging engine (ADR-0013): one python implementation for both twins
$GatesScript  = Join-Path $LibraryRoot 'scripts\stage-gates.py'
$TemplatesDir = Join-Path $LibraryRoot 'templates'
# (no ?? operator: must run on Windows PowerShell 5.1)
$PythonCmd = Get-Command python3 -ErrorAction SilentlyContinue
if (-not $PythonCmd) { $PythonCmd = Get-Command python -ErrorAction SilentlyContinue }
function Test-Gates {
    # python must actually RUN (present-but-broken behaves like absent).
    if (($null -eq $PythonCmd) -or -not (Test-Path -LiteralPath $GatesScript)) { return $false }
    try {
        & $PythonCmd.Source -c "" 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}
function Invoke-Gates {
    param([string[]]$ExtraArgs = @())
    & $PythonCmd.Source $GatesScript --target $TargetProject --templates $TemplatesDir @ExtraArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "gate staging reported a problem (skills staging unaffected)"
    }
}

# --- Validate target existence first (before Join-Path, which fails hard on missing drives)
if (-not (Test-Path -LiteralPath $TargetProject)) { throw "TargetProject does not exist: $TargetProject" }

# --- Paths
$TgtClaude = Join-Path $TargetProject '.claude'
$TgtSkills = Join-Path $TgtClaude 'skills'
$Manifest  = Join-Path $TgtSkills '.skill-manifest.json'

# --- Load existing manifest (managedSkills)
$prev = $null
$prevSet = New-Object 'System.Collections.Generic.HashSet[string]'
if (Test-Path -LiteralPath $Manifest) {
    try {
        $prev = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
        foreach ($n in $prev.managedSkills) { [void]$prevSet.Add($n) }
    } catch {
        Write-Warning "Manifest unreadable; treating as empty: $_"
    }
}

# --- Clean mode -------------------------------------------------------------
if ($Clean) {
    if ($prevSet.Count -eq 0 -and -not (Test-Path -LiteralPath $Manifest)) {
        Write-Host "Nothing to clean (no manifest)."; return
    }
    # Parity with the bash twin (review blocker): a schema-3 manifest records
    # gate files whose safe (hash-checked) removal needs the python engine.
    # Cleaning without it would delete the manifest and orphan those files.
    $prevSchema = 0
    if ($null -ne $prev -and $prev.PSObject.Properties['schema']) {
        $prevSchema = [int]$prev.schema
    }
    if ($prevSchema -ge 3 -and -not (Test-Gates)) {
        throw "This manifest (schema 3+) records staged gate files; cleaning them safely needs python. Install python 3 and re-run -Clean."
    }
    Write-Host ""
    Write-Host "=== Clean plan" -ForegroundColor Cyan
    foreach ($n in ($prevSet | Sort-Object)) { Write-Host ("    - {0}" -f $n) -ForegroundColor Yellow }
    if ($DryRun) {
        if (Test-Gates) { Invoke-Gates -ExtraArgs @('--clean', '--dry-run') }
        Write-Host ""
        Write-Host "DRY RUN - no changes made." -ForegroundColor Magenta
        return
    }
    # Gate clean always runs when the engine is available: -NoGates means
    # "don't STAGE gates", not "leave gate files orphaned on clean".
    if (Test-Gates) { Invoke-Gates -ExtraArgs @('--clean') }
    foreach ($n in $prevSet) {
        $tgt = Join-Path $TgtSkills $n
        if (Test-Path -LiteralPath $tgt) { Remove-Item -LiteralPath $tgt -Recurse -Force }
    }
    if (Test-Path -LiteralPath $Manifest) { Remove-Item -LiteralPath $Manifest -Force }
    Write-Host ("OK Removed {0} staged skills from {1}" -f $prevSet.Count, $TgtSkills) -ForegroundColor Green
    return
}

# --- Library validation (activate path only)
if (-not (Test-Path -LiteralPath $LibraryRoot)) { throw "LibraryRoot does not exist: $LibraryRoot" }
$LibSkills = Join-Path $LibraryRoot 'skills'
if (-not (Test-Path -LiteralPath $LibSkills)) { throw "Library skills folder not found: $LibSkills" }

# --- Self-target guard (ADR-0004)
# Refuse to sync the library onto itself: a later re-run with a narrower -Packs
# list would remove skills from the library based on the manifest created here.
$resolvedTarget  = (Resolve-Path -LiteralPath $TargetProject).Path.TrimEnd('\','/')
$resolvedLibrary = (Resolve-Path -LiteralPath $LibraryRoot).Path.TrimEnd('\','/')
if ($resolvedTarget -ieq $resolvedLibrary) {
    if (-not $AllowLibraryTarget) {
        throw @"
TargetProject resolves to LibraryRoot ($resolvedTarget).
Refusing to sync the library onto itself -- a later re-run with a narrower
-Packs list would delete library skills based on the manifest written here.

If you really need this (e.g., the library IS your working project),
pass -AllowLibraryTarget. Not recommended.
"@
    } else {
        Write-Warning "Self-target override active (-AllowLibraryTarget). Library at '$resolvedLibrary' will be treated as a consumer project."
    }
}

$KnownPrefixes = @(
    'game','saas','mobile','ai','dataplat','ecom','fintech','devtool',
    'desktop','ext','embed','media','orch','infra'
)

$invalid = @($Packs | Where-Object { $_ -notin $KnownPrefixes })
if ($invalid.Count -gt 0) {
    throw "Unknown pack(s): $($invalid -join ', '). Valid: $($KnownPrefixes -join ', ')"
}

# --- Desired set: project-scoped skill dirs for the selected packs
# A library skill is project-scoped if its dir name starts with <pack>- and the pack is
# a valid domain prefix AND it has a SKILL.md. This excludes common-* and the global
# meta skills by design.
$LibDirs = Get-ChildItem -LiteralPath $LibSkills -Directory | Sort-Object Name

$desired = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($d in $LibDirs) {
    if (-not (Test-Path -LiteralPath (Join-Path $d.FullName 'SKILL.md'))) { continue }
    foreach ($p in $Packs) {
        if ($d.Name -like "$p-*") { [void]$desired.Add($d.Name); break }
    }
}

# --- Compute deltas
$toAdd    = @($desired | Where-Object { -not $prevSet.Contains($_) } | Sort-Object)
$toRemove = @($prevSet | Where-Object { -not $desired.Contains($_) } | Sort-Object)
$toKeep   = @($desired | Where-Object {      $prevSet.Contains($_) })

# --- Plan output
Write-Host ""
$header = "=== Sync plan  [Mode=copy$(if ($DryRun) { ', DRY RUN' })]"
Write-Host $header -ForegroundColor Cyan
Write-Host ("Library : {0}" -f $LibSkills)
Write-Host ("Target  : {0}" -f $TgtSkills)
Write-Host ("Packs   : {0}" -f ($Packs -join ', '))
Write-Host ""
Write-Host ("  + Add    : {0}" -f $toAdd.Count)    -ForegroundColor Green
Write-Host ("  - Remove : {0}" -f $toRemove.Count) -ForegroundColor Yellow
Write-Host ("  = Keep   : {0}" -f $toKeep.Count)   -ForegroundColor DarkGray

if ($toAdd.Count    -gt 0) { Write-Host "  Adding:";   $toAdd    | ForEach-Object { Write-Host "    + $_" -ForegroundColor Green  } }
if ($toRemove.Count -gt 0) { Write-Host "  Removing:"; $toRemove | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow } }

if ($DryRun) {
    if (-not $NoGates) {
        if (Test-Gates) { Invoke-Gates -ExtraArgs @('--dry-run') }
        else { Write-Host "gates: skipped (python or templates unavailable)" }
    }
    Write-Host ""
    Write-Host "DRY RUN - no changes made." -ForegroundColor Magenta
    return
}

# --- Ensure target dir
if (-not (Test-Path -LiteralPath $TgtClaude)) { New-Item -ItemType Directory -Path $TgtClaude | Out-Null }
if (-not (Test-Path -LiteralPath $TgtSkills)) { New-Item -ItemType Directory -Path $TgtSkills | Out-Null }

# --- Apply removes (only skill dirs previously managed by this script)
foreach ($n in $toRemove) {
    $tgt = Join-Path $TgtSkills $n
    if (Test-Path -LiteralPath $tgt) { Remove-Item -LiteralPath $tgt -Recurse -Force }
}

# --- Apply adds (copy whole skill directories, recursive)
foreach ($n in $toAdd) {
    $src = Join-Path $LibSkills $n
    $tgt = Join-Path $TgtSkills $n
    if (Test-Path -LiteralPath $tgt) { Remove-Item -LiteralPath $tgt -Recurse -Force }  # replace shadowing copy if present
    Copy-Item -LiteralPath $src -Destination $tgt -Recurse -Force
}

# --- Write manifest (BOM-less UTF-8) — preserve the gate engine's keys
$manifestObj = [ordered]@{
    schema        = $SchemaVersion
    updated       = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.000Z")
    libraryRoot   = $LibraryRoot
    packs         = $Packs
    managedSkills = @($desired | Sort-Object)
}
if ($null -ne $prev) {
    if ($prev.PSObject.Properties['managedGateFiles']) { $manifestObj['managedGateFiles'] = $prev.managedGateFiles }
    if ($prev.PSObject.Properties['gateEdits'])        { $manifestObj['gateEdits']        = $prev.gateEdits }
}
$json = [pscustomobject]$manifestObj | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($Manifest, $json, [System.Text.UTF8Encoding]::new($false))

# --- Gate staging (ADR-0013): Gates 2/3/4, stack-matched, never-destroy
if (-not $NoGates) {
    if (Test-Gates) { Invoke-Gates }
    else { Write-Warning "gates skipped: python or $GatesScript unavailable (skills staged normally)" }
}

Write-Host ""
Write-Host ("OK Sync complete. {0} skills staged; manifest: {1}" -f $desired.Count, $Manifest) -ForegroundColor Green
Write-Host "   (cross-cutting skills are global in ~/.claude/skills; the 19 agents are always-on)" -ForegroundColor DarkGray
Write-Host "   Restart or refresh the session so the new skills are discovered." -ForegroundColor DarkGray

# --- Optional ADR (BOM-less append)
if ($WriteAdr) {
    $decisions = Join-Path $TargetProject 'DECISIONS.md'
    $today     = (Get-Date).ToString('yyyy-MM-dd')
    $packList  = ($Packs | ForEach-Object { "``$_``" }) -join ', '

    $adr = @"

---

## ADR - Activate domain skills ($today)

**Date:** $today
**Status:** Accepted
**Phase:** Initialize

### Context
The 19 always-on agents are present globally; this project needs the domain skills for: $packList.

### Decision
Stage the $packList domain skills into ``.claude\skills\`` (managed by ``Sync-AgentPacks.ps1``; see ``.claude\skills\.skill-manifest.json``).

### Consequences
- $($desired.Count) skill folders staged under ``.claude\skills\``.
- Re-running with a different pack list adds/removes skills per the manifest; ``-Clean`` removes all staged skills.
"@

    $existing = if (Test-Path -LiteralPath $decisions) { [System.IO.File]::ReadAllText($decisions) } else { '' }
    [System.IO.File]::WriteAllText($decisions, $existing + $adr, [System.Text.UTF8Encoding]::new($false))
    Write-Host ("OK ADR appended to {0}" -f $decisions) -ForegroundColor Green
}
