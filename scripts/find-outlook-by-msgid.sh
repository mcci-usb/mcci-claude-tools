#!/bin/bash
# find-outlook-by-msgid.sh -- look up an Outlook message by Internet Message-Id
# and print key=value lines (folder, subject, from, received, entry_id).
#
# Copyright (c) 2026 MCCI Corporation. MIT license.
#
# Usage:
#   find-outlook-by-msgid.sh <message-id>
#   find-outlook-by-msgid.sh --folders 6,5,16 --all <message-id>
#
# The message-id may be passed with or without the surrounding angle
# brackets; the script normalizes either form.
#
# Exit codes:
#   0  match found (one or more lines printed)
#   1  no match
#   2  error (Outlook unavailable, etc.)

set -euo pipefail

FOLDERS=""
ALL=0
MID=""

while [ $# -gt 0 ]; do
    case "$1" in
        --folders) FOLDERS="$2"; shift 2 ;;
        --all)     ALL=1;        shift   ;;
        --help|-h)
            sed -n '2,17p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        --*)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
        *)
            if [ -n "$MID" ]; then
                echo "Error: multiple message-id arguments not supported." >&2
                exit 2
            fi
            MID="$1"; shift ;;
    esac
done

if [ -z "$MID" ]; then
    echo "Error: message-id is required." >&2
    echo "Usage: $(basename "$0") [--folders 6,5,16] [--all] <message-id>" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PS1_NAME="Find-OutlookByMessageId.ps1"

if [ -n "${WSL_DISTRO_NAME:-}" ]; then
    SCRIPT_PATH="$(wslpath -w "$SCRIPT_DIR/$PS1_NAME")"
elif [ "${OSTYPE:-}" = "msys" ] || [ "${MSYSTEM:-}" != "" ]; then
    SCRIPT_PATH="$SCRIPT_DIR/$PS1_NAME"
else
    echo "Error: this script requires WSL or Git Bash (MINGW) on Windows." >&2
    exit 2
fi

PS_ARGS=(-ExecutionPolicy Bypass -File "$SCRIPT_PATH" -MessageId "$MID")
if [ -n "$FOLDERS" ]; then
    PS_ARGS+=(-Folders "$FOLDERS")
fi
if [ "$ALL" -eq 1 ]; then
    PS_ARGS+=(-All)
fi

# powershell.exe emits CRLF line endings; strip the CR for clean shell parsing.
powershell.exe "${PS_ARGS[@]}" | tr -d '\r'
exit ${PIPESTATUS[0]}
