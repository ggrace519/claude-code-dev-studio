#!/usr/bin/env bash
# install-playbook.sh -- Install / update / rollback / uninstall claude-playbook
#                        from GitHub Releases (Linux / macOS).
#
# Installed layout:
#   $PREFIX/
#     bin/                 (dispatcher)
#     scripts/             (Sync-AgentPacks, Verify-Agents, both PS and sh)
#     .claude/agents/      (agent library)
#     CLAUDE.md
#     README.md
#     version.txt
#
# Atomic upgrade:
#   1. Stage to $PREFIX.new
#   2. If $PREFIX exists: remove $PREFIX.previous, move $PREFIX -> $PREFIX.previous
#   3. Move $PREFIX.new -> $PREFIX
#
# Rollback restores $PREFIX.previous in place of $PREFIX.
#
# Usage:
#   install-playbook.sh [options]
#
# Options:
#   --version <tag>           Release tag to install (default: latest)
#   --prefix <path>           Install root (default: $HOME/.local/share/claude-playbook)
#   --local-zip <file>        Install from a locally built ZIP instead of downloading
#   --token <pat>             GitHub PAT for private-repo downloads (or $GITHUB_TOKEN)
#   --no-path                 Skip shell-rc PATH update
#   --include-prerelease      When resolving 'latest', include prereleases
#   --dry-run                 Show actions without changing the filesystem
#   --force                   Overwrite existing install without confirmation
#   --rollback                Restore $PREFIX from $PREFIX.previous
#   --uninstall               Remove $PREFIX and the PATH block
#   -h, --help                Show this help
#
# Examples:
#   curl -fsSL https://raw.githubusercontent.com/ggrace519/claude-code-dev-studio/main/install-playbook.sh | bash
#   ./install-playbook.sh --version v0.4.0
#   ./install-playbook.sh --local-zip ./dist/claude-playbook-v0.4.0-rc1.zip
#   ./install-playbook.sh --rollback
#   ./install-playbook.sh --uninstall

set -euo pipefail

OWNER="ggrace519"
REPO="claude-code-dev-studio"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
VERSION="latest"
PREFIX="${HOME}/.local/share/claude-playbook"
LOCAL_ZIP=""
TOKEN=""
NO_PATH=0
INCLUDE_PRERELEASE=0
DRY_RUN=0
FORCE=0
MODE="install"   # install | rollback | uninstall

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RESET=$'\033[0m'
else
    C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RESET=""
fi
log_step()  { printf '%s==> %s%s\n' "$C_CYAN" "$*" "$C_RESET"; }
log_info()  { printf '    %s\n' "$*"; }
log_ok()    { printf '%sOK  %s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
log_warn()  { printf '%s!!  %s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }
die()       { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
show_help() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; }

while (( $# > 0 )); do
    case "$1" in
        --version)           [[ -n "${2:-}" ]] || die "--version requires a value"; VERSION="$2"; shift 2 ;;
        --prefix)            [[ -n "${2:-}" ]] || die "--prefix requires a path"; PREFIX="$2"; shift 2 ;;
        --local-zip)         [[ -n "${2:-}" ]] || die "--local-zip requires a path"; LOCAL_ZIP="$2"; shift 2 ;;
        --token)             [[ -n "${2:-}" ]] || die "--token requires a value"; TOKEN="$2"; shift 2 ;;
        --no-path)           NO_PATH=1; shift ;;
        --include-prerelease) INCLUDE_PRERELEASE=1; shift ;;
        --dry-run)           DRY_RUN=1; shift ;;
        --force)             FORCE=1; shift ;;
        --rollback)          MODE="rollback"; shift ;;
        --uninstall)         MODE="uninstall"; shift ;;
        -h|--help)           show_help; exit 0 ;;
        *)                   die "Unknown argument: $1" ;;
    esac
done

# Expand ~ in PREFIX if passed as literal
PREFIX="${PREFIX/#\~/$HOME}"

# Effective token (arg wins over env)
if [[ -z "$TOKEN" && -n "${GITHUB_TOKEN:-}" ]]; then
    TOKEN="$GITHUB_TOKEN"
