Draft an Outlook email. The user's instructions are:

$ARGUMENTS

Workflow:
1. Parse the user's instructions for recipients (to, cc, bcc), subject, and body content. When multiple addresses appear in any field, join them with semicolons (e.g., `-To "alice@example.com; bob@example.com"`). Outlook requires semicolons, not commas.
2. Compose the email body in Markdown format. Keep the tone direct and matter-of-fact. The body is rendered via CommonMark, so follow its rules:
   - A single newline between lines is a *soft break* (rendered as a space, not a line break). To force a hard line break, use `<br/>` at the break point.
   - Sign-offs like "Best regards," followed by a name on the next line must use `<br/>`: `Best regards,<br/>--Terry`. Without it, CommonMark will collapse them onto one line.
3. Show the user the draft body and the To/Cc/Bcc/Subject fields for review before opening Outlook.
4. Once approved, use the Write tool to save the Markdown body to `/tmp/email-body.md`, then invoke the wrapper script. The script handles WSL/MINGW path conversion internally:
   ```
   ~/.claude/scripts/send-outlook-draft.sh \
     --to "<to>" --cc "<cc>" --bcc "<bcc>" --subject "<subject>" \
     --body-file /tmp/email-body.md
   ```
   Omit --cc/--bcc flags if not specified. The script copies the body to a Windows-accessible temp location and cleans up automatically.
5. **Reply mode:** If the user says "reply to" or "respond to" an existing email thread, you need the Outlook EntryID of the original message. To get it, run:
   ```
   powershell.exe -Command "(New-Object -ComObject Outlook.Application).ActiveExplorer().Selection.Item(1).EntryID"
   ```
   This returns the EntryID of the currently selected message in Outlook. Then use `--entry-id` instead of `--to` and `--subject` (omit both -- recipients and subject come from the original). Add `--reply-all` to reply to all recipients. You can still override `--cc` or `--bcc`. Example:
   ```
   ~/.claude/scripts/send-outlook-draft.sh \
     --entry-id "<entry-id>" --reply-all \
     --body-file /tmp/email-body.md
   ```

If the user provides the body content directly, use it as-is. If they describe what the email should say, compose appropriate text.
