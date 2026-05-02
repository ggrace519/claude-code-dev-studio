#!/usr/bin/env bash
# ccds-completion.bash
# Bash/Zsh argument completion for the ccds CLI (Claude Code Dev Studio)
#
# Install (per-user, bash — auto-loaded on next shell start):
#   mkdir -p ~/.local/share/bash-completion/completions
#   cp ccds-completion.bash ~/.local/share/bash-completion/completions/ccds
#
# Install (system-wide, requires root):
#   sudo cp ccds-completion.bash /etc/bash_completion.d/ccds
#
# Or source it directly in your shell profile:
#   . /path/to/ccds-completion.bash

_ccds_completion() {
    local cur prev words cword
    _init_completion -n = 2>/dev/null || {
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        words=("${COMP_WORDS[@]}")
        cword=$COMP_CWORD
    }

    local commands="sync verify update uninstall version help"
    local packs="game saas mobile ai dataplat ecom fintech devtool desktop ext embed media orch infra common"
    local sync_flags="--dry-run --write-adr --no-generalists --mode --target --help -h"
    local update_flags="--rollback --include-prerelease --dry-run --help -h"
    local global_flags="--help -h"
    local modes="copy symlink"

    # Detect active command (first non-flag token after 'ccds')
    local command=""
    local i
    for ((i=1; i < cword; i++)); do
        case "${words[i]}" in
            sync|verify|update|uninstall|version|help)
                command="${words[i]}"
                break
                ;;
        esac
    done

    # Value completions for flags that consume the next token
    case "$prev" in
        --mode)
            mapfile -t COMPREPLY < <(compgen -W "$modes" -- "$cur")
            return 0
            ;;
        --target)
            _filedir -d 2>/dev/null || mapfile -t COMPREPLY < <(compgen -d -- "$cur")
            return 0
            ;;
    esac

    case "$command" in
        sync)
            if [[ "$cur" == -* ]]; then
                mapfile -t COMPREPLY < <(compgen -W "$sync_flags" -- "$cur")
                return 0
            fi
            # Pack completion.  Handles comma-separated tokens ("saas,common"):
            # complete after the last comma so "saas,<TAB>" offers remaining packs.
            local prefix="" word="$cur"
            if [[ "$cur" == *,* ]]; then
                prefix="${cur%,*},"
                word="${cur##*,}"
            fi
            # Collect packs already used in prior tokens and in the comma prefix
            local used=""
            for ((i=1; i < cword; i++)); do
                if [[ "${words[i]}" != -* ]]; then
                    used="$used ${words[i]//,/ }"
                fi
            done
            [[ -n "$prefix" ]] && used="$used ${prefix%,}"
            # Offer packs not already used, prepending the typed prefix
            mapfile -t COMPREPLY < <(
                for p in $packs; do
                    [[ " $used " == *" $p "* ]] && continue
                    [[ "$p" == "$word"* ]] && echo "${prefix}${p}"
                done
            )
            return 0
            ;;
        update)
            if [[ "$cur" == -* ]]; then
                mapfile -t COMPREPLY < <(compgen -W "$update_flags" -- "$cur")
            fi
            return 0
            ;;
        verify|uninstall|version|help)
            mapfile -t COMPREPLY < <(compgen -W "$global_flags" -- "$cur")
            return 0
            ;;
    esac

    # No command yet: offer commands or global flags
    if [[ "$cur" == -* ]]; then
        mapfile -t COMPREPLY < <(compgen -W "$global_flags" -- "$cur")
    elif [[ $cword -eq 1 ]]; then
        mapfile -t COMPREPLY < <(compgen -W "$commands" -- "$cur")
    fi
    return 0
}

complete -F _ccds_completion ccds
