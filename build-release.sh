#!/usr/bin/env bash
# build-release.sh -- Build Claude Code Dev Studio Linux packages (.deb + .rpm).
# Requires: fpm (gem install fpm), rpmbuild (for .rpm)
# Usage: ./build-release.sh --version v0.5.0 [--output-dir dist] [--skip-rpm]

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VERSION=""; OUTPUT_DIR="$REPO_ROOT/dist"; SKIP_RPM=0; KEEP_STAGE=0

while (( $# > 0 )); do
    case "$1" in
        --version)    VERSION="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --skip-rpm)   SKIP_RPM=1; shift ;;
        --keep-stage) KEEP_STAGE=1; shift ;;
        -h|--help) echo "Usage: $0 --version vX.Y.Z [--output-dir dist] [--skip-rpm]"; exit 0 ;;
        *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
    esac
done

[[ -n "$VERSION" ]] || { echo "ERROR: --version is required" >&2; exit 1; }
VERSION_BARE="${VERSION#v}"

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
echo "==> Checking prerequisites"
command -v fpm >/dev/null 2>&1 || { echo "ERROR: fpm not found. Install: gem install fpm" >&2; exit 1; }
if (( SKIP_RPM == 0 )); then
    command -v rpmbuild >/dev/null 2>&1 || {
        echo "WARN: rpmbuild not found -- skipping .rpm (pass --skip-rpm to suppress)" >&2
        SKIP_RPM=1
    }
fi

REQUIRED_SOURCES=( ".claude/agents" "catalog.json" "scripts/jit-claude.md"
    "scripts/ccds-user-setup.sh" "Sync-AgentPacks.sh" "verify-agents.sh"
    "bin/ccds.sh" "bin/ccds.ps1" "README.md" "packaging/postinst" "packaging/prerm" )