fi

# ---------------------------------------------------------------------------
# Required tools
# ---------------------------------------------------------------------------
need() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
need curl
need unzip

if command -v sha256sum >/dev/null 2>&1; then
    SHA256_CMD="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
    SHA256_CMD="shasum -a 256"
else
    die "Neither sha256sum nor shasum is available."
fi

# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------
curl_auth_args() {
    local -a args=(-fsSL -H "User-Agent: claude-playbook-installer")
    if [[ -n "$TOKEN" ]]; then
        args+=(-H "Authorization: Bearer $TOKEN")
    fi
    printf '%s\n' "${args[@]}"
}

http_api() {
    # Usage: http_api <url>  -> writes JSON to stdout
    local url="$1"
    local -a auth
    mapfile -t auth < <(curl_auth_args) 2>/dev/null || {
        # bash 3.2 fallback: read line-by-line
        auth=()
        while IFS= read -r line; do auth+=("$line"); done < <(curl_auth_args)
    }
    if ! curl "${auth[@]}" "$url"; then
        die "GitHub API request failed: $url (if repo is private, set GITHUB_TOKEN or use --token)"
    fi
}

http_download() {
    # Usage: http_download <url> <outfile>
    local url="$1" outfile="$2"
    local -a auth=()
    while IFS= read -r line; do auth+=("$line"); done < <(curl_auth_args)
    auth+=(-H "Accept: application/octet-stream")
    if ! curl "${auth[@]}" -o "$outfile" "$url"; then
        die "Download failed: $url"
    fi
}

# ---------------------------------------------------------------------------
# JSON extraction (no jq dependency)
# ---------------------------------------------------------------------------
# Extract a top-level string field value: json_get_string <json> <field>
json_get_string() {
    local json="$1" field="$2"
    # Matches "field": "value" at the first occurrence.
    printf '%s' "$json" | grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
        | head -n1 \
        | sed -E "s/\"$field\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"/\1/"
}

