# bash completion for the Claude Code CLI (`claude`)
# Source: https://code.claude.com/docs/en/cli-reference
#
# Install (per-user):
#   mkdir -p ~/.local/share/bash-completion/completions
#   cp claude-completion.bash ~/.local/share/bash-completion/completions/claude
#
# Install (system-wide, requires root):
#   sudo cp claude-completion.bash /etc/bash_completion.d/claude
#
# Then start a new shell or: source ~/.local/share/bash-completion/completions/claude

_claude_completion() {
    local cur prev words cword
    _init_completion -n = || return

    # ---- Subcommands (first positional after `claude`) ----
    local subcommands="update install auth agents auto-mode mcp plugin plugins \
remote-control setup-token ultrareview"

    # ---- Top-level flags ----
    local global_flags="\
--add-dir --agent --agents --allow-dangerously-skip-permissions --allowedTools \
--append-system-prompt --append-system-prompt-file --bare --betas --channels \
--chrome --continue -c --dangerously-load-development-channels \
--dangerously-skip-permissions --debug --debug-file --disable-slash-commands \
--disallowedTools --effort --exclude-dynamic-system-prompt-sections \
--fallback-model --fork-session --from-pr --ide --init --init-only \
--include-hook-events --include-partial-messages --input-format --json-schema \
--maintenance --max-budget-usd --max-turns --mcp-config --model --name -n \
--no-chrome --no-session-persistence --output-format --permission-mode \
--permission-prompt-tool --plugin-dir --print -p --remote --remote-control --rc \
--remote-control-session-name-prefix --replay-user-messages --resume -r \
--session-id --setting-sources --settings --strict-mcp-config --system-prompt \
--system-prompt-file --teleport --teammate-mode --tmux --tools --verbose \
--version -v --worktree -w --help -h"

    # ---- Enum values for specific flags ----
    local models="sonnet opus haiku claude-sonnet-4-6 claude-opus-4-6 \
claude-haiku-4-5 claude-sonnet-4-7 claude-opus-4-7"
    local permission_modes="default acceptEdits plan auto dontAsk bypassPermissions"
    local effort_levels="low medium high xhigh max"
    local output_formats="text json stream-json"
    local input_formats="text stream-json"
    local teammate_modes="auto in-process tmux"
    local setting_sources="user project local"
    local auth_subs="login logout status"
    local auto_mode_subs="defaults config"
    local mcp_subs="add remove list get serve add-json add-from-claude-desktop reset-project-choices"
    local plugin_subs="install uninstall list update enable disable marketplace"
    local install_versions="stable latest"

    # ---- Determine the active subcommand (if any) ----
    local subcommand=""
    local i
    for ((i=1; i < cword; i++)); do
        case "${words[i]}" in
            update|install|auth|agents|auto-mode|mcp|plugin|plugins|\
remote-control|setup-token|ultrareview)
                subcommand="${words[i]}"
                break
                ;;
        esac
    done

    # ---- Value completion: previous token expects an argument ----
    case "$prev" in
        --model|--fallback-model)
            COMPREPLY=( $(compgen -W "$models" -- "$cur") )
            return 0
            ;;
        --permission-mode)
            COMPREPLY=( $(compgen -W "$permission_modes" -- "$cur") )
            return 0
            ;;
        --effort)
            COMPREPLY=( $(compgen -W "$effort_levels" -- "$cur") )
            return 0
            ;;
        --output-format)
            COMPREPLY=( $(compgen -W "$output_formats" -- "$cur") )
            return 0
            ;;
        --input-format)
            COMPREPLY=( $(compgen -W "$input_formats" -- "$cur") )
            return 0
            ;;
        --teammate-mode)
            COMPREPLY=( $(compgen -W "$teammate_modes" -- "$cur") )
            return 0
            ;;
        --setting-sources)
            # Comma-separated; offer the three values, user post-processes
            COMPREPLY=( $(compgen -W "$setting_sources" -- "$cur") )
            return 0
            ;;
        --add-dir|--plugin-dir|--worktree|-w)
            _filedir -d
            return 0
            ;;
        --settings|--mcp-config|--system-prompt-file|--append-system-prompt-file|--debug-file)
            _filedir
            return 0
            ;;
        --agents|--system-prompt|--append-system-prompt|--betas|--name|-n|\
--session-id|--from-pr|--max-turns|--max-budget-usd|--allowedTools|\
--disallowedTools|--tools|--agent|--debug|--channels|--json-schema|\
--permission-prompt-tool|--remote|--remote-control-session-name-prefix)
            # Free-form values; no completion
            return 0
            ;;
    esac

    # ---- Subcommand-specific completion ----
    case "$subcommand" in
        auth)
            # Complete the auth subcommand and its flags
            local auth_flags="--email --sso --console --text"
            local auth_sub=""
            for ((i=1; i < cword; i++)); do
                case "${words[i]}" in
                    login|logout|status) auth_sub="${words[i]}"; break ;;
                esac
            done
            if [[ -z "$auth_sub" ]]; then
                COMPREPLY=( $(compgen -W "$auth_subs" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "$auth_flags" -- "$cur") )
            fi
            return 0
            ;;
        auto-mode)
            COMPREPLY=( $(compgen -W "$auto_mode_subs" -- "$cur") )
            return 0
            ;;
        mcp)
            local mcp_sub=""
            for ((i=1; i < cword; i++)); do
                case "${words[i]}" in
                    add|remove|list|get|serve|add-json|add-from-claude-desktop|reset-project-choices)
                        mcp_sub="${words[i]}"; break ;;
                esac
            done
            if [[ -z "$mcp_sub" ]]; then
                COMPREPLY=( $(compgen -W "$mcp_subs" -- "$cur") )
            fi
            return 0
            ;;
        plugin|plugins)
            local plug_sub=""
            for ((i=1; i < cword; i++)); do
                case "${words[i]}" in
                    install|uninstall|list|update|enable|disable|marketplace)
                        plug_sub="${words[i]}"; break ;;
                esac
            done
            if [[ -z "$plug_sub" ]]; then
                COMPREPLY=( $(compgen -W "$plugin_subs" -- "$cur") )
            fi
            return 0
            ;;
        install)
            # Only complete version once
            if [[ "$cur" != -* ]]; then
                COMPREPLY=( $(compgen -W "$install_versions" -- "$cur") )
            fi
            return 0
            ;;
        ultrareview)
            local ur_flags="--json --timeout"
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "$ur_flags" -- "$cur") )
            fi
            return 0
            ;;
        remote-control)
            local rc_flags="--name --remote-control-session-name-prefix"
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "$rc_flags $global_flags" -- "$cur") )
            fi
            return 0
            ;;
        update|agents|setup-token)
            # No subcommand args; allow flags only
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "$global_flags" -- "$cur") )
            fi
            return 0
            ;;
    esac

    # ---- No active subcommand: complete subcommands + flags ----
    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$global_flags" -- "$cur") )
    elif [[ $cword -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$subcommands" -- "$cur") )
    fi
    return 0
}

complete -F _claude_completion claude
