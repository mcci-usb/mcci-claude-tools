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

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude"

FORCE=0
if [ "$1" = "-f" ] || [ "$1" = "--force" ]; then
    FORCE=1
fi

install_file() {
    local src="$1"
    local dest="$2"
    local name
    name="$(basename "$src")"

    if [ -f "$dest" ] && [ "$FORCE" -eq 0 ]; then
        echo "  SKIP $name (already exists; use -f to overwrite)"
        return
    fi

    cp "$src" "$dest"
    echo "  OK   $name"
}

echo "Installing mcci-claude-tools to $DEST ..."

# Scripts
echo ""
echo "Scripts -> $DEST/scripts/"
mkdir -p "$DEST/scripts"
for f in "$SCRIPT_DIR"/scripts/*; do
    [ -f "$f" ] && install_file "$f" "$DEST/scripts/$(basename "$f")"
done

# Commands (slash commands)
echo ""
echo "Commands -> $DEST/commands/"
mkdir -p "$DEST/commands"
for f in "$SCRIPT_DIR"/commands/*; do
    [ -f "$f" ] && install_file "$f" "$DEST/commands/$(basename "$f")"
done

echo ""
echo "Done. Restart Claude Code to pick up new slash commands."