# Given the full release JSON and an asset name, return that asset's API url.
# Uses awk to find the asset object with matching name and extract "url".
asset_api_url() {
    local json="$1" name="$2"
    printf '%s' "$json" | awk -v name="$name" '
        BEGIN { RS="{"; FS="\n" }
        {
            if (index($0, "\"name\": \"" name "\"") > 0 || index($0, "\"name\":\"" name "\"") > 0) {
                match($0, /"url"[[:space:]]*:[[:space:]]*"[^"]+"/)
                if (RSTART > 0) {
                    chunk = substr($0, RSTART, RLENGTH)
                    sub(/^"url"[[:space:]]*:[[:space:]]*"/, "", chunk)
                    sub(/"$/, "", chunk)
                    print chunk
                    exit
                }
            }
        }
    '
}

# ---------------------------------------------------------------------------
# Release resolution
# ---------------------------------------------------------------------------
resolve_release_tag() {
    if [[ "$VERSION" != "latest" ]]; then
        printf '%s\n' "$VERSION"
        return
    fi

    if (( INCLUDE_PRERELEASE )); then
        local json
        json="$(http_api "https://api.github.com/repos/$OWNER/$REPO/releases")"
        # First occurrence of "tag_name" is the newest release.
        local tag
        tag="$(json_get_string "$json" "tag_name")"
        [[ -n "$tag" ]] || die "No releases found for $OWNER/$REPO."
        printf '%s\n' "$tag"
    else
        local json
        json="$(http_api "https://api.github.com/repos/$OWNER/$REPO/releases/latest")"
        local tag
        tag="$(json_get_string "$json" "tag_name")"
        [[ -n "$tag" ]] || die "No latest stable release for $OWNER/$REPO."
        printf '%s\n' "$tag"
    fi
}

# Populates ASSET_ZIP_URL and ASSET_SHA_URL globals.
lookup_release_assets() {
    local tag="$1"
    local zip_name="claude-playbook-$tag.zip"
    local sha_name="$zip_name.sha256"
    local json
    json="$(http_api "https://api.github.com/repos/$OWNER/$REPO/releases/tags/$tag")"

    ASSET_ZIP_NAME="$zip_name"
    ASSET_SHA_NAME="$sha_name"
    ASSET_ZIP_URL="$(asset_api_url "$json" "$zip_name")"
    ASSET_SHA_URL="$(asset_api_url "$json" "$sha_name")"

    [[ -n "$ASSET_ZIP_URL" ]] || die "Asset '$zip_name' not found on release $tag."
    [[ -n "$ASSET_SHA_URL" ]] || die "Asset '$sha_name' not found on release $tag."
}

# ---------------------------------------------------------------------------
# SHA256 verification
# ---------------------------------------------------------------------------
verify_sha256() {
    local zip_path="$1" sidecar_path="$2"
    local recorded actual
    recorded="$(awk '{print tolower($1); exit}' "$sidecar_path")"
    actual="$($SHA256_CMD "$zip_path" | awk '{print tolower($1); exit}')"
    if [[ "$recorded" != "$actual" ]]; then
        die "SHA256 mismatch. Recorded=$recorded Actual=$actual File=$zip_path"
    fi
    printf '%s\n' "$actual"
}

# ---------------------------------------------------------------------------
# Shell-rc PATH management
# ---------------------------------------------------------------------------
PATH_MARKER_BEGIN="# >>> claude-playbook PATH >>>"
PATH_MARKER_END="# <<< claude-playbook PATH <<<"

rc_targets() {
    # Emit one rc file per line. Only existing OR sensible-to-create files.
    local -a candidates=()
    case "${SHELL:-}" in
        */zsh)  candidates+=("$HOME/.zshrc") ;;
        */bash) candidates+=("$HOME/.bashrc") ;;
    esac
    # Always cover bash + zsh + profile if they exist, even if SHELL differs.
    [[ -f "$HOME/.bashrc"  ]] && candidates+=("$HOME/.bashrc")
    [[ -f "$HOME/.zshrc"   ]] && candidates+=("$HOME/.zshrc")
    [[ -f "$HOME/.profile" ]] && candidates+=("$HOME/.profile")
    # Deduplicate while preserving order
    local seen="" f
    for f in "${candidates[@]}"; do
        case ":$seen:" in *":$f:"*) ;; *) printf '%s\n' "$f"; seen="$seen:$f" ;; esac
    done
}

add_to_path_rc() {
    local bin_dir="$1"
    local block
    block=$'\n'"$PATH_MARKER_BEGIN"$'\n'"export PATH=\"$bin_dir:\$PATH\""$'\n'"$PATH_MARKER_END"$'\n'

    local rc updated=0
    while IFS= read -r rc; do
        [[ -z "$rc" ]] && continue
        if [[ ! -e "$rc" ]]; then
            touch "$rc"
        fi
        if grep -qF "$PATH_MARKER_BEGIN" "$rc"; then
            # Replace existing block in place via temp file (portable sed).
            local tmp
            tmp="$(mktemp)"
            awk -v b="$PATH_MARKER_BEGIN" -v e="$PATH_MARKER_END" -v bin="$bin_dir" '
                BEGIN { in_block=0 }
                $0 == b { in_block=1; print; print "export PATH=\"" bin ":$PATH\""; next }
                $0 == e { in_block=0; print; next }
                in_block == 1 { next }
                { print }
            ' "$rc" > "$tmp"
            mv "$tmp" "$rc"
            log_info "Refreshed claude-playbook PATH block in $rc"
        else
            printf '%s' "$block" >> "$rc"
            log_ok "Added claude-playbook PATH block to $rc"
        fi
        updated=1
    done < <(rc_targets)

    if (( updated == 0 )); then
        log_warn "No shell rc files found. Add '$bin_dir' to PATH manually."
    fi

    # Make it usable in the current process too.
    case ":$PATH:" in
        *":$bin_dir:"*) ;;
        *) export PATH="$bin_dir:$PATH" ;;
    esac
}

