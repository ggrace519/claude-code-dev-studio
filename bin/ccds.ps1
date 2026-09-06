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
    ccds doctor
    ccds setup
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
                       and quality/security gates (settings deny rules,
                       CLAUDE.md standards, pre-commit, CI) stack-matched to
                       the project (ADR-0013)
      --clean               Remove staged skills + unmodified ccds-created gate files
      --no-gates            Skip gate staging (skills only)
      --dry-run             Preview changes without writing
      --write-adr           Record activation as an ADR in DECISIONS.md
      --target <path>       Target project path (default: current directory)

  verify               Validate global agents and project skills
      --target <path>       Target path (default: current directory)

  doctor               Run proactive environment health checks: layout shape,
                       version drift vs the latest release, install
                       completeness (agents, skills, CLAUDE.md block, catalog),
                       BOM/CRLF corruption, PATH and dual-install conflicts,
                       Claude Code version floor, and whether the ccds-guard /
                       ccds-loops enforcement plugins are installed + enabled.
                       Exit 0 = healthy (WARNs allowed), 1 = failures found.

  setup                Install the always-on agents + cross-cutting skills into
                       %USERPROFILE%\.claude\, inject the CLAUDE.md block, and
                       install the ccds-guard + ccds-loops enforcement plugins
                       (ADR-0016)
      --dry-run             Preview without writing
      --skip-plugins        Skip the enforcement-plugin install

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
  ccds doctor
  ccds setup
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
        NoGates           = $false
        SkipPlugins       = $false
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
            '^--no-gates$'            { $result.NoGates = $true; $i++; continue }
            '^--skip-plugins$'        { $result.SkipPlugins = $true; $i++; continue }
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
# Twin of bin/ccds.sh needs_user_setup / run_user_setup_if_needed. Without
# this, a Windows user who only ever ran `ccds sync` never got per-user setup
# at all -- and after ADR-0016 that also means never got the enforcement
# plugins, while the bash user did. Same outlet, same result.
function Test-NeedsUserSetup {
    $claudeHome = Join-Path $env:USERPROFILE '.claude'
    if (-not (Test-Path -LiteralPath (Join-Path $claudeHome 'agents\plan-architect.md'))) { return $true }
    $claudeMd = Join-Path $claudeHome 'CLAUDE.md'
    if (-not (Test-Path -LiteralPath $claudeMd)) { return $true }
    if (-not (Select-String -LiteralPath $claudeMd -SimpleMatch '# >>> ccds >>>' -Quiet)) { return $true }
    return $false
}

function Invoke-UserSetupIfNeeded {
    param([hashtable]$Opts)
    if (Test-NeedsUserSetup) {
        Write-Host "==> First run: performing per-user setup..." -ForegroundColor Cyan
        Invoke-SetupCommand -Opts $Opts
        Write-Host ""
    }
}

function Invoke-SyncCommand {
    param([hashtable]$Opts)

    Invoke-UserSetupIfNeeded -Opts $Opts

    $target = if ($Opts.Target) { $Opts.Target } else { (Get-Location).Path }

    # --clean removes previously-staged skills and ignores any pack list.
    if ($Opts.Clean) {
        & $syncScript `
            -TargetProject $target `
            -LibraryRoot   $libraryRoot `
            -Clean `
            -DryRun:$Opts.DryRun `
            -WriteAdr:$Opts.WriteAdr `
            -NoGates:$Opts.NoGates
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
        -WriteAdr:$Opts.WriteAdr `
        -NoGates:$Opts.NoGates

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
# Shared: authoritative cross-cutting (global) skill list, extracted at RUNTIME
# from whichever installer source is present -- never a third hardcoded copy
# that can drift. Dev layout ships Install-Playbook.ps1 at the repo root;
# installed/packaged layouts ship scripts\ccds-user-setup.sh.
# Returns $null when neither source parses.
# ---------------------------------------------------------------------------
function Get-GlobalSkillList {
    # Source 1: Install-Playbook.ps1 ($Script:GlobalSkills = @( ... ))
    $ps1Src = Join-Path $installRoot 'Install-Playbook.ps1'
    if (Test-Path -LiteralPath $ps1Src) {
        try {
            $text = [System.IO.File]::ReadAllText($ps1Src)
            $m = [regex]::Match($text, '\$Script:GlobalSkills\s*=\s*@\(([^)]*)\)')
            if ($m.Success) {
                $names = @($m.Groups[1].Value -split "`n" | ForEach-Object {
                    ($_ -replace '#.*$', '').Trim().Trim("'").Trim('"')
                } | Where-Object { $_ -match '^[a-z0-9-]+$' })
                if ($names.Count -gt 0) {
                    return @{ Names = $names; Source = 'Install-Playbook.ps1' }
                }
            }
        } catch { }
    }
    # Source 2: scripts\ccds-user-setup.sh (GLOBAL_SKILLS=( ... ))
    $shSrc = Join-Path $installRoot 'scripts\ccds-user-setup.sh'
    if (Test-Path -LiteralPath $shSrc) {
        try {
            $text = [System.IO.File]::ReadAllText($shSrc)
            $m = [regex]::Match($text, 'GLOBAL_SKILLS=\(([^)]*)\)')
            if ($m.Success) {
                $names = @($m.Groups[1].Value -split "`n" | ForEach-Object {
                    ($_ -replace '#.*$', '').Trim()
                } | Where-Object { $_ -match '^[a-z0-9-]+$' })
                if ($names.Count -gt 0) {
                    return @{ Names = $names; Source = 'scripts\ccds-user-setup.sh' }
                }
            }
        } catch { }
    }
    return $null
}

