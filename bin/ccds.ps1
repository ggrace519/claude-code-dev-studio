#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Code Dev Studio dispatcher — project-level domain skill staging from a global install.

.DESCRIPTION
    Resolves paths (library, scripts, target project) from its own location, then
    delegates to the appropriate underlying script. The 19 always-on agents and the
    cross-cutting skills are installed globally by the installer; 'sync' stages the
    per-pack domain skills into a project's .claude\skills\.

    Layout assumed:
      <install-root>\
        bin\ccds.ps1     (this script)
        scripts\Sync-AgentPacks.ps1
        scripts\Verify-Agents.ps1
        agents\*.md          (the 19 always-on agents)
        skills\<name>\SKILL.md (all skills; domain skills staged per project)
        version.txt

    Dev-repo layout is auto-detected (scripts at repo root) so the same dispatcher
    works without installation.

.EXAMPLE
    ccds sync saas
    ccds sync saas,ai --write-adr
    ccds sync game --dry-run
    ccds sync --clean
    ccds verify
    ccds loop init
    ccds update
    ccds version
    ccds help
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

# Error paths use `Write-Error ... -ErrorAction Continue; exit 2` — under
# ErrorActionPreference='Stop' a bare Write-Error is TERMINATING (script dies
# with exit 1 and the exit 2 is dead code). See #33.
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
    Write-Error "Cannot locate Sync-AgentPacks.ps1. Checked: $installedSync, $devSync" -ErrorAction Continue
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
ccds -- Claude Code Dev Studio

USAGE
  ccds <command> [arguments]

COMMANDS
  sync <packs>         Stage domain skills for the packs into .\.claude\skills\
      --clean               Remove all skills staged by a previous sync
      --dry-run             Preview changes without writing
      --write-adr           Record activation as an ADR in DECISIONS.md
      --target <path>       Target project path (default: current directory)

  verify               Validate global agents and project skills
      --target <path>       Target path (default: current directory)

  lint                 Lint the playbook library's semantic invariants
                       (skill cross-refs, catalog freshness, URL/description
                       conventions). Requires a repo clone (dev layout).

  loop init            Scaffold the long-horizon loop state-file kit into .\.loop\
                       (feature_list.json, progress.md, PROMPT.md, init.sh -- see the
                       loop-long-horizon skill)
      --target <path>       Target project path (default: current directory)
      --dry-run             Preview without writing

  update [tag]         Download and install a release (default: latest stable)
      --rollback            Restore the previous installed version
      --include-prerelease  Pick up release candidates when resolving 'latest'

  uninstall            Remove the installation and PATH entries

  version              Print the installed version

  help                 Show this help

