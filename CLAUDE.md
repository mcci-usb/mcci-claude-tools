# mcci-claude-tools

Shared Claude Code tools for MCCI -- currently the Outlook email draft pipeline.

## File Layout

| File | Role |
|------|------|
| `scripts/md-to-email-html.py` | Markdown-to-inline-styled-HTML converter. PEP 723 inline metadata; run via `uv run`. |
| `scripts/New-OutlookDraft.ps1` | Outlook COM automation -- creates a draft window (does not send). Calls `md-to-email-html.py` internally. |
| `commands/draft-email.md` | `/draft-email` slash command template for Claude Code. |
| `install.sh` | Copies scripts, commands, and skills into `$HOME/.claude/`, adding provenance lines. Installs another repo's tree with `--source DIR`. |
| `README.md` | User-facing docs (prerequisites, usage, parameters). |
| `LICENSE` | MIT, MCCI Corporation. |

## Install Model

`install.sh` copies files into `$HOME/.claude/`. Because `$HOME` differs between environments, you must run it separately in each:

- **Git Bash on Windows** -- installs to `C:\Users\tmm\.claude\`. The Outlook pipeline uses these copies (PowerShell reads Windows paths directly).
- **WSL** -- installs to `/home/tmm/.claude/`. Claude Code sessions in WSL see these copies.

The two installs are independent. Run `install.sh -f` in both after pulling changes.

**Source vs. installed copies:**
- Repo files carry an `# ORIGINAL SOURCE` marker.
- Installed copies replace that marker with a provenance line (`# INSTALLED FROM mcci-claude-tools`) plus the path within the repo. It records the repo-relative path, not the absolute path of the clone, so `--check` gives the same answer from either clone.
- In markdown those two lines go at the *end* of the file, as HTML comments. Markdown keeps its metadata in the opening lines, so a comment on line 1 is read as YAML frontmatter or as a slash command's description.
- **Always edit the repo copies**, never the installed copies.

## Development Conventions

- **Issues before commits.** File an issue first, then commit with `fixes #N` so it auto-closes on push.
- **Edit source in the repo**, never installed copies under `~/.claude/`.
- **`# ORIGINAL SOURCE` marker** is required on every installable file (first non-shebang comment line in scripts, or near the top in other files).
- **Skills** live in `skills/<name>/SKILL.md`. Add a `SKILL.windows.md` beside it when Windows needs different instructions; `install.sh` picks it under Git Bash.
- **Python:** PEP 723 inline metadata for dependencies (no `requirements.txt`). Run with `uv run`.
- **Shell:** `printf '%s\n'` over `echo "$var"` (avoids backslash interpretation differences across shells).
- **Commit messages:** lowercase area prefix -- `fix:`, `feat:`, `docs:`, `chore:`.
- **Test from both WSL and Git Bash** after any change to the install path or script invocation.
- **Copyright:** MCCI Corporation, current year, MIT license.

## Open Issues

Run `gh issue list` for the current list. Do not hardcode issue numbers in docs -- they go stale.

## Repo Hosting

Public on GitHub at `mcci-usb/mcci-claude-tools`, MIT. The `gh` CLI is installed and authenticated; inside the repo working directory it picks up the remote automatically.

Because the repo is public, keep personal and MCCI-internal material out of it. Machine-specific or personal Claude Code material belongs in `tmm/personal-claude-context` on `gitlab-x.mcci.com`, which installs it by calling this repo's `install.sh --source .`.