# ---------------------------------------------------------------------------
# Command: setup (per-user install: agents + global skills + CLAUDE.md block).
# PowerShell twin of scripts/ccds-user-setup.sh -- same three steps, same
# BOM-less UTF-8 writes (ADR-0001).
# ---------------------------------------------------------------------------
function Invoke-SetupCommand {
    param([hashtable]$Opts)

    $claudeHome  = Join-Path $env:USERPROFILE '.claude'
    $agentsSrc   = Join-Path $installRoot 'agents'
    $skillsSrc   = Join-Path $installRoot 'skills'
    $jitSrc      = Join-Path $installRoot 'scripts\jit-claude.md'
    $agentsDst   = Join-Path $claudeHome 'agents'
    $skillsDst   = Join-Path $claudeHome 'skills'
    $claudeMd    = Join-Path $claudeHome 'CLAUDE.md'

    # Step 0 -- which route supplies the always-on roster? (ADR-0020) The
    # roster reaches Claude Code by the ccds content plugins OR by the file
    # copies below, never both: both at once loads every agent twice. Read-only
    # probe; skipped under -SkipPlugins (never touch the CLI) and -DryRun.
    $contentPlugins = @()
    if (-not $Opts.SkipPlugins -and -not $Opts.DryRun) {
        Resolve-ContentPlugins
        if ($Script:ContentPluginsKnown) { $contentPlugins = @($Script:ContentPlugins) }
    }
    $srcAgents = @()
    if (Test-Path -LiteralPath $agentsSrc) {
        $srcAgents = @(Get-ChildItem -LiteralPath $agentsSrc -Filter *.md -File -ErrorAction SilentlyContinue)
    }
    $skillList = Get-GlobalSkillList
    if ($contentPlugins.Count -gt 0) {
        Write-Host "==> Always-on agents and cross-cutting skills" -ForegroundColor Cyan
        Write-Host "OK  Supplied by enabled plugin(s): $($contentPlugins -join ' ') -- skipping the file copies so Claude Code does not load the roster twice" -ForegroundColor Green
        # Stale copies next to enabled plugins: name them with the exact
        # removal command, but never delete a user's files from setup.
        $staleAgents = @($srcAgents | Where-Object { Test-Path -LiteralPath (Join-Path $agentsDst $_.Name) } | ForEach-Object { $_.Name })
        $staleSkills = @()
        if ($skillList) {
            $staleSkills = @($skillList.Names | Where-Object { Test-Path -LiteralPath (Join-Path $skillsDst "$_\SKILL.md") })
        }
        if ($staleAgents.Count -gt 0 -or $staleSkills.Count -gt 0) {
            Write-Host "!!  File copies from an earlier setup are still present and are loaded in ADDITION to the plugins:" -ForegroundColor Yellow
            Write-Host "!!    $($staleAgents.Count) agent file(s) in $agentsDst, $($staleSkills.Count) cross-cutting skill(s) in $skillsDst" -ForegroundColor Yellow
            Write-Host "!!  Remove them (the plugins keep working):" -ForegroundColor Yellow
            if ($staleAgents.Count -gt 0) {
                Write-Host ("!!    Remove-Item -Force " + (($staleAgents | ForEach-Object { "'" + (Join-Path $agentsDst $_) + "'" }) -join ', ')) -ForegroundColor Yellow
            }
            if ($staleSkills.Count -gt 0) {
                Write-Host ("!!    Remove-Item -Recurse -Force " + (($staleSkills | ForEach-Object { "'" + (Join-Path $skillsDst $_) + "'" }) -join ', ')) -ForegroundColor Yellow
            }
        }
    } else {
    # Step 1 -- always-on agents
    Write-Host "==> Installing always-on agents to $agentsDst" -ForegroundColor Cyan
    if ($Opts.DryRun) {
        Write-Host "    DRY RUN -- would copy $($srcAgents.Count) always-on agents to $agentsDst"
    } else {
        if (-not (Test-Path -LiteralPath $agentsDst)) {
            New-Item -ItemType Directory -Path $agentsDst -Force | Out-Null
        }
        $copied = 0
        foreach ($f in $srcAgents) {
            Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $agentsDst $f.Name) -Force
            $copied++
        }
        Write-Host "OK  Copied $copied always-on agents to $agentsDst" -ForegroundColor Green
    }

    # Step 2 -- cross-cutting (global) skills
    Write-Host "==> Installing cross-cutting skills to $skillsDst" -ForegroundColor Cyan
    if (-not $skillList) {
        Write-Error "cannot determine the global skill list (no parsable Install-Playbook.ps1 or scripts\ccds-user-setup.sh under $installRoot)" -ErrorAction Continue
        exit 2
    }
    if ($Opts.DryRun) {
        Write-Host "    DRY RUN -- would copy $($skillList.Names.Count) cross-cutting skills to $skillsDst (list from $($skillList.Source))"
    } else {
        if (-not (Test-Path -LiteralPath $skillsDst)) {
            New-Item -ItemType Directory -Path $skillsDst -Force | Out-Null
        }
        $copied = 0
        foreach ($name in $skillList.Names) {
            $src     = Join-Path $skillsSrc $name
            $skillMd = Join-Path $src 'SKILL.md'
            if ((Test-Path -LiteralPath $src) -and (Test-Path -LiteralPath $skillMd)) {
                $dst = Join-Path $skillsDst $name
                if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
                Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
                $copied++
            } else {
                Write-Host "!!  Global skill not found in package: skills\$name\SKILL.md" -ForegroundColor Yellow
            }
        }
        Write-Host "OK  Copied $copied/$($skillList.Names.Count) cross-cutting skills to $skillsDst" -ForegroundColor Green
    }
    } # end file route (Step 0 gate)

    # Step 3 -- ccds pointer block in ~/.claude/CLAUDE.md (idempotent)
    Write-Host "==> Updating ccds block in $claudeMd" -ForegroundColor Cyan
    if (-not (Test-Path -LiteralPath $jitSrc)) {
        Write-Host "!!  jit-claude.md not found at $jitSrc -- skipping CLAUDE.md injection" -ForegroundColor Yellow
    } elseif ($Opts.DryRun) {
        # No early return: Step 4 must still report what it *would* do, and the
        # single "DRY RUN -- no changes made." line is printed at the end.
        Write-Host "    DRY RUN -- would inject/update ccds block in $claudeMd"
    } else {
        if (-not (Test-Path -LiteralPath $claudeHome)) {
            New-Item -ItemType Directory -Path $claudeHome -Force | Out-Null
        }
        $existing = ''
        if (Test-Path -LiteralPath $claudeMd) {
            $existing = [System.IO.File]::ReadAllText($claudeMd, [System.Text.Encoding]::UTF8)
            $stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
            Copy-Item -LiteralPath $claudeMd -Destination "$claudeMd.ccds-backup-$stamp" -Force
            Write-Host "    Backed up existing CLAUDE.md to CLAUDE.md.ccds-backup-$stamp"
        }
        $blockContent = ([System.IO.File]::ReadAllText($jitSrc, [System.Text.Encoding]::UTF8)).TrimEnd("`r", "`n")
        $markerStart  = '# >>> ccds >>>'
        $markerEnd    = '# <<< ccds <<<'
        # Strip ALL existing ccds blocks (duplicates from prior buggy installs,
        # trailing whitespace on marker lines) -- same contract as the bash twin.
        $stripPattern = "(?s)\r?\n?[ \t]*$([regex]::Escape($markerStart))[ \t\r]*\r?\n.*?[ \t]*$([regex]::Escape($markerEnd))[ \t\r]*\r?\n?"
        $cleaned = ([regex]::Replace($existing, $stripPattern, '')).TrimEnd("`r", "`n")
        if ($cleaned -match '##\s+Playbook JIT Agent Loading') {
            Write-Host "!!  Detected legacy 'Playbook JIT Agent Loading' content outside markers -- inspect $claudeMd." -ForegroundColor Yellow
        }
        if ($cleaned.Length -gt 0) {
            $updated = $cleaned + "`n`n" + $blockContent + "`n"
        } else {
            $updated = $blockContent + "`n"
        }
        [System.IO.File]::WriteAllText($claudeMd, $updated, [System.Text.UTF8Encoding]::new($false))
        Write-Host "OK  Refreshed ccds block in $claudeMd" -ForegroundColor Green
    }

    # Step 4 -- enforcement plugins (ADR-0016). Twin of ccds-user-setup.sh
    # install_plugins: plugins are the only hook-shipping mechanism, so every
    # outlet installs them. Best-effort; never fails setup.
    $pluginStatus = 'skipped (-SkipPlugins)'
    if (-not $Opts.SkipPlugins) {
        $marketplace = if ($env:CCDS_MARKETPLACE_SOURCE) { $env:CCDS_MARKETPLACE_SOURCE }
                       else { 'ggrace519/claude-code-dev-studio' }
        $claudeCmd   = if ($env:CCDS_CLAUDE_CMD) { $env:CCDS_CLAUDE_CMD } else { 'claude' }
        $plugins     = @('ccds-guard', 'ccds-loops')
        Write-Host "==> Installing enforcement plugins ($($plugins -join ', '))" -ForegroundColor Cyan
        if ($Opts.DryRun) {
            $pluginStatus = 'dry run'
            Write-Host "    DRY RUN -- would run:"
            Write-Host "      $claudeCmd plugin marketplace add $marketplace"
            foreach ($p in $plugins) {
                Write-Host "      $claudeCmd plugin install $p@ccds --scope user"
            }
        } elseif (-not (Get-Command $claudeCmd -ErrorAction SilentlyContinue)) {
            $pluginStatus = 'skipped (claude CLI not on PATH)'
            Write-Host "!!  claude CLI not found -- skipping plugin install." -ForegroundColor Yellow
            Write-Host "!!  Without these, this install has no security guard and no loop" -ForegroundColor Yellow
            Write-Host "!!  enforcement. After installing Claude Code, run:" -ForegroundColor Yellow
            Write-Host "!!    claude plugin marketplace add $marketplace" -ForegroundColor Yellow
            foreach ($p in $plugins) {
                Write-Host "!!    claude plugin install $p@ccds --scope user" -ForegroundColor Yellow
            }
        } else {
            # `marketplace add` fails when already registered, and that
            # registration may predate a plugin -- refresh instead of assuming.
            & $claudeCmd plugin marketplace add $marketplace 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "    marketplace 'ccds' already registered; refreshing catalog"
                & $claudeCmd plugin marketplace update ccds 2>$null | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "!!  could not refresh marketplace 'ccds'; plugin installs may see a stale catalog" -ForegroundColor Yellow
                }
            }
            $pluginStatus = "installed ($($plugins -join ', '))"
            foreach ($p in $plugins) {
                & $claudeCmd plugin install "$p@ccds" --scope user 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "OK  $p plugin installed (user scope)" -ForegroundColor Green
                } else {
                    $pluginStatus = 'partial -- see warnings'
                    Write-Host "!!  Could not install $p automatically. Run:" -ForegroundColor Yellow
                    Write-Host "!!    claude plugin install $p@ccds --scope user" -ForegroundColor Yellow
                }
            }
        }
    }

    if ($Opts.DryRun) {
        Write-Host ""
        Write-Host "DRY RUN -- no changes made." -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host "User setup complete." -ForegroundColor Green
        if ($contentPlugins.Count -gt 0) {
            Write-Host "Agents      : from plugins ($($contentPlugins -join ' '))"
            Write-Host "Skills      : from plugins ($($contentPlugins -join ' '))"
        } else {
            Write-Host "Agents      : $agentsDst (19 always-on)"
            Write-Host "Skills      : $skillsDst ($(if ($skillList) { $skillList.Names.Count } else { '?' }) cross-cutting)"
        }
        Write-Host "Plugins     : $pluginStatus"
    }
}

