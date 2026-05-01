#Requires -Version 5.1
<#
.SYNOPSIS
    Install / update / rollback / uninstall Claude Code Dev Studio from GitHub Releases.

.DESCRIPTION
    Downloads the Claude Code Dev Studio release ZIP from GitHub, verifies its SHA256
    against the published .sha256 sidecar, and installs it to ~/.claude/playbook/
    (i.e. %USERPROFILE%\.claude\playbook). Prepends <prefix>\bin to the User PATH
    so 'ccds <cmd>' is resolvable from any shell.

    Installed layout:
      %USERPROFILE%\.claude\
        agents\              (7 generalist agents — always loaded by Claude Code)
        playbook\            (<prefix> — this is what the installer manages)
          bin\               (dispatcher: ccds.ps1 / .sh)
          scripts\           (Sync-AgentPacks, Verify-Agents, jit-claude.md)
          agents\            (98 pack agents — copied to project on demand)
          catalog.json       (agent index for JIT selection)
          version.txt
          README.md
        CLAUDE.md            (user's global Claude instructions; playbook appends JIT block)

    Atomic upgrade:
      1. Stage to <prefix>.new
      2. If <prefix> exists: remove <prefix>.previous, move <prefix> -> <prefix>.previous
      3. Move <prefix>.new -> <prefix>

    Rollback restores <prefix>.previous in place of <prefix>.

.PARAMETER Version
    Release tag to install. Default 'latest' (latest stable; use -IncludePrerelease
    to pick up release candidates).

.PARAMETER Prefix
    Install root. Default: %USERPROFILE%\.claude\playbook (Claude Code Dev Studio default).

.PARAMETER LocalZip
    Bypass download and install from a locally built ZIP (e.g. output of
    build-release.ps1). Useful for smoke-testing before tagging.

.PARAMETER Token
    GitHub personal-access token for private-repo release downloads.
    Can also be supplied via $env:GITHUB_TOKEN.

.PARAMETER NoPath
    Skip the PATH update. Caller is responsible for making 'ccds' (and 'ccds')
    resolvable.

.PARAMETER IncludePrerelease
    When -Version is 'latest', include prerelease tags in the resolution.

.PARAMETER DryRun
    Print what would happen without touching the filesystem or PATH.

.PARAMETER Force
    Overwrite existing install without stopping to confirm.

.PARAMETER Rollback
    Restore the previous install from <prefix>.previous. Does not download.

.PARAMETER Uninstall
    Remove <prefix> and the PATH entry. Leaves <prefix>.previous alone.

.EXAMPLE
    # One-line bootstrap (public repo, latest stable)
    irm https://raw.githubusercontent.com/ggrace519/claude-code-dev-studio/main/Install-Playbook.ps1 | iex

.EXAMPLE
    # Pin a specific release
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/ggrace519/claude-code-dev-studio/main/Install-Playbook.ps1))) -Version v0.4.0-rc1

.EXAMPLE
    # Local smoke test from build-release.ps1 output
    .\Install-Playbook.ps1 -LocalZip .\dist\ccds-v0.4.0-rc1.zip

.EXAMPLE
    # Roll back to previous version
    .\Install-Playbook.ps1 -Rollback

.EXAMPLE
    # Remove entirely
    .\Install-Playbook.ps1 -Uninstall
