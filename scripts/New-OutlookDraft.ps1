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

# --- Markdown to HTML conversion ---

function ConvertFrom-Markdown {
    param([string]$Markdown)

    $lines = $Markdown -split "`r?`n"

    # State machine
    $html = New-Object System.Text.StringBuilder
    $inCodeBlock = $false
    $inList = $false       # currently inside a list
    $listType = ''         # 'ul' or 'ol'
    $olItemCount = 0       # running count for ordered list continuity
    $paragraph = New-Object System.Collections.Generic.List[string]

    # Style constants
    $bodyFont = "font-family: Calibri, sans-serif; font-size: 11pt;"
    $codeBlockStyle = "font-family: Consolas, monospace; font-size: 10pt; background-color: #f5f5f5; padding: 8px 12px; border: 1px solid #e0e0e0; white-space: pre; display: block;"
    $inlineCodeStyle = "font-family: Consolas, monospace; font-size: 10pt; background-color: #f0f0f0; padding: 1px 4px;"

    # Flush accumulated paragraph lines
    function Flush-Paragraph {
        if ($paragraph.Count -gt 0) {
            $text = ($paragraph -join ' ')
            $text = Convert-InlineMarkdown $text
            [void]$html.AppendLine("<p style=`"$bodyFont margin: 0 0 10px 0;`">$text</p>")
            $paragraph.Clear()
        }
    }

    # Close any open list
    function Close-List {
        if ($inList) {
            [void]$html.AppendLine("</$listType>")
            Set-Variable -Name inList -Value $false -Scope 1
            Set-Variable -Name listType -Value '' -Scope 1
        }
    }

    # Convert inline markdown (bold, inline code, links)
    function Convert-InlineMarkdown {
        param([string]$text)

        # Inline code (do this first so content inside backticks is not processed)
        $text = [regex]::Replace($text, '`([^`]+)`', "<code style=`"$inlineCodeStyle`">`$1</code>")

        # Bold
        $text = [regex]::Replace($text, '\*\*(.+?)\*\*', '<b>$1</b>')

        # Links
        $text = [regex]::Replace($text, '\[([^\]]+)\]\(([^)]+)\)', '<a href="$2">$1</a>')

        return $text
    }

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]

        # --- Fenced code blocks ---
        if ($line -match '^\s*```') {
            if ($inCodeBlock) {
                # Closing fence
                [void]$html.AppendLine("</pre>")
                $inCodeBlock = $false
            } else {
                # Opening fence
                Flush-Paragraph
                Close-List
                [void]$html.Append("<pre style=`"$codeBlockStyle`">")
                $inCodeBlock = $true
            }
            continue
        }

        if ($inCodeBlock) {
            $escaped = [System.Net.WebUtility]::HtmlEncode($line)
            [void]$html.AppendLine($escaped)
            continue
        }

        # --- Blank line ---
        if ($line -match '^\s*$') {
            Flush-Paragraph
            Close-List
            continue
        }

        # --- Headers ---
        if ($line -match '^(#{1,3})\s+(.+)$') {
            Flush-Paragraph
            Close-List
            $olItemCount = 0
            $level = $matches[1].Length
            $headerText = Convert-InlineMarkdown ([System.Net.WebUtility]::HtmlEncode($matches[2]))
            switch ($level) {
                1 { $hStyle = "$bodyFont font-size: 16pt; font-weight: bold; margin: 0 0 10px 0;" }
                2 { $hStyle = "$bodyFont font-size: 14pt; font-weight: bold; margin: 0 0 8px 0;" }
                3 { $hStyle = "$bodyFont font-size: 12pt; font-weight: bold; margin: 0 0 6px 0;" }
            }
            [void]$html.AppendLine("<p style=`"$hStyle`">$headerText</p>")
            continue
        }

        # --- Bullet list ---
        if ($line -match '^\s*[-*]\s+(.+)$') {
            Flush-Paragraph
            $olItemCount = 0
            $itemText = Convert-InlineMarkdown ([System.Net.WebUtility]::HtmlEncode($matches[1]))
            if (-not $inList -or $listType -ne 'ul') {
                Close-List
                [void]$html.AppendLine("<ul style=`"$bodyFont margin: 0 0 10px 0; padding-left: 24px;`">")
                $inList = $true
                $listType = 'ul'
            }
            [void]$html.AppendLine("<li style=`"margin: 0 0 4px 0;`">$itemText</li>")
            continue
        }

        # --- Numbered list ---
        if ($line -match '^\s*\d+\.\s+(.+)$') {
            Flush-Paragraph
            $itemText = Convert-InlineMarkdown ([System.Net.WebUtility]::HtmlEncode($matches[1]))
            if (-not $inList -or $listType -ne 'ol') {
                Close-List
                if ($olItemCount -gt 0) {
                    $startAttr = " start=`"$($olItemCount + 1)`""
                } else {
                    $startAttr = ""
                }
                [void]$html.AppendLine("<ol${startAttr} style=`"$bodyFont margin: 0 0 10px 0; padding-left: 24px;`">")
                $inList = $true
                $listType = 'ol'
            }
            $olItemCount++
            [void]$html.AppendLine("<li style=`"margin: 0 0 4px 0;`">$itemText</li>")
            continue
        }

        # --- Regular text (accumulate into paragraph) ---
        Close-List
        $olItemCount = 0
        $escaped = [System.Net.WebUtility]::HtmlEncode($line)
        $paragraph.Add($escaped)
    }

    # Flush remaining state
    if ($inCodeBlock) {
        [void]$html.AppendLine("</pre>")
    }
    Flush-Paragraph
    Close-List

    return $html.ToString()
}

$htmlBody = ConvertFrom-Markdown $markdownText

# Wrap in a container div with base font
$fullHtml = @"
<div style="font-family: Calibri, sans-serif; font-size: 11pt;">
$htmlBody
</div>
"@

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