# ---------------------------------------------------------------------------
# Command: doctor -- proactive environment health checks.
# PowerShell twin of bin/ccds.sh cmd_doctor: same 12 checks, same output
# contract (one 'OK|WARN|FAIL  name: detail' line per check + indented remedy
# on WARN/FAIL, summary block, exit 0 = no FAIL / 1 = FAIL found).
#
# CCDS_DOCTOR_RELEASE_URL is a TEST-ONLY override for the GitHub
# latest-release endpoint, so tests can force the offline path
# deterministically. Do not set it in normal use.
#
# All error paths are non-terminating (-ErrorAction Continue / try-catch):
# under $ErrorActionPreference='Stop' a bare cmdlet error would kill the run
# with exit 1 mid-checks (see #33/#36).
# ---------------------------------------------------------------------------
$Script:DocOk = 0; $Script:DocWarn = 0; $Script:DocFail = 0

function Write-DoctorLine {
    param([string]$Status, [string]$Name, [string]$Detail, [string]$Remedy = '')
    Write-Host ('{0}  {1}: {2}' -f $Status, $Name, $Detail)
    switch ($Status) {
        'OK'   { $Script:DocOk++ }
        'WARN' { $Script:DocWarn++ }
        'FAIL' { $Script:DocFail++ }
        default {
            Write-Error "Write-DoctorLine: unknown status '$Status'" -ErrorAction Continue
            exit 2
        }
    }
    if ($Status -ne 'OK' -and $Remedy) {
        Write-Host "      remedy: $Remedy"
    }
}