remove_path_rc() {
    local rc
    while IFS= read -r rc; do
        [[ -z "$rc" || ! -f "$rc" ]] && continue
        if grep -qF "$PATH_MARKER_BEGIN" "$rc"; then
            local tmp
            tmp="$(mktemp)"
            awk -v b="$PATH_MARKER_BEGIN" -v e="$PATH_MARKER_END" '
                BEGIN { in_block=0 }
                $0 == b { in_block=1; next }
                $0 == e { in_block=0; next }
                in_block == 1 { next }
                { print }
            ' "$rc" > "$tmp"
            mv "$tmp" "$rc"
            log_ok "Removed claude-playbook PATH block from $rc"
        fi
    done < <(rc_targets)
}

# ---------------------------------------------------------------------------
# Install / rollback / uninstall cores
# ---------------------------------------------------------------------------
install_from_zip() {
    local zip_path="$1"
    local new_dir="$PREFIX.new"
    local prev_dir="$PREFIX.previous"

    if [[ -d "$PREFIX" && $FORCE -eq 0 ]]; then
        local current_version="unknown"
        [[ -f "$PREFIX/version.txt" ]] && current_version="$(tr -d '[:space:]' < "$PREFIX/version.txt")"
        log_info "Existing install found at $PREFIX (version=$current_version). Will snapshot to $prev_dir."
    fi

    if (( DRY_RUN )); then
        log_step "DRY RUN -- would extract $zip_path to $new_dir"
        [[ -d "$PREFIX" ]] && log_info "DRY RUN -- would move $PREFIX -> $prev_dir (replacing any existing)"
        log_info "DRY RUN -- would move $new_dir -> $PREFIX"
        return
    fi

    [[ -d "$new_dir" ]] && rm -rf "$new_dir"
    mkdir -p "$new_dir"
    log_step "Extracting to $new_dir"
    unzip -q "$zip_path" -d "$new_dir"

    # Sanity: bin/claude-playbook.sh must exist in the extracted tree.
    local sentinel="$new_dir/bin/claude-playbook.sh"
    if [[ ! -f "$sentinel" ]]; then
        rm -rf "$new_dir"
        die "Extraction did not produce bin/claude-playbook.sh -- archive layout is unexpected."
    fi
    chmod +x "$new_dir/bin/claude-playbook.sh" 2>/dev/null || true
    # Make all *.sh under scripts/ executable too
    find "$new_dir/scripts" -maxdepth 1 -name '*.sh' -type f -exec chmod +x {} + 2>/dev/null || true

    # Create bare 'claude-playbook' symlink for PATH resolution.
    ln -sf "claude-playbook.sh" "$new_dir/bin/claude-playbook"

    if [[ -d "$PREFIX" ]]; then
        if [[ -d "$prev_dir" ]]; then
            log_info "Removing stale snapshot: $prev_dir"
            rm -rf "$prev_dir"
        fi
        log_step "Snapshotting current install to $prev_dir"
        mv "$PREFIX" "$prev_dir"
    fi

    log_step "Promoting $new_dir to $PREFIX"
    mv "$new_dir" "$PREFIX"
}

do_rollback() {
    local prev_dir="$PREFIX.previous"
    [[ -d "$prev_dir" ]] || die "No previous install at $prev_dir. Nothing to roll back."

    if (( DRY_RUN )); then
        log_step "DRY RUN -- would restore $prev_dir to $PREFIX"
        return
    fi

    local trash="$PREFIX.rollback-discard-$(date +%Y%m%d%H%M%S)"
    if [[ -d "$PREFIX" ]]; then
        log_step "Moving current $PREFIX -> $trash"
        mv "$PREFIX" "$trash"
    fi
    log_step "Restoring $prev_dir -> $PREFIX"
    mv "$prev_dir" "$PREFIX"
    if [[ -d "$trash" ]]; then
        log_step "Deleting discarded post-rollback tree: $trash"
        rm -rf "$trash"
    fi
    log_ok "Rollback complete."
}

