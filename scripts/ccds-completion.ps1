# ccds-completion.ps1
# PowerShell argument completer for the ccds CLI (Claude Code Dev Studio)
#
# Auto-installed to your PowerShell profile by Install-Playbook.ps1.
# Load manually for the current session:
#   . '<prefix>\scripts\ccds-completion.ps1'
#
# Tested on PowerShell 5.1 and 7+.

Register-ArgumentCompleter -Native -CommandName ccds -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $elements   = @($commandAst.CommandElements | ForEach-Object { $_.ToString() })
    $tokenCount = $elements.Count

    if ($wordToComplete -and $tokenCount -ge 1 -and $elements[$tokenCount - 1] -eq $wordToComplete) {
        $prev = if ($tokenCount -ge 2) { $elements[$tokenCount - 2] } else { '' }
    } else {
        $prev = if ($tokenCount -ge 1) { $elements[$tokenCount - 1] } else { '' }
    }

    $commands    = @('sync', 'verify', 'update', 'uninstall', 'version', 'help')
    $packs       = @('game','saas','mobile','ai','dataplat','ecom','fintech',
                     'devtool','desktop','ext','embed','media','orch','infra','common')
    $modes       = @('copy', 'symlink')
    $syncFlags   = @('--dry-run','--write-adr','--no-generalists','--mode','--target','--help','-h')
    $updateFlags = @('--rollback','--include-prerelease','--dry-run','--help','-h')
    $globalFlags = @('--help', '-h')

    function Complete-FromList {
        param([string[]]$Candidates, [string]$Word, [string]$CompletionPrefix = '')
        $Candidates |
            Where-Object { $_ -like "$Word*" } |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new(
                    "$CompletionPrefix$_", "$CompletionPrefix$_", 'ParameterValue', $_
                )
            }
    }

    function Complete-Dir {
        param([string]$Word)
        $base = if ($Word) { $Word } else { '.' }
        try {
            $parent = Split-Path -Path $base -Parent
            $leaf   = Split-Path -Path $base -Leaf
            if (-not $parent) { $parent = '.' }
            Get-ChildItem -LiteralPath $parent -Filter "$leaf*" -Directory -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $p = if ($parent -eq '.') { $_.Name } else { Join-Path $parent $_.Name }
                    [System.Management.Automation.CompletionResult]::new(
                        "$p\", $_.Name, 'ProviderContainer', $_.FullName
                    )
                }
        } catch { }
    }

    # Detect active command (first non-flag token after 'ccds')
    $command = $null
    for ($i = 1; $i -lt $tokenCount; $i++) {
        $tok = $elements[$i]
        if ($tok -eq $wordToComplete) { break }
        if ($commands -contains $tok) { $command = $tok; break }
    }

    # Value completions for flags that consume the next token
    switch -Regex ($prev) {
        '^--mode$'   { return Complete-FromList $modes $wordToComplete }
        '^--target$' { return Complete-Dir $wordToComplete }
    }

    switch ($command) {
        'sync' {
            if ($wordToComplete.StartsWith('-')) {
                return Complete-FromList $syncFlags $wordToComplete
            }
            # Pack name completion.  Handles comma-separated tokens ("saas,common"):
            # complete after the last comma so typing "saas,<TAB>" offers the remaining packs.
            $cpPrefix = ''
            $word     = $wordToComplete
            if ($wordToComplete.Contains(',')) {
                $lastComma = $wordToComplete.LastIndexOf(',')
                $cpPrefix  = $wordToComplete.Substring(0, $lastComma + 1)
                $word      = $wordToComplete.Substring($lastComma + 1)
            }
            # Exclude packs already present as separate tokens or in the comma prefix
            $used = [System.Collections.Generic.HashSet[string]]::new(
                        [System.StringComparer]::OrdinalIgnoreCase)
            for ($i = 1; $i -lt $tokenCount; $i++) {
                if ($elements[$i] -eq $wordToComplete) { break }
                if (-not $elements[$i].StartsWith('-')) {
                    foreach ($p in ($elements[$i] -split ',')) { [void]$used.Add($p.Trim()) }
                }
            }
            if ($cpPrefix) {
                foreach ($p in ($cpPrefix.TrimEnd(',') -split ',')) { [void]$used.Add($p.Trim()) }
            }
            $remaining = $packs | Where-Object { -not $used.Contains($_) }
            return Complete-FromList $remaining $word $cpPrefix
        }
        'update' {
            if ($wordToComplete.StartsWith('-')) {
                return Complete-FromList $updateFlags $wordToComplete
            }
            return @()
        }
        { $_ -in 'verify', 'uninstall', 'version', 'help' } {
            return Complete-FromList $globalFlags $wordToComplete
        }
    }

    # No command yet: offer commands or global flags
    if ($wordToComplete.StartsWith('-')) {
        return Complete-FromList $globalFlags $wordToComplete
    }
    if ($tokenCount -le 2) {
        return Complete-FromList $commands $wordToComplete
    }
    return @()
}
