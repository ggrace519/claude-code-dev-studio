# claude-completion.ps1
# PowerShell argument completer for the Claude Code CLI (`claude`)
# Source: https://code.claude.com/docs/en/cli-reference
#
# Install (current user):
#   . .\install-claude-completion.ps1
#
# Or load manually for the current session:
#   . .\claude-completion.ps1
#
# Tested on PowerShell 5.1 and 7+.

Register-ArgumentCompleter -Native -CommandName claude -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    # ---- Token model ----
    # CommandElements[0] is `claude` itself.
    $elements = @($commandAst.CommandElements | ForEach-Object { $_.ToString() })
    $tokenCount = $elements.Count

    # The "previous" token is the one immediately before the cursor.
    # If $wordToComplete is non-empty, the last element IS the partial we're typing.
    if ($wordToComplete -and $tokenCount -ge 1 -and $elements[$tokenCount - 1] -eq $wordToComplete) {
        $prev = if ($tokenCount -ge 2) { $elements[$tokenCount - 2] } else { '' }
    } else {
        $prev = if ($tokenCount -ge 1) { $elements[$tokenCount - 1] } else { '' }
    }

    # ---- Catalog ----
    $subcommands = @(
        'update','install','auth','agents','auto-mode','mcp','plugin','plugins',
        'remote-control','setup-token','ultrareview'
    )

    $globalFlags = @(
        '--add-dir','--agent','--agents','--allow-dangerously-skip-permissions',
        '--allowedTools','--append-system-prompt','--append-system-prompt-file',
        '--bare','--betas','--channels','--chrome','--continue','-c',
        '--dangerously-load-development-channels','--dangerously-skip-permissions',
        '--debug','--debug-file','--disable-slash-commands','--disallowedTools',
        '--effort','--exclude-dynamic-system-prompt-sections','--fallback-model',
        '--fork-session','--from-pr','--ide','--init','--init-only',
        '--include-hook-events','--include-partial-messages','--input-format',
        '--json-schema','--maintenance','--max-budget-usd','--max-turns',
        '--mcp-config','--model','--name','-n','--no-chrome',
        '--no-session-persistence','--output-format','--permission-mode',
        '--permission-prompt-tool','--plugin-dir','--print','-p','--remote',
        '--remote-control','--rc','--remote-control-session-name-prefix',
        '--replay-user-messages','--resume','-r','--session-id',
        '--setting-sources','--settings','--strict-mcp-config','--system-prompt',
        '--system-prompt-file','--teleport','--teammate-mode','--tmux','--tools',
        '--verbose','--version','-v','--worktree','-w','--help','-h'
    )

    $models           = @('sonnet','opus','haiku','claude-sonnet-4-6','claude-opus-4-6','claude-haiku-4-5','claude-sonnet-4-7','claude-opus-4-7')
    $permissionModes  = @('default','acceptEdits','plan','auto','dontAsk','bypassPermissions')
    $effortLevels     = @('low','medium','high','xhigh','max')
    $outputFormats    = @('text','json','stream-json')
    $inputFormats     = @('text','stream-json')
    $teammateModes    = @('auto','in-process','tmux')
    $settingSources   = @('user','project','local')
    $authSubs         = @('login','logout','status')
    $autoModeSubs     = @('defaults','config')
    $mcpSubs          = @('add','remove','list','get','serve','add-json','add-from-claude-desktop','reset-project-choices')
    $pluginSubs       = @('install','uninstall','list','update','enable','disable','marketplace')
    $installVersions  = @('stable','latest')

    # ---- Helpers ----
    function Complete-FromList {
        param([string[]]$Candidates, [string]$Word, [string]$Tip = '')
        $Candidates |
            Where-Object { $_ -like "$Word*" } |
            ForEach-Object {
                $tip = if ($Tip) { $Tip } else { $_ }
                [System.Management.Automation.CompletionResult]::new(
                    $_, $_, 'ParameterValue', $tip
                )
            }
    }

    function Complete-Path {
        param([string]$Word, [switch]$DirectoryOnly)
        $base = if ($Word) { $Word } else { '.' }
        try {
            $parent = Split-Path -Path $base -Parent
            $leaf   = Split-Path -Path $base -Leaf
            if (-not $parent) { $parent = '.' }
            if (-not $leaf -and $base.EndsWith([IO.Path]::DirectorySeparatorChar)) { $leaf = '' }
            $items = Get-ChildItem -LiteralPath $parent -Filter "$leaf*" -ErrorAction SilentlyContinue
            if ($DirectoryOnly) { $items = $items | Where-Object { $_.PSIsContainer } }
            $items | ForEach-Object {
                $p = if ($parent -eq '.') { $_.Name } else { Join-Path $parent $_.Name }
                if ($_.PSIsContainer) { $p = "$p$([IO.Path]::DirectorySeparatorChar)" }
                [System.Management.Automation.CompletionResult]::new(
                    $p, $_.Name, 'ProviderItem', $_.FullName
                )
            }
        } catch { }
    }

    # ---- Detect active subcommand ----
    $subcommand = $null
    for ($i = 1; $i -lt $tokenCount; $i++) {
        $tok = $elements[$i]
        if ($tok -eq $wordToComplete) { break }
        if ($subcommands -contains $tok) { $subcommand = $tok; break }
    }

    # ---- Value completion based on previous flag ----
    switch -Regex ($prev) {
        '^(--model|--fallback-model)$'                                   { return Complete-FromList $models $wordToComplete }
        '^--permission-mode$'                                            { return Complete-FromList $permissionModes $wordToComplete }
        '^--effort$'                                                     { return Complete-FromList $effortLevels $wordToComplete }
        '^--output-format$'                                              { return Complete-FromList $outputFormats $wordToComplete }
        '^--input-format$'                                               { return Complete-FromList $inputFormats $wordToComplete }
        '^--teammate-mode$'                                              { return Complete-FromList $teammateModes $wordToComplete }
        '^--setting-sources$'                                            { return Complete-FromList $settingSources $wordToComplete }
        '^(--add-dir|--plugin-dir|--worktree|-w)$'                       { return Complete-Path $wordToComplete -DirectoryOnly }
        '^(--settings|--mcp-config|--system-prompt-file|--append-system-prompt-file|--debug-file)$' {
            return Complete-Path $wordToComplete
        }
        # Free-form values: explicitly return nothing so PowerShell does not
        # fall back to filename completion for opaque arguments.
        '^(--agents|--system-prompt|--append-system-prompt|--betas|--name|-n|--session-id|--from-pr|--max-turns|--max-budget-usd|--allowedTools|--disallowedTools|--tools|--agent|--debug|--channels|--json-schema|--permission-prompt-tool|--remote|--remote-control-session-name-prefix)$' {
            return @()
        }
    }

    # ---- Subcommand-specific dispatch ----
    switch ($subcommand) {
        'auth' {
            $authSub = $null
            for ($i = 1; $i -lt $tokenCount; $i++) {
                if ($authSubs -contains $elements[$i]) { $authSub = $elements[$i]; break }
            }
            if (-not $authSub) {
                return Complete-FromList $authSubs $wordToComplete
            } else {
                return Complete-FromList @('--email','--sso','--console','--text') $wordToComplete
            }
        }
        'auto-mode' {
            return Complete-FromList $autoModeSubs $wordToComplete
        }
        'mcp' {
            $mcpSub = $null
            for ($i = 1; $i -lt $tokenCount; $i++) {
                if ($mcpSubs -contains $elements[$i]) { $mcpSub = $elements[$i]; break }
            }
            if (-not $mcpSub) {
                return Complete-FromList $mcpSubs $wordToComplete
            }
            return @()
        }
        { $_ -in 'plugin','plugins' } {
            $plugSub = $null
            for ($i = 1; $i -lt $tokenCount; $i++) {
                if ($pluginSubs -contains $elements[$i]) { $plugSub = $elements[$i]; break }
            }
            if (-not $plugSub) {
                return Complete-FromList $pluginSubs $wordToComplete
            }
            return @()
        }
        'install' {
            if (-not $wordToComplete.StartsWith('-')) {
                return Complete-FromList $installVersions $wordToComplete
            }
            return @()
        }
        'ultrareview' {
            if ($wordToComplete.StartsWith('-')) {
                return Complete-FromList @('--json','--timeout') $wordToComplete
            }
            return @()
        }
        'remote-control' {
            if ($wordToComplete.StartsWith('-')) {
                return Complete-FromList (@('--name','--remote-control-session-name-prefix') + $globalFlags) $wordToComplete
            }
            return @()
        }
        { $_ -in 'update','agents','setup-token' } {
            if ($wordToComplete.StartsWith('-')) {
                return Complete-FromList $globalFlags $wordToComplete
            }
            return @()
        }
    }

    # ---- No subcommand: complete subcommands or flags ----
    if ($wordToComplete.StartsWith('-')) {
        return Complete-FromList $globalFlags $wordToComplete
    }
    if ($tokenCount -le 2) {
        return Complete-FromList $subcommands $wordToComplete
    }
    return @()
}