function Test-DoctorLayout {
    if ($layoutKind -eq 'dev') {
        Write-DoctorLine WARN 'layout' `
            "dev (repo clone at $installRoot); 'ccds setup' expects the packaged shape (<root>\agents, <root>\skills) -- this repo keeps agents in .claude\agents" `
            "stage a release first (build-release.ps1) or install via Install-Playbook.ps1, then run 'ccds setup' from that tree"
    } else {
        Write-DoctorLine OK 'layout' "$layoutKind ($installRoot)"
    }
}

function Test-DoctorVersion {
    $installed = Get-InstalledVersion
    $url = if ($env:CCDS_DOCTOR_RELEASE_URL) { $env:CCDS_DOCTOR_RELEASE_URL }
           else { 'https://api.github.com/repos/ggrace519/claude-code-dev-studio/releases/latest' }

    $body = $null
    try {
        [Net.ServicePointManager]::SecurityProtocol = `
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $resp = Invoke-WebRequest -Uri $url -Headers @{ 'User-Agent' = 'ccds-doctor' } `
                    -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
        $body = $resp.Content
    } catch {
        Write-DoctorLine WARN 'version' `
            "installed $installed; could not check latest release (offline, timeout, or rate-limited)" `
            'retry with network access, or check https://github.com/ggrace519/claude-code-dev-studio/releases'
        return
    }

    $latest = $null
    try { $latest = (ConvertFrom-Json $body).tag_name } catch { }
    if (-not $latest) {
        Write-DoctorLine WARN 'version' `
            "installed $installed; could not parse latest release tag from $url" `
            'check https://github.com/ggrace519/claude-code-dev-studio/releases'
        return
    }

    $vi = "$installed" -replace '^v', ''
    $vl = "$latest" -replace '^v', ''
    if ($installed -eq 'dev') {
        Write-DoctorLine OK 'version' "dev (repo clone; latest release is $latest)"
        return
    }
    if ($vi -eq $vl) {
        Write-DoctorLine OK 'version' "$installed (up to date with latest release $latest)"
        return
    }
    # Compare numeric prefixes (0.10.1, 0.11.0-rc1 -> 0.11.0). If either side
    # refuses to parse, degrade to a WARN rather than guessing an order.
    $pi = [regex]::Match($vi, '^\d+(\.\d+)+').Value
    $pl = [regex]::Match($vl, '^\d+(\.\d+)+').Value
    $parsedI = $null; $parsedL = $null
    if ($pi -and $pl) {
        try { $parsedI = [version]$pi; $parsedL = [version]$pl } catch { }
    }
    if (-not $parsedI -or -not $parsedL) {
        Write-DoctorLine WARN 'version' `
            "installed $installed; could not compare against latest release $latest" `
            'check https://github.com/ggrace519/claude-code-dev-studio/releases'
    } elseif ($parsedI -lt $parsedL) {
        Write-DoctorLine WARN 'version' `
            "installed $installed is older than latest release $latest" `
            "run 'ccds update'"
    } else {
        Write-DoctorLine OK 'version' "$installed (ahead of latest release $latest)"
    }
}