missing=()
for src in "${REQUIRED_SOURCES[@]}"; do [[ -e "$REPO_ROOT/$src" ]] || missing+=("$src"); done
(( ${#missing[@]} == 0 )) || { echo "ERROR: Missing: ${missing[*]}" >&2; exit 1; }

AGENT_COUNT=$(find "$REPO_ROOT/.claude/agents" -maxdepth 1 -name '*.md' | wc -l)
echo "    Found $AGENT_COUNT agent files"

# ---------------------------------------------------------------------------
# Stage
# ---------------------------------------------------------------------------
STAGE_DIR="$(mktemp -d -t ccds-pkg-stage.XXXXXXXX)"
(( KEEP_STAGE == 1 )) || trap 'rm -rf "$STAGE_DIR"' EXIT

PKG_ROOT="$STAGE_DIR/usr/share/ccds"
BIN_ROOT="$STAGE_DIR/usr/bin"
mkdir -p "$PKG_ROOT/agents" "$PKG_ROOT/scripts" "$PKG_ROOT/bin" "$BIN_ROOT"

echo "==> Staging files to $PKG_ROOT"
cp "$REPO_ROOT/.claude/agents/"*.md       "$PKG_ROOT/agents/"
cp "$REPO_ROOT/scripts/jit-claude.md"      "$PKG_ROOT/scripts/"
cp "$REPO_ROOT/scripts/ccds-user-setup.sh" "$PKG_ROOT/scripts/"
cp "$REPO_ROOT/Sync-AgentPacks.sh"         "$PKG_ROOT/scripts/Sync-AgentPacks.sh"
cp "$REPO_ROOT/verify-agents.sh"           "$PKG_ROOT/scripts/verify-agents.sh"
chmod 755 "$PKG_ROOT/scripts/"*.sh
cp "$REPO_ROOT/bin/ccds.sh"  "$PKG_ROOT/bin/"
cp "$REPO_ROOT/bin/ccds.ps1" "$PKG_ROOT/bin/"
chmod 755 "$PKG_ROOT/bin/ccds.sh"
cp "$REPO_ROOT/catalog.json" "$PKG_ROOT/"
cp "$REPO_ROOT/README.md"    "$PKG_ROOT/"
printf '%s\n' "$VERSION" > "$PKG_ROOT/version.txt"
ln -sf "../share/ccds/bin/ccds.sh" "$BIN_ROOT/ccds"

# Normalize line endings: strip \r so scripts edited on Windows work on Linux.
echo "==> Normalizing line endings (LF)"
find "$STAGE_DIR" -type f \( -name '*.sh' -o -name '*.md' \) \
    -exec sed -i 's/\r$//' {} +
# postinst/prerm are copied into the package by fpm from the source dir;
# normalize them at source so fpm picks up the clean versions.
sed -i 's/\r$//' "$REPO_ROOT/packaging/postinst" \
                 "$REPO_ROOT/packaging/prerm"

echo "==> Stage complete: $(find "$STAGE_DIR" -type f | wc -l) files"

# ---------------------------------------------------------------------------
# fpm flags -- ALL flags must precede the positional path argument
# ---------------------------------------------------------------------------
mkdir -p "$OUTPUT_DIR"

DESC="Claude Code Dev Studio - archetype-aware agent packs for Claude Code CLI"
FPM_FLAGS=(
    -s dir -C "$STAGE_DIR"
    --name "ccds" --version "$VERSION_BARE" --iteration "1"
    --architecture "all"
    --description "$DESC"
    --url "https://github.com/ggrace519/claude-code-dev-studio"
    --license "PolyForm-Noncommercial-1.0.0"
    --maintainer "Greg Grace <ggrace@519lab.com>"
    --vendor "Onward Investment LLC"
    --after-install  "$REPO_ROOT/packaging/postinst"
    --before-remove  "$REPO_ROOT/packaging/prerm"
    --package "$OUTPUT_DIR"
)

# Run fpm and return the path of the created package.
# Display output goes to stderr so it shows in terminal even when called with $().
# Only the package path is printed to stdout (captured by the caller).
fpm_build() {
    local out
    out=$(fpm "$@" 2>&1) || { printf '%s\n' "$out" | sed 's/^/    /' >&2; return 1; }
    printf '%s\n' "$out" | sed 's/^/    /' >&2
    printf '%s\n' "$out" | grep -oP '(?<=:path=>")[^"]+' | tail -1
}

# Ensure the package ended up at the expected path (rename if fpm added iteration suffix)
ensure_path() {
    local created="$1" want="$2" glob="$3"
    if [[ -n "$created" && -f "$created" && "$created" != "$want" ]]; then
        mv "$created" "$want"
    elif [[ -z "$created" || ! -f "$created" ]]; then
        local newest
        newest=$(ls -t $glob 2>/dev/null | head -1 || true)
        [[ -n "$newest" ]] || { echo "ERROR: package not found after fpm run" >&2; return 1; }
        [[ "$newest" == "$want" ]] || mv "$newest" "$want"
    fi
    [[ -f "$want" ]] || { echo "ERROR: expected package not found: $want" >&2; return 1; }
}

# ---------------------------------------------------------------------------
# Pre-build cleanup: remove any existing packages for this version so fpm
# does not refuse to run with "File already exists".
# ---------------------------------------------------------------------------
echo "==> Cleaning previous packages for $VERSION_BARE"
rm -f "$OUTPUT_DIR/ccds_${VERSION_BARE}"*.deb \
      "$OUTPUT_DIR/ccds-${VERSION_BARE}"*.rpm  2>/dev/null || true

# ---------------------------------------------------------------------------
# Build .deb
# ---------------------------------------------------------------------------
echo "==> Building .deb"
DEB_WANT="$OUTPUT_DIR/ccds_${VERSION_BARE}_all.deb"
CREATED_DEB=$(fpm_build "${FPM_FLAGS[@]}" -t deb --deb-no-default-config-files "usr/")
ensure_path "$CREATED_DEB" "$DEB_WANT" "$OUTPUT_DIR/ccds_*.deb"
echo "    => $DEB_WANT"

# ---------------------------------------------------------------------------
# Build .rpm
# ---------------------------------------------------------------------------
if (( SKIP_RPM == 0 )); then
    echo "==> Building .rpm"
    RPM_WANT="$OUTPUT_DIR/ccds-${VERSION_BARE}-1.noarch.rpm"
    CREATED_RPM=$(fpm_build "${FPM_FLAGS[@]}" -t rpm "usr/")
    ensure_path "$CREATED_RPM" "$RPM_WANT" "$OUTPUT_DIR/ccds-*.rpm"
    echo "    => $RPM_WANT"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=== Build summary ==="
echo "Version : $VERSION"
for f in "$OUTPUT_DIR"/ccds_*.deb "$OUTPUT_DIR"/ccds-*.rpm; do
    [[ -f "$f" ]] || continue
    SIZE=$(du -h "$f" | cut -f1)
    printf "  %-40s  %s\n" "$(basename "$f")" "$SIZE"
done
