#Requires -Version 5.1
<#
.SYNOPSIS
    DEPRECATED — thin wrapper that forwards to Sync-AgentPacks.ps1 with -Packs saas.

.DESCRIPTION
    install-agents.ps1 was the original single-pack installer for the SaaS archetype
    (6 agents written with content embedded inline). It has been superseded by
    Sync-AgentPacks.ps1, which is the canonical activation mechanism for all 15
    packs (see ADR-0004).

    This wrapper is retained for backward compatibility. It preserves the original
    parameter shape ($ProjectRoot, $DryRun) and forwards to the new script. It will
    be removed in a future revision.

    New callers should use:
        .\Sync-AgentPacks.ps1 -TargetProject <path> -Packs saas[,common,...]

.PARAMETER ProjectRoot
    Path to the Claude Code project root. Defaults to current directory.
    Forwarded as -TargetProject to Sync-AgentPacks.ps1.

.PARAMETER DryRun
    Show what would be written without writing. Forwarded as-is.

.EXAMPLE
    PS> .\install-agents.ps1
    # Equivalent to: .\Sync-AgentPacks.ps1 -TargetProject (pwd) -Packs saas

.EXAMPLE
    PS> .\install-agents.ps1 -DryRun
    # Equivalent to: .\Sync-AgentPacks.ps1 -TargetProject (pwd) -Packs saas -DryRun

.NOTES
    Deprecated in Session 7 (2026-04-19). See DECISIONS.md ADR-0004.
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot = (Get-Location).Path,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Write-Warning @"
install-agents.ps1 is DEPRECATED. Use Sync-AgentPacks.ps1 instead:

    .\Sync-AgentPacks.ps1 -TargetProject '$ProjectRoot' -Packs saas$(if ($DryRun) { ' -DryRun' })

This wrapper forwards the call and will be removed in a future revision.
See DECISIONS.md (ADR-0004) for the rationale.
"@

$syncScript = Join-Path $PSScriptRoot 'Sync-AgentPacks.ps1'
if (-not (Test-Path $syncScript)) {
    throw "Canonical installer not found: $syncScript. Cannot forward."
}

$forwardArgs = @{
    TargetProject = $ProjectRoot
    Packs         = @('saas')
}
if ($DryRun) { $forwardArgs['DryRun'] = $true }

& $syncScript @forwardArgs
