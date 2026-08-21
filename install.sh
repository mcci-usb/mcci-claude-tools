#!/bin/bash
# install.sh -- install mcci-claude-tools into ~/.claude/
#
# Run from the repo root directory:
#   ./install.sh
#
# What it does:
#   - Copies scripts/* to ~/.claude/scripts/
#   - Copies commands/* to ~/.claude/commands/
#   - Copies skills/* to ~/.claude/skills/
#   - Does NOT overwrite existing files unless -f is passed
#   - With --check, compares installed copies against repo (no changes made)
#
# Options:
#   -f, --force        overwrite existing installed copies
#   --check            compare and report, write nothing
#   --source DIR       read scripts/, commands/, and skills/ from DIR instead
#                      of this repo. Lets another repo that holds Claude Code
#                      material install it without carrying its own installer.
#   --name NAME        repo name to record in the provenance line. Defaults to
#                      this repo's name when installing its own material, and
#                      to the basename of the source directory otherwise.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.claude"

# SCRIPT_DIR locates this script. SRC_DIR is the tree it reads material from;
# they are the same unless --source says otherwise.
SRC_DIR="$SCRIPT_DIR"
SRC_NAME=""

# This repo's name, recorded in the provenance line when installing its own
# material. It is not the basename of the clone: as a submodule this repo sits
# under whatever directory the parent chose.
REPO_NAME="mcci-claude-tools"

# Git Bash on Windows installs the Windows variant of a skill; every other
# environment installs the POSIX one.
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) IS_WINDOWS=1 ;;
    *)                    IS_WINDOWS=0 ;;
esac

FORCE=0
CHECK=0
while [ $# -gt 0 ]; do
    case "$1" in
        -f|--force) FORCE=1 ;;
        --check)    CHECK=1 ;;
        --source)   SRC_DIR="$2"; shift ;;
        --source=*) SRC_DIR="${1#--source=}" ;;
        --name)     SRC_NAME="$2"; shift ;;
        --name=*)   SRC_NAME="${1#--name=}" ;;
        -h|--help)  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)          printf 'install.sh: unknown option %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

SRC_DIR="$(cd "$SRC_DIR" 2>/dev/null && pwd)" || {
    printf 'install.sh: no such source directory\n' >&2
    exit 2
}
if [ -z "$SRC_NAME" ]; then
    if [ "$SRC_DIR" = "$SCRIPT_DIR" ]; then
        SRC_NAME="$REPO_NAME"
    else
        SRC_NAME="$(basename "$SRC_DIR")"
    fi
fi

# Build the installed content from a repo source file (to stdout).
# If the file starts with a shebang (#!), preserve it on line 1 so the
# kernel can find it; place the provenance header on lines 2-3 instead.
#
# The provenance names the repo and the path within it, not the absolute path
# of the clone. Clones of one repo sit at different absolute paths in different
# environments (/home/tmm/mcci-claude-tools in WSL, /c/ss/mcci-claude-tools
# under Git Bash), and an absolute path made --check report every file stale
# when run from the other clone.
transform_file() {
    local src="$1"
    local first_line rel
    rel="$SRC_NAME/${src#$SRC_DIR/}"

    # Markdown keeps its metadata in the opening lines: YAML frontmatter in a
    # SKILL.md, the description line in a slash command. A provenance header on
    # line 1 is read as that metadata -- it breaks frontmatter parsing and shows
    # up as the command description -- so for markdown it goes at the end.
    case "$src" in
    *.md)
        grep -v '^# ORIGINAL SOURCE --' "$src"
        printf '\n<!-- INSTALLED FROM %s -- do not edit this copy. -->\n' "$SRC_NAME"
        printf '<!-- Source: %s -->\n' "$rel"
        return
        ;;
    esac

    first_line=$(head -1 "$src")
    if [[ "$first_line" == '#!'* ]]; then
        printf '%s\n' "$first_line"
        printf '# INSTALLED FROM %s -- do not edit this copy.\n' "$SRC_NAME"
        printf '# Source: %s\n' "$rel"
        tail -n +2 "$src" | grep -v '^# ORIGINAL SOURCE --'
    else
        printf '# INSTALLED FROM %s -- do not edit this copy.\n' "$SRC_NAME"
        printf '# Source: %s\n' "$rel"
        grep -v '^# ORIGINAL SOURCE --' "$src"
    fi
}

