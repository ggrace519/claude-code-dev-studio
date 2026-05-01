# Shell completion for the `claude` CLI

Tab-completion for the [Claude Code](https://code.claude.com) command-line tool — subcommands, global flags, and enum values like `--model`, `--permission-mode`, `--effort`, `--output-format`, etc.

> These scripts are **independent of the Claude Code Dev Studio playbook**. Install them only if you want shell completion; nothing else in this repo depends on them.

```
claude_auto_completion/
├── Linux/                           # bash, also works in WSL and macOS bash
│   ├── claude-completion.bash       # the completion definitions
│   └── claude-autocomplete.sh       # installer (per-user or system-wide)
└── Windows/                         # PowerShell 5.1 and 7+
    ├── claude-completion.ps1        # the argument completer
    └── install-claude-completion.ps1 # installer (per-user)
```

---

## Linux / macOS / WSL (bash)

### Install (per-user, recommended)

```bash
cd claude_auto_completion/Linux
./claude-autocomplete.sh
```

This copies `claude-completion.bash` to `~/.local/share/bash-completion/completions/claude` (respecting `$XDG_DATA_HOME` if set).

### Install (system-wide)

```bash
cd claude_auto_completion/Linux
sudo ./claude-autocomplete.sh --system
```

This installs to `/etc/bash_completion.d/claude` and is picked up by every user on the host.

### Activate

Open a new shell, or source the file in the current one:

```bash
source ~/.local/share/bash-completion/completions/claude   # per-user
# or
source /etc/bash_completion.d/claude                       # system-wide
```

Then try:

```bash
claude --<TAB>
claude auth <TAB>
claude --model <TAB>
```

### Prerequisites

- `bash` 4+
- The `bash-completion` package, providing `_init_completion`:
  - Debian / Ubuntu: `sudo apt install bash-completion`
  - Fedora / RHEL: `sudo dnf install bash-completion`
  - macOS (Homebrew): `brew install bash-completion@2` and follow its post-install instructions
- If your `~/.bashrc` doesn't already load bash-completion, add:
  ```bash
  [[ -r /usr/share/bash-completion/bash_completion ]] && . /usr/share/bash-completion/bash_completion
  ```

The installer prints a reminder if it detects bash-completion is missing or not loaded.

### Uninstall

```bash
rm ~/.local/share/bash-completion/completions/claude          # per-user
sudo rm /etc/bash_completion.d/claude                         # system-wide
```

---

## Windows (PowerShell 5.1 / 7+)

### Install

From a PowerShell prompt:

```powershell
cd claude_auto_completion\Windows
. .\install-claude-completion.ps1
```

The installer:

1. Copies `claude-completion.ps1` to `<profile-dir>\completions\claude-completion.ps1` next to your `CurrentUserAllHosts` profile.
2. Adds a marker-bounded loader block to `$PROFILE.CurrentUserAllHosts` so the completer is picked up by **every host** — `pwsh`, `powershell.exe`, ISE, the VS Code PowerShell extension, etc.
3. Dot-sources the completer into the current session, so you can use it immediately.

Use `-Force` to overwrite an existing copy:

```powershell
. .\install-claude-completion.ps1 -Force
```

### Activate

The installer activates the completer in the current session. For new sessions, the profile loads it automatically. If your execution policy blocks profile scripts, either fix the policy:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

…or dot-source the script manually in each session:

```powershell
. $env:USERPROFILE\Documents\PowerShell\completions\claude-completion.ps1
```

Then try:

```powershell
claude --<TAB>
claude auth <TAB>
claude --model <TAB>
```

### Uninstall

```powershell
$dest = Join-Path (Split-Path -Parent $PROFILE.CurrentUserAllHosts) 'completions\claude-completion.ps1'
Remove-Item -LiteralPath $dest -ErrorAction SilentlyContinue

# Strip the loader block from the profile (between the markers)
$profilePath = $PROFILE.CurrentUserAllHosts
if (Test-Path $profilePath) {
    $content = Get-Content -LiteralPath $profilePath -Raw
    $cleaned = [regex]::Replace($content, "(?s)\r?\n?# >>> claude-completion >>>.*?# <<< claude-completion <<<\r?\n?", '')
    [System.IO.File]::WriteAllText($profilePath, $cleaned, [System.Text.UTF8Encoding]::new($false))
}
```

---

## What gets completed

Both scripts cover the same surface area:

| Position | Completion |
|---|---|
| First positional after `claude` | Subcommands: `update`, `install`, `auth`, `agents`, `auto-mode`, `mcp`, `plugin`/`plugins`, `remote-control`, `setup-token`, `ultrareview` |
| `claude auth <TAB>` | `login`, `logout`, `status` |
| `claude mcp <TAB>` | `add`, `remove`, `list`, `get`, `serve`, `add-json`, `add-from-claude-desktop`, `reset-project-choices` |
| `claude plugin <TAB>` | `install`, `uninstall`, `list`, `update`, `enable`, `disable`, `marketplace` |
| `claude install <TAB>` | `stable`, `latest` |
| Any `--<TAB>` | All documented top-level flags |
| `--model` / `--fallback-model` | `sonnet`, `opus`, `haiku`, plus pinned versions like `claude-sonnet-4-7` |
| `--permission-mode` | `default`, `acceptEdits`, `plan`, `auto`, `dontAsk`, `bypassPermissions` |
| `--effort` | `low`, `medium`, `high`, `xhigh`, `max` |
| `--output-format` | `text`, `json`, `stream-json` |
| `--input-format` | `text`, `stream-json` |
| `--teammate-mode` | `auto`, `in-process`, `tmux` |
| `--setting-sources` | `user`, `project`, `local` |
| `--add-dir`, `--plugin-dir`, `--worktree`, `-w` | Directory completion |
| `--settings`, `--mcp-config`, `--system-prompt-file`, `--append-system-prompt-file`, `--debug-file` | File completion |

The catalog tracks the public CLI reference at <https://code.claude.com/docs/en/cli-reference>. If a future Claude Code release adds new subcommands or flags, update the arrays in both scripts to match.

---

## Troubleshooting

**`claude --<TAB>` doesn't expand on Linux**
- Confirm bash-completion is loaded: `type _init_completion` should print a function.
- Confirm the file is in place: `ls ~/.local/share/bash-completion/completions/claude`.
- Open a fresh shell — the installer doesn't reload the current shell.

**Completion expands subcommands but not flags / values**
- Some shells run an older bash. Verify with `bash --version` (need 4+).
- macOS ships bash 3.2 by default — install bash 4+ via Homebrew or use the bash-completion@2 package.

**PowerShell completer doesn't fire**
- Check the loader block exists: `Select-String '# >>> claude-completion >>>' $PROFILE.CurrentUserAllHosts`
- Check execution policy: `Get-ExecutionPolicy -Scope CurrentUser` — if it's `Restricted`, profile scripts won't run.
- Confirm the completer is registered: `Get-PSReadlineKeyHandler` and try `claude <TAB>` after `Register-ArgumentCompleter` has run.

**I want completions for a specific Claude Code version**
- The flag and subcommand lists are static. Pull the latest CLI reference and edit the arrays at the top of `claude-completion.bash` / `claude-completion.ps1`.