#>
[CmdletBinding(DefaultParameterSetName = 'Install')]
param(
    [Parameter(ParameterSetName = 'Install')]
    [string]$Version = 'latest',

    [Parameter(ParameterSetName = 'Install')]
    [string]$LocalZip,

    [Parameter(ParameterSetName = 'Install')]
    [switch]$IncludePrerelease,

    [Parameter(ParameterSetName = 'Install')]
    [Parameter(ParameterSetName = 'Rollback')]
    [Parameter(ParameterSetName = 'Uninstall')]
    [string]$Prefix = (Join-Path $env:USERPROFILE '.claude\playbook'),

    [Parameter(ParameterSetName = 'Install')]
    [string]$Token,

    [Parameter(ParameterSetName = 'Install')]
    [Parameter(ParameterSetName = 'Uninstall')]
    [switch]$NoPath,

    [Parameter(ParameterSetName = 'Install')]
    [switch]$Force,

    [Parameter(ParameterSetName = 'Install')]
    [Parameter(ParameterSetName = 'Rollback')]
    [Parameter(ParameterSetName = 'Uninstall')]
    [switch]$DryRun,

    [Parameter(ParameterSetName = 'Rollback', Mandatory)]
    [switch]$Rollback,

    [Parameter(ParameterSetName = 'Uninstall', Mandatory)]
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$Script:Owner = 'ggrace519'
$Script:Repo  = 'claude-code-dev-studio'

# The 7 generalist agents that live permanently in ~/.claude/agents/
$Script:GeneralistAgents = @(
    'api-expert'
    'deploy-checklist'
    'plan-architect'
    'pr-code-reviewer'
    'secure-auditor'
    'test-writer-runner'
    'ux-design-critic'
)

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
function Write-Step   { param([string]$m) Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Info   { param([string]$m) Write-Host "    $m" }
function Write-OkMsg  { param([string]$m) Write-Host "OK  $m" -ForegroundColor Green }
function Write-WarnMsg{ param([string]$m) Write-Host "!!  $m" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
# HTTP helpers (TLS 1.2 for PS 5.1 on old Windows)
# ---------------------------------------------------------------------------
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Get-EffectiveToken {
    if ($Token) { return $Token }
    if ($env:GITHUB_TOKEN) { return $env:GITHUB_TOKEN }
    return $null
}

function New-AuthHeader {
    $t = Get-EffectiveToken
    if ($t) {
        return @{ Authorization = "Bearer $t"; 'User-Agent' = 'ccds-installer' }
    }
    return @{ 'User-Agent' = 'ccds-installer' }
}

function Invoke-Api {
    param([string]$Uri)
    try {
        return Invoke-RestMethod -Uri $Uri -Headers (New-AuthHeader)
    } catch {
        if ($_.Exception.Response.StatusCode.value__ -eq 404) {
            throw "GitHub API 404 for $Uri. If the repo is private, supply -Token or set `$env:GITHUB_TOKEN."
        }
        throw
    }
}

function Invoke-Download {
    param(
        [string]$Uri,
        [string]$OutFile
    )
    $headers = New-AuthHeader
    # For private-repo asset downloads, GitHub requires this Accept header.
    $headers['Accept'] = 'application/octet-stream'
    Invoke-WebRequest -Uri $Uri -Headers $headers -OutFile $OutFile -UseBasicParsing
}

# ---------------------------------------------------------------------------
# Release resolution
# ---------------------------------------------------------------------------
function Resolve-ReleaseTag {
    param(
        [string]$RequestedVersion,
        [switch]$IncludePre
    )

    if ($RequestedVersion -ne 'latest') {
        return $RequestedVersion
    }

    if ($IncludePre) {
        $all = Invoke-Api "https://api.github.com/repos/$Script:Owner/$Script:Repo/releases"
        if (-not $all) { throw "No releases found for $Script:Owner/$Script:Repo." }
        # API returns releases in reverse-chronological order by creation.
        return $all[0].tag_name
    }

    $stable = Invoke-Api "https://api.github.com/repos/$Script:Owner/$Script:Repo/releases/latest"
    return $stable.tag_name
}

function Get-AssetUrls {
    param([string]$Tag)

    $release = Invoke-Api "https://api.github.com/repos/$Script:Owner/$Script:Repo/releases/tags/$Tag"
    $zipName = "ccds-$Tag.zip"
    $shaName = "$zipName.sha256"

    $zip = $release.assets | Where-Object { $_.name -eq $zipName } | Select-Object -First 1
    $sha = $release.assets | Where-Object { $_.name -eq $shaName } | Select-Object -First 1
    if (-not $zip) { throw "Asset '$zipName' not found on release $Tag." }
    if (-not $sha) { throw "Asset '$shaName' not found on release $Tag." }

    return @{
        Tag         = $Tag
        ZipUrl      = $zip.url         # 'url' is the API URL --works with Bearer token
        ZipBrowser  = $zip.browser_download_url
        ShaUrl      = $sha.url
        ShaBrowser  = $sha.browser_download_url
        ZipName     = $zipName
        ShaName     = $shaName
    }
}

# ---------------------------------------------------------------------------
# SHA256 verification
# ---------------------------------------------------------------------------
function Test-ZipHash {
    param(
        [string]$ZipPath,
        [string]$SidecarPath
    )
    $recorded = ((Get-Content -LiteralPath $SidecarPath -Raw).Split(' ')[0]).Trim().ToLower()
    $actual   = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLower()
    if ($recorded -ne $actual) {
        throw "SHA256 mismatch. Recorded=$recorded Actual=$actual File=$ZipPath"
    }
    return $actual
}

# ---------------------------------------------------------------------------
# PATH management (User scope)
# ---------------------------------------------------------------------------
function Get-UserPath {
    [Environment]::GetEnvironmentVariable('PATH', 'User')
}

function Set-UserPath {
    param([string]$Value)
    [Environment]::SetEnvironmentVariable('PATH', $Value, 'User')
}

function Add-ToUserPath {
    param([string]$Entry)

    $current = Get-UserPath
    $entries = @()
    if ($current) { $entries = $current -split ';' | Where-Object { $_ -ne '' } }

    # Normalise for comparison
    $norm = [System.IO.Path]::GetFullPath($Entry).TrimEnd('\')
    $already = $entries | Where-Object {
        try { [System.IO.Path]::GetFullPath($_).TrimEnd('\') -ieq $norm } catch { $false }
    }

    if ($already) {
        Write-Info "PATH already contains $Entry"
        return $false
    }

    $newEntries = @($Entry) + $entries
    Set-UserPath ($newEntries -join ';')

    # Also update current session for immediate use
    $env:PATH = "$Entry;$env:PATH"
    Write-OkMsg "Prepended to User PATH: $Entry"
    return $true
}

function Remove-FromUserPath {
    param([string]$Entry)

    $current = Get-UserPath
    if (-not $current) { return $false }

    $norm = [System.IO.Path]::GetFullPath($Entry).TrimEnd('\')
    $kept = @()
    $removed = $false
    foreach ($e in ($current -split ';')) {
        if ($e -eq '') { continue }
        try {
            if ([System.IO.Path]::GetFullPath($e).TrimEnd('\') -ieq $norm) {
                $removed = $true
                continue
            }
        } catch { }
        $kept += $e
    }

    if ($removed) {
        Set-UserPath ($kept -join ';')
        Write-OkMsg "Removed from User PATH: $Entry"
    }
    return $removed
}

# ---------------------------------------------------------------------------
# ~/.claude/ post-install helpers
# ---------------------------------------------------------------------------

# Copy the 7 generalist agents from <prefix>\agents\ to ~/.claude/agents/
function Install-GeneralistAgents {
    param(
        [string]$Prefix,
        [switch]$DryRun
    )
    $claudeAgentsDir = Join-Path $env:USERPROFILE '.claude\agents'

    if ($DryRun) {
        Write-Info "DRY RUN --would copy $($Script:GeneralistAgents.Count) generalist agents to $claudeAgentsDir"
        return
    }

    if (-not (Test-Path $claudeAgentsDir)) {
        New-Item -ItemType Directory -Path $claudeAgentsDir -Force | Out-Null
    }

    $copied = 0
    foreach ($name in $Script:GeneralistAgents) {
        $src = Join-Path $Prefix "agents\$name.md"
        $dst = Join-Path $claudeAgentsDir "$name.md"
        if (Test-Path $src) {
            Copy-Item -LiteralPath $src -Destination $dst -Force
            $copied++
        } else {
            Write-WarnMsg "Generalist agent not found in package: agents\$name.md"
        }
    }
    Write-OkMsg "Copied $copied generalist agents to $claudeAgentsDir"
}

# Inject or update the playbook JIT block in ~/.claude/CLAUDE.md (idempotent)
function Set-ClaudePlaybookBlock {
    param(
        [string]$JitBlockPath,
        [switch]$DryRun
    )
    $claudeHome = Join-Path $env:USERPROFILE '.claude'
    $claudeMd   = Join-Path $claudeHome 'CLAUDE.md'

    if ($DryRun) {
        Write-Info "DRY RUN --would inject/update playbook JIT block in $claudeMd"
        return
    }

    if (-not (Test-Path $claudeHome)) {
        New-Item -ItemType Directory -Path $claudeHome -Force | Out-Null
    }

    $blockContent = (Get-Content -LiteralPath $JitBlockPath -Raw).TrimEnd("`r","`n")
    $existing     = if (Test-Path $claudeMd) { Get-Content -LiteralPath $claudeMd -Raw } else { '' }

    # Backup before any mutation. Timestamped so reinstalls keep history.
    if (Test-Path $claudeMd) {
        $stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = "$claudeMd.ccds-backup-$stamp"
        Copy-Item -LiteralPath $claudeMd -Destination $backup -Force
        Write-Info "Backed up existing CLAUDE.md to $(Split-Path -Leaf $backup)"
    }

    $markerStart = '# >>> ccds >>>'
    $markerEnd   = '# <<< ccds <<<'

    # Strip ALL existing ccds blocks (handles duplicates from prior buggy
    # installs and tolerates trailing whitespace on the marker lines).
    $stripPattern = "(?s)\r?\n?[ \t]*$([regex]::Escape($markerStart))[ \t\r]*\r?\n.*?[ \t]*$([regex]::Escape($markerEnd))[ \t\r]*\r?\n?"
    $cleaned = [regex]::Replace($existing, $stripPattern, '')
    $cleaned = $cleaned.TrimEnd("`r","`n")

    # Canary: legacy installs (pre-marker era, or hand-edited) may have left
    # JIT content in CLAUDE.md without markers. We can't safely auto-strip it,
    # but we can warn so the user can clean up by hand or restore the backup.
    if ($cleaned -match '##\s+Playbook JIT Agent Loading') {
        Write-WarnMsg "Detected legacy 'Playbook JIT Agent Loading' content outside markers."
        if ($backup) {
            Write-WarnMsg "Inspect $claudeMd and (if duplicated) restore from $(Split-Path -Leaf $backup)."
        }
    }

    if ($cleaned.Length -gt 0) {
        $updated = $cleaned + "`n`n" + $blockContent + "`n"
    } else {
        $updated = $blockContent + "`n"
    }
    [System.IO.File]::WriteAllText($claudeMd, $updated, [System.Text.UTF8Encoding]::new($false))
    Write-OkMsg "Refreshed playbook JIT block in $claudeMd"
}

# Remove the playbook JIT block from ~/.claude/CLAUDE.md (used by uninstall)
function Remove-ClaudePlaybookBlock {
    param([switch]$DryRun)
    $claudeMd = Join-Path $env:USERPROFILE '.claude\CLAUDE.md'

    if (-not (Test-Path $claudeMd)) {
        Write-Info "No CLAUDE.md at $claudeMd - nothing to remove."
        return
    }

    $existing    = Get-Content $claudeMd -Raw
    $markerStart = '# >>> ccds >>>'

    if (-not ($existing -match [regex]::Escape($markerStart))) {
        Write-Info "No playbook block found in CLAUDE.md - nothing to remove."
        return
    }

    if ($DryRun) {
        Write-Info "DRY RUN --would remove playbook JIT block from $claudeMd"
        return
    }

    $markerEnd = '# <<< ccds <<<'
    $pattern   = "(?s)`r?`n?$([regex]::Escape($markerStart)).*?$([regex]::Escape($markerEnd))`r?`n?"
    $updated   = [regex]::Replace($existing, $pattern, '')
    [System.IO.File]::WriteAllText($claudeMd, $updated, [System.Text.UTF8Encoding]::new($false))
    Write-OkMsg "Removed playbook JIT block from $claudeMd"
}

# ---------------------------------------------------------------------------
# Install core
# ---------------------------------------------------------------------------
function Install-FromZip {
    param(
        [string]$ZipPath,
        [string]$Prefix,
        [switch]$DryRun,
        [switch]$Force
    )

    $newDir  = "$Prefix.new"
    $prevDir = "$Prefix.previous"

    if ((Test-Path $Prefix) -and -not $Force) {
        $currentVersion = 'unknown'
        $vf = Join-Path $Prefix 'version.txt'
        if (Test-Path $vf) { $currentVersion = (Get-Content $vf -Raw).Trim() }
        Write-Info "Existing install found at $Prefix (version=$currentVersion). Will snapshot to $prevDir."
    }

    if ($DryRun) {
        Write-Step "DRY RUN --would extract $ZipPath to $newDir"
        if (Test-Path $Prefix)  { Write-Info "DRY RUN --would move $Prefix -> $prevDir (replacing any existing)" }
        Write-Info "DRY RUN --would move $newDir -> $Prefix"
        return
    }

    if (Test-Path $newDir) { Remove-Item -LiteralPath $newDir -Recurse -Force }
    Write-Step "Extracting to $newDir"
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $newDir -Force

    # Sanity: key files must exist in the extracted tree
    foreach ($sentinel in @('bin\ccds.ps1', 'catalog.json', 'agents')) {
        if (-not (Test-Path (Join-Path $newDir $sentinel))) {
            Remove-Item -LiteralPath $newDir -Recurse -Force
            throw "Extraction did not produce '$sentinel' -- archive layout is unexpected."
        }
    }

    if (Test-Path $Prefix) {
        if (Test-Path $prevDir) {
            Write-Info "Removing stale snapshot: $prevDir"
            Remove-Item -LiteralPath $prevDir -Recurse -Force
        }
        Write-Step "Snapshotting current install to $prevDir"
        Move-Item -LiteralPath $Prefix -Destination $prevDir
    }

    Write-Step "Promoting $newDir to $Prefix"
    Move-Item -LiteralPath $newDir -Destination $Prefix
}

function Invoke-Rollback {
    param(
        [string]$Prefix,
        [switch]$DryRun
    )
    $prevDir = "$Prefix.previous"

    if (-not (Test-Path $prevDir)) {
        throw "No previous install at $prevDir. Nothing to roll back."
    }

    if ($DryRun) {
        Write-Step "DRY RUN --would restore $prevDir to $Prefix"
        return
    }

    $trash = "$Prefix.rollback-discard-$((Get-Date).ToString('yyyyMMddHHmmss'))"
    if (Test-Path $Prefix) {
        Write-Step "Moving current $Prefix -> $trash"
        Move-Item -LiteralPath $Prefix -Destination $trash
    }
    Write-Step "Restoring $prevDir -> $Prefix"
    Move-Item -LiteralPath $prevDir -Destination $Prefix
    if (Test-Path $trash) {
        Write-Step "Deleting discarded post-rollback tree: $trash"
        Remove-Item -LiteralPath $trash -Recurse -Force
    }
    Write-OkMsg "Rollback complete."
}

function Invoke-Uninstall {
    param(
        [string]$Prefix,
        [switch]$NoPath,
        [switch]$DryRun
    )
    $binDir = Join-Path $Prefix 'bin'

    if ($DryRun) {
        if (Test-Path $Prefix) { Write-Info "DRY RUN --would remove $Prefix" }
        if (-not $NoPath)      { Write-Info "DRY RUN --would remove $binDir from User PATH" }
        Write-Info "DRY RUN --would remove playbook JIT block from $(Join-Path $env:USERPROFILE '.claude\CLAUDE.md')"
        Write-Info "DRY RUN --note: generalist agents in $(Join-Path $env:USERPROFILE '.claude\agents') are NOT removed"
        return
    }

    if (Test-Path $Prefix) {
        Write-Step "Removing $Prefix"
        Remove-Item -LiteralPath $Prefix -Recurse -Force
        Write-OkMsg "Removed install directory."
    } else {
        Write-WarnMsg "$Prefix does not exist; nothing to remove on disk."
    }

    if (-not $NoPath) {
        [void](Remove-FromUserPath -Entry $binDir)
    }

    # Remove the JIT block from ~/.claude/CLAUDE.md
    Write-Step "Removing playbook JIT block from CLAUDE.md"
    Remove-ClaudePlaybookBlock -DryRun:$DryRun

    Write-WarnMsg "Generalist agents in $(Join-Path $env:USERPROFILE '.claude\agents') were NOT removed."
    Write-WarnMsg "Delete them manually if desired."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
switch ($PSCmdlet.ParameterSetName) {
    'Rollback' {
        Invoke-Rollback -Prefix $Prefix -DryRun:$DryRun
        return
    }
    'Uninstall' {
        Invoke-Uninstall -Prefix $Prefix -NoPath:$NoPath -DryRun:$DryRun
        return
    }
}

# --- Install path ---
$tempDir = $null
try {
    if ($LocalZip) {
        if (-not (Test-Path $LocalZip)) { throw "LocalZip not found: $LocalZip" }
        $zipPath = (Resolve-Path $LocalZip).Path

        # Optional: verify sibling .sha256 if present
        $sideBySide = "$zipPath.sha256"
        if (Test-Path $sideBySide) {
            $hash = Test-ZipHash -ZipPath $zipPath -SidecarPath $sideBySide
            Write-OkMsg "Local ZIP SHA256 verified: $hash"
        } else {
            Write-WarnMsg "No sidecar at $sideBySide --skipping hash verification."
        }

        $resolvedTag = 'local'
    } else {
        Write-Step "Resolving release tag (requested: $Version)"
        $resolvedTag = Resolve-ReleaseTag -RequestedVersion $Version -IncludePre:$IncludePrerelease
        Write-Info "Tag: $resolvedTag"

        Write-Step "Looking up release assets for $resolvedTag"
        $assets = Get-AssetUrls -Tag $resolvedTag

        $tempDir = New-Item -ItemType Directory -Path (Join-Path $env:TEMP "cp-install-$([guid]::NewGuid().ToString('N'))") -Force
        $zipPath = Join-Path $tempDir.FullName $assets.ZipName
        $shaPath = Join-Path $tempDir.FullName $assets.ShaName

        Write-Step "Downloading $($assets.ZipName)"
        Invoke-Download -Uri $assets.ZipUrl -OutFile $zipPath
        Write-Step "Downloading $($assets.ShaName)"
        Invoke-Download -Uri $assets.ShaUrl -OutFile $shaPath

        $hash = Test-ZipHash -ZipPath $zipPath -SidecarPath $shaPath
        Write-OkMsg "Downloaded ZIP SHA256 verified: $hash"
    }

    Install-FromZip -ZipPath $zipPath -Prefix $Prefix -DryRun:$DryRun -Force:$Force

    if ($DryRun) {
        Write-Step "DRY RUN --no changes made."
        return
    }

    $installedVersionFile = Join-Path $Prefix 'version.txt'
    $installedVersion = if (Test-Path $installedVersionFile) {
        (Get-Content $installedVersionFile -Raw).Trim()
    } else { $resolvedTag }

    # Copy 7 generalist agents to ~/.claude/agents/ (always-loaded by Claude Code)
    Write-Step "Installing generalist agents to $(Join-Path $env:USERPROFILE '.claude\agents')"
    Install-GeneralistAgents -Prefix $Prefix -DryRun:$DryRun

    # Inject/update JIT protocol block in ~/.claude/CLAUDE.md
    Write-Step "Updating JIT block in $(Join-Path $env:USERPROFILE '.claude\CLAUDE.md')"
    $jitBlock = Join-Path $Prefix 'scripts\jit-claude.md'
    Set-ClaudePlaybookBlock -JitBlockPath $jitBlock -DryRun:$DryRun

    if (-not $NoPath) {
        $binDir = Join-Path $Prefix 'bin'
        [void](Add-ToUserPath -Entry $binDir)
    }

    Write-Host ""
    Write-Host "=== Claude Code Dev Studio installed ===" -ForegroundColor Green
    Write-Host "Prefix  : $Prefix"
    Write-Host "Version : $installedVersion"
    if (-not $NoPath) {
        Write-Host "PATH    : $(Join-Path $Prefix 'bin') (prepended to User PATH)"
        Write-Host ""
        Write-Host "Current session: 'ccds' is available now." -ForegroundColor Yellow
        Write-Host "Future shells : PATH update persists automatically." -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Library : $(Join-Path $env:USERPROFILE '.claude\playbook\agents') ($($Script:GeneralistAgents.Count) generalists -> .claude\agents; 98 pack agents here)"
    Write-Host "CLAUDE  : $(Join-Path $env:USERPROFILE '.claude\CLAUDE.md') (JIT block injected)"
    Write-Host ""
    Write-Host "Smoke test:" -ForegroundColor Yellow
    Write-Host "  ccds version"
    Write-Host "  cd <your-project>"
    Write-Host "  ccds sync saas,common --dry-run"
    Write-Host ""
    Write-Host "Then restart Claude Code to activate the generalist agents." -ForegroundColor Yellow
} finally {
    if ($tempDir -and (Test-Path $tempDir.FullName)) {
        Remove-Item -LiteralPath $tempDir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}
