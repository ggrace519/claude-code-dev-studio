#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Playbook dispatcher — project-level agent pack activation from a global install.

.DESCRIPTION
    Resolves paths (library, scripts, target project) from its own location, then
    delegates to the appropriate underlying script.

    Layout assumed:
      <install-root>\
        bin\claude-playbook.ps1     (this script)
        scripts\Sync-AgentPacks.ps1
        scripts\Verify-Agents.ps1
        library\agents\*.md         (the pack library)
        version.txt

    Dev-repo layout is auto-detected (library at <repo>\.claude\agents,
    scripts at repo root) so the same dispatcher works without installation.

.EXAMPLE
    claude-playbook sync saas,common
    claude-playbook sync saas,ai,common --write-adr
    claude-playbook sync game --dry-run
    claude-playbook verify
    claude-playbook update
    claude-playbook version
    claude-playbook help
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command,

    # NOTE: do NOT type this as [string[]] — PS 5.1/7 join the remaining args
    # into a single space-delimited string when ValueFromRemainingArguments is
    # combined with a typed string-array parameter. Leave untyped so PS
    # delivers @("saas", "common", "--dry-run") rather than "saas common --dry-run".
    [Parameter(ValueFromRemainingArguments = $true)]
    $RemainingArgs
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Resolve install root
# ---------------------------------------------------------------------------
$binDir      = $PSScriptRoot
$installRoot = Split-Path -Parent $binDir

# Detect layout:
#   Installed layout: <root>\scripts\Sync-AgentPacks.ps1 + <root>\library\agents\
#   Dev-repo layout : <root>\Sync-AgentPacks.ps1 + <root>\.claude\agents\
$installedSync = Join-Path $installRoot 'scripts\Sync-AgentPacks.ps1'
$installedLib  = Join-Path $installRoot 'library\agents'
$devSync       = Join-Path $installRoot 'Sync-AgentPacks.ps1'
$devLib        = Join-Path $installRoot '.claude\agents'

if (Test-Path -LiteralPath $installedSync) {
    $syncScript   = $installedSync
    $verifyScript = Join-Path $installRoot 'scripts\Verify-Agents.ps1'
    $libraryRoot  = $installRoot
    $layoutKind   = 'installed'
} elseif (Test-Path -LiteralPath $devSync) {
    $syncScript   = $devSync
    $verifyScript = Join-Path $installRoot 'Verify-Agents.ps1'
    $libraryRoot  = $installRoot   # Sync-AgentPacks.ps1 looks for .\claude\agents under this
    $layoutKind   = 'dev'
} else {
    Write-Error "Cannot locate Sync-AgentPacks.ps1. Checked: $installedSync, $devSync"
    exit 2
}

function Get-InstalledVersion {
    $vFile = Join-Path $installRoot 'version.txt'
    if (Test-Path -LiteralPath $vFile) {
        (Get-Content -LiteralPath $vFile -Raw).Trim()
    } else {
        'dev'
    }
}

function Show-Help {
    @"
claude-playbook -- Claude Code agent pack activator

USAGE
  claude-playbook <command> [arguments]

COMMANDS
  sync <packs>         Activate packs in the current directory (default: apply)
      --dry-run             Preview changes without writing
      --write-adr           Record activation as an ADR in DECISIONS.md
      --no-generalists      Exclude the 7 generalist agents
      --mode <copy|symlink> Sync mode (default: copy)
      --target <path>       Target project path (default: current directory)

  verify               Validate .claude\agents\ in the current directory
      --target <path>       Target path (default: current directory)

  update [tag]         Download and install a release (default: latest stable)
      --rollback            Restore the previous installed version
      --include-prerelease  Pick up release candidates when resolving 'latest'

  uninstall            Remove the installation and PATH entries

  version              Print the installed version

  help                 Show this help

EXAMPLES
  claude-playbook sync saas,common
  claude-playbook sync saas,ai,common --write-adr
  claude-playbook sync game --dry-run
  claude-playbook verify
  claude-playbook --target C:\proj\foo verify

LAYOUT
  Install location : $installRoot
  Layout           : $layoutKind
  Library          : $libraryRoot
  Sync script      : $syncScript
  Verify script    : $verifyScript
  Version          : $(Get-InstalledVersion)
"@
}

