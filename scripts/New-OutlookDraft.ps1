# ORIGINAL SOURCE -- install to ~/.claude/scripts/ using install.sh
<#
.SYNOPSIS
    Creates an Outlook email draft (new or reply) from Markdown content.

.DESCRIPTION
    Converts Markdown to inline-styled HTML and opens an Outlook compose
    window with the content pre-filled. Does not send the email.

    In reply mode (-EntryID), finds the original message and creates a
    threaded reply with proper In-Reply-To/References headers.

.PARAMETER To
    Recipient email address(es), semicolon-separated. Not used in reply mode.

.PARAMETER Cc
    CC recipient email address(es), semicolon-separated.
    In reply mode, overrides the reply's CC if specified.

.PARAMETER Bcc
    BCC recipient email address(es), semicolon-separated.

.PARAMETER Subject
    Email subject line. Not used in reply mode (Outlook adds "RE:" automatically).

.PARAMETER BodyFile
    Path to a Markdown (.md) file for the email body.

.PARAMETER Body
    Inline Markdown string for the email body (alternative to BodyFile).

.PARAMETER EntryID
    Outlook EntryID of the message to reply to. When specified, creates a
    threaded reply instead of a new message. Get this from Outlook via:
      (New-Object -ComObject Outlook.Application).ActiveExplorer().Selection.Item(1).EntryID

.PARAMETER ReplyAll
    Use ReplyAll instead of Reply. Only valid with -EntryID.

.EXAMPLE
    .\New-OutlookDraft.ps1 -To "user@example.com" -Subject "Hello" -Body "**Bold** text"

.EXAMPLE
    .\New-OutlookDraft.ps1 -To "user@example.com" -Subject "Report" -BodyFile "C:\tmp\report.md"

.EXAMPLE
    .\New-OutlookDraft.ps1 -EntryID "00000000ABC..." -ReplyAll -Body "Thanks for the update."
#>

[CmdletBinding()]
param(
    [string]$To,
    [string]$Cc,
    [string]$Bcc,
    [string]$Subject,
    [string]$BodyFile,
    [string]$Body,
    [string]$EntryID,
    [switch]$ReplyAll
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# --- Validate input ---
if ($BodyFile -and $Body) {
    Write-Error "Specify either -BodyFile or -Body, not both."
    exit 1
}
if (-not $BodyFile -and -not $Body) {
    Write-Error "Specify -BodyFile or -Body."
    exit 1
}
if ($ReplyAll -and -not $EntryID) {
    Write-Error "-ReplyAll requires -EntryID."
    exit 1
}
if ($EntryID -and $To) {
    Write-Error "-To is not used in reply mode. Recipients come from the original message."
    exit 1
}
if ($EntryID -and $Subject) {
    Write-Error "-Subject is not used in reply mode. Outlook adds 'RE:' automatically."
    exit 1
}

if ($BodyFile) {
    if (-not (Test-Path $BodyFile)) {
        Write-Error "File not found: $BodyFile"
        exit 1
    }
    $markdownText = [System.IO.File]::ReadAllText($BodyFile)
} else {
    $markdownText = $Body
}

# --- Markdown to HTML conversion via md-to-email-html.py ---

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$converterScript = Join-Path $scriptDir "md-to-email-html.py"

if (-not (Test-Path $converterScript)) {
    Write-Error "Converter script not found: $converterScript"
    exit 1
}

# Write markdown to a temp file if using -Body
$tempMd = $null
if ($Body) {
    $tempMd = [System.IO.Path]::GetTempFileName() + ".md"
    [System.IO.File]::WriteAllText($tempMd, $markdownText)
    $BodyFile = $tempMd
}

try {
    # Ensure PowerShell captures UTF-8 stdout from the Python subprocess
    $savedOutputEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    # uv run emits install/download messages on stderr; let those pass
    # through to the console but only capture stdout.
    $fullHtml = & uv run $converterScript $BodyFile
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Markdown conversion failed (exit code $LASTEXITCODE)"
        exit 1
    }
    if ($fullHtml -is [System.Array]) {
        $fullHtml = $fullHtml -join "`n"
    }
} finally {
    [Console]::OutputEncoding = $savedOutputEncoding
    if ($tempMd -and (Test-Path $tempMd)) {
        Remove-Item $tempMd -Force
    }
}

# --- Outlook COM automation ---
try {
    $outlook = New-Object -ComObject Outlook.Application
} catch {
    Write-Error "Could not connect to Outlook. Make sure Outlook is running."
    exit 1
}

$namespace = $null
$original = $null

try {
    if ($EntryID) {
        # Reply mode: find original message and create a threaded reply
        $namespace = $outlook.GetNamespace("MAPI")
        $original = $namespace.GetItemFromID($EntryID)
        if ($ReplyAll) {
            $mail = $original.ReplyAll()
        } else {
            $mail = $original.Reply()
        }
        # Prepend new body before the quoted original
        $mail.HTMLBody = $fullHtml + $mail.HTMLBody
        if ($Cc) { $mail.CC = $Cc }
        if ($Bcc) { $mail.BCC = $Bcc }
        $mail.Display()
        Write-Host "Outlook reply draft opened."
    } else {
        # New message mode
        # olMailItem = 0
        $mail = $outlook.CreateItem(0)

        if ($To) {
            $mail.To = $To
        }
        if ($Cc) {
            $mail.CC = $Cc
        }
        if ($Bcc) {
            $mail.BCC = $Bcc
        }
        if ($Subject) {
            $mail.Subject = $Subject
        }

        $mail.HTMLBody = $fullHtml
        $mail.Display()

        Write-Host "Outlook draft opened."
    }
} catch {
    Write-Error "Failed to create Outlook mail item: $_"
    exit 1
} finally {
    # Release COM objects
    if ($mail) {
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($mail) | Out-Null
    }
    if ($original) {
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($original) | Out-Null
    }
    if ($namespace) {
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($namespace) | Out-Null
    }
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($outlook) | Out-Null
}
