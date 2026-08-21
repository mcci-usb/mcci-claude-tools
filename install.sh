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

# Git Bash on Windows installs the Windows variant of a skill; every other
# environment installs the POSIX one.
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=1 ;;
    *)                    IS_WINDOWS=0 ;;
esac

FORCE=0
CHECK=0
for arg in "$@"; do
    case "$arg" in
        -f|--force) FORCE=1 ;;
        --check)    CHECK=1 ;;
    esac
done

# Build the installed content from a repo source file (to stdout).
# If the file starts with a shebang (#!), preserve it on line 1 so the
# kernel can find it; place the provenance header on lines 2-3 instead.
transform_file() {
    local src="$1"
    local first_line

    # Markdown keeps its metadata in the opening lines: YAML frontmatter in a
    # SKILL.md, the description line in a slash command. A provenance header on
    # line 1 is read as that metadata -- it breaks frontmatter parsing and shows
    # up as the command description -- so for markdown it goes at the end.
    case "$src" in
    *.md)
        grep -v '^# ORIGINAL SOURCE --' "$src"
        printf '\n<!-- INSTALLED FROM mcci-claude-tools -- do not edit this copy. -->\n'
        printf '<!-- Original: %s -->\n' "$src"
        return
        ;;
    esac

    first_line=$(head -1 "$src")
    if [[ "$first_line" == '#!'* ]]; then
        printf '%s\n' "$first_line"
        printf '# INSTALLED FROM mcci-claude-tools -- do not edit this copy.\n'
        printf '# Original: %s\n' "$src"
        tail -n +2 "$src" | grep -v '^# ORIGINAL SOURCE --'
    else
        printf '# INSTALLED FROM mcci-claude-tools -- do not edit this copy.\n'
        printf '# Original: %s\n' "$src"
        grep -v '^# ORIGINAL SOURCE --' "$src"
    fi
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
    # Shell scripts, and anything else with a shebang, need execute permission
    case "$name" in
        *.sh) chmod +x "$dest" ;;
        *)   [ "$(head -c 2 "$src")" = '#!' ] && chmod +x "$dest" || true ;;
    esac
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

# Install or check every skill. One directory per skill, each holding a
# SKILL.md. A skill that needs different instructions on Windows carries a
# SKILL.windows.md alongside it, which replaces SKILL.md there.
handle_skills() {
    local mode="$1"
    local d f name base target

    [ -d "$SCRIPT_DIR/skills" ] || return 0

    printf '\nSkills -> %s/skills/\n' "$DEST"
    for d in "$SCRIPT_DIR"/skills/*/; do
        [ -d "$d" ] || continue
        name="$(basename "$d")"
        [ "$mode" = "install" ] && mkdir -p "$DEST/skills/$name"

        for f in "$d"*; do
            [ -f "$f" ] || continue
            base="$(basename "$f")"
            target="$base"

            case "$base" in
                SKILL.windows.md)
                    [ "$IS_WINDOWS" -eq 1 ] || continue
                    target="SKILL.md"
                    ;;
                SKILL.md)
                    if [ "$IS_WINDOWS" -eq 1 ] && [ -f "${d}SKILL.windows.md" ]; then
                        continue
                    fi
                    ;;
            esac

            if [ "$mode" = "check" ]; then
                check_file "$f" "$DEST/skills/$name/$target"
            else
                install_file "$f" "$DEST/skills/$name/$target"
            fi
        done
    done
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

    handle_skills check

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

handle_skills install

echo ""
echo "Done. Restart Claude Code to pick up new slash commands and skills."
