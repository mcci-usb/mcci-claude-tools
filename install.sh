#!/bin/bash
# install.sh -- install mcci-claude-tools into ~/.claude/
#
# Run from the repo root directory:
#   ./install.sh
#
# What it does:
#   - Copies scripts/* to ~/.claude/scripts/
#   - Copies commands/* to ~/.claude/commands/
#   - Does NOT overwrite existing files unless -f is passed
#   - With --check, compares installed copies against repo (no changes made)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude"

FORCE=0
CHECK=0
for arg in "$@"; do
    case "$arg" in
        -f|--force) FORCE=1 ;;
        --check)    CHECK=1 ;;
    esac
done

# Build the installed content from a repo source file (to stdout).
transform_file() {
    local src="$1"
    printf '# INSTALLED FROM mcci-claude-tools -- do not edit this copy.\n'
    printf '# Original: %s\n' "$src"
    grep -v '^# ORIGINAL SOURCE --' "$src"
}

install_file() {
    local src="$1"
    local dest="$2"
    local name
    name="$(basename "$src")"

    if [ -f "$dest" ] && [ "$FORCE" -eq 0 ]; then
        echo "  SKIP $name (already exists; use -f to overwrite)"
        return
    fi

    transform_file "$src" > "$dest"
    echo "  OK   $name"
}

# Compare installed copy against repo source (ignoring line endings).
# Returns 0 if up to date, 1 if stale or missing.
check_file() {
    local src="$1"
    local dest="$2"
    local name
    name="$(basename "$src")"

    if [ ! -f "$dest" ]; then
        printf '  MISSING  %s\n' "$name"
        STALE=1
        return
    fi

    # Compare transformed repo content against installed copy.
    # Use tr to strip \r so CR/LF vs LF differences are ignored.
    local expected installed
    expected=$(transform_file "$src" | tr -d '\r')
    installed=$(tr -d '\r' < "$dest")

    if [ "$expected" = "$installed" ]; then
        printf '  OK       %s\n' "$name"
    else
        printf '  STALE    %s\n' "$name"
        STALE=1
    fi
}

# --check mode: compare and report, no writes
if [ "$CHECK" -eq 1 ]; then
    STALE=0
    printf 'Checking installed copies against %s ...\n' "$SCRIPT_DIR"

    printf '\nScripts -> %s/scripts/\n' "$DEST"
    for f in "$SCRIPT_DIR"/scripts/*; do
        [ -f "$f" ] && check_file "$f" "$DEST/scripts/$(basename "$f")"
    done

    printf '\nCommands -> %s/commands/\n' "$DEST"
    for f in "$SCRIPT_DIR"/commands/*; do
        [ -f "$f" ] && check_file "$f" "$DEST/commands/$(basename "$f")"
    done

    echo ""
    if [ "$STALE" -eq 1 ]; then
        echo "Some files are stale or missing. Run ./install.sh -f to update."
        exit 1
    else
        echo "All installed copies are up to date."
        exit 0
    fi
fi

# Check for uv
if ! command -v uv &>/dev/null; then
    echo "ERROR: 'uv' is required but not found."
    echo "Install it from https://docs.astral.sh/uv/getting-started/installation/"
    exit 1
fi

printf 'Installing mcci-claude-tools to %s ...\n' "$DEST"

# Scripts
printf '\nScripts -> %s/scripts/\n' "$DEST"
mkdir -p "$DEST/scripts"
for f in "$SCRIPT_DIR"/scripts/*; do
    [ -f "$f" ] && install_file "$f" "$DEST/scripts/$(basename "$f")"
done

# Commands (slash commands)
printf '\nCommands -> %s/commands/\n' "$DEST"
mkdir -p "$DEST/commands"
for f in "$SCRIPT_DIR"/commands/*; do
    [ -f "$f" ] && install_file "$f" "$DEST/commands/$(basename "$f")"
done

echo ""
echo "Done. Restart Claude Code to pick up new slash commands."
