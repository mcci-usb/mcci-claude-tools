# mcci-claude-tools

Shared Claude Code tools for MCCI -- currently the Outlook email draft pipeline.

## File Layout

| File | Role |
|------|------|
| `scripts/md-to-email-html.py` | Markdown-to-inline-styled-HTML converter. PEP 723 inline metadata; run via `uv run`. |
| `scripts/New-OutlookDraft.ps1` | Outlook COM automation -- creates a draft window (does not send). Calls `md-to-email-html.py` internally. |
| `commands/draft-email.md` | `/draft-email` slash command template for Claude Code. |
| `install.sh` | Copies scripts and commands into `$HOME/.claude/`, adding provenance headers. |
| `README.md` | User-facing docs (prerequisites, usage, parameters). |
| `LICENSE` | MIT, MCCI Corporation. |

## Install Model

`install.sh` copies files into `$HOME/.claude/`. Because `$HOME` differs between environments, you must run it separately in each:

- **Git Bash on Windows** -- installs to `C:\Users\tmm\.claude\`. The Outlook pipeline uses these copies (PowerShell reads Windows paths directly).
- **WSL** -- installs to `/home/tmm/.claude/`. Claude Code sessions in WSL see these copies.

The two installs are independent. Run `install.sh -f` in both after pulling changes.

**Source vs. installed copies:**
- Repo files carry an `# ORIGINAL SOURCE` marker.
- Installed copies replace that marker with a provenance header (`# INSTALLED FROM mcci-claude-tools -- do not edit this copy.`).
- **Always edit the repo copies**, never the installed copies.

## Development Conventions

- **Issues before commits.** File an issue first, then commit with `fixes #N` so it auto-closes on push.
- **Edit source in the repo**, never installed copies under `~/.claude/`.
- **`# ORIGINAL SOURCE` marker** is required on every installable file (first non-shebang comment line in scripts, or near the top in other files).
- **Python:** PEP 723 inline metadata for dependencies (no `requirements.txt`). Run with `uv run`.
- **Shell:** `printf '%s\n'` over `echo "$var"` (avoids backslash interpretation differences across shells).
- **Commit messages:** lowercase area prefix -- `fix:`, `feat:`, `docs:`, `chore:`.
- **Test from both WSL and Git Bash** after any change to the install path or script invocation.
- **Copyright:** MCCI Corporation, current year, MIT license.

## Open Issues

Run `gh issue list` for the current list. Do not hardcode issue numbers in docs -- they go stale.

## Repo Hosting

GitLab at `gitlab-x.mcci.com`. The `glab` CLI is installed and authenticated; inside the repo working directory it picks up the remote automatically.