function Test-DoctorAgents {
    $dir = Join-Path $env:USERPROFILE '.claude\agents'
    if (Test-CorePluginEnabled) {
        Write-DoctorLine OK 'agents-installed' "supplied by the enabled ccds-core plugin (no file copies needed in $dir)"
        return
    }
    if (Test-Path -LiteralPath (Join-Path $dir 'plan-architect.md')) {
        $n = @(Get-ChildItem -LiteralPath $dir -Filter *.md -File -ErrorAction SilentlyContinue).Count
        Write-DoctorLine OK 'agents-installed' "core sentinel plan-architect.md present ($n agent file(s) in $dir)"
    } else {
        Write-DoctorLine FAIL 'agents-installed' `
            "plan-architect.md missing from $dir and the ccds-core plugin is not enabled -- the always-on agents are not installed" `
            "run 'ccds setup' (or: claude plugin install ccds-core@ccds --scope user)"
    }
}

function Test-DoctorSkills {
    if (Test-CorePluginEnabled) {
        Write-DoctorLine OK 'skills-installed' "supplied by the enabled ccds-core plugin (no file copies needed in $(Join-Path $env:USERPROFILE '.claude\skills'))"
        return
    }
    $skillList = Get-GlobalSkillList
    if (-not $skillList) {
        Write-DoctorLine WARN 'skills-installed' `
            "cannot determine expected skill list (no parsable Install-Playbook.ps1 or scripts\ccds-user-setup.sh under $installRoot)" `
            "reinstall via 'ccds update' or the installer"
        return
    }
    $skillsDir = Join-Path $env:USERPROFILE '.claude\skills'
    $missing = @()
    foreach ($name in $skillList.Names) {
        if (-not (Test-Path -LiteralPath (Join-Path $skillsDir "$name\SKILL.md"))) {
            $missing += $name
        }
    }
    if ($missing.Count -eq 0) {
        Write-DoctorLine OK 'skills-installed' `
            "all $($skillList.Names.Count) cross-cutting skills present in $skillsDir (expected list from $($skillList.Source))"
    } else {
        Write-DoctorLine FAIL 'skills-installed' `
            "$($missing.Count)/$($skillList.Names.Count) cross-cutting skills missing from ${skillsDir}: $($missing -join ' ')" `
            "run 'ccds setup' (or: claude plugin install ccds-core@ccds --scope user)"
    }
}

function Test-DoctorPluginFileOverlap {
    # The always-on agents and cross-cutting skills reach Claude Code by ONE of
    # two routes: the ccds content plugins, or file copies written by setup.
    # Both at once means every agent is in the roster twice (two identical
    # descriptions for the router, the stale file copy owns the bare name) and
    # the descriptions cost context twice. Twin of bin/ccds.sh.
    Resolve-ContentPlugins
    if (-not $Script:ContentPluginsKnown) {
        Write-DoctorLine WARN 'plugin-file-overlap' `
            "cannot check: claude CLI not on PATH or 'claude plugin list --json' unreadable" `
            "install Claude Code / run 'claude plugin list', then re-run 'ccds doctor'"
        return
    }
    $agentsDir = Join-Path $env:USERPROFILE '.claude\agents'
    $skillsDir = Join-Path $env:USERPROFILE '.claude\skills'
    # ccds-owned agent names come from catalog.json (authoritative, shipped in
    # every layout); the package's agents\ dir is the fallback for an old tree.
    $owned = @()
    $catalog = Join-Path $installRoot 'catalog.json'
    if (Test-Path -LiteralPath $catalog) {
        try {
            $entries = @([System.IO.File]::ReadAllText($catalog) | ConvertFrom-Json)
            $owned = @($entries | Where-Object { $_.kind -eq 'agent' } | ForEach-Object { "$($_.name).md" })
        } catch { $owned = @() }
    }
    if ($owned.Count -eq 0) {
        $src = Join-Path $installRoot 'agents'
        if (-not (Test-Path -LiteralPath $src)) { $src = Join-Path $installRoot '.claude\agents' }
        if (Test-Path -LiteralPath $src) {
            $owned = @(Get-ChildItem -LiteralPath $src -Filter *.md -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        }
    }
    $agentFiles = @($owned | Where-Object { Test-Path -LiteralPath (Join-Path $agentsDir $_) })
    $skillList = Get-GlobalSkillList
    $skillNames = if ($skillList) { @($skillList.Names) } else { @() }
    $skillDirs = @($skillNames | Where-Object { Test-Path -LiteralPath (Join-Path $skillsDir "$_\SKILL.md") })
    if ($Script:ContentPlugins.Count -eq 0) {
        Write-DoctorLine OK 'plugin-file-overlap' 'no ccds content plugin enabled; agents and skills come from the file copies only'
        return
    }
    $pluginNames = $Script:ContentPlugins -join ' '
    if ($agentFiles.Count -eq 0 -and $skillDirs.Count -eq 0) {
        Write-DoctorLine OK 'plugin-file-overlap' "plugins ($pluginNames) supply the agents and skills; no file copies present"
        return
    }
    $cmds = @()
    if ($agentFiles.Count -gt 0) {
        $cmds += 'Remove-Item -Force ' + (($agentFiles | ForEach-Object { "'" + (Join-Path $agentsDir $_) + "'" }) -join ', ')
    }
    if ($skillDirs.Count -gt 0) {
        $cmds += 'Remove-Item -Recurse -Force ' + (($skillDirs | ForEach-Object { "'" + (Join-Path $skillsDir $_) + "'" }) -join ', ')
    }
    Write-DoctorLine FAIL 'plugin-file-overlap' `
        "loaded twice: plugin(s) $pluginNames are enabled AND $($agentFiles.Count) agent file(s) + $($skillDirs.Count) cross-cutting skill(s) from a file install (version $(Get-InstalledVersion)) sit in $(Join-Path $env:USERPROFILE '.claude') -- Claude Code loads both copies, and the file copies (which own the bare names) go stale the moment the plugins update" `
        ("remove the file copies (the plugins keep working): " + ($cmds -join '; '))
}

function Test-DoctorBom {
    $candidates = @()
    $agentsDir = Join-Path $env:USERPROFILE '.claude\agents'
    $skillsDir = Join-Path $env:USERPROFILE '.claude\skills'
    if (Test-Path -LiteralPath $agentsDir) {
        $candidates += @(Get-ChildItem -LiteralPath $agentsDir -Filter *.md -File -ErrorAction SilentlyContinue)
    }
    if (Test-Path -LiteralPath $skillsDir) {
        $candidates += @(Get-ChildItem -LiteralPath $skillsDir -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { Get-Item -LiteralPath (Join-Path $_.FullName 'SKILL.md') -ErrorAction SilentlyContinue })
    }
    $hits = @()
    foreach ($f in $candidates) {
        if (-not $f) { continue }
        try {
            $fs = [System.IO.File]::OpenRead($f.FullName)
            try {
                $buf = New-Object byte[] 3
                $n = $fs.Read($buf, 0, 3)
            } finally {
                $fs.Dispose()
            }
            if ($n -eq 3 -and $buf[0] -eq 0xEF -and $buf[1] -eq 0xBB -and $buf[2] -eq 0xBF) {
                $hits += $f.FullName
            }
        } catch { }
    }
    if ($hits.Count -eq 0) {
        Write-DoctorLine OK 'bom-scan' 'no UTF-8 BOM in installed agents or skills'
    } else {
        Write-DoctorLine FAIL 'bom-scan' `
            "$($hits.Count) installed file(s) start with a UTF-8 BOM, which makes Claude Code silently skip the frontmatter (ADR-0001): $($hits -join ' ')" `
            "run 'ccds setup' to restore clean copies; re-save any hand-edited file as UTF-8 without BOM"
    }
}

function Test-DoctorCrlf {
    # Scoped to *.sh only (same as the bash twin): CR bytes break bash scripts;
    # on Windows checkouts with autocrlf this can legitimately fire.
    $hits = @()
    try {
        $shFiles = @(Get-ChildItem -LiteralPath $installRoot -Recurse -Filter '*.sh' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
        foreach ($f in $shFiles) {
            try {
                if (([System.IO.File]::ReadAllText($f.FullName)).Contains("`r")) {
                    $hits += $f.FullName
                }
            } catch { }
        }
    } catch { }
    if ($hits.Count -eq 0) {
        Write-DoctorLine OK 'crlf-scan' "no CR bytes in *.sh under $installRoot"
    } else {
        Write-DoctorLine WARN 'crlf-scan' `
            "$($hits.Count) shell script(s) under $installRoot contain CR (CRLF) bytes: $($hits -join ' ')" `
            "normalize to LF (e.g. sed -i 's/\r`$//' <file>) or reinstall via 'ccds update'"
    }
}

