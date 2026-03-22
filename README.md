# mcci-claude-tools

Shared tools for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) at MCCI.

## Prerequisites

- Windows with Outlook desktop (COM automation)
- Claude Code CLI
- Git Bash / MINGW (ships with Git for Windows)
- PowerShell 5.1 (built into Windows)
- [uv](https://docs.astral.sh/uv/getting-started/installation/) (Python package runner -- used for markdown-to-HTML conversion)

## Installation

Clone this repo and run the install script **in each environment** where you use Claude Code:

```bash
git clone <repo-url> mcci-claude-tools
cd mcci-claude-tools
./install.sh
```

This copies files into `~/.claude/`, adding a provenance header so installed copies are clearly marked as non-editable.

| Source | Destination | Purpose |
|--------|-------------|---------|
| `scripts/send-outlook-draft.sh` | `~/.claude/scripts/` | Bash wrapper -- resolves WSL/MINGW paths, calls PowerShell |
| `scripts/New-OutlookDraft.ps1` | `~/.claude/scripts/` | PowerShell script for Outlook drafts (called by the wrapper) |
| `scripts/md-to-email-html.py` | `~/.claude/scripts/` | Markdown-to-HTML converter (called by the PS1 script) |
| `commands/draft-email.md` | `~/.claude/commands/` | `/draft-email` slash command |

Restart Claude Code after installing to pick up the new slash commands.

To avoid permission prompts when `/draft-email` calls the wrapper script, add this to `~/.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(~/.claude/scripts/send-outlook-draft.sh:*)"
    ]
  }
}
```

To update after a `git pull`:

```bash
./install.sh -f
```

The `-f` flag overwrites existing files.

### Install model: WSL vs. Git Bash vs. native

`install.sh` installs to `$HOME/.claude/`. What `$HOME` resolves to depends on where you run it:

| Environment | `$HOME` | Installed path | Notes |
|-------------|---------|----------------|-------|
| **Git Bash on Windows** | `C:\Users\tmm` | `C:\Users\tmm\.claude\scripts\` | `powershell.exe` reads these paths directly |
| **WSL** | `/home/tmm` | `/home/tmm/.claude/scripts/` | `powershell.exe` needs `wslpath -w` to find them |
| **macOS / Linux** | `/home/user` | `/home/user/.claude/scripts/` | PowerShell scripts are irrelevant (no Outlook) |

The two installs (Git Bash and WSL) are **independent** -- both are valid, and both should be kept up to date. Run `install.sh -f` in each environment after pulling changes.

Source files contain an `# ORIGINAL SOURCE` marker. Installed copies replace this with a provenance header pointing back to the repo, so it's clear which copy is the editable original.

## Tools

### `/draft-email` -- Outlook Email Drafts

Composes a formatted email and opens it as an Outlook draft (does not send).

**Usage in Claude Code:**

```
/draft-email to: user@example.com; cc: other@example.com; subject: RE: Widget issue; tell them we found the root cause and will have a fix in v3.42
```

Claude will compose the email body, show it for your review, then open the Outlook draft window.

**What it handles:**

Uses [markdown-it-py](https://github.com/executablebooks/markdown-it-py) (the same engine as VS Code's markdown preview) with [premailer](https://github.com/peterbe/premailer) for CSS inlining. Supports the full CommonMark spec plus:

- Bold, italic, strikethrough
- Fenced code blocks with syntax highlighting styles
- Inline code
- Bullet and numbered lists (including nested)
- Tables
- Blockquotes
- Links
- Horizontal rules
- Base font: 11pt, inherits Outlook's default (currently Aptos)
- Code blocks: Consolas 10pt on light gray background

You can also ask Claude to draft an email without the slash command -- just say something like "draft an email to user@example.com about ...".

**Reply mode:** Say "reply to the selected message" or "respond to the selected email". Claude will grab the EntryID of the message currently selected in Outlook's main window and create a threaded reply.

**Important:** "Selected message" means the highlighted message in Outlook's main Explorer list pane, **not** a message open in a separate read window. If you have a message open in its own window, click it in the main list first so it's highlighted there.

### `send-outlook-draft.sh` -- Bash Wrapper

The `/draft-email` command calls this wrapper script, which handles WSL/MINGW path resolution internally. This avoids `$()` command substitutions in the generated bash command (which would trigger Claude Code security prompts).

```bash
# New email
~/.claude/scripts/send-outlook-draft.sh \
  --to "user@example.com" --cc "other@example.com" \
  --subject "Hello" --body-file /tmp/body.md

# Reply to selected message
~/.claude/scripts/send-outlook-draft.sh \
  --entry-id "000000..." --reply-all \
  --body-file /tmp/body.md
```

| Flag | Description |
|------|-------------|
| `--to` | Recipient(s), semicolon-separated |
| `--cc` | CC recipient(s) |
| `--bcc` | BCC recipient(s) |
| `--subject` | Subject line |
| `--body-file` | Path to a Markdown file for the body (required) |
| `--entry-id` | Outlook EntryID for reply mode (replaces `--to`/`--subject`) |
| `--reply-all` | Reply to all recipients (only with `--entry-id`) |

In WSL, the script copies the body file to Windows `%TEMP%` before calling PowerShell, since Linux-only paths (e.g. `/tmp/`) resolve to UNC paths that `uv`/PowerShell can't handle. The temp copy is cleaned up automatically.

### `New-OutlookDraft.ps1` -- Direct Script Usage

The PowerShell script can be called directly from PowerShell if needed (the bash wrapper calls it under the hood):

```powershell
.\New-OutlookDraft.ps1 -To "user@example.com" -Subject "Hello" -Body "**Bold** and `code`"
```

```powershell
.\New-OutlookDraft.ps1 -To "a@example.com" -Cc "b@example.com" -Bcc "c@example.com" -Subject "Report" -BodyFile "C:\tmp\body.md"
```

```powershell
# Reply to the currently selected message in Outlook's main window
$entryId = (New-Object -ComObject Outlook.Application).ActiveExplorer().Selection.Item(1).EntryID
.\New-OutlookDraft.ps1 -EntryID $entryId -ReplyAll -Body "Thanks for the update."
```

Parameters:

| Parameter | Description |
|-----------|-------------|
| `-To` | Recipient(s), semicolon-separated |
| `-Cc` | CC recipient(s) |
| `-Bcc` | BCC recipient(s) |
| `-Subject` | Subject line |
| `-BodyFile` | Path to a Markdown file for the body |
| `-Body` | Inline Markdown string (alternative to `-BodyFile`) |
| `-EntryID` | Outlook EntryID for reply mode (replaces `-To`/`-Subject`) |
| `-ReplyAll` | Reply to all recipients (only with `-EntryID`) |

## License

[MIT](LICENSE) Copyright (c) 2026 MCCI Corporation.
