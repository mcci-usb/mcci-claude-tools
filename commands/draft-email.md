Draft an Outlook email. The user's instructions are:

$ARGUMENTS

Workflow:
1. Parse the user's instructions for recipients (to, cc, bcc), subject, and body content.
2. Compose the email body in Markdown format. Keep the tone direct and matter-of-fact.
3. Show the user the draft body and the To/Cc/Bcc/Subject fields for review before opening Outlook.
4. Once approved, write the Markdown body to a temp file and invoke the script in a single Bash command. This ensures shell variables like `$TEMP` and `$HOME` are expanded consistently:
   ```
   cat > "$TEMP/email-body.md" <<'EMAILEOF'
   <markdown body here>
   EMAILEOF
   powershell.exe -ExecutionPolicy Bypass -File "$HOME/.claude/scripts/New-OutlookDraft.ps1" -To "<to>" -Cc "<cc>" -Bcc "<bcc>" -Subject "<subject>" -BodyFile "$TEMP/email-body.md"
   rm -f "$TEMP/email-body.md"
   ```
   Omit -Cc/-Bcc flags if not specified.

If the user provides the body content directly, use it as-is. If they describe what the email should say, compose appropriate text.
