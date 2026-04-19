#Requires -Version 5.1
<#
.SYNOPSIS
    Validate Claude Code agent files in .claude/agents/ against the invariants
    that allow /agents to load them successfully.

.DESCRIPTION
    Enforces the following per-file rules (see ADR-0001):

    - No UTF-8 BOM (EF BB BF) -- the known silent failure mode
    - Filename is lowercase kebab-case: ^[a-z0-9]+(-[a-z0-9]+)*\.md$
    - File begins with a valid YAML frontmatter block (---/--- fences)
    - Frontmatter has required keys 'name' and 'description' (non-empty)
    - Frontmatter 'name' matches the filename basename
    - No duplicate 'name' values across the corpus

    The frontmatter parser is intentionally simple key:value only -- sufficient
    for Claude Code agent frontmatter, which has no nested structures.

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
    .\Verify-Agents.ps1 -AgentsPath 'D:\code\consumer\.claude\agents'

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

$files = @(Get-ChildItem -LiteralPath $AgentsPath -Filter *.md -File | Sort-Object Name)
if ($files.Count -eq 0) {
    Write-Error "No .md files found under $AgentsPath"
    exit 2
}

$seenNames = @{}
$failureCount = 0

foreach ($f in $files) {
    $fileErrors = @()

    # --- Rule 1: filename format (lowercase kebab-case)
    if ($f.Name -notmatch '^[a-z0-9]+(-[a-z0-9]+)*\.md$') {
        $fileErrors += "Filename must be lowercase kebab-case (matches ^[a-z0-9]+(-[a-z0-9]+)*\.md$)"
    }

    # --- Rule 2: no UTF-8 BOM
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $fileErrors += "UTF-8 BOM detected (EF BB BF) -- breaks Claude Code YAML parser (ADR-0001)"
    }

    # Read as text for frontmatter parsing
    $content = [System.IO.File]::ReadAllText($f.FullName)

    # --- Rule 3: YAML frontmatter block present
    $fmMatch = [regex]::Match($content, '^---\s*\r?\n([\s\S]*?)\r?\n---\s*(\r?\n|$)')
    if (-not $fmMatch.Success) {
        $fileErrors += "No valid YAML frontmatter block found (expected ---/--- fences at file start)"
    } else {
        $frontmatterRaw = $fmMatch.Groups[1].Value

        # --- Parse key:value (naive, sufficient for agent frontmatter)
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

        # --- Rule 5: name matches filename basename
        if ($fm.ContainsKey('name') -and -not [string]::IsNullOrWhiteSpace($fm['name'])) {
            if ($fm['name'] -ne $f.BaseName) {
                $fileErrors += "Frontmatter name '$($fm['name'])' does not match filename basename '$($f.BaseName)'"
            }

            # --- Rule 6: duplicate name detection
            if ($seenNames.ContainsKey($fm['name'])) {
                $fileErrors += "Duplicate agent name '$($fm['name'])' also used by: $($seenNames[$fm['name']])"
            } else {
                $seenNames[$fm['name']] = $f.Name
            }
        }
    }

    if ($fileErrors.Count -gt 0) {
        $failureCount += $fileErrors.Count
        Write-Host ("FAIL {0}" -f $f.Name) -ForegroundColor Red
        foreach ($e in $fileErrors) {
            Write-Host ("     - {0}" -f $e) -ForegroundColor Red
        }
    } elseif (-not $Quiet) {
        Write-Host ("OK   {0}" -f $f.Name) -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "=== Verify-Agents summary ===" -ForegroundColor Cyan
Write-Host ("Files scanned    : {0}" -f $files.Count)
Write-Host ("Unique names     : {0}" -f $seenNames.Count)
Write-Host ("Failure count    : {0}" -f $failureCount)

if ($failureCount -gt 0) {
    Write-Host "RESULT: FAIL" -ForegroundColor Red
    exit 1
}

Write-Host "RESULT: PASS" -ForegroundColor Green
exit 0
