# mcci-claude-tools

Shared tools for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) at MCCI.

## Prerequisites

- Windows with Outlook desktop (COM automation)
- Claude Code CLI
- Git Bash / MINGW (ships with Git for Windows)
- PowerShell 5.1 (built into Windows)

## Installation

Clone this repo and run the install script:

```bash
git clone <repo-url> mcci-claude-tools
cd mcci-claude-tools
./install.sh
```

This copies files into `~/.claude/`:

| Source | Destination | Purpose |
|--------|-------------|---------|
| `scripts/New-OutlookDraft.ps1` | `~/.claude/scripts/` | PowerShell script for Outlook drafts |
| `commands/draft-email.md` | `~/.claude/commands/` | `/draft-email` slash command |

Restart Claude Code after installing to pick up the new slash commands.

To update after a `git pull`:

```bash
./install.sh -f
```

The `-f` flag overwrites existing files.

## Tools

### `/draft-email` -- Outlook Email Drafts

Composes a formatted email and opens it as an Outlook draft (does not send).

**Usage in Claude Code:**

```
/draft-email to: user@example.com; cc: other@example.com; subject: RE: Widget issue; tell them we found the root cause and will have a fix in v3.42
```

Claude will compose the email body, show it for your review, then open the Outlook draft window.

**What it handles:**

- Markdown to inline-styled HTML (Outlook-compatible)
- Paragraphs, headers, bold, inline code, fenced code blocks, bullet/numbered lists, links
- Base font: Calibri 11pt (matches Outlook default)
- Code blocks: Consolas 10pt on light gray background

You can also ask Claude to draft an email without the slash command -- just say something like "draft an email to user@example.com about ...".

### `New-OutlookDraft.ps1` -- Direct Script Usage

The PowerShell script can be called directly if needed:

```powershell
.\New-OutlookDraft.ps1 -To "user@example.com" -Subject "Hello" -Body "**Bold** and `code`"
```

```powershell
.\New-OutlookDraft.ps1 -To "a@example.com" -Cc "b@example.com" -Bcc "c@example.com" -Subject "Report" -BodyFile "C:\tmp\body.md"
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

## License

[MIT](LICENSE) Copyright (c) 2026 MCCI Corporation.