# ---------------------------------------------------------------------------
# Argument parsing helpers
# ---------------------------------------------------------------------------
function ConvertTo-Hashtable {
    param([string[]]$Arguments)

    $result = @{
        Positional        = @()
        DryRun            = $false
        WriteAdr          = $false
        NoGeneralists     = $false
        Mode              = 'Copy'
        Target            = $null
        Rollback          = $false
        IncludePrerelease = $false
    }

    $i = 0
    while ($i -lt $Arguments.Count) {
        $a = $Arguments[$i]
        switch -Regex ($a) {
            '^--dry-run$'             { $result.DryRun = $true; $i++; continue }
            '^--write-adr$'           { $result.WriteAdr = $true; $i++; continue }
            '^--no-generalists$'      { $result.NoGeneralists = $true; $i++; continue }
            '^--rollback$'            { $result.Rollback = $true; $i++; continue }
            '^--include-prerelease$'  { $result.IncludePrerelease = $true; $i++; continue }
            '^--mode$' {
                if ($i + 1 -ge $Arguments.Count) { throw "--mode requires a value (copy|symlink)" }
                $result.Mode = $Arguments[$i + 1]
                $i += 2; continue
            }
            '^--target$' {
                if ($i + 1 -ge $Arguments.Count) { throw "--target requires a path" }
                $result.Target = $Arguments[$i + 1]
                $i += 2; continue
            }
            '^--help$|^-h$' {
                Show-Help; exit 0
            }
            '^--' {
                throw "Unknown flag: $a"
            }
            default {
                $result.Positional += $a; $i++
            }
        }
    }

    return $result
}

