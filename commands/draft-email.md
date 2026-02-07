Draft an Outlook email. The user's instructions are:

$ARGUMENTS

Workflow:
1. Parse the user's instructions for recipients (to, cc, bcc), subject, and body content.
2. Compose the email body in Markdown format. Keep the tone direct and matter-of-fact.
3. Write the Markdown body to a temp file. Use `$TEMP/email-body.md` in the shell environment (expands to the user's temp directory).
4. Show the user the draft body and the To/Cc/Bcc/Subject fields for review before opening Outlook.
5. Once approved, invoke the script:
   ```
   powershell.exe -ExecutionPolicy Bypass -File "$HOME/.claude/scripts/New-OutlookDraft.ps1" -To "<to>" -Cc "<cc>" -Bcc "<bcc>" -Subject "<subject>" -BodyFile "$TEMP/email-body.md"
   ```
   Omit -Cc/-Bcc flags if not specified. `$HOME` and `$TEMP` are shell variables -- do not quote them inside double quotes in the bash command so they expand properly.
6. Clean up the temp file after the draft opens.

If the user provides the body content directly, use it as-is. If they describe what the email should say, compose appropriate text.
