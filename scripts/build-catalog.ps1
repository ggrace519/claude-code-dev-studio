#Requires -Version 5.1
<#
.SYNOPSIS
    Generates catalog.json from agent and skill files (ADR-0007).

.DESCRIPTION
    PowerShell port of scripts/build-catalog.py — produces byte-identical output.

    Indexes two artifact kinds:
      - agents:  .claude/agents/*.md       (kind=agent,  scope=global, always loaded)
      - skills:  skills/<name>/SKILL.md    (kind=skill,  scope=global|project)

    For each file it parses the YAML frontmatter between the first two '---'
    fences (name, model, description), derives pack/kind/scope per the rules
    below, and writes catalog.json (indent 2, UTF-8 WITHOUT BOM, trailing
    newline, non-ASCII like the em dash and arrow preserved as UTF-8).

    Pack rules:
      - Core agents/meta skills  -> "core"
      - common-* names           -> "common"
      - <prefix>-... where prefix is a known domain pack -> that prefix
      - otherwise                -> "core"

    Scope rules:
      - agents                                  -> "global"
      - skills in GLOBAL_META_SKILLS or common-* -> "global"
      - all other skills                         -> "project"

    Run as part of build-release.ps1 before packaging.

.PARAMETER RepoRoot
    Repository root. Defaults to the parent of this script's directory.

.PARAMETER OutputPath
    Path to write catalog.json. Defaults to catalog.json in the repo root.

.EXAMPLE
    .\scripts\build-catalog.ps1
    .\scripts\build-catalog.ps1 -RepoRoot . -OutputPath catalog.json
#>
param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot '..'),
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
if (-not $OutputPath) {
    $OutputPath = Join-Path $RepoRoot 'catalog.json'
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)

$AgentsDir = Join-Path $RepoRoot '.claude/agents'
$SkillsDir = Join-Path $RepoRoot 'skills'

$CoreAgents = @(
    'plan-architect', 'pr-code-reviewer', 'secure-auditor',
    'test-writer-runner', 'deploy-checklist'
)
# skills installed globally (always available), not JIT per project
$GlobalMetaSkills = @(
    'playbook-conventions', 'sync-agents', 'api-design', 'ux-design',
    'security-checklist', 'code-review-checklist'
)
$Packs = @(
    'saas', 'ai', 'infra', 'game', 'mobile', 'dataplat', 'ecom', 'fintech',
    'devtool', 'desktop', 'ext', 'embed', 'media', 'orch'
)

function Get-Frontmatter {
    param([string]$Content)
    if ($Content -match '(?s)^---\s*\n(.*?)\n---') {
        return $Matches[1]
    }
    return $null
}

function Get-Field {
    param([string]$Fm, [string]$Name)
    if ($Fm -match "(?m)^$([regex]::Escape($Name)):\s*(.+)$") {
        return $Matches[1].Trim().Trim('"').Trim("'")
    }
    return ''
}

function Get-Pack {
    param([string]$Name)
    if (($CoreAgents -contains $Name) -or ($GlobalMetaSkills -contains $Name)) {
        return 'core'
    }
    if ($Name.StartsWith('common-')) {
        return 'common'
    }
    $prefix = $Name.Split('-', 2)[0]
    if ($Packs -contains $prefix) {
        return $prefix
    }
    return 'core'
}

$catalog = [System.Collections.Generic.List[object]]::new()

# --- Agents: .claude/agents/*.md (kind=agent, scope=global) ---
if (-not (Test-Path -LiteralPath $AgentsDir)) {
    Write-Error "Agents directory not found: $AgentsDir"
    exit 1
}
$agentFiles = Get-ChildItem -LiteralPath $AgentsDir -Filter '*.md' -File | Sort-Object Name
foreach ($file in $agentFiles) {
    $name = $file.BaseName
    $content = [System.IO.File]::ReadAllText($file.FullName, [System.Text.UTF8Encoding]::new($false))
    $fm = Get-Frontmatter $content
    if ($null -eq $fm) {
        Write-Warning "no frontmatter in agents/$($file.Name)"
        continue
    }
    $fieldName = Get-Field $fm 'name'
    $catalog.Add([ordered]@{
        name        = if ($fieldName) { $fieldName } else { $name }
        pack        = Get-Pack $name
        kind        = 'agent'
        scope       = 'global'
        model       = Get-Field $fm 'model'
        description = Get-Field $fm 'description'
    })
}

# --- Skills: skills/<name>/SKILL.md (kind=skill, scope=global|project) ---
if (Test-Path -LiteralPath $SkillsDir) {
    $skillDirs = Get-ChildItem -LiteralPath $SkillsDir -Directory | Sort-Object Name
    foreach ($dir in $skillDirs) {
        $name = $dir.Name
        $skillPath = Join-Path $dir.FullName 'SKILL.md'
        if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
            continue
        }
        $content = [System.IO.File]::ReadAllText($skillPath, [System.Text.UTF8Encoding]::new($false))
        $fm = Get-Frontmatter $content
        if ($null -eq $fm) {
            Write-Warning "no frontmatter in skills/$name/SKILL.md"
            continue
        }
        $scope = if (($GlobalMetaSkills -contains $name) -or $name.StartsWith('common-')) {
            'global'
        } else {
            'project'
        }
        $fieldName = Get-Field $fm 'name'
        $catalog.Add([ordered]@{
            name        = if ($fieldName) { $fieldName } else { $name }
            pack        = Get-Pack $name
            kind        = 'skill'
            scope       = $scope
            model       = ''
            description = Get-Field $fm 'description'
        })
    }
}

# ---------------------------------------------------------------------------
# Serialize to JSON matching python's json.dump(indent=2, ensure_ascii=False).
#
# PowerShell's ConvertTo-Json differs from python in several ways (escaping,
# empty-array/object rendering, unicode escaping). To guarantee byte-identical
# output we emit the JSON manually with the exact same formatting as
# json.dump(indent=2, ensure_ascii=False): 2-space indent, ": " separators,
# "," item separators, and only the standard JSON string escapes.
# ---------------------------------------------------------------------------
function ConvertTo-JsonString {
    param([string]$Value)
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('"')
    foreach ($ch in $Value.ToCharArray()) {
        $code = [int]$ch
        switch ($ch) {
            '"'  { [void]$sb.Append('\"') }
            '\'  { [void]$sb.Append('\\') }
            "`b" { [void]$sb.Append('\b') }
            "`f" { [void]$sb.Append('\f') }
            "`n" { [void]$sb.Append('\n') }
            "`r" { [void]$sb.Append('\r') }
            "`t" { [void]$sb.Append('\t') }
            default {
                if ($code -lt 0x20) {
                    [void]$sb.Append(('\u{0:x4}' -f $code))
                } else {
                    # ensure_ascii=False: emit the character as-is (UTF-8 on write)
                    [void]$sb.Append($ch)
                }
            }
        }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

$order = @('name', 'pack', 'kind', 'scope', 'model', 'description')
$lines = [System.Collections.Generic.List[string]]::new()
if ($catalog.Count -eq 0) {
    $jsonText = "[]`n"
} else {
    $lines.Add('[')
    for ($i = 0; $i -lt $catalog.Count; $i++) {
        $entry = $catalog[$i]
        $lines.Add('  {')
        for ($k = 0; $k -lt $order.Count; $k++) {
            $key = $order[$k]
            $val = ConvertTo-JsonString ([string]$entry[$key])
            $comma = if ($k -lt $order.Count - 1) { ',' } else { '' }
            $lines.Add("    `"$key`": $val$comma")
        }
        $objComma = if ($i -lt $catalog.Count - 1) { ',' } else { '' }
        $lines.Add("  }$objComma")
    }
    $lines.Add(']')
    # json.dump uses "\n" newlines; add a trailing newline like the python script.
    $jsonText = ($lines -join "`n") + "`n"
}

[System.IO.File]::WriteAllText($OutputPath, $jsonText, [System.Text.UTF8Encoding]::new($false))

$nAgents = ($catalog | Where-Object { $_['kind'] -eq 'agent' }).Count
$nSkills = ($catalog | Where-Object { $_['kind'] -eq 'skill' }).Count
Write-Host "catalog.json -> $OutputPath  ($nAgents agents + $nSkills skills = $($catalog.Count) entries)"