# install_file SRC DEST [LABEL] -- LABEL is what the progress line prints,
# defaulting to the source basename. Skills pass "<skill>/<file>", since every
# skill has a file called SKILL.md.
install_file() {
    local src="$1"
    local dest="$2"
    local name
    name="${3:-$(basename "$src")}"

    if [ -f "$dest" ] && [ "$FORCE" -eq 0 ]; then
        echo "  SKIP $name (already exists; use -f to overwrite)"
        return
    fi

    transform_file "$src" > "$dest"
    # Anything with a shebang needs execute permission, not only *.sh: an
    # extensionless script installed without it will not run.
    if [ "$(head -c 2 "$src")" = '#!' ]; then
        chmod +x "$dest"
    fi
    echo "  OK   $name"
}

# Compare installed copy against repo source (ignoring line endings).
# Returns 0 if up to date, 1 if stale or missing.
check_file() {
    local src="$1"
    local dest="$2"
    local name
    name="${3:-$(basename "$src")}"

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

    [ -d "$SRC_DIR/skills" ] || return 0

    printf '\nSkills -> %s/skills/\n' "$DEST"
    for d in "$SRC_DIR"/skills/*/; do
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
                check_file "$f" "$DEST/skills/$name/$target" "$name/$target"
            else
                install_file "$f" "$DEST/skills/$name/$target" "$name/$target"
            fi
        done
    done
}

# --check mode: compare and report, no writes
if [ "$CHECK" -eq 1 ]; then
    STALE=0
    printf 'Checking installed copies against %s ...\n' "$SRC_DIR"

    if [ -d "$SRC_DIR/scripts" ]; then
        printf '\nScripts -> %s/scripts/\n' "$DEST"
        for f in "$SRC_DIR"/scripts/*; do
            [ -f "$f" ] && check_file "$f" "$DEST/scripts/$(basename "$f")"
        done
    fi

    if [ -d "$SRC_DIR/commands" ]; then
        printf '\nCommands -> %s/commands/\n' "$DEST"
        for f in "$SRC_DIR"/commands/*; do
            [ -f "$f" ] && check_file "$f" "$DEST/commands/$(basename "$f")"
        done
    fi

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

# The .py scripts carry PEP 723 inline metadata and run under `uv run`. A
# source tree holding none of them does not need uv.
if ls "$SRC_DIR"/scripts/*.py >/dev/null 2>&1 && ! command -v uv &>/dev/null; then
    echo "ERROR: 'uv' is required but not found."
    echo "Install it from https://docs.astral.sh/uv/getting-started/installation/"
    exit 1
fi

printf 'Installing %s to %s ...\n' "$SRC_NAME" "$DEST"

# Scripts
if [ -d "$SRC_DIR/scripts" ]; then
    printf '\nScripts -> %s/scripts/\n' "$DEST"
    mkdir -p "$DEST/scripts"
    for f in "$SRC_DIR"/scripts/*; do
        [ -f "$f" ] && install_file "$f" "$DEST/scripts/$(basename "$f")"
    done
fi

# Commands (slash commands)
if [ -d "$SRC_DIR/commands" ]; then
    printf '\nCommands -> %s/commands/\n' "$DEST"
    mkdir -p "$DEST/commands"
    for f in "$SRC_DIR"/commands/*; do
        [ -f "$f" ] && install_file "$f" "$DEST/commands/$(basename "$f")"
    done
fi

handle_skills install

echo ""
echo "Done. Restart Claude Code to pick up new slash commands and skills."
