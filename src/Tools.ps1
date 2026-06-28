<#
.SYNOPSIS
    Crabby AI — Built-in Tools
.DESCRIPTION
    Tool definitions and execution for shell, file I/O, web, and document creation.
    v2.0: Persistent session, safety guardrails, document creation (docx/xlsx/pptx/pdf).
#>

# ============================================================
# Persistent PowerShell Session
# ============================================================

$script:CrabbyRunspace = $null

function Initialize-CrabbyShell {
    if ($script:CrabbyRunspace -and $script:CrabbyRunspace.RunspaceStateInfo.State -eq 'Opened') {
        return
    }
    $script:CrabbyRunspace = [runspacefactory]::CreateRunspace()
    $script:CrabbyRunspace.Open()
    $script:CrabbyRunspace.SessionStateProxy.SetVariable('crabby_cwd', $env:USERPROFILE)
}

function Invoke-CrabbyShellCommand {
    param(
        [string]$Command,
        [int]$TimeoutSeconds = 30
    )
    
    Initialize-CrabbyShell
    
    # Dangerous command patterns
    $dangerousPatterns = @(
        'rm\s+(-r|-rf|-recurse|/s)',
        'Remove-Item.*-Recurse',
        'del\s+(/s|/q|-recurse)',
        'rmdir\s+(/s|/q)',
        'Format-Volume',
        'format\s+[a-z]:',
        'Stop-Computer',
        'Restart-Computer',
        'net\s+(user|localgroup)',
        'reg\s+(delete|add)',
        'Remove-Service'
    )
    
    foreach ($pattern in $dangerousPatterns) {
        if ($Command -match $pattern) {
            return "⚠️ DANGEROUS_COMMAND_DETECTED`nThe command may cause irreversible changes:`n  $Command`n`nIf you're sure, use the shell_confirm tool to proceed."
        }
    }
    
    $wrappedCommand = @"
try {
    $Command
    `$crabby_cwd = (Get-Location).Path
} catch {
    Write-Error `$_.Exception.Message
}
"@
    
    $pipeline = $script:CrabbyRunspace.CreatePipeline($wrappedCommand)
    
    $trackedCwd = $script:CrabbyRunspace.SessionStateProxy.GetVariable('crabby_cwd')
    if ($trackedCwd -and (Test-Path $trackedCwd)) {
        $pipeline.Commands.Insert(0, [System.Management.Automation.Runspaces.Command]::new("Set-Location"))
        $pipeline.Commands[0].Parameters.Add("Path", $trackedCwd)
    }
    
    $pipeline.InvokeAsync()
    $startTime = Get-Date
    $timeoutMs = $TimeoutSeconds * 1000
    
    # P1.7 Fix: Use synchronous wait with timeout instead of polling EndOfPipeline
    # This avoids race conditions with async output collection
    try {
        $pipeline.WaitForOutputAvailable($timeoutMs)
    }
    catch {
        # Timeout or other error, pipeline may have stopped
    }
    
    # Give a small delay for output to fully collect
    Start-Sleep -Milliseconds 200
    
    $output = @()
    foreach ($item in $pipeline.Output) { $output += $item.ToString() }
    $errors = @()
    foreach ($err in $pipeline.Error) { $errors += $err.ToString() }
    
    $result = ""
    if ($output.Count -gt 0) { $result = ($output -join "`n").Trim() }
    if ($errors.Count -gt 0) {
        $errText = ($errors -join "`n").Trim()
        if ($errText) { $result += "`n❌ $errText" }
    }
    
    $newCwd = $script:CrabbyRunspace.SessionStateProxy.GetVariable('crabby_cwd')
    if ($newCwd) { $script:CrabbyRunspace.SessionStateProxy.SetVariable('crabby_cwd', $newCwd) }
    
    if ($result.Length -gt 8000) { $result = $result.Substring(0, 8000) + "`n... (truncated)" }
    
    $cwdInfo = if ($newCwd) { $newCwd } elseif ($trackedCwd) { $trackedCwd } else { "unknown" }
    if ([string]::IsNullOrWhiteSpace($result)) {
        return "✅ Done. CWD: $cwdInfo"
    }
    $result += "`n📂 CWD: $cwdInfo"
    return $result
}

