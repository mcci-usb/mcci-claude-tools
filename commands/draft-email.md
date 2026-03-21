Draft an Outlook email. The user's instructions are:

$ARGUMENTS

Workflow:
1. Parse the user's instructions for recipients (to, cc, bcc), subject, and body content. When multiple addresses appear in any field, join them with semicolons (e.g., `-To "alice@example.com; bob@example.com"`). Outlook requires semicolons, not commas.
2. Compose the email body in Markdown format. Keep the tone direct and matter-of-fact. The body is rendered via CommonMark, so follow its rules:
   - A single newline between lines is a *soft break* (rendered as a space, not a line break). To force a hard line break, use `<br/>` at the break point.
   - Sign-offs like "Best regards," followed by a name on the next line must use `<br/>`: `Best regards,<br/>--Terry`. Without it, CommonMark will collapse them onto one line.
3. Show the user the draft body and the To/Cc/Bcc/Subject fields for review before opening Outlook.
4. Once approved, write the Markdown body to a temp file and invoke the script in a single Bash command. The snippet below handles both WSL and Git Bash (MINGW) environments:
   ```
   # Determine paths -- WSL needs wslpath conversion for powershell.exe
   if [ -n "$WSL_DISTRO_NAME" ]; then
     WINTMP=$(wslpath "$(cmd.exe /C 'echo %TEMP%' 2>/dev/null | tr -d '\r')")
     TMPFILE="$WINTMP/email-body.md"
     SCRIPT_PATH=$(wslpath -w "$HOME/.claude/scripts/New-OutlookDraft.ps1")
     BODY_PATH=$(wslpath -w "$TMPFILE")
   else
     TMPFILE="$TEMP/email-body.md"
     SCRIPT_PATH="$HOME/.claude/scripts/New-OutlookDraft.ps1"
     BODY_PATH="$TMPFILE"
   fi

   cat > "$TMPFILE" <<'EMAILEOF'
   <markdown body here>
   EMAILEOF
   powershell.exe -ExecutionPolicy Bypass -File "$SCRIPT_PATH" \
     -To "<to>" -Cc "<cc>" -Bcc "<bcc>" -Subject "<subject>" \
     -BodyFile "$BODY_PATH"
   rm -f "$TMPFILE"
   ```
   Omit -Cc/-Bcc flags if not specified.
5. **Reply mode:** If the user says "reply to" or "respond to" an existing email thread, you need the Outlook EntryID of the original message. To get it, run:
   ```
   powershell.exe -Command "(New-Object -ComObject Outlook.Application).ActiveExplorer().Selection.Item(1).EntryID"
   ```
   This returns the EntryID of the currently selected message in Outlook. Then use `-EntryID` instead of `-To` and `-Subject` (omit both -- recipients and subject come from the original). Add `-ReplyAll` to reply to all recipients. You can still override `-Cc` or `-Bcc`. Example:
   ```
   powershell.exe -ExecutionPolicy Bypass -File "$SCRIPT_PATH" \
     -EntryID "<entry-id>" -ReplyAll \
     -BodyFile "$BODY_PATH"
   ```

If the user provides the body content directly, use it as-is. If they describe what the email should say, compose appropriate text.
