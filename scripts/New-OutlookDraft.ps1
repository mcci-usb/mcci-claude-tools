# ORIGINAL SOURCE -- install to ~/.claude/scripts/ using install.sh
<#
.SYNOPSIS
    Creates an Outlook email draft from Markdown content.

.DESCRIPTION
    Converts Markdown to inline-styled HTML and opens an Outlook compose
    window with the content pre-filled. Does not send the email.

.PARAMETER To
    Recipient email address(es), semicolon-separated.

.PARAMETER Cc
    CC recipient email address(es), semicolon-separated.

.PARAMETER Bcc
    BCC recipient email address(es), semicolon-separated.

.PARAMETER Subject
    Email subject line.

.PARAMETER BodyFile
    Path to a Markdown (.md) file for the email body.

.PARAMETER Body
    Inline Markdown string for the email body (alternative to BodyFile).

.EXAMPLE
    .\New-OutlookDraft.ps1 -To "user@example.com" -Subject "Hello" -Body "**Bold** text"

.EXAMPLE
    .\New-OutlookDraft.ps1 -To "user@example.com" -Subject "Report" -BodyFile "C:\tmp\report.md"
#>

[CmdletBinding()]
param(
    [string]$To,
    [string]$Cc,
    [string]$Bcc,
    [string]$Subject,
    [string]$BodyFile,
    [string]$Body
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

try {
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
} catch {
    Write-Error "Failed to create Outlook mail item: $_"
    exit 1
} finally {
    # Release COM objects
    if ($mail) {
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($mail) | Out-Null
    }
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($outlook) | Out-Null
}
