<#
.SYNOPSIS
    Find an Outlook message by Internet Message-Id and emit its EntryID
    plus identifying fields (subject, sender, received time, folder).

.DESCRIPTION
    Searches the user's MAPI mailbox for a message whose
    PR_INTERNET_MESSAGE_ID_W (proptag 0x1035001F) matches the supplied
    Message-Id. By default searches Inbox first, then Sent Items, and
    returns the first match.

    Output is one key=value line per field, lowercase keys:
        folder=Inbox
        subject=RE: ...
        from=sender@example.com
        received=05/05/2026 06:38:53
        entry_id=000000008253A9...

    Exit 0 on match, exit 1 on not-found, exit 2 on error.

    The Message-Id is matched verbatim, so the angle brackets matter --
    PR_INTERNET_MESSAGE_ID stores the value WITH the surrounding < >.
    If the caller supplies a bare id (no brackets), this script wraps
    it before searching. Trailing CR/LF and surrounding whitespace are
    trimmed.

.PARAMETER MessageId
    The RFC 5322 Message-Id of the email to find. Brackets optional.
    Examples (all equivalent):
        abc123@example.com
        <abc123@example.com>

.PARAMETER Folders
    Comma-separated MAPI default-folder ids to search, in order.
    Defaults to "6,5" (Inbox, Sent Items). Other useful values:
        4   Outbox
        9   Calendar
        10  Contacts
        16  Drafts

.PARAMETER All
    Continue searching after the first match and emit every match.
    Without -All, the script stops at the first match.

.EXAMPLE
    Find-OutlookByMessageId.ps1 -MessageId '<abc@example.com>'

.EXAMPLE
    Find-OutlookByMessageId.ps1 -MessageId 'abc@example.com' -Folders '6,5,16'
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$MessageId,

    [string]$Folders = "6,5",

    [switch]$All
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# Normalize the Message-Id: trim whitespace, ensure angle brackets.
$mid = $MessageId.Trim()
if (-not $mid.StartsWith('<')) { $mid = '<' + $mid }
if (-not $mid.EndsWith('>'))   { $mid = $mid + '>' }

# Build the DASL filter. PR_INTERNET_MESSAGE_ID_W = 0x1035001F.
# Single quotes inside the filter value must be doubled.
$escaped = $mid.Replace("'", "''")
$filter = '@SQL="http://schemas.microsoft.com/mapi/proptag/0x1035001F" = ''' + $escaped + ''''

try {
    $ol = New-Object -ComObject Outlook.Application
} catch {
    Write-Error "Could not connect to Outlook. Is Outlook running?"
    exit 2
}

$ns = $ol.Session
$folderIds = $Folders.Split(',') | ForEach-Object { [int]$_.Trim() }

$anyFound = $false

try {
    foreach ($fid in $folderIds) {
        try {
            $folder = $ns.GetDefaultFolder($fid)
        } catch {
            Write-Warning "Could not open default folder id $fid : $_"
            continue
        }

        $items = $folder.Items
        $found = $items.Find($filter)
        while ($found) {
            $anyFound = $true
            Write-Output ("folder=" + $folder.Name)
            Write-Output ("subject=" + $found.Subject)
            Write-Output ("from=" + $found.SenderEmailAddress)
            Write-Output ("received=" + $found.ReceivedTime)
            Write-Output ("entry_id=" + $found.EntryID)
            if (-not $All) { exit 0 }
            Write-Output "---"
            $found = $items.FindNext()
        }
    }
} finally {
    if ($ns)  { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($ns)  | Out-Null }
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($ol) | Out-Null
}

if ($anyFound) { exit 0 }

Write-Output ("not_found=" + $mid)
exit 1