function Test-DoctorClaudeBlock {
    $md = Join-Path $env:USERPROFILE '.claude\CLAUDE.md'
    if (-not (Test-Path -LiteralPath $md)) {
        Write-DoctorLine FAIL 'claude-md-block' "$md not found -- the ccds pointer block is not installed" "run 'ccds setup'"
        return
    }
    $nb = 0; $ne = 0
    try {
        $lines = [System.IO.File]::ReadAllLines($md)
        $nb = @($lines | Where-Object { $_.Contains('# >>> ccds >>>') }).Count
        $ne = @($lines | Where-Object { $_.Contains('# <<< ccds <<<') }).Count
    } catch { }
    if ($nb -eq 1 -and $ne -eq 1) {
        Write-DoctorLine OK 'claude-md-block' "exactly one ccds marker block in $md"
    } else {
        Write-DoctorLine FAIL 'claude-md-block' `
            "expected exactly one ccds block in $md; found $nb begin / $ne end marker(s)" `
            "run 'ccds setup' (it strips duplicate/broken blocks and reinjects a single fresh one)"
    }
}

function Test-DoctorCatalog {
    $cat = Join-Path $libraryRoot 'catalog.json'
    if (-not (Test-Path -LiteralPath $cat)) {
        Write-DoctorLine FAIL 'catalog' "catalog.json not found at $cat" `
            "reinstall via 'ccds update' (or regenerate with scripts/build-catalog.py in a repo clone)"
        return
    }
    try {
        [System.IO.File]::ReadAllText($cat) | ConvertFrom-Json | Out-Null
        Write-DoctorLine OK 'catalog' "$cat parses as valid JSON"
    } catch {
        Write-DoctorLine FAIL 'catalog' "$cat is not valid JSON" `
            "regenerate with scripts/build-catalog.py or reinstall via 'ccds update'"
    }
}