# ============================================================
# Document Creation Helpers
# ============================================================

function Test-PandocAvailable {
    try { pandoc --version | Out-Null; return $true } catch { return $false }
}

function Test-ImportExcelAvailable {
    try { Get-Module -ListAvailable ImportExcel | Out-Null; return $true } catch { return $false }
}

function Test-WkhtmltopdfAvailable {
    try { wkhtmltopdf --version | Out-Null; return $true } catch { return $false }
}

function New-CrabbyDocx {
    param([string]$Path, [string]$Content, [string]$Title = "")
    
    if (-not (Test-PandocAvailable)) {
        return "❌ pandoc not installed. Run .\setup-tools.ps1 first, or install from https://pandoc.org"
    }
    
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    
    # Build markdown with title
    $md = ""
    if ($Title) { $md += "# $Title`n`n" }
    $md += $Content
    
    # Write temp markdown
    $tempMd = [System.IO.Path]::GetTempFileName() + ".md"
    Set-Content $tempMd $md -Encoding UTF8
    
    try {
        pandoc $tempMd -o $Path --from markdown --to docx 2>&1 | Out-Null
        Remove-Item $tempMd -Force -ErrorAction SilentlyContinue
        
        if (Test-Path $Path) {
            $size = (Get-Item $Path).Length
            return "✅ Word document created: $Path ($size bytes)"
        }
        return "❌ Failed to create docx — pandoc returned no output"
    }
    catch {
        Remove-Item $tempMd -Force -ErrorAction SilentlyContinue
        return "❌ Error creating docx: $($_.Exception.Message)"
    }
}

function New-CrabbyXlsx {
    param([string]$Path, [string]$Data, [string]$SheetName = "Sheet1", [string]$Title = "")
    
    if (-not (Test-ImportExcelAvailable)) {
        return "❌ ImportExcel module not installed. Run .\setup-tools.ps1 first, or: Install-Module ImportExcel -Scope CurrentUser"
    }
    
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    
    try {
        Import-Module ImportExcel
        
        # Parse JSON data
        $rows = $Data | ConvertFrom-Json
        
        # Ensure it's an array
        if ($rows -isnot [System.Array]) { $rows = @($rows) }
        
        # Build export params
        $exportParams = @{
            Path         = $Path
            WorksheetName = $SheetName
            AutoSize     = $true
            AutoFilter   = $true
            FreezeTopRow = $true
            TableName    = "Data"
        }
        
        if ($Title) {
            # Add title row
            $exportParams.Title = $Title
            $exportParams.TitleFill = @{ SolidColor = "4472C4" }
            $exportParams.TitleFontSize = 14
            $exportParams.TitleBold = $true
        }
        
        $rows | Export-Excel @exportParams
        
        if (Test-Path $Path) {
            $size = (Get-Item $Path).Length
            return "✅ Excel spreadsheet created: $Path ($size bytes, $($rows.Count) rows)"
        }
        return "❌ Failed to create xlsx"
    }
    catch {
        return "❌ Error creating xlsx: $($_.Exception.Message)"
    }
}

function New-CrabbyPptx {
    param([string]$Path, [string]$Slides, [string]$Title = "Presentation")
    
    if (-not (Test-PandocAvailable)) {
        return "❌ pandoc not installed. Run .\setup-tools.ps1 first, or install from https://pandoc.org"
    }
    
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    
    try {
        # Build markdown with slide separators
        $slideData = $Slides | ConvertFrom-Json
        if ($slideData -isnot [System.Array]) { $slideData = @($slideData) }
        
        $md = "% $Title`n% $(whoami)`n% $(Get-Date -Format 'yyyy-MM-dd')`n`n"
        
        foreach ($slide in $slideData) {
            $slideTitle = if ($slide.title) { $slide.title } else { "Slide" }
            $slideContent = if ($slide.content) { $slide.content } else { "" }
            $slideNotes = if ($slide.notes) { $slide.notes } else { "" }
            
            $md += "---`n`n## $slideTitle`n`n$slideContent`n`n"
            if ($slideNotes) {
                $md += "::: notes`n$slideNotes`n:::`n`n"
            }
        }
        
        $tempMd = [System.IO.Path]::GetTempFileName() + ".md"
        Set-Content $tempMd $md -Encoding UTF8
        
        pandoc $tempMd -o $Path --from markdown --to pptx --slide-level=2 2>&1 | Out-Null
        Remove-Item $tempMd -Force -ErrorAction SilentlyContinue
        
        if (Test-Path $Path) {
            $size = (Get-Item $Path).Length
            return "✅ PowerPoint created: $Path ($size bytes, $($slideData.Count) slides)"
        }
        return "❌ Failed to create pptx"
    }
    catch {
        return "❌ Error creating pptx: $($_.Exception.Message)"
    }
}