EXAMPLES
  ccds sync saas
  ccds sync saas,ai --write-adr
  ccds sync game --dry-run
  ccds sync --clean
  ccds verify
  ccds loop init

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
        Clean             = $false
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
            '^--clean$'               { $result.Clean = $true; $i++; continue }
            '^--rollback$'            { $result.Rollback = $true; $i++; continue }
            '^--include-prerelease$'  { $result.IncludePrerelease = $true; $i++; continue }
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

    $target = if ($Opts.Target) { $Opts.Target } else { (Get-Location).Path }

    # --clean removes previously-staged skills and ignores any pack list.
    if ($Opts.Clean) {
        & $syncScript `
            -TargetProject $target `
            -LibraryRoot   $libraryRoot `
            -Clean `
            -DryRun:$Opts.DryRun `
            -WriteAdr:$Opts.WriteAdr
        exit $LASTEXITCODE
    }

    if ($Opts.Positional.Count -lt 1) {
        throw "sync requires a pack list (or --clean). Example: ccds sync saas"
    }

    # Accept packs as a single comma-separated token (saas,ai) or as
    # multiple positional tokens (saas ai). Join then re-split to normalize.
    # The @(...) wrapper forces array context even when the pipeline yields a scalar.
    $packsCsv  = ($Opts.Positional -join ',')
    $packList  = @($packsCsv -split ',' | Where-Object { $_ -ne '' } | ForEach-Object { $_.Trim() })

    if ($env:CLAUDE_PLAYBOOK_DEBUG) {
        Write-Host "DEBUG Positional count=$($Opts.Positional.Count) items=[$($Opts.Positional -join '|')]" -ForegroundColor Cyan
        Write-Host "DEBUG packsCsv='$packsCsv'" -ForegroundColor Cyan
        Write-Host "DEBUG packList count=$($packList.Count) items=[$($packList -join '|')]" -ForegroundColor Cyan
    }

    # Force [string[]] at the call site so the parameter binder sees a real array
    # even if upstream pipelines returned a scalar.
    & $syncScript `
        -TargetProject $target `
        -Packs         ([string[]]$packList) `
        -LibraryRoot   $libraryRoot `
        -DryRun:$Opts.DryRun `
        -WriteAdr:$Opts.WriteAdr

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
        Write-Error "No .claude\agents\ found under $target" -ErrorAction Continue
        exit 2
    }

    & $verifyScript -AgentsPath $agentsPath
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# Command: lint
# ---------------------------------------------------------------------------
function Invoke-LintCommand {
    $lintScript = Join-Path $installRoot 'scripts\lint-playbook.py'
    if (-not (Test-Path -LiteralPath $lintScript)) {
        Write-Error "lint-playbook.py not found at $lintScript. 'ccds lint' validates the library source; run it from a repo clone." -ErrorAction Continue
        exit 2
    }
    $python = Get-Command python3 -ErrorAction SilentlyContinue
    if (-not $python) { $python = Get-Command python -ErrorAction SilentlyContinue }
    if (-not $python) {
        Write-Error "python3 is required for lint" -ErrorAction Continue
        exit 2
    }
    & $python.Source $lintScript $installRoot
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------------------
# Command: loop (scaffold the long-horizon loop state-file kit -- loop-long-horizon skill)
# ---------------------------------------------------------------------------
function Write-LoopFile {
    param([string]$Path, [string]$Content)
    # Templates must stay byte-identical to the bash twin (bin/ccds.sh cmd_loop):
    # LF line endings, UTF-8 without BOM (a BOM breaks frontmatter parsing, ADR-0001).
    # Normalize CRLF that autocrlf checkouts can bake into the here-strings, and
    # append the trailing newline the bash heredocs produce.
    $lf = $Content.Replace("`r`n", "`n") + "`n"
    [System.IO.File]::WriteAllText($Path, $lf, [System.Text.UTF8Encoding]::new($false))
}

function Invoke-LoopCommand {
    param([hashtable]$Opts)

    $sub = if ($Opts.Positional.Count -ge 1) { $Opts.Positional[0] } else { '<none>' }
    # -ErrorAction Continue: under $ErrorActionPreference='Stop' a plain Write-Error
    # terminates the script with exit 1 before `exit 2` runs; the bash twin (and the
    # test suite) contract is exit 2 for loop usage/refusal errors.
    if ($sub -ne 'init') {
        Write-Error "unknown loop subcommand '$sub'. Usage: ccds loop init [--target <path>] [--dry-run]" -ErrorAction Continue
        exit 2
    }

    $target  = if ($Opts.Target) { $Opts.Target } else { (Get-Location).Path }
    $loopDir = Join-Path $target '.loop'

    if (Test-Path -LiteralPath $loopDir) {
        Write-Error "$loopDir already exists -- refusing to overwrite an existing kit. Remove or rename it first if you really want to re-init." -ErrorAction Continue
        exit 2
    }
    if ($Opts.DryRun) {
        Write-Host "DRY RUN -- would create $loopDir\ with feature_list.json, progress.md, PROMPT.md, init.sh"
        return
    }

    New-Item -ItemType Directory -Path $loopDir -Force | Out-Null

    # Non-ASCII characters are injected via [char] codes: PowerShell 5.1 reads
    # BOM-less scripts as ANSI, which would mangle literal em-dashes/middle dots
    # in the here-strings (and the repo forbids a BOM, ADR-0001).
    $emDash = [string][char]0x2014   # em dash
    $midDot = [string][char]0x00B7   # middle dot

    $featureListJson = @'
{
  "features": [
    {
      "id": "example-feature",
      "description": "Replace me: one observable behavior, phrased so its absence is detectable",
      "verify": "replace me: the command that proves this feature works",
      "priority": 1,
      "passes": false
    }
  ]
}
'@
    Write-LoopFile -Path (Join-Path $loopDir 'feature_list.json') -Content $featureListJson

    $progressMd = @'
# Loop progress log

Append-only. One entry per iteration, newest last. The "why" line is the one that
stops the next iteration from re-walking this one's dead ends.

<!-- entry template:
## <date> <<MIDDOT>> iteration <n> <<MIDDOT>> <feature-id>
- Done: <what, with the verify evidence>
- Why it took a detour: <the non-obvious part>
- Next: <feature-id or note>
-->
'@
    Write-LoopFile -Path (Join-Path $loopDir 'progress.md') -Content $progressMd.Replace('<<MIDDOT>>', $midDot)

    $promptMd = @'
Work on the project in this directory. THE ONE UNBREAKABLE RULE: exactly ONE
feature this run. Finishing early does not earn a second one.

1. Read .loop/progress.md and .loop/feature_list.json. Run .loop/init.sh;
   if it fails, fixing it is this iteration's ONLY task.
2. Pick the ONE highest-priority feature with "passes": false. That id is
   the only feature you may touch this run. Search the codebase first <<EMDASH>> do
   not re-implement something that exists.
3. Implement it COMPLETELY. No placeholders, no stubs, no simplified
   versions. A stub that compiles is a failure, not progress.
4. Run the feature's verify command and read the output. Only then set
   "passes": true.
5. Append an entry (what / why / next) to .loop/progress.md. Commit with a
   message naming the feature id.
6. STOP. If other features remain "passes": false, do NOT start one <<EMDASH>> not
   even a small one; the loop runs again with fresh context. End your reply
   with exactly: ITERATION DONE
7. Only if EVERY feature now has "passes": true, output exactly:
   ALL FEATURES COMPLETE
'@
    Write-LoopFile -Path (Join-Path $loopDir 'PROMPT.md') -Content $promptMd.Replace('<<EMDASH>>', $emDash)

    $initSh = @'
#!/usr/bin/env bash
# Health check: must prove the project still BUILDS and minimally RUNS.
# Replace the placeholders with this project's real commands.
set -euo pipefail
echo "TODO: replace with this project's build command" >&2
echo "TODO: replace with this project's smoke check (the app actually serves/runs)" >&2
exit 1
'@
    Write-LoopFile -Path (Join-Path $loopDir 'init.sh') -Content $initSh
    # Exec bit: best effort on Unix pwsh only; meaningless on Windows / NTFS mounts.
    if ($PSVersionTable.PSEdition -eq 'Core' -and -not $IsWindows) {
        & chmod +x (Join-Path $loopDir 'init.sh') 2>$null
    }

    $nextSteps = @'
==> Loop kit created in <<LOOPDIR>>

Next steps:
  1. Fill .loop/feature_list.json with every unit of work (all "passes": false).
  2. Make .loop/init.sh actually build + smoke-check this project.
  3. Run the loop, capped -- never unbounded:

     for i in $(seq 1 40); do
       cat .loop/PROMPT.md | claude -p --dangerously-skip-permissions && \
         grep -q '"passes": false' .loop/feature_list.json || break
     done

     or with the ralph-wiggum plugin:
     /ralph-loop "$(cat .loop/PROMPT.md)" --max-iterations 40 --completion-promise "ALL FEATURES COMPLETE"

  Unattended runs belong in a sandbox (container/VM/worktree). See the
  loop-long-horizon skill for the full discipline.
'@
    Write-Host $nextSteps.Replace('<<LOOPDIR>>', $loopDir)
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
    $headers = @{ 'User-Agent' = 'ccds-dispatcher' }
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
    Write-Error $_ -ErrorAction Continue
    exit 2
}

switch ($Command) {
    'sync'       { Invoke-SyncCommand -Opts $opts }
    'verify'     { Invoke-VerifyCommand -Opts $opts }
    'lint'       { Invoke-LintCommand }
    'loop'       { Invoke-LoopCommand -Opts $opts }
    'update'     { Invoke-UpdateCommand -Opts $opts }
    'uninstall'  { Invoke-UninstallCommand }
    default {
        Write-Error "Unknown command: $Command. Run 'ccds help' for usage." -ErrorAction Continue
        exit 2
    }
}