do_uninstall() {
    local bin_dir="$PREFIX/bin"

    if (( DRY_RUN )); then
        [[ -d "$PREFIX" ]] && log_info "DRY RUN -- would remove $PREFIX"
        (( NO_PATH == 0 )) && log_info "DRY RUN -- would remove claude-playbook PATH block from shell rc files"
        return
    fi

    if [[ -d "$PREFIX" ]]; then
        log_step "Removing $PREFIX"
        rm -rf "$PREFIX"
        log_ok "Removed install directory."
    else
        log_warn "$PREFIX does not exist; nothing to remove on disk."
    fi

    if (( NO_PATH == 0 )); then
        remove_path_rc
    fi
}

# ---------------------------------------------------------------------------
# Main dispatch
# ---------------------------------------------------------------------------
case "$MODE" in
    rollback)
        do_rollback
        exit 0
        ;;
    uninstall)
        do_uninstall
        exit 0
        ;;
esac

# --- Install path ---
TMPDIR_INST=""
cleanup() {
    if [[ -n "$TMPDIR_INST" && -d "$TMPDIR_INST" ]]; then
        rm -rf "$TMPDIR_INST"
    fi
}
trap cleanup EXIT

if [[ -n "$LOCAL_ZIP" ]]; then
    [[ -f "$LOCAL_ZIP" ]] || die "LocalZip not found: $LOCAL_ZIP"
    ZIP_PATH="$(cd "$(dirname "$LOCAL_ZIP")" && pwd)/$(basename "$LOCAL_ZIP")"
    SIDECAR="$ZIP_PATH.sha256"
    if [[ -f "$SIDECAR" ]]; then
        hash="$(verify_sha256 "$ZIP_PATH" "$SIDECAR")"
        log_ok "Local ZIP SHA256 verified: $hash"
    else
        log_warn "No sidecar at $SIDECAR -- skipping hash verification."
    fi
    RESOLVED_TAG="local"
else
    log_step "Resolving release tag (requested: $VERSION)"
    RESOLVED_TAG="$(resolve_release_tag)"
    log_info "Tag: $RESOLVED_TAG"

    log_step "Looking up release assets for $RESOLVED_TAG"
    lookup_release_assets "$RESOLVED_TAG"

    TMPDIR_INST="$(mktemp -d -t cp-install.XXXXXXXX)"
    ZIP_PATH="$TMPDIR_INST/$ASSET_ZIP_NAME"
    SHA_PATH="$TMPDIR_INST/$ASSET_SHA_NAME"

    log_step "Downloading $ASSET_ZIP_NAME"
    http_download "$ASSET_ZIP_URL" "$ZIP_PATH"
    log_step "Downloading $ASSET_SHA_NAME"
    http_download "$ASSET_SHA_URL" "$SHA_PATH"

    hash="$(verify_sha256 "$ZIP_PATH" "$SHA_PATH")"
    log_ok "Downloaded ZIP SHA256 verified: $hash"
fi

install_from_zip "$ZIP_PATH"

if (( DRY_RUN )); then
    log_step "DRY RUN -- no changes made."
    exit 0
fi

INSTALLED_VERSION="$RESOLVED_TAG"
if [[ -f "$PREFIX/version.txt" ]]; then
    INSTALLED_VERSION="$(tr -d '[:space:]' < "$PREFIX/version.txt")"
fi

if (( NO_PATH == 0 )); then
    add_to_path_rc "$PREFIX/bin"
fi

printf '\n'
printf '%s=== claude-playbook installed ===%s\n' "$C_GREEN" "$C_RESET"
printf 'Prefix  : %s\n' "$PREFIX"
printf 'Version : %s\n' "$INSTALLED_VERSION"
if (( NO_PATH == 0 )); then
    printf 'PATH    : %s (added to shell rc files)\n' "$PREFIX/bin"
    printf '\n'
    printf '%sCurrent session: PATH updated for this process.%s\n' "$C_YELLOW" "$C_RESET"
    printf '%sNew shells     : rc files will pick up PATH automatically.%s\n' "$C_YELLOW" "$C_RESET"
fi
printf '\n'
printf '%sSmoke test:%s\n' "$C_YELLOW" "$C_RESET"
printf '  claude-playbook version\n'
printf '  cd <your-project>\n'
printf '  claude-playbook sync saas,common --dry-run\n'