function New-CrabbyPdf {
    param([string]$Path, [string]$Content, [string]$Title = "")
    
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    
    # Build HTML content with styling
    $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
body { font-family: 'Microsoft YaHei', 'SimSun', Arial, sans-serif; margin: 40px 60px; line-height: 1.8; color: #333; }
h1 { color: #2c3e50; border-bottom: 2px solid #3498db; padding-bottom: 10px; }
h2 { color: #34495e; margin-top: 30px; }
h3 { color: #7f8c8d; }
table { border-collapse: collapse; width: 100%; margin: 15px 0; }
th, td { border: 1px solid #bdc3c7; padding: 8px 12px; text-align: left; }
th { background-color: #3498db; color: white; }
tr:nth-child(even) { background-color: #f2f2f2; }
code { background-color: #ecf0f1; padding: 2px 6px; border-radius: 3px; font-size: 0.9em; }
pre { background-color: #2c3e50; color: #ecf0f1; padding: 15px; border-radius: 5px; overflow-x: auto; }
blockquote { border-left: 4px solid #3498db; margin: 15px 0; padding: 10px 20px; background: #f8f9fa; }
</style>
</head>
<body>
"@
    
    if ($Title) { $htmlContent += "<h1>$Title</h1>`n" }
    
    # Convert markdown-ish content to HTML
    # Simple converter: headings, bold, italic, code, lists, tables
    $lines = $Content -split "`n"
    $inCodeBlock = $false
    $inTable = $false
    
    foreach ($line in $lines) {
        # Code blocks
        if ($line -match '^```') {
            if ($inCodeBlock) {
                $htmlContent += "</pre>`n"
                $inCodeBlock = $false
            } else {
                $htmlContent += "<pre><code>"
                $inCodeBlock = $true
            }
            continue
        }
        if ($inCodeBlock) {
            $htmlContent += "$([System.Web.HttpUtility]::HtmlEncode($line))`n"
            continue
        }
        
        # Headings
        if ($line -match '^### (.+)') { $htmlContent += "<h3>$($Matches[1])</h3>`n"; continue }
        if ($line -match '^## (.+)')  { $htmlContent += "<h2>$($Matches[1])</h2>`n"; continue }
        if ($line -match '^# (.+)')   { $htmlContent += "<h1>$($Matches[1])</h1>`n"; continue }
        
        # Horizontal rule
        if ($line -match '^---+$') { $htmlContent += "<hr>`n"; continue }
        
        # Table rows
        if ($line -match '^\|') {
            if (-not $inTable) {
                $htmlContent += "<table>`n"
                $inTable = $true
            }
            $cells = $line -split '\|' | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^[-:]+$' }
            if ($line -match '^[-|:]+$') { continue } # Skip separator
            $htmlContent += "<tr>"
            foreach ($cell in $cells) {
                $htmlContent += "<td>$($cell.Trim())</td>"
            }
            $htmlContent += "</tr>`n"
            continue
        } elseif ($inTable) {
            $htmlContent += "</table>`n"
            $inTable = $false
        }
        
        # Blockquote
        if ($line -match '^>\s*(.*)') {
            $htmlContent += "<blockquote>$($Matches[1])</blockquote>`n"
            continue
        }
        
        # Unordered list
        if ($line -match '^[-*]\s+(.+)') {
            $htmlContent += "<li>$($Matches[1])</li>`n"
            continue
        }
        
        # Ordered list
        if ($line -match '^\d+\.\s+(.+)') {
            $htmlContent += "<li>$($Matches[1])</li>`n"
            continue
        }
        
        # Paragraph
        if ($line.Trim() -ne "") {
            $formatted = $line -replace '\*\*(.+?)\*\*', '<strong>$1</strong>'
            $formatted = $formatted -replace '\*(.+?)\*', '<em>$1</em>'
            $formatted = $formatted -replace '`(.+?)`', '<code>$1</code>'
            $htmlContent += "<p>$formatted</p>`n"
        }
    }
    
    if ($inTable) { $htmlContent += "</table>`n" }
    if ($inCodeBlock) { $htmlContent += "</pre>`n" }
    
    $htmlContent += "</body></html>"
    
    # Try wkhtmltopdf first
    if (Test-WkhtmltopdfAvailable) {
        $tempHtml = [System.IO.Path]::GetTempFileName() + ".html"
        Set-Content $tempHtml $htmlContent -Encoding UTF8
        
        try {
            wkhtmltopdf --quiet --encoding utf-8 --page-size A4 --margin-top 20 --margin-bottom 20 --margin-left 20 --margin-right 20 $tempHtml $Path 2>&1 | Out-Null
            Remove-Item $tempHtml -Force -ErrorAction SilentlyContinue
            
            if (Test-Path $Path) {
                $size = (Get-Item $Path).Length
                return "✅ PDF created: $Path ($size bytes)"
            }
        }
        catch {
            Remove-Item $tempHtml -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Try pandoc with wkhtmltopdf engine
    if (Test-PandocAvailable) {
        $tempMd = [System.IO.Path]::GetTempFileName() + ".md"
        $md = ""
        if ($Title) { $md += "# $Title`n`n" }
        $md += $Content
        Set-Content $tempMd $md -Encoding UTF8
        
        try {
            if (Test-WkhtmltopdfAvailable) {
                pandoc $tempMd -o $Path --pdf-engine=wkhtmltopdf 2>&1 | Out-Null
            } else {
                pandoc $tempMd -o $Path 2>&1 | Out-Null
            }
            Remove-Item $tempMd -Force -ErrorAction SilentlyContinue
            
            if (Test-Path $Path) {
                $size = (Get-Item $Path).Length
                return "✅ PDF created: $Path ($size bytes)"
            }
        }
        catch {
            Remove-Item $tempMd -Force -ErrorAction SilentlyContinue
        }
    }
    
    # Fallback: save as HTML
    $htmlPath = $Path -replace '\.pdf$', '.html'
    Set-Content $htmlPath $htmlContent -Encoding UTF8
    return "⚠️ PDF engine not available. Saved as HTML instead: $htmlPath`nInstall wkhtmltopdf or run .\setup-tools.ps1 for PDF support."
}

# ============================================================
# Tool Schema
# ============================================================

function Get-CrabbyToolsSchema {
    return @(
        @{
            type = "function"
            function = @{
                name = "shell"
                description = "Execute a PowerShell command on the local machine. Persistent session — variables, working directory, and imports persist across calls."
                parameters = @{
                    type = "object"
                    properties = @{
                        command = @{ type = "string"; description = "PowerShell command to execute" }
                        timeout = @{ type = "integer"; description = "Timeout in seconds (default 30, max 300)" }
                    }
                    required = @("command")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "shell_confirm"
                description = "Confirm and execute a previously blocked dangerous command. Only use when user explicitly says 'yes'."
                parameters = @{
                    type = "object"
                    properties = @{
                        command = @{ type = "string"; description = "The dangerous command to confirm" }
                    }
                    required = @("command")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "file_read"
                description = "Read file contents from local filesystem. Supports text files, code, config, etc."
                parameters = @{
                    type = "object"
                    properties = @{
                        path = @{ type = "string"; description = "Absolute path to the file" }
                        lines = @{ type = "integer"; description = "Number of lines to read (default: all)" }
                        offset = @{ type = "integer"; description = "Line number to start from (0-based)" }
                    }
                    required = @("path")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "file_write"
                description = "Write content to a file. Creates file and parent directories if needed. Supports .md, .txt, .json, .yaml, .html, .css, .js, .py, .ps1, etc."
                parameters = @{
                    type = "object"
                    properties = @{
                        path = @{ type = "string"; description = "Absolute path to the file" }
                        content = @{ type = "string"; description = "Content to write" }
                        append = @{ type = "boolean"; description = "Append instead of overwrite (default: false)" }
                    }
                    required = @("path", "content")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "file_edit"
                description = "Edit a specific part of a text file by replacing old text with new text."
                parameters = @{
                    type = "object"
                    properties = @{
                        path = @{ type = "string"; description = "Absolute path to the file" }
                        old_text = @{ type = "string"; description = "The text to find and replace" }
                        new_text = @{ type = "string"; description = "The replacement text" }
                        replace_all = @{ type = "boolean"; description = "Replace all occurrences (default: only first)" }
                    }
                    required = @("path", "old_text", "new_text")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "file_list"
                description = "List files and directories."
                parameters = @{
                    type = "object"
                    properties = @{
                        path = @{ type = "string"; description = "Directory path (default: current)" }
                        pattern = @{ type = "string"; description = "Filter pattern (e.g. '*.txt')" }
                        recurse = @{ type = "boolean"; description = "List recursively (default: false)" }
                    }
                    required = @()
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "file_download"
                description = "Download a file from a URL to a local path."
                parameters = @{
                    type = "object"
                    properties = @{
                        url = @{ type = "string"; description = "URL to download from" }
                        path = @{ type = "string"; description = "Local path to save the file" }
                    }
                    required = @("url", "path")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "file_create_docx"
                description = "Create a Word document (.docx) from markdown content. Supports headings, bold, italic, lists, tables, code blocks."
                parameters = @{
                    type = "object"
                    properties = @{
                        path = @{ type = "string"; description = "Output .docx file path" }
                        content = @{ type = "string"; description = "Markdown content for the document" }
                        title = @{ type = "string"; description = "Document title (optional)" }
                    }
                    required = @("path", "content")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "file_create_xlsx"
                description = "Create an Excel spreadsheet (.xlsx) from structured data. Data should be a JSON array of objects where keys become column headers."
                parameters = @{
                    type = "object"
                    properties = @{
                        path = @{ type = "string"; description = "Output .xlsx file path" }
                        data = @{ type = "string"; description = "JSON array of objects, e.g. [{Name:'Alice',Age:30},{Name:'Bob',Age:25}]" }
                        sheet_name = @{ type = "string"; description = "Worksheet name (default: Sheet1)" }
                        title = @{ type = "string"; description = "Title row (optional)" }
                    }
                    required = @("path", "data")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "file_create_pptx"
                description = "Create a PowerPoint presentation (.pptx) from slide data. Each slide has a title and content in markdown."
                parameters = @{
                    type = "object"
                    properties = @{
                        path = @{ type = "string"; description = "Output .pptx file path" }
                        slides = @{ type = "string"; description = 'JSON array of slides, e.g. [{title:"Intro",content:"Hello world"},{title:"Details",content:"- Point 1\n- Point 2"}]' }
                        title = @{ type = "string"; description = "Presentation title (default: Presentation)" }
                    }
                    required = @("path", "slides")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "file_create_pdf"
                description = "Create a PDF document from markdown content. Supports headings, bold, italic, lists, tables. Falls back to HTML if PDF engine unavailable."
                parameters = @{
                    type = "object"
                    properties = @{
                        path = @{ type = "string"; description = "Output .pdf file path" }
                        content = @{ type = "string"; description = "Markdown content for the document" }
                        title = @{ type = "string"; description = "Document title (optional)" }
                    }
                    required = @("path", "content")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "web_fetch"
                description = "Fetch content from a web page by URL."
                parameters = @{
                    type = "object"
                    properties = @{
                        url = @{ type = "string"; description = "URL to fetch" }
                    }
                    required = @("url")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "web_search"
                description = "Search the web. Returns results with titles and snippets."
                parameters = @{
                    type = "object"
                    properties = @{
                        query = @{ type = "string"; description = "Search query" }
                        count = @{ type = "integer"; description = "Number of results (default 5)" }
                    }
                    required = @("query")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "memory_save"
                description = "Save important information to persistent memory."
                parameters = @{
                    type = "object"
                    properties = @{
                        entry = @{ type = "string"; description = "Information to save" }
                    }
                    required = @("entry")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "skill_run"
                description = "Run an installed skill by name."
                parameters = @{
                    type = "object"
                    properties = @{
                        name = @{ type = "string"; description = "Skill name" }
                        arguments = @{ type = "string"; description = "JSON arguments" }
                    }
                    required = @("name")
                }
            }
        }
    )
}

function Get-CrabbyToolsDescription {
    return @"
- **shell** — Execute PowerShell commands (persistent session)
- **shell_confirm** — Confirm dangerous command
- **file_read** — Read file contents
- **file_write** — Write text files (.md, .txt, .json, .py, .ps1, .html, etc.)
- **file_edit** — Find and replace text in a file
- **file_list** — List directory contents
- **file_download** — Download file from URL
- **file_create_docx** — Create Word document (.docx) from markdown
- **file_create_xlsx** — Create Excel spreadsheet (.xlsx) from JSON data
- **file_create_pptx** — Create PowerPoint (.pptx) from slide data
- **file_create_pdf** — Create PDF from markdown
- **web_fetch** — Fetch web page content
- **web_search** — Search the web
- **memory_save** — Save to persistent memory
- **skill_run** — Run installed skill
"@
}

# ============================================================
# Tool Execution
# ============================================================

function Invoke-CrabbyTool {
    param(
        [string]$Name,
        [string]$Arguments,
        [string]$RootDir
    )
    
    # P0.2 Fix: Use $toolArgs instead of $args to avoid conflict with PowerShell's built-in $args
    $toolArgs = @{}
    if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
        try { 
            # P0.3 Fix: Use PS 5.1 compatible method instead of -AsHashtable
            $parsed = $Arguments | ConvertFrom-Json
            foreach ($prop in $parsed.PSObject.Properties) {
                $toolArgs[$prop.Name] = $prop.Value
            }
        }
        catch { $toolArgs = @{ _raw = $Arguments } }
    }
    
    try {
        switch ($Name) {
            "shell" {
                # P0.1 Fix: Dangerous command detection is in Invoke-CrabbyShellCommand
                $cmd = $toolArgs["command"]
                $timeout = if ($toolArgs["timeout"]) { [Math]::Min($toolArgs["timeout"], 300) } else { 30 }
                return Invoke-CrabbyShellCommand -Command $cmd -TimeoutSeconds $timeout
            }
            
            "shell_confirm" {
                # P0.1 Fix: Add dangerous command detection to shell_confirm for security
                $cmd = $toolArgs["command"]
                
                # Same dangerous pattern detection as shell
                $dangerousPatterns = @(
                    'rm\s+(-r|-rf|-recurse|/s)',
                    'Remove-Item.*-Recurse',
                    'del\s+(/s|/q|-recurse)',
                    'rmdir\s+(/s|/q)',
                    'Format-Volume',
                    'format\s+[a-z]:',
                    'Stop-Computer',
                    'Restart-Computer',
                    'net\s+(user|localgroup)',
                    'reg\s+(delete|add)',
                    'Remove-Service'
                )
                
                foreach ($pattern in $dangerousPatterns) {
                    if ($cmd -match $pattern) {
                        return "⚠️ DANGEROUS_COMMAND_BLOCKED`nConfirmed command still matches dangerous pattern:`n  $cmd`n`nThis command has been blocked for safety."
                    }
                }
                
                Initialize-CrabbyShell
                $pipeline = $script:CrabbyRunspace.CreatePipeline($cmd)
                
                # P1.8 Fix: Add cwd tracking like shell does
                $trackedCwd = $script:CrabbyRunspace.SessionStateProxy.GetVariable('crabby_cwd')
                if ($trackedCwd -and (Test-Path $trackedCwd)) {
                    $pipeline.Commands.Insert(0, [System.Management.Automation.Runspaces.Command]::new("Set-Location"))
                    $pipeline.Commands[0].Parameters.Add("Path", $trackedCwd)
                }
                
                $output = $pipeline.Invoke() | Out-String
                
                # P1.8 Fix: Update cwd tracking after execution
                $newCwd = $script:CrabbyRunspace.SessionStateProxy.GetVariable('crabby_cwd')
                if ($newCwd) { $script:CrabbyRunspace.SessionStateProxy.SetVariable('crabby_cwd', $newCwd) }
                
                $result = $output.Trim()
                if ($result.Length -gt 8000) { $result = $result.Substring(0, 8000) + "`n... (truncated)" }
                $cwdInfo = if ($newCwd) { $newCwd } elseif ($trackedCwd) { $trackedCwd } else { "unknown" }
                if ([string]::IsNullOrWhiteSpace($result)) {
                    return "✅ Done. CWD: $cwdInfo"
                }
                return $result + "`n📂 CWD: $cwdInfo"
            }
            
            "file_read" {
                # P1.6 Fix: Add path boundary check for sensitive directories
                $path = $toolArgs["path"]
                $lines = $toolArgs["lines"]
                $offset = if ($toolArgs["offset"]) { $toolArgs["offset"] } else { 0 }
                
                # Check for path traversal attempts
                $normalizedPath = $path -replace '\\', '/'
                if ($normalizedPath -match '\.\./' -or $normalizedPath -match '/\.\.') {
                    return "❌ Path traversal attempt detected: $path"
                }
                
                # P1.6 Fix: Block sensitive system directories (Windows)
                $normalizedPathUpper = $normalizedPath.ToUpper()
                $sensitivePaths = @('C:\WINDOWS', 'C:\PROGRAM FILES', 'C:\PROGRAM FILES (X86)', 
                                   'C:\PROGRAM DATA', 'C:\SYSTEM', 'C:\BOOT',
                                   'C:\RECOVERY', 'C:\$', '/WINDOWS', '/PROGRAM FILES', 
                                   '/PROGRAM FILES (X86)', '/PROGRAM DATA', '/SYSTEM',
                                   '/BOOT', '/RECOVERY', '/ETC', '/ROOT', '/VAR', '/SYS')
                
                foreach ($sensitive in $sensitivePaths) {
                    if ($normalizedPathUpper.StartsWith($sensitive.ToUpper())) {
                        return "❌ Access denied: Cannot read from system directory: $path"
                    }
                }
                
                if (-not (Test-Path $path)) { return "File not found: $path" }
                
                $content = Get-Content $path -Encoding UTF8
                if ($offset -gt 0) { $content = $content | Select-Object -Skip $offset }
                if ($lines) { $content = $content | Select-Object -First $lines }
                
                $result = ($content | Out-String).Trim()
                if ($result.Length -gt 10000) {
                    $result = $result.Substring(0, 10000) + "`n... (truncated, use offset to read more)"
                }
                return $result
            }
            
            "file_write" {
                $path = $toolArgs["path"]
                $content = $toolArgs["content"]
                $append = $toolArgs["append"]
                
                $dir = Split-Path $path -Parent
                if ($dir -and -not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
                
                if ($append) {
                    Add-Content $path $content -Encoding UTF8
                } else {
                    Set-Content $path $content -Encoding UTF8 -NoNewline
                }
                return "✅ File written: $path ($($content.Length) chars)"
            }
            
            "file_edit" {
                $path = $toolArgs["path"]
                $oldText = $toolArgs["old_text"]
                $newText = $toolArgs["new_text"]
                $replaceAll = $toolArgs["replace_all"]
                
                if (-not (Test-Path $path)) { return "File not found: $path" }
                
                $content = Get-Content $path -Raw -Encoding UTF8
                
                if ($content -notlike "*$oldText*") {
                    return "❌ Text not found in file: '$oldText'"
                }
                
                # P0.5 Fix: Use literal string replacement instead of regex to avoid $1/$2 injection
                if ($replaceAll) {
                    # Use IndexOf for literal replacement (case-sensitive)
                    $escapedOld = [regex]::Escape($oldText)
                    $newContent = $content -replace $escapedOld, $newText
                } else {
                    $idx = $content.IndexOf($oldText)
                    if ($idx -ge 0) {
                        $newContent = $content.Substring(0, $idx) + $newText + $content.Substring($idx + $oldText.Length)
                    }
                }
                
                Set-Content $path $newContent -Encoding UTF8 -NoNewline
                return "✅ File edited: $path"
            }
            
            "file_list" {
                $path = if ($toolArgs["path"]) { $toolArgs["path"] } else { "." }
                $pattern = if ($toolArgs["pattern"]) { $toolArgs["pattern"] } else { "*" }
                $recurse = $toolArgs["recurse"]
                
                $params = @{ Path = $path; Filter = $pattern }
                if ($recurse) { $params.Recurse = $true }
                
                $items = Get-ChildItem @params | Select-Object Mode, LastWriteTime, @{N='Size';E={if($_.PSIsContainer){'<DIR>'}else{$_.Length}}}, Name
                return ($items | Format-Table -AutoSize | Out-String).Trim()
            }
            
            "file_download" {
                $url = $toolArgs["url"]
                $path = $toolArgs["path"]
                
                $dir = Split-Path $path -Parent
                if ($dir -and -not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
                
                try {
                    Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing -TimeoutSec 120
                    if (Test-Path $path) {
                        $size = (Get-Item $path).Length
                        return "✅ Downloaded: $path ($size bytes) from $url"
                    }
                    return "❌ Download failed — file not created"
                }
                catch {
                    return "❌ Download error: $($_.Exception.Message)"
                }
            }
            
            "file_create_docx" {
                return New-CrabbyDocx -Path $toolArgs["path"] -Content $toolArgs["content"] -Title $(if($toolArgs["title"]){$toolArgs["title"]}else{""})
            }
            
            "file_create_xlsx" {
                return New-CrabbyXlsx -Path $toolArgs["path"] -Data $toolArgs["data"] -SheetName $(if($toolArgs["sheet_name"]){$toolArgs["sheet_name"]}else{"Sheet1"}) -Title $(if($toolArgs["title"]){$toolArgs["title"]}else{""})
            }
            
            "file_create_pptx" {
                return New-CrabbyPptx -Path $toolArgs["path"] -Slides $toolArgs["slides"] -Title $(if($toolArgs["title"]){$toolArgs["title"]}else{"Presentation"})
            }
            
            "file_create_pdf" {
                return New-CrabbyPdf -Path $toolArgs["path"] -Content $toolArgs["content"] -Title $(if($toolArgs["title"]){$toolArgs["title"]}else{""})
            }
            
            "web_fetch" {
                $url = $toolArgs["url"]
                try {
                    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
                    $content = $response.Content -replace '<[^>]+>', ' ' -replace '\s+', ' '
                    $content = $content.Trim()
                    if ($content.Length -gt 8000) { $content = $content.Substring(0, 8000) + "... (truncated)" }
                    return $content
                }
                catch { return "❌ Fetch failed: $($_.Exception.Message)" }
            }
            
            "web_search" {
                $query = $toolArgs["query"]
                $count = if ($toolArgs["count"]) { $toolArgs["count"] } else { 5 }
                $searchUrl = "https://html.duckduckgo.com/html/?q=$([Uri]::EscapeDataString($query))"
                try {
                    $response = Invoke-WebRequest -Uri $searchUrl -UseBasicParsing -TimeoutSec 15
                    $html = $response.Content
                    $results = @()
                    $regex = '<a rel="nofollow" class="result__a" href="([^"]+)">(.*?)</a>.*?<a class="result__snippet"[^>]*>(.*?)</a>'
                    $matches = [regex]::Matches($html, $regex, [System.Text.RegularExpressions.RegexOptions]::Singleline)
                    foreach ($m in $matches | Select-Object -First $count) {
                        $title = $m.Groups[2].Value -replace '<[^>]+>', '' -replace '&amp;', '&'
                        $snippet = $m.Groups[3].Value -replace '<[^>]+>', '' -replace '&amp;', '&'
                        $link = $m.Groups[1].Value
                        $results += "- **$title**`n  $snippet`n  $link"
                    }
                    if ($results.Count -eq 0) { return "No results found for: $query" }
                    return ($results -join "`n`n")
                }
                catch { return "❌ Search failed: $($_.Exception.Message)" }
            }
            
            "memory_save" {
                Add-CrabbyMemory -RootDir $RootDir -Entry $toolArgs["entry"]
                return "💾 Saved to memory: $($toolArgs["entry"])"
            }
            
            "skill_run" {
                return Invoke-CrabbySkillByName -Name $toolArgs["name"] -Arguments $toolArgs["arguments"] -RootDir $RootDir
            }
            
            default { return "❌ Unknown tool: $Name" }
        }
    }
    catch {
        return "❌ Tool error ($Name): $($_.Exception.Message)"
    }
}

# Initialize shell on module load
Initialize-CrabbyShell
