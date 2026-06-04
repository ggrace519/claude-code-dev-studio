#Requires -Version 5.1
<#
.SYNOPSIS
    Validate Claude Code agent and skill files under a path against the invariants
    that allow Claude Code to load them successfully.

.DESCRIPTION
    Scans BOTH layouts under the given path (ADR-0007):
      - Flat agents : <name>.md       (expected frontmatter name = file basename)
      - Skills      : <name>/SKILL.md (expected frontmatter name = parent dir name)
    Skill entries are detected by the presence of */SKILL.md.

    Enforces the following per-file rules (see ADR-0001):

    - No UTF-8 BOM (EF BB BF) -- the known silent failure mode
    - Name is lowercase kebab-case: ^[a-z0-9]+(-[a-z0-9]+)*$
    - File begins with a valid YAML frontmatter block (---/--- fences)
    - Frontmatter has required keys 'name' and 'description' (non-empty)
    - Frontmatter 'name' matches the expected name (basename, or skill dir name)
    - No duplicate 'name' values across the corpus

    The frontmatter parser is intentionally simple key:value only -- sufficient
    for Claude Code frontmatter, which has no nested structures.

    Exit codes:
      0 = all files pass
      1 = one or more validation failures
      2 = configuration error (path missing, no files)

.PARAMETER AgentsPath
    Directory to scan. Default: .claude\agents relative to this script.

.PARAMETER Quiet
    Suppress per-file OK lines. Failures and summary are always printed.

.EXAMPLE
    .\Verify-Agents.ps1

.EXAMPLE
    .\Verify-Agents.ps1 -Quiet

.EXAMPLE
    .\Verify-Agents.ps1 -AgentsPath 'D:\code\consumer\.claude\skills'

.NOTES
    Pair with verify-agents.sh (equivalent *nix port). Both are wired into CI.
#>
[CmdletBinding()]
param(
    [string]$AgentsPath,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

if (-not $AgentsPath) {
    $AgentsPath = Join-Path $PSScriptRoot '.claude\agents'
}

if (-not (Test-Path -LiteralPath $AgentsPath)) {
    Write-Error "Agents path not found: $AgentsPath"
    exit 2
}

# Build a list of entries covering both layouts (ADR-0007):
#   - agents : flat <name>.md          (expected frontmatter name = basename)
#   - skills : <name>/SKILL.md         (expected frontmatter name = parent dir)
$entries = @()

# Flat agents directly under the path
Get-ChildItem -LiteralPath $AgentsPath -Filter *.md -File | Sort-Object Name | ForEach-Object {
    $entries += [pscustomobject]@{
        Path     = $_.FullName
        Expected = $_.BaseName
        Display  = $_.Name
    }
}

# Skills: immediate subdirectories that contain a SKILL.md
Get-ChildItem -LiteralPath $AgentsPath -Directory | Sort-Object Name | ForEach-Object {
    $skillFile = Join-Path $_.FullName 'SKILL.md'
    if (Test-Path -LiteralPath $skillFile) {
        $entries += [pscustomobject]@{
            Path     = $skillFile
            Expected = $_.Name
            Display  = "$($_.Name)/SKILL.md"
        }
    }
}

if ($entries.Count -eq 0) {
    Write-Error "No agent (.md) or skill (SKILL.md) files found under $AgentsPath"
    exit 2
}

$seenNames = @{}
$failureCount = 0

foreach ($e in $entries) {
    $fileErrors = @()
    $expectedName = $e.Expected

    # --- Rule 1: name format (lowercase kebab-case)
    if ($expectedName -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
        $fileErrors += "Name must be lowercase kebab-case (matches ^[a-z0-9]+(-[a-z0-9]+)*$)"
    }

    # --- Rule 2: no UTF-8 BOM
    $bytes = [System.IO.File]::ReadAllBytes($e.Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $fileErrors += "UTF-8 BOM detected (EF BB BF) -- breaks Claude Code YAML parser (ADR-0001)"
    }

    # Read as text for frontmatter parsing
    $content = [System.IO.File]::ReadAllText($e.Path)

    # --- Rule 3: YAML frontmatter block present
    $fmMatch = [regex]::Match($content, '^---\s*\r?\n([\s\S]*?)\r?\n---\s*(\r?\n|$)')
    if (-not $fmMatch.Success) {
        $fileErrors += "No valid YAML frontmatter block found (expected ---/--- fences at file start)"
    } else {
        $frontmatterRaw = $fmMatch.Groups[1].Value

        # --- Parse key:value (naive, sufficient for frontmatter)
        $fm = @{}
        foreach ($line in ($frontmatterRaw -split "`n")) {
            $line = $line.TrimEnd("`r")
            if ($line -match '^([a-zA-Z_][a-zA-Z0-9_-]*)\s*:\s*(.*)$') {
                $key = $Matches[1]
                $value = $Matches[2].Trim()
                if ($value -match '^"(.*)"$') { $value = $Matches[1] }
                elseif ($value -match "^'(.*)'$") { $value = $Matches[1] }
                $fm[$key] = $value
            }
        }

        # --- Rule 4: required fields
        if (-not $fm.ContainsKey('name') -or [string]::IsNullOrWhiteSpace($fm['name'])) {
            $fileErrors += "Frontmatter missing or empty required field: name"
        }
        if (-not $fm.ContainsKey('description') -or [string]::IsNullOrWhiteSpace($fm['description'])) {
            $fileErrors += "Frontmatter missing or empty required field: description"
        }

        # --- Rule 5: name matches expected (basename, or skill dir name)
        if ($fm.ContainsKey('name') -and -not [string]::IsNullOrWhiteSpace($fm['name'])) {
            if ($fm['name'] -ne $expectedName) {
                $fileErrors += "Frontmatter name '$($fm['name'])' does not match expected '$expectedName'"
            }

            # --- Rule 6: duplicate name detection
            if ($seenNames.ContainsKey($fm['name'])) {
                $fileErrors += "Duplicate name '$($fm['name'])' also used by: $($seenNames[$fm['name']])"
            } else {
                $seenNames[$fm['name']] = $e.Display
            }
        }
    }

    if ($fileErrors.Count -gt 0) {
        $failureCount += $fileErrors.Count
        Write-Host ("FAIL {0}" -f $e.Display) -ForegroundColor Red
        foreach ($err in $fileErrors) {
            Write-Host ("     - {0}" -f $err) -ForegroundColor Red
        }
    } elseif (-not $Quiet) {
        Write-Host ("OK   {0}" -f $e.Display) -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "=== Verify-Agents summary (agents + skills) ===" -ForegroundColor Cyan
Write-Host ("Files scanned    : {0}" -f $entries.Count)
Write-Host ("Unique names     : {0}" -f $seenNames.Count)
Write-Host ("Failure count    : {0}" -f $failureCount)

if ($failureCount -gt 0) {
    Write-Host "RESULT: FAIL" -ForegroundColor Red
    exit 1
}

Write-Host "RESULT: PASS" -ForegroundColor Green
exit 0