# ---------------------------------------------------------------------------
# Command: sync
# ---------------------------------------------------------------------------
function Invoke-SyncCommand {
    param([hashtable]$Opts)

    if ($Opts.Positional.Count -lt 1) {
        throw "sync requires a pack list. Example: claude-playbook sync saas,common"
    }

    # Accept packs as a single comma-separated token (saas,common) or as
    # multiple positional tokens (saas common). Join then re-split to normalize.
    # The @(...) wrapper forces array context even when the pipeline yields a scalar.
    $packsCsv  = ($Opts.Positional -join ',')
    $packList  = @($packsCsv -split ',' | Where-Object { $_ -ne '' } | ForEach-Object { $_.Trim() })

    if ($env:CLAUDE_PLAYBOOK_DEBUG) {
        Write-Host "DEBUG Positional count=$($Opts.Positional.Count) items=[$($Opts.Positional -join '|')]" -ForegroundColor Cyan
        Write-Host "DEBUG packsCsv='$packsCsv'" -ForegroundColor Cyan
        Write-Host "DEBUG packList count=$($packList.Count) items=[$($packList -join '|')]" -ForegroundColor Cyan
    }

    $target = if ($Opts.Target) { $Opts.Target } else { (Get-Location).Path }

    # Force [string[]] at the call site so the parameter binder sees a real array
    # even if upstream pipelines returned a scalar.
    & $syncScript `
        -TargetProject $target `
        -Packs         ([string[]]$packList) `
        -LibraryRoot   $libraryRoot `
        -Mode          $Opts.Mode `
        -DryRun:$Opts.DryRun `
        -WriteAdr:$Opts.WriteAdr `
        -NoGeneralists:$Opts.NoGeneralists

    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# Command: verify
# ---------------------------------------------------------------------------
function Invoke-VerifyCommand {
    param([hashtable]$Opts)

    $target = if ($Opts.Target) { $Opts.Target } else { (Get-Location).Path }
    $agentsPath = Join-Path $target '.claude\agents'

    if (-not (Test-Path -LiteralPath $agentsPath)) {
        Write-Error "No .claude\agents\ found under $target"
        exit 2
    }

    & $verifyScript -AgentsPath $agentsPath
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# Command: update / uninstall (delegate to Install-Playbook.ps1 fetched from main)
# ---------------------------------------------------------------------------
$Script:InstallerUrlPs1 = 'https://raw.githubusercontent.com/ggrace519/claude-code-dev-studio/main/Install-Playbook.ps1'

function Get-InstallerTempPath {
    Join-Path $env:TEMP ("Install-Playbook-{0}.ps1" -f [guid]::NewGuid().ToString('N'))
}

function Save-RemoteInstaller {
    param([string]$OutFile)
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $headers = @{ 'User-Agent' = 'claude-playbook-dispatcher' }
    Invoke-WebRequest -Uri $Script:InstallerUrlPs1 -Headers $headers -OutFile $OutFile -UseBasicParsing
}

function Invoke-UpdateCommand {
    param([hashtable]$Opts)

    $installerTmp = Get-InstallerTempPath
    try {
        Write-Host "==> Fetching installer from main" -ForegroundColor Cyan
        Save-RemoteInstaller -OutFile $installerTmp

        $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installerTmp,
                    '-Prefix', $installRoot)

        if ($Opts.Rollback) {
            $psArgs += '-Rollback'
        } else {
            $requestedVersion = if ($Opts.Positional.Count -ge 1) { $Opts.Positional[0] } else { 'latest' }
            $psArgs += @('-Version', $requestedVersion, '-Force')
            if ($Opts.IncludePrerelease) { $psArgs += '-IncludePrerelease' }
        }

        & powershell.exe @psArgs
        $code = $LASTEXITCODE
    } finally {
        if (Test-Path -LiteralPath $installerTmp) {
            Remove-Item -LiteralPath $installerTmp -Force -ErrorAction SilentlyContinue
        }
    }
    exit $code
}

function Invoke-UninstallCommand {
    $installerTmp = Get-InstallerTempPath
    try {
        Write-Host "==> Fetching installer from main" -ForegroundColor Cyan
        Save-RemoteInstaller -OutFile $installerTmp

        $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $installerTmp,
                    '-Prefix', $installRoot, '-Uninstall')

        & powershell.exe @psArgs
        $code = $LASTEXITCODE
    } finally {
        if (Test-Path -LiteralPath $installerTmp) {
            Remove-Item -LiteralPath $installerTmp -Force -ErrorAction SilentlyContinue
        }
    }
    exit $code
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
if (-not $Command -or $Command -in @('help', '-h', '--help')) {
    Show-Help
    exit 0
}

if ($Command -eq 'version' -or $Command -eq '--version') {
    Get-InstalledVersion
    exit 0
}

# Flatten $RemainingArgs. PowerShell command-mode syntax like `saas,common`
# produces an inline array expression. When that arrives at a parameter with
# ValueFromRemainingArguments, PS wraps the sub-array rather than flattening,
# so we receive @(@('saas','common'), '--dry-run') instead of
# @('saas','common','--dry-run'). Any downstream [string[]] cast then turns
# the sub-array into a space-joined string via $OFS. Flatten defensively here.
function Expand-RemainingArgs {
    param($InputArgs)
    $flat = New-Object System.Collections.Generic.List[string]
    foreach ($a in @($InputArgs)) {
        if ($null -eq $a) { continue }
        if ($a -is [System.Collections.IEnumerable] -and -not ($a -is [string])) {
            foreach ($inner in $a) {
                if ($null -ne $inner) { $flat.Add([string]$inner) }
            }
        } else {
            $flat.Add([string]$a)
        }
    }
    return ,$flat.ToArray()
}

try {
    $argList = if ($null -eq $RemainingArgs) { @() } else { Expand-RemainingArgs -InputArgs $RemainingArgs }
    $opts = ConvertTo-Hashtable -Arguments $argList
} catch {
    Write-Error $_
    exit 2
}

switch ($Command) {
    'sync'       { Invoke-SyncCommand -Opts $opts }
    'verify'     { Invoke-VerifyCommand -Opts $opts }
    'update'     { Invoke-UpdateCommand -Opts $opts }
    'uninstall'  { Invoke-UninstallCommand }
    default {
        Write-Error "Unknown command: $Command. Run 'claude-playbook help' for usage."
        exit 2
    }
}
