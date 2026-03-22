#!/bin/bash
# ORIGINAL SOURCE -- install to ~/.claude/scripts/ using install.sh
#
# send-outlook-draft.sh -- wrapper that resolves WSL/MINGW paths and
# invokes New-OutlookDraft.ps1 via powershell.exe.
#
# Copyright (c) 2026 MCCI Corporation. MIT license.
#
# Usage:
#   send-outlook-draft.sh --to "a@b.com" --subject "Hi" --body-file /tmp/body.md
#   send-outlook-draft.sh --entry-id "0000..." --reply-all --body-file /tmp/body.md

set -euo pipefail

# --- Parse arguments ---
TO=""
CC=""
BCC=""
SUBJECT=""
BODY_FILE=""
ENTRY_ID=""
REPLY_ALL=0

while [ $# -gt 0 ]; do
    case "$1" in
        --to)        TO="$2";        shift 2 ;;
        --cc)        CC="$2";        shift 2 ;;
        --bcc)       BCC="$2";       shift 2 ;;
        --subject)   SUBJECT="$2";   shift 2 ;;
        --body-file) BODY_FILE="$2"; shift 2 ;;
        --entry-id)  ENTRY_ID="$2";  shift 2 ;;
        --reply-all) REPLY_ALL=1;    shift   ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [ -z "$BODY_FILE" ]; then
    echo "Error: --body-file is required." >&2
    exit 1
fi

if [ ! -f "$BODY_FILE" ]; then
    echo "Error: body file not found: $BODY_FILE" >&2
    exit 1
fi

# --- Resolve paths for the current environment ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PS1_NAME="New-OutlookDraft.ps1"

CLEANUP_BODY=""

if [ -n "${WSL_DISTRO_NAME:-}" ]; then
    # WSL: convert to Windows paths for powershell.exe
    SCRIPT_PATH="$(wslpath -w "$SCRIPT_DIR/$PS1_NAME")"

    # Body file must be on a Windows-native filesystem for uv/PowerShell.
    # If it's under a Linux-only path (e.g. /tmp/), copy to Windows %TEMP%.
    WINTMP="$(wslpath "$(cmd.exe /C 'echo %TEMP%' 2>/dev/null | tr -d '\r')")"
    WIN_BODY="$WINTMP/claude-email-body-$$.md"
    cp "$BODY_FILE" "$WIN_BODY"
    CLEANUP_BODY="$WIN_BODY"
    BODY_PATH="$(wslpath -w "$WIN_BODY")"
elif [ "${OSTYPE:-}" = "msys" ] || [ "${MSYSTEM:-}" != "" ]; then
    # Git Bash / MINGW: paths work as-is for powershell.exe
    SCRIPT_PATH="$SCRIPT_DIR/$PS1_NAME"
    BODY_PATH="$BODY_FILE"
else
    echo "Error: this script requires WSL or Git Bash (MINGW) on Windows." >&2
    exit 1
fi

cleanup() {
    [ -n "$CLEANUP_BODY" ] && rm -f "$CLEANUP_BODY"
}
trap cleanup EXIT

# --- Build the powershell.exe command ---
PS_ARGS=(-ExecutionPolicy Bypass -File "$SCRIPT_PATH")

if [ -n "$ENTRY_ID" ]; then
    PS_ARGS+=(-EntryID "$ENTRY_ID")
    if [ "$REPLY_ALL" -eq 1 ]; then
        PS_ARGS+=(-ReplyAll)
    fi
else
    if [ -n "$TO" ]; then
        PS_ARGS+=(-To "$TO")
    fi
    if [ -n "$SUBJECT" ]; then
        PS_ARGS+=(-Subject "$SUBJECT")
    fi
fi

if [ -n "$CC" ]; then
    PS_ARGS+=(-Cc "$CC")
fi
if [ -n "$BCC" ]; then
    PS_ARGS+=(-Bcc "$BCC")
fi

PS_ARGS+=(-BodyFile "$BODY_PATH")

# --- Invoke ---
exec powershell.exe "${PS_ARGS[@]}"
