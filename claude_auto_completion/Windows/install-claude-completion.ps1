# install-claude-completion.ps1
# Installs the claude CLI argument completer into the current user's PowerShell profile.
#
# Usage:
#   . .\install-claude-completion.ps1
#
# Or with -Force to overwrite an existing copy:
#   . .\install-claude-completion.ps1 -Force

[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$source    = Join-Path $scriptDir 'claude-completion.ps1'

if (-not (Test-Path -LiteralPath $source)) {
    Write-Error "claude-completion.ps1 not found next to installer ($source)"
    return
}

# Destination: per-user, alongside the profile so it's portable across hosts.
$destDir  = Join-Path (Split-Path -Parent $PROFILE.CurrentUserAllHosts) 'completions'
$destFile = Join-Path $destDir 'claude-completion.ps1'

if (-not (Test-Path -LiteralPath $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
}

if ((Test-Path -LiteralPath $destFile) -and -not $Force) {
    Write-Host "Updating existing: $destFile"
} else {
    Write-Host "Installing to: $destFile"
}
Copy-Item -LiteralPath $source -Destination $destFile -Force

# Use CurrentUserAllHosts so it loads in pwsh, ISE, VSCode, etc.
$profilePath = $PROFILE.CurrentUserAllHosts
$profileDir  = Split-Path -Parent $profilePath
if (-not (Test-Path -LiteralPath $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}
if (-not (Test-Path -LiteralPath $profilePath)) {
    New-Item -ItemType File -Path $profilePath -Force | Out-Null
}

$loaderLine = ". `"$destFile`""
$marker     = '# >>> claude-completion >>>'
$endMarker  = '# <<< claude-completion <<<'

$existing = Get-Content -LiteralPath $profilePath -Raw -ErrorAction SilentlyContinue
if ($existing -and $existing.Contains($marker)) {
    Write-Host "Profile already loads claude-completion: $profilePath"
} else {
    $block = @"

$marker
if (Test-Path '$destFile') { . '$destFile' }
$endMarker
"@
    Add-Content -LiteralPath $profilePath -Value $block
    Write-Host "Added loader to: $profilePath"
}

# Load it into the current session immediately
. $destFile
Write-Host ""
Write-Host "Activated for this session. Try:  claude --<TAB>"