function Test-DoctorPathDuals {
    $resolvedCmd = Get-Command ccds -ErrorAction SilentlyContinue
    $resolved = if ($resolvedCmd) { $resolvedCmd.Source } else { '' }
    # Dual-install: this dispatcher runs from an installed root that is NOT the
    # default per-user prefix while that prefix also exists (two live copies).
    # Windows translation of the bash /usr/share/ccds vs ~/.claude/playbook check.
    $defaultPrefix = Join-Path $env:USERPROFILE '.claude\playbook'
    $dual = $false
    if ($layoutKind -eq 'installed' -and (Test-Path -LiteralPath $defaultPrefix)) {
        try {
            $a = (Resolve-Path -LiteralPath $installRoot).Path.TrimEnd('\')
            $b = (Resolve-Path -LiteralPath $defaultPrefix).Path.TrimEnd('\')
            if ($a -ne $b) { $dual = $true }
        } catch { }
    }
    if ($dual) {
        $resolvedDetail = if ($resolved) { $resolved } else { '<none -- ccds not on PATH>' }
        Write-DoctorLine WARN 'path-and-duals' `
            "both $installRoot and $defaultPrefix (default per-user prefix) are installed; this shell runs: $resolvedDetail" `
            "keep one install: run 'ccds uninstall' from the copy you want to remove"
    } elseif (-not $resolved) {
        Write-DoctorLine WARN 'path-and-duals' `
            "'ccds' is not resolvable on PATH (this run used $PSCommandPath)" `
            "add $binDir to PATH (the installer normally does this) or re-run the installer"
    } else {
        Write-DoctorLine OK 'path-and-duals' "ccds resolves to $resolved"
    }
}

# Twins of bin/ccds.sh doc_check_claude_cli / doc_check_plugins.
# Minimum Claude Code for ccds-guard's unattended adjudicator: v2.1.169 added
# --safe-mode, without which the judge is not isolated (ADR-0015).
$Script:MinClaudeVersion = [version]'2.1.169'

function Get-ClaudeCommand {
    if ($env:CCDS_CLAUDE_CMD) { return $env:CCDS_CLAUDE_CMD }
    return 'claude'
}

# Content plugins are the ccds-* plugins that ship agents and skills (ccds-core
# + the archetype packs) -- every ccds plugin except the hooks-only enforcement
# pair. When one is enabled, Claude Code already loads that roster from the
# plugin, so file copies in ~/.claude/{agents,skills} are a SECOND load.
# Twin of bin/ccds.sh content_plugins_enabled. Sets two script variables:
#   $Script:ContentPluginsKnown  $false when the CLI is absent / unreadable
#   $Script:ContentPlugins       enabled content-plugin names (may be empty)
# Probed once per run.
$Script:ContentPluginsProbed = $false
$Script:ContentPluginsKnown  = $false
$Script:ContentPlugins       = @()

function Resolve-ContentPlugins {
    if ($Script:ContentPluginsProbed) { return }
    $Script:ContentPluginsProbed = $true
    $claudeCmd = Get-ClaudeCommand
    if (-not (Get-Command $claudeCmd -ErrorAction SilentlyContinue)) { return }
    $plugins = $null
    try {
        # Join first: the real CLI pretty-prints one field per line, and a
        # line-by-line pipe into ConvertFrom-Json parses each line alone.
        $raw = @(& $claudeCmd plugin list --json 2>$null) -join "`n"
        if ($raw.Trim()) { $plugins = @($raw | ConvertFrom-Json) } else { $plugins = @() }
    } catch { return }
    $names = @()
    foreach ($pl in $plugins) {
        if ($null -eq $pl -or -not $pl.enabled) { continue }
        if ("$($pl.id)" -match '^(ccds-[a-z]+)@') {
            $n = $Matches[1]
            if ($n -ne 'ccds-guard' -and $n -ne 'ccds-loops') { $names += $n }
        }
    }
    $Script:ContentPluginsKnown = $true
    $Script:ContentPlugins = @($names | Sort-Object -Unique)
}

function Test-CorePluginEnabled {
    Resolve-ContentPlugins
    return ($Script:ContentPluginsKnown -and ($Script:ContentPlugins -contains 'ccds-core'))
}

function Test-DoctorClaudeCli {
    # WARN, not FAIL: an older CLI does not break ccds -- the guard's deny and
    # ask tiers work unchanged. It silently costs the unattended adjudicator.
    $claudeCmd = Get-ClaudeCommand
    if (-not (Get-Command $claudeCmd -ErrorAction SilentlyContinue)) {
        Write-DoctorLine 'WARN' 'claude-cli' `
            "claude CLI not on PATH; ccds's agents/skills still load, but the guard plugin and 'ccds setup' plugin install cannot run" `
            "install Claude Code, then run 'ccds setup'"
        return
    }
    $raw = ''
    try { $raw = (& $claudeCmd --version 2>$null | Select-Object -First 1) } catch { }
    $m = [regex]::Match([string]$raw, '\d+\.\d+\.\d+')
    if (-not $m.Success) {
        Write-DoctorLine 'WARN' 'claude-cli' `
            "could not parse a version from '$claudeCmd --version' (got: $(if ($raw) { $raw } else { 'empty' }))" `
            "check that '$claudeCmd --version' prints a x.y.z version"
        return
    }
    $ver = [version]$m.Value
    if ($ver -lt $Script:MinClaudeVersion) {
        Write-DoctorLine 'WARN' 'claude-cli' `
            "Claude Code $ver is older than $($Script:MinClaudeVersion); ccds-guard's unattended adjudicator needs --safe-mode to isolate its judge, so every unattended ask-gate hit denies instead of being judged (ADR-0015)" `
            "upgrade Claude Code to $($Script:MinClaudeVersion) or newer"
        return
    }
    Write-DoctorLine 'OK' 'claude-cli' "Claude Code $ver (>= $($Script:MinClaudeVersion))"
}

function Test-DoctorPlugins {
    # FAIL, not WARN: hooks ship ONLY via plugins (ADR-0012), so a missing or
    # disabled ccds-guard means this install has no security layer at all --
    # an incomplete install, same class as a missing core agent.
    $claudeCmd = Get-ClaudeCommand
    if (-not (Get-Command $claudeCmd -ErrorAction SilentlyContinue)) {
        Write-DoctorLine 'WARN' 'plugins-installed' `
            'cannot check: claude CLI not on PATH' `
            "install Claude Code, then run 'ccds setup'"
        return
    }
    $plugins = $null
    try {
        # Join first: the real CLI pretty-prints one field per line (see #70).
        $raw = @(& $claudeCmd plugin list --json 2>$null) -join "`n"
        $plugins = if ($raw.Trim()) { @($raw | ConvertFrom-Json) } else { @() }
    } catch { }
    if ($null -eq $plugins) {
        Write-DoctorLine 'WARN' 'plugins-installed' `
            "could not read 'claude plugin list --json'" `
            "run 'claude plugin list' and check the CLI is healthy"
        return
    }
    $missing = @(); $disabled = @()
    foreach ($name in @('ccds-guard', 'ccds-loops')) {
        # Match the plugin id from any marketplace: "<name>@<marketplace>".
        $hit = @($plugins | Where-Object { $_.id -like "$name@*" })
        if ($hit.Count -eq 0) { $missing += $name }
        elseif (@($hit | Where-Object { $_.enabled }).Count -eq 0) { $disabled += $name }
    }
    if ($missing.Count -gt 0) {
        Write-DoctorLine 'FAIL' 'plugins-installed' `
            "not installed: $($missing -join ' ') -- hooks ship only via plugins, so this install is missing that protection" `
            "run 'ccds setup' (or: claude plugin install $($missing[0])@ccds --scope user)"
        return
    }
    if ($disabled.Count -gt 0) {
        Write-DoctorLine 'FAIL' 'plugins-installed' `
            "installed but DISABLED: $($disabled -join ' ') -- a disabled guard protects nothing" `
            "claude plugin enable $($disabled[0])"
        return
    }
    Write-DoctorLine 'OK' 'plugins-installed' 'ccds-guard ccds-loops installed and enabled'
}

function Invoke-DoctorCommand {
    # Registry: check-name -> check function. Adding a check = one function
    # plus one row here (keep in lockstep with bin/ccds.sh cmd_doctor).
    $checks = @(
        @{ Name = 'layout'          ; Fn = ${function:Test-DoctorLayout} }
        @{ Name = 'version'         ; Fn = ${function:Test-DoctorVersion} }
        @{ Name = 'agents-installed'; Fn = ${function:Test-DoctorAgents} }
        @{ Name = 'skills-installed'; Fn = ${function:Test-DoctorSkills} }
        @{ Name = 'bom-scan'        ; Fn = ${function:Test-DoctorBom} }
        @{ Name = 'crlf-scan'       ; Fn = ${function:Test-DoctorCrlf} }
        @{ Name = 'claude-md-block' ; Fn = ${function:Test-DoctorClaudeBlock} }
        @{ Name = 'catalog'         ; Fn = ${function:Test-DoctorCatalog} }
        @{ Name = 'path-and-duals'  ; Fn = ${function:Test-DoctorPathDuals} }
        @{ Name = 'claude-cli'      ; Fn = ${function:Test-DoctorClaudeCli} }
        @{ Name = 'plugins-installed'; Fn = ${function:Test-DoctorPlugins} }
        @{ Name = 'plugin-file-overlap'; Fn = ${function:Test-DoctorPluginFileOverlap} }
    )

    Write-Host "ccds doctor -- environment checks (version $(Get-InstalledVersion), $layoutKind layout)"
    Write-Host ""
    foreach ($check in $checks) {
        & $check.Fn
    }
    Write-Host ""
    Write-Host '=== ccds doctor summary ==='
    Write-Host ('OK    : {0}' -f $Script:DocOk)
    Write-Host ('WARN  : {0}' -f $Script:DocWarn)
    Write-Host ('FAIL  : {0}' -f $Script:DocFail)
    if ($Script:DocFail -gt 0) {
        Write-Host 'RESULT: FAIL'
        exit 1
    }
    Write-Host 'RESULT: PASS'
    exit 0
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
    'setup'      { Invoke-SetupCommand -Opts $opts }
    'sync'       { Invoke-SyncCommand -Opts $opts }
    'verify'     { Invoke-VerifyCommand -Opts $opts }
    'doctor'     { Invoke-DoctorCommand }
    'lint'       { Invoke-LintCommand }
    'loop'       { Invoke-LoopCommand -Opts $opts }
    'update'     { Invoke-UpdateCommand -Opts $opts }
    'uninstall'  { Invoke-UninstallCommand }
    default {
        Write-Error "Unknown command: $Command. Run 'ccds help' for usage." -ErrorAction Continue
        exit 2
    }
}
