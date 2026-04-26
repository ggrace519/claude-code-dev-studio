#Requires -Version 5.1
<#
.SYNOPSIS
    Generates catalog.json from all agent .md files in the repository.

.DESCRIPTION
    Scans .claude/agents/ for agent markdown files, extracts name/model/description
    from YAML frontmatter, derives the pack from the filename prefix, and writes
    catalog.json to the specified output path.

    Run as part of build-release.ps1 before packaging.

.PARAMETER AgentsPath
    Path to the agents directory. Defaults to .claude/agents relative to repo root.

.PARAMETER OutputPath
    Path to write catalog.json. Defaults to catalog.json in repo root.

.EXAMPLE
    .\scripts\build-catalog.ps1
    .\scripts\build-catalog.ps1 -AgentsPath ".claude/agents" -OutputPath "catalog.json"
#>
param(
    [string]$AgentsPath = (Join-Path $PSScriptRoot ".." ".claude" "agents"),
    [string]$OutputPath = (Join-Path $PSScriptRoot ".." "catalog.json")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$AgentsPath = [IO.Path]::GetFullPath($AgentsPath)
$OutputPath = [IO.Path]::GetFullPath($OutputPath)

if (-not (Test-Path $AgentsPath)) {
    Write-Error "Agents directory not found: $AgentsPath"
    exit 1
}

$files = Get-ChildItem -Path $AgentsPath -Filter "*.md" | Sort-Object Name
Write-Host "Found $($files.Count) agent files in $AgentsPath"

$catalog = [System.Collections.Generic.List[hashtable]]::new()

$knownGeneralists = @(
    'api-expert','deploy-checklist','plan-architect',
    'pr-code-reviewer','secure-auditor','test-writer-runner','ux-design-critic'
)

foreach ($file in $files) {
    $content  = Get-Content $file.FullName -Raw -Encoding UTF8
    $basename = $file.BaseName

    # Extract YAML frontmatter
    if ($content -notmatch '(?s)^---\s*\n(.+?)\n---') {
        Write-Warning "Skipping $($file.Name): no YAML frontmatter"
        continue
    }
    $fm = $Matches[1]

    $name  = if ($fm -match '(?m)^name:\s*(.+)$')  { $Matches[1].Trim() } else { $basename }
    $model = if ($fm -match '(?m)^model:\s*(.+)$') { $Matches[1].Trim() } else { '' }

    # description: strip indent, escaped newlines, example tags
    $desc = ''
    if ($fm -match '(?s)description:\s*\|?\s*\n((?:  .+\n?)+)') {
        $desc = $Matches[1]
        $desc = ($desc -split '\n' | ForEach-Object { $_ -replace '^  ', '' }) -join ' '
        $desc = $desc -replace '\\n', ' '
        $desc = $desc -replace '(?s)<example>.*?</example>', ''
        $desc = $desc -replace '\s{2,}', ' '
        $desc = $desc.Trim()
    }

    # Derive pack
    $pack = if ($knownGeneralists -contains $basename) {
        'core'
    } elseif ($basename -match '^([^-]+)-') {
        $Matches[1]
    } else {
        'core'
    }

    $catalog.Add([ordered]@{
        name        = $name
        pack        = $pack
        model       = $model
        description = $desc
    })
}

$json = $catalog | ConvertTo-Json -Depth 3
[System.IO.File]::WriteAllText($OutputPath, $json, [System.Text.UTF8Encoding]::new($false))
Write-Host "catalog.json written -> $OutputPath  ($($catalog.Count) entries)"
