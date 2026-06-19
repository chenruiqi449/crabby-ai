<#
.SYNOPSIS
    Crabby AI — Native Windows GUI (WPF)
.DESCRIPTION
    Beautiful desktop chat interface using WPF. No browser, no web server, no extra dependencies.
    Just run it and chat.
#>

param([string]$RootDir = "")

if (-not $RootDir) {
    # When running as compiled .exe, use the exe's directory
    $exePath = [Environment]::GetCommandLineArgs()[0]
    if ($exePath -and (Test-Path $exePath)) {
        $RootDir = Split-Path -Parent $exePath
    } else {
        $RootDir = $PSScriptRoot
    }
}
$ErrorActionPreference = "Stop"

# Load modules




#region ===== LLM =====
<#
.SYNOPSIS
    Crabby AI — LLM API Client
.DESCRIPTION
    OpenAI-compatible API client supporting SiliconFlow, Zhipu, DeepSeek, etc.
#>

function Get-CrabbySettings {
    param([string]$RootDir)
    
    $settingsPath = Join-Path $RootDir "config\settings.json"
    
    if (-not (Test-Path $settingsPath)) {
        Write-Host "🦀 First run detected! Let's set you up." -ForegroundColor Cyan
        Write-Host ""
        
        $settings = Invoke-CrabbyOnboard -RootDir $RootDir
        return $settings
    }
    
    $raw = Get-Content $settingsPath -Raw -Encoding UTF8
    return $raw | ConvertFrom-Json
}

function Invoke-CrabbyOnboard {
    param([string]$RootDir)
    
    Write-Host "  🦀 Crabby AI Setup Wizard" -ForegroundColor DarkCyan
    Write-Host "  ─────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    
    # Select provider
    Write-Host "  Choose your LLM provider:" -ForegroundColor Gray
    Write-Host "  1. SiliconFlow (硅基流动) — Free 2000万 tokens" -ForegroundColor Gray
    Write-Host "  2. Zhipu (智谱) — Free 2000万 tokens" -ForegroundColor Gray
    Write-Host "  3. DeepSeek — 200万 tokens/7天" -ForegroundColor Gray
    Write-Host "  4. OpenAI — Paid" -ForegroundColor Gray
    Write-Host "  5. Custom (OpenAI-compatible)" -ForegroundColor Gray
    Write-Host ""
    
    $choice = Read-Host "  Enter number (1-5)"
    
    $providers = @{
        "1" = @{ name = "siliconflow"; base_url = "https://api.siliconflow.cn/v1"; model = "Qwen/Qwen3-8B" }
        "2" = @{ name = "zhipu"; base_url = "https://open.bigmodel.cn/api/paas/v4/"; model = "glm-4-flash" }
        "3" = @{ name = "deepseek"; base_url = "https://api.deepseek.com/v1"; model = "deepseek-chat" }
        "4" = @{ name = "openai"; base_url = "https://api.openai.com/v1"; model = "gpt-4o-mini" }
        "5" = @{ name = "custom"; base_url = ""; model = "" }
    }
    
    $provider = $providers[$choice]
    
    if (-not $provider) {
        $provider = $providers["1"]
    }
    
    if ($choice -eq "5") {
        $provider.base_url = Read-Host "  Enter base URL (e.g. https://api.example.com/v1)"
        $provider.model = Read-Host "  Enter model name"
    }
    
    $apiKey = Read-Host "  Enter your API key"
    
    Write-Host ""
    $userName = Read-Host "  Your name (for personalization)"
    
    # Build settings
    $settings = @{
        llm = @{
            provider = $provider.name
            api_key = $apiKey
            model = $provider.model
            base_url = $provider.base_url
            max_tokens = 1024
            temperature = 0.7
            repetition_penalty = 1.1
        }
        user = @{
            name = $userName
        }
    }
    
    # Save settings
    $configDir = Join-Path $RootDir "config"
    if (-not (Test-Path $configDir)) {
        New-Item -Path $configDir -ItemType Directory -Force | Out-Null
    }
    
    $settings | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $RootDir "config\settings.json") -Encoding UTF8
    
    # Create default SOUL.md if not exists
    $soulPath = Join-Path $RootDir "config\SOUL.md"
    if (-not (Test-Path $soulPath)) {
        $defaultSoul = @"
# Crabby Soul

You are Crabby 🦀, a personal AI assistant.
You are helpful, witty, and slightly snarky — like a clever crab who's always got your back.
You speak concisely and naturally, avoiding robotic phrases.
You adapt your tone to the user's mood: supportive when they're stuck, celebratory when they succeed, and gently honest when they need a reality check.
"@
        Set-Content $soulPath $defaultSoul -Encoding UTF8
    }
    
    # Create default USER.md
    $userPath = Join-Path $RootDir "config\USER.md"
    if (-not (Test-Path $userPath)) {
        Set-Content $userPath "## User Profile`n- Name: $userName" -Encoding UTF8
    }
    
    # Create memory directory
    $memDir = Join-Path $RootDir "memory"
    if (-not (Test-Path $memDir)) {
        New-Item -Path $memDir -ItemType Directory -Force | Out-Null
    }
    $memFile = Join-Path $memDir "MEMORY.md"
    if (-not (Test-Path $memFile)) {
        Set-Content $memFile "# Crabby Memory`n" -Encoding UTF8
    }
    
    Write-Host ""
    Write-Host "  🦀 Setup complete! Run .\crabby.ps1 to start chatting." -ForegroundColor DarkCyan
    Write-Host ""
    
    return $settings
}

function Invoke-CrabbyLLM {
    param(
        [object]$Settings,
        [string]$SystemPrompt,
        [string]$UserMessage,
        [int]$MaxTokens = 0
    )
    
    if ($MaxTokens -eq 0) { $MaxTokens = $Settings.llm.max_tokens }
    
    $messages = @(
        @{ role = "system"; content = $SystemPrompt }
        @{ role = "user"; content = $UserMessage }
    )
    
    $body = @{
        model = $Settings.llm.model
        messages = $messages
        max_tokens = $MaxTokens
        temperature = $Settings.llm.temperature
    }
    
    if ($Settings.llm.repetition_penalty) {
        $body.repetition_penalty = $Settings.llm.repetition_penalty
    }
    
    $headers = @{
        "Authorization" = "Bearer $($Settings.llm.api_key)"
        "Content-Type" = "application/json"
    }
    
    $url = "$($Settings.llm.base_url)/chat/completions"
    
    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body ($body | ConvertTo-Json -Depth 10 -Compress) -ContentType "application/json" -TimeoutSec 60
        return $response.choices[0].message.content
    }
    catch {
        Write-Host "  ❌ LLM Error: $($_.Exception.Message)" -ForegroundColor Red
        return "[Error calling LLM: $($_.Exception.Message)]"
    }
}

function Invoke-CrabbyChat {
    param(
        [object]$Settings,
        [array]$Conversation,
        [bool]$SupportTools = $false
    )
    
    $body = @{
        model = $Settings.llm.model
        messages = $Conversation
        max_tokens = $Settings.llm.max_tokens
        temperature = $Settings.llm.temperature
    }
    
    if ($Settings.llm.repetition_penalty) {
        $body.repetition_penalty = $Settings.llm.repetition_penalty
    }
    
    if ($SupportTools) {
        $body.tools = Get-CrabbyToolsSchema
        $body.tool_choice = "auto"
    }
    
    $headers = @{
        "Authorization" = "Bearer $($Settings.llm.api_key)"
        "Content-Type" = "application/json"
    }
    
    $url = "$($Settings.llm.base_url)/chat/completions"
    
    try {
        $jsonBody = $body | ConvertTo-Json -Depth 10
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $jsonBody -ContentType "application/json" -TimeoutSec 120
        
        $choice = $response.choices[0]
        $msg = $choice.message
        
        $result = @{
            Content = if ($msg.content) { $msg.content } else { "" }
            ToolCalls = $null
        }
        
        if ($msg.tool_calls -and $msg.tool_calls.Count -gt 0) {
            $result.ToolCalls = $msg.tool_calls
        }
        
        return $result
    }
    catch {
        Write-Host "  ❌ LLM Error: $($_.Exception.Message)" -ForegroundColor Red
        return @{ Content = "[Error calling LLM: $($_.Exception.Message)]"; ToolCalls = $null }
    }
}

#endregion ===== LLM =====

#region ===== Memory =====
<#
.SYNOPSIS
    Crabby AI — Memory Management
.DESCRIPTION
    Persistent memory using Markdown files, inspired by OpenClaw.
#>

function Get-CrabbySoul {
    param([string]$RootDir)
    
    $soulPath = Join-Path $RootDir "config\SOUL.md"
    
    if (Test-Path $soulPath) {
        return Get-Content $soulPath -Raw -Encoding UTF8
    }
    
    return "You are Crabby, a helpful AI assistant."
}

function Get-CrabbyUserProfile {
    param([string]$RootDir)
    
    $userPath = Join-Path $RootDir "config\USER.md"
    
    if (Test-Path $userPath) {
        return Get-Content $userPath -Raw -Encoding UTF8
    }
    
    return "No user profile set."
}

function Get-CrabbyMemoryContent {
    param([string]$RootDir)
    
    $memPath = Join-Path $RootDir "memory\MEMORY.md"
    
    if (Test-Path $memPath) {
        $content = Get-Content $memPath -Raw -Encoding UTF8
        # Trim if too long (keep last 3000 chars)
        if ($content.Length -gt 3000) {
            $content = "...(truncated)`n" + $content.Substring($content.Length - 3000)
        }
        return $content
    }
    
    return "No memory yet."
}

function Add-CrabbyMemory {
    param(
        [string]$RootDir,
        [string]$Entry
    )
    
    $memPath = Join-Path $RootDir "memory\MEMORY.md"
    $memDir = Split-Path $memPath -Parent
    
    if (-not (Test-Path $memDir)) {
        New-Item -Path $memDir -ItemType Directory -Force | Out-Null
    }
    
    if (-not (Test-Path $memPath)) {
        Set-Content $memPath "# Crabby Memory`n" -Encoding UTF8
    }
    
    $current = Get-Content $memPath -Raw -Encoding UTF8
    
    # Keep memory under ~5000 chars
    if ($current.Length -gt 5000) {
        $lines = $current -split "`n"
        $header = $lines[0]
        $body = ($lines | Select-Object -Skip 1) -join "`n"
        $body = $body.Substring([Math]::Max(0, $body.Length - 4000))
        $current = "$header`n$body"
    }
    
    $updated = "$current`n- $Entry"
    Set-Content $memPath $updated -Encoding UTF8
}

function Save-CrabbyConversation {
    param(
        [string]$RootDir,
        [string]$UserMessage,
        [string]$AssistantResponse
    )
    
    $convDir = Join-Path $RootDir "memory\conversations"
    
    if (-not (Test-Path $convDir)) {
        New-Item -Path $convDir -ItemType Directory -Force | Out-Null
    }
    
    $dateStr = Get-Date -Format "yyyy-MM-dd"
    $convFile = Join-Path $convDir "$dateStr.md"
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $entry = @"

## $timestamp

**User:** $UserMessage

**Crabby:** $AssistantResponse

"@
    
    if (Test-Path $convFile) {
        Add-Content $convFile $entry -Encoding UTF8
    } else {
        Set-Content $convFile "# Conversation — $dateStr$entry" -Encoding UTF8
    }
}

function Get-CrabbyRecentConversation {
    param(
        [string]$RootDir,
        [int]$Count = 5
    )
    
    $convDir = Join-Path $RootDir "memory\conversations"
    
    if (-not (Test-Path $convDir)) {
        return @()
    }
    
    $files = Get-ChildItem $convDir -Filter "*.md" | Sort-Object Name -Descending | Select-Object -First 1
    
    if ($files.Count -eq 0) {
        return @()
    }
    
    $content = Get-Content $files[0].FullName -Raw -Encoding UTF8
    
    # Parse conversation entries (simple approach)
    $entries = $content -split "## \d{2}:\d{2}:\d{2}" | Where-Object { $_.Trim() -ne "" } | Select-Object -Last $Count
    
    return $entries
}

#endregion ===== Memory =====

#region ===== Tools =====
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
    
    while (-not $pipeline.Output.EndOfPipeline) {
        if (((Get-Date) - $startTime).TotalMilliseconds -gt $timeoutMs) {
            $pipeline.Stop()
            return "⏱️ Command timed out after $TimeoutSeconds seconds."
        }
        Start-Sleep -Milliseconds 100
    }
    
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
    
    $args = @{}
    if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
        try { $args = $Arguments | ConvertFrom-Json -AsHashtable }
        catch { $args = @{ _raw = $Arguments } }
    }
    
    try {
        switch ($Name) {
            "shell" {
                $cmd = $args["command"]
                $timeout = if ($args["timeout"]) { [Math]::Min($args["timeout"], 300) } else { 30 }
                return Invoke-CrabbyShellCommand -Command $cmd -TimeoutSeconds $timeout
            }
            
            "shell_confirm" {
                $cmd = $args["command"]
                Initialize-CrabbyShell
                $pipeline = $script:CrabbyRunspace.CreatePipeline($cmd)
                $trackedCwd = $script:CrabbyRunspace.SessionStateProxy.GetVariable('crabby_cwd')
                if ($trackedCwd -and (Test-Path $trackedCwd)) {
                    $pipeline.Commands.Insert(0, [System.Management.Automation.Runspaces.Command]::new("Set-Location"))
                    $pipeline.Commands[0].Parameters.Add("Path", $trackedCwd)
                }
                $output = $pipeline.Invoke() | Out-String
                return $output.Trim()
            }
            
            "file_read" {
                $path = $args["path"]
                $lines = $args["lines"]
                $offset = if ($args["offset"]) { $args["offset"] } else { 0 }
                
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
                $path = $args["path"]
                $content = $args["content"]
                $append = $args["append"]
                
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
                $path = $args["path"]
                $oldText = $args["old_text"]
                $newText = $args["new_text"]
                $replaceAll = $args["replace_all"]
                
                if (-not (Test-Path $path)) { return "File not found: $path" }
                
                $content = Get-Content $path -Raw -Encoding UTF8
                
                if ($content -notlike "*$oldText*") {
                    return "❌ Text not found in file: '$oldText'"
                }
                
                if ($replaceAll) {
                    $newContent = $content -replace [regex]::Escape($oldText), $newText
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
                $path = if ($args["path"]) { $args["path"] } else { "." }
                $pattern = if ($args["pattern"]) { $args["pattern"] } else { "*" }
                $recurse = $args["recurse"]
                
                $params = @{ Path = $path; Filter = $pattern }
                if ($recurse) { $params.Recurse = $true }
                
                $items = Get-ChildItem @params | Select-Object Mode, LastWriteTime, @{N='Size';E={if($_.PSIsContainer){'<DIR>'}else{$_.Length}}}, Name
                return ($items | Format-Table -AutoSize | Out-String).Trim()
            }
            
            "file_download" {
                $url = $args["url"]
                $path = $args["path"]
                
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
                return New-CrabbyDocx -Path $args["path"] -Content $args["content"] -Title $(if($args["title"]){$args["title"]}else{""})
            }
            
            "file_create_xlsx" {
                return New-CrabbyXlsx -Path $args["path"] -Data $args["data"] -SheetName $(if($args["sheet_name"]){$args["sheet_name"]}else{"Sheet1"}) -Title $(if($args["title"]){$args["title"]}else{""})
            }
            
            "file_create_pptx" {
                return New-CrabbyPptx -Path $args["path"] -Slides $args["slides"] -Title $(if($args["title"]){$args["title"]}else{"Presentation"})
            }
            
            "file_create_pdf" {
                return New-CrabbyPdf -Path $args["path"] -Content $args["content"] -Title $(if($args["title"]){$args["title"]}else{""})
            }
            
            "web_fetch" {
                $url = $args["url"]
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
                $query = $args["query"]
                $count = if ($args["count"]) { $args["count"] } else { 5 }
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
                Add-CrabbyMemory -RootDir $RootDir -Entry $args["entry"]
                return "💾 Saved to memory: $($args["entry"])"
            }
            
            "skill_run" {
                return Invoke-CrabbySkillByName -Name $args["name"] -Arguments $args["arguments"] -RootDir $RootDir
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

#endregion ===== Tools =====

#region ===== Skills =====
<#
.SYNOPSIS
    Crabby AI — Skills System
.DESCRIPTION
    Load and execute PowerShell-based skills from the skills/ directory.
#>

function Get-CrabbySkills {
    param([string]$RootDir)
    
    $skillsDir = Join-Path $RootDir "skills"
    
    if (-not (Test-Path $skillsDir)) {
        return @()
    }
    
    $skillFiles = Get-ChildItem $skillsDir -Filter "*.ps1"
    $skills = @()
    
    foreach ($file in $skillFiles) {
        $content = Get-Content $file.FullName -Raw -Encoding UTF8
        
        # Parse skill metadata from comment-based help
        $nameMatch = [regex]::Match($content, '\.SkillName\s+(.+)')
        $descMatch = [regex]::Match($content, '\.Description\s+(.+)')
        $triggerMatch = [regex]::Match($content, '\.Trigger\s+(.+)')
        
        $skills += @{
            Name = if ($nameMatch.Success) { $nameMatch.Groups[1].Value.Trim() } else { $file.BaseName }
            Description = if ($descMatch.Success) { $descMatch.Groups[1].Value.Trim() } else { "No description" }
            Trigger = if ($triggerMatch.Success) { $triggerMatch.Groups[1].Value.Trim() } else { "" }
            Path = $file.FullName
        }
    }
    
    return $skills
}

function Invoke-CrabbySkillByName {
    param(
        [string]$Name,
        [string]$Arguments,
        [string]$RootDir
    )
    
    $skillsDir = Join-Path $RootDir "skills"
    
    if (-not (Test-Path $skillsDir)) {
        return "No skills directory found."
    }
    
    # Find skill file by name
    $skillFile = Get-ChildItem $skillsDir -Filter "*.ps1" | Where-Object {
        $content = Get-Content $_.FullName -Raw -Encoding UTF8
        $nameMatch = [regex]::Match($content, '\.SkillName\s+(.+)')
        if ($nameMatch.Success -and $nameMatch.Groups[1].Value.Trim() -eq $Name) {
            return $true
        }
        return $_.BaseName -eq $Name
    } | Select-Object -First 1
    
    if (-not $skillFile) {
        return "Skill not found: $Name"
    }
    
    # Build argument string
    $argString = ""
    if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
        try {
            $parsedArgs = $Arguments | ConvertFrom-Json -AsHashtable
            $argPairs = @()
            foreach ($key in $parsedArgs.Keys) {
                $val = $parsedArgs[$key]
                if ($val -is [string]) {
                    $argPairs += "-$key '$val'"
                } else {
                    $argPairs += "-$key $val"
                }
            }
            $argString = $argPairs -join " "
        }
        catch {
            $argString = $Arguments
        }
    }
    
    try {
        # Execute the skill script
        $result = & $skillFile.FullName $argString.Split() 2>&1 | Out-String
        return $result.Trim()
    }
    catch {
        return "Skill execution error: $($_.Exception.Message)"
    }
}

function New-CrabbySkill {
    param(
        [string]$RootDir,
        [string]$Name,
        [string]$Description,
        [string]$Trigger
    )
    
    $skillsDir = Join-Path $RootDir "skills"
    
    if (-not (Test-Path $skillsDir)) {
        New-Item -Path $skillsDir -ItemType Directory -Force | Out-Null
    }
    
    $safeName = $Name -replace '[^a-zA-Z0-9_-]', '-'
    $skillPath = Join-Path $skillsDir "$safeName.ps1"
    
    $template = @"
<#
.SkillName $safeName
.Description $Description
.Trigger $Trigger
#>
param(
    [string]`$Input = ""
)

# TODO: Implement your skill logic here
Write-Output "Skill '$safeName' executed. Input: `$Input"
"@
    
    Set-Content $skillPath $template -Encoding UTF8
    
    return "Skill created: $skillPath"
}

#endregion ===== Skills =====



# Auto-create data directories if missing
@("$RootDir\config", "$RootDir\memory", "$RootDir\memory\conversations", "$RootDir\skills") | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item -Path $_ -ItemType Directory -Force | Out-Null }
}

# Load WPF assemblies
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml

# Load configuration
$Settings = Get-CrabbySettings -RootDir $RootDir
$Soul = Get-CrabbySoul -RootDir $RootDir
$UserProfile = Get-CrabbyUserProfile -RootDir $RootDir

# ============================================================
# Conversation State
# ============================================================

$script:Conversation = @(
    @{ role = "system"; content = @"
$Soul

## User Profile
$UserProfile

## Memory
$(Get-CrabbyMemoryContent -RootDir $RootDir)

## Available Tools
$(Get-CrabbyToolsDescription)

## Instructions
- You are Crabby, a helpful AI assistant running locally on the user's Windows machine.
- You have FULL CONTROL of this computer via PowerShell. You can run any command, install software, manage files, configure system settings — anything the user can do in PowerShell, you can do too.
- The shell tool maintains a persistent session: working directory, variables, and imports persist across commands.
- When the user asks you to do something, DO IT directly using shell/file tools. Don't just give instructions — execute them.
- For dangerous operations, you will get a confirmation prompt. Tell the user what you're about to do and ask before using shell_confirm.
- Keep responses concise and natural, like chatting with a friend.
- Respond in the same language the user uses.
"@
    }
)

# ============================================================
# XAML — Window Definition
# ============================================================

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Crabby AI" Height="700" Width="1000"
        WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ResizeMode="CanResizeWithGrip"
        WindowStartupLocation="CenterScreen" MinWidth="600" MinHeight="450">

  <Window.Resources>
    <!-- Colors — Light Theme -->
    <SolidColorBrush x:Key="BgPrimary" Color="#FAFAFA"/>
    <SolidColorBrush x:Key="BgSecondary" Color="#F5F5F5"/>
    <SolidColorBrush x:Key="BgTertiary" Color="#EFEFEF"/>
    <SolidColorBrush x:Key="BgHover" Color="#E8E8E8"/>
    <SolidColorBrush x:Key="TextPrimary" Color="#1A1A1A"/>
    <SolidColorBrush x:Key="TextSecondary" Color="#6B6B6B"/>
    <SolidColorBrush x:Key="TextMuted" Color="#9E9E9E"/>
    <SolidColorBrush x:Key="Accent" Color="#E8653A"/>
    <SolidColorBrush x:Key="AccentLight" Color="#F0845E"/>
    <SolidColorBrush x:Key="Success" Color="#2EAE6D"/>
    <SolidColorBrush x:Key="Border" Color="#E5E5E5"/>

    <!-- Button Style -->
    <Style x:Key="SidebarBtn" TargetType="Button">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="#6B6B6B"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="10,8"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#E8E8E8"/>
                <Setter Property="Foreground" Value="#1A1A1A"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Title Button Style -->
    <Style x:Key="TitleBtn" TargetType="Button">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="#6B6B6B"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Width" Value="40"/>
      <Setter Property="Height" Value="32"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#E8E8E8"/>
                <Setter Property="Foreground" Value="#1A1A1A"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Send Button Style -->
    <Style x:Key="SendBtn" TargetType="Button">
      <Setter Property="Background" Value="#E8653A"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Width" Value="40"/>
      <Setter Property="Height" Value="40"/>
      <Setter Property="FontSize" Value="16"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="10">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#F0845E"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Background" Value="#D5D5D5"/>
                <Setter Property="Foreground" Value="#9E9E9E"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <!-- Main Border (window chrome) -->
  <Border Background="#FAFAFA" CornerRadius="12" BorderBrush="#E5E5E5" BorderThickness="1"
          MouseLeftButtonDown="Border_MouseLeftButtonDown">
    <Grid>
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="220" MinWidth="180"/>
        <ColumnDefinition Width="1"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- ====== SIDEBAR ====== -->
      <Border Grid.Column="0" Background="#F5F5F5" CornerRadius="12,0,0,12">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <!-- Logo -->
          <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="18,22,0,16">
            <Border Background="#E8653A" CornerRadius="10" Width="34" Height="34">
              <TextBlock Text="🦀" FontSize="18" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <TextBlock Text="Crabby AI" FontSize="16" FontWeight="Bold" Foreground="#1A1A1A"
                       VerticalAlignment="Center" Margin="10,0,0,0"/>
          </StackPanel>

          <!-- Actions -->
          <StackPanel Grid.Row="1" Margin="12,0,12,0">
            <Button x:Name="BtnNewChat" Style="{StaticResource SidebarBtn}" Content="✦  新对话" Margin="0,2"/>
            <Button x:Name="BtnReset" Style="{StaticResource SidebarBtn}" Content="↻  清除上下文" Margin="0,2"/>
          </StackPanel>

          <!-- Status -->
          <StackPanel Grid.Row="3" Margin="16,0,16,16">
            <StackPanel Orientation="Horizontal" Margin="0,4">
              <TextBlock Text="模型" FontSize="11" Foreground="#9E9E9E"/>
              <TextBlock x:Name="LblModel" Text="—" FontSize="11" Foreground="#6B6B6B" Margin="8,0,0,0"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal" Margin="0,4">
              <TextBlock Text="版本" FontSize="11" Foreground="#9E9E9E"/>
              <TextBlock Text="v1.3" FontSize="11" Foreground="#6B6B6B" Margin="8,0,0,0"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal" Margin="0,4">
              <TextBlock Text="状态" FontSize="11" Foreground="#9E9E9E"/>
              <TextBlock x:Name="LblStatus" Text="就绪" FontSize="11" Foreground="#2EAE6D" Margin="8,0,0,0"/>
            </StackPanel>
          </StackPanel>
        </Grid>
      </Border>

      <!-- Divider -->
      <Border Grid.Column="1" Background="#E5E5E5"/>

      <!-- ====== MAIN AREA ====== -->
      <Grid Grid.Column="2">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Title Bar -->
        <Border Grid.Row="0" Background="#F5F5F5" CornerRadius="0,12,0,0" Padding="20,10">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0" VerticalAlignment="Center">
              <TextBlock Text="Crabby AI" FontSize="14" FontWeight="SemiBold" Foreground="#1A1A1A"/>
              <TextBlock x:Name="LblSubtitle" Text="你的本地 AI 助手" FontSize="11" Foreground="#9E9E9E"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Orientation="Horizontal">
              <Button x:Name="BtnMinimize" Style="{StaticResource TitleBtn}" Content="─"/>
              <Button x:Name="BtnMaximize" Style="{StaticResource TitleBtn}" Content="□"/>
              <Button x:Name="BtnClose" Style="{StaticResource TitleBtn}" Content="✕"/>
            </StackPanel>
          </Grid>
        </Border>

        <!-- Messages Area -->
        <ScrollViewer Grid.Row="1" x:Name="MsgScroll" VerticalScrollBarVisibility="Auto"
                      Padding="24,16" Background="#FAFAFA">
          <StackPanel x:Name="MsgPanel">
            <!-- Welcome -->
            <StackPanel x:Name="WelcomePanel" HorizontalAlignment="Center" VerticalAlignment="Center"
                        Margin="0,80,0,0">
              <Border Background="#E8653A" CornerRadius="20" Width="72" Height="72" HorizontalAlignment="Center"
                      Margin="0,0,0,16">
                <TextBlock Text="🦀" FontSize="36" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <TextBlock Text="嘿，我是 Crabby" FontSize="22" FontWeight="Bold" Foreground="#1A1A1A"
                         HorizontalAlignment="Center" Margin="0,0,0,8"/>
              <TextBlock Text="你的本地 AI 助手，可以控制 PowerShell、创建文档、管理文件。"
                         FontSize="13" Foreground="#6B6B6B" HorizontalAlignment="Center"
                         TextWrapping="Wrap" MaxWidth="360" TextAlignment="Center" Margin="0,0,0,20"/>
              <WrapPanel HorizontalAlignment="Center">
                <Button x:Name="QuickSysInfo" Content="查看系统信息" Margin="3" Padding="10,6"
                        Background="#EFEFEF" Foreground="#6B6B6B" BorderThickness="1" BorderBrush="#E5E5E5"
                        FontSize="12" Cursor="Hand"/>
                <Button x:Name="QuickDoc" Content="创建文档" Margin="3" Padding="10,6"
                        Background="#EFEFEF" Foreground="#6B6B6B" BorderThickness="1" BorderBrush="#E5E5E5"
                        FontSize="12" Cursor="Hand"/>
                <Button x:Name="QuickWeather" Content="查天气" Margin="3" Padding="10,6"
                        Background="#EFEFEF" Foreground="#6B6B6B" BorderThickness="1" BorderBrush="#E5E5E5"
                        FontSize="12" Cursor="Hand"/>
                <Button x:Name="QuickFiles" Content="查看文件" Margin="3" Padding="10,6"
                        Background="#EFEFEF" Foreground="#6B6B6B" BorderThickness="1" BorderBrush="#E5E5E5"
                        FontSize="12" Cursor="Hand"/>
              </WrapPanel>
            </StackPanel>
          </StackPanel>
        </ScrollViewer>

        <!-- Typing Indicator (hidden by default) -->
        <StackPanel x:Name="TypingPanel" Grid.Row="1" VerticalAlignment="Bottom"
                    Orientation="Horizontal" Margin="32,0,0,16" Visibility="Collapsed">
          <Border Background="#E8653A" CornerRadius="10" Width="28" Height="28" Margin="0,0,8,0">
            <TextBlock Text="🦀" FontSize="14" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <TextBlock x:Name="TypingText" Text="思考中..." FontSize="13" Foreground="#9E9E9E"
                     VerticalAlignment="Center"/>
        </StackPanel>

        <!-- Input Area -->
        <Border Grid.Row="2" Background="#F5F5F5" BorderBrush="#E5E5E5" BorderThickness="0,1,0,0"
                Padding="20,14,20,20">
          <Grid MaxWidth="760">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Border Grid.Column="0" Background="#FFFFFF" CornerRadius="12" BorderBrush="#E5E5E5" BorderThickness="1"
                    x:Name="InputBorder">
              <TextBox x:Name="InputBox" Background="Transparent" Foreground="#1A1A1A"
                       BorderThickness="0" Padding="14,10"
                       FontSize="14" AcceptsReturn="False" MaxLines="1"
                       CaretBrush="#E8653A" VerticalContentAlignment="Center"/>
            </Border>
            <Button Grid.Column="1" x:Name="BtnSend" Style="{StaticResource SendBtn}" Content="➤" Margin="8,0,0,0"/>
          </Grid>
        </Border>
      </Grid>
    </Grid>
  </Border>
</Window>
"@

# ============================================================
# Load Window
# ============================================================

$window = [System.Windows.Markup.XamlReader]::Parse($xaml)

# Get controls
$inputBox = $window.FindName("InputBox")
$btnSend = $window.FindName("BtnSend")
$msgPanel = $window.FindName("MsgPanel")
$msgScroll = $window.FindName("MsgScroll")
$welcomePanel = $window.FindName("WelcomePanel")
$typingPanel = $window.FindName("TypingPanel")
$typingText = $window.FindName("TypingText")
$lblStatus = $window.FindName("LblStatus")
$lblModel = $window.FindName("LblModel")
$inputBorder = $window.FindName("InputBorder")
$lblSubtitle = $window.FindName("LblSubtitle")

# Title bar buttons
$btnClose = $window.FindName("BtnClose")
$btnMinimize = $window.FindName("BtnMinimize")
$btnMaximize = $window.FindName("BtnMaximize")
$btnNewChat = $window.FindName("BtnNewChat")
$btnReset = $window.FindName("BtnReset")

# Quick action buttons
$quickSysInfo = $window.FindName("QuickSysInfo")
$quickDoc = $window.FindName("QuickDoc")
$quickWeather = $window.FindName("QuickWeather")
$quickFiles = $window.FindName("QuickFiles")

# Set model label
$lblModel.Text = $Settings.llm.model

# ============================================================
# Window Chrome Events
# ============================================================

$btnClose.Add_Click({ $window.Close() })
$btnMinimize.Add_Click({ $window.WindowState = [System.Windows.WindowState]::Minimized })

$script:IsMaximized = $false
$btnMaximize.Add_Click({
    if ($script:IsMaximized) {
        $window.WindowState = [System.Windows.WindowState]::Normal
        $script:IsMaximized = $false
    } else {
        $window.WindowState = [System.Windows.WindowState]::Maximized
        $script:IsMaximized = $true
    }
})

# Drag window
$window.Add_MouseLeftButtonDown({
    if ($_.OriginalSource -is [System.Windows.Controls.Border] -or
        $_.OriginalSource -is [System.Windows.Controls.Grid] -or
        $_.OriginalSource -is [System.Windows.Controls.StackPanel] -or
        $_.OriginalSource -is [System.Windows.Controls.TextBlock]) {
        $window.DragMove()
    }
})

# ============================================================
# UI Helpers
# ============================================================

function Add-MessageBubble {
    param(
        [string]$Role,     # "user" or "assistant"
        [string]$Text,
        [array]$Tools = @()
    )

    # Hide welcome
    $welcomePanel.Visibility = [System.Windows.Visibility]::Collapsed

    $container = New-Object System.Windows.Controls.StackPanel
    $container.Margin = "0,0,0,16"

    # Tool calls
    foreach ($tool in $Tools) {
        $toolBorder = New-Object System.Windows.Controls.Border
        $toolBorder.Background = "#F5F5F5"
        $toolBorder.BorderBrush = "#E5E5E5"
        $toolBorder.BorderThickness = "1"
        $toolBorder.CornerRadius = "8"
        $toolBorder.Margin = "0,0,0,4"
        $toolBorder.Padding = "8,6"
        $toolBorder.Cursor = [System.Windows.Input.Cursors]::Hand

        $toolPanel = New-Object System.Windows.Controls.StackPanel
        $toolPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal

        $toolIcon = New-Object System.Windows.Controls.TextBlock
        $toolIcon.Text = "⚙️"
        $toolIcon.FontSize = "12"
        $toolIcon.Margin = "0,0,6,0"
        $toolIcon.VerticalAlignment = "Center"

        $toolName = New-Object System.Windows.Controls.TextBlock
        $toolName.Text = $tool.name
        $toolName.FontSize = "12"
        $toolName.Foreground = "#F0845E"
        $toolName.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
        $toolName.VerticalAlignment = "Center"

        $toolStatus = New-Object System.Windows.Controls.TextBlock
        $toolStatus.Text = " ✓"
        $toolStatus.FontSize = "11"
        $toolStatus.Foreground = "#3ECF8E"
        $toolStatus.Margin = "6,0,0,0"
        $toolStatus.VerticalAlignment = "Center"

        $toolPanel.Children.Add($toolIcon) | Out-Null
        $toolPanel.Children.Add($toolName) | Out-Null
        $toolPanel.Children.Add($toolStatus) | Out-Null
        $toolBorder.Child = $toolPanel
        $container.Children.Add($toolBorder) | Out-Null
    }

    # Message row: avatar + bubble
    $row = New-Object System.Windows.Controls.DockPanel

    # Avatar
    $avatar = New-Object System.Windows.Controls.Border
    if ($Role -eq "user") {
        $avatar.Background = "#E5E5E5"
        $avatar.Width = "28"
        $avatar.Height = "28"
        $avatar.CornerRadius = "8"
        $avatar.Margin = "0,0,8,0"
        $avatarImg = New-Object System.Windows.Controls.TextBlock
        $avatarImg.Text = "👤"
        $avatarImg.FontSize = "14"
        $avatarImg.HorizontalAlignment = "Center"
        $avatarImg.VerticalAlignment = "Center"
        $avatar.Child = $avatarImg
        [System.Windows.Controls.DockPanel]::SetDock($avatar, [System.Windows.Controls.Dock]::Right)
    } else {
        $avatar.Background = "#E8653A"
        $avatar.Width = "28"
        $avatar.Height = "28"
        $avatar.CornerRadius = "8"
        $avatar.Margin = "0,0,8,0"
        $avatarImg = New-Object System.Windows.Controls.TextBlock
        $avatarImg.Text = "🦀"
        $avatarImg.FontSize = "14"
        $avatarImg.HorizontalAlignment = "Center"
        $avatarImg.VerticalAlignment = "Center"
        $avatar.Child = $avatarImg
        [System.Windows.Controls.DockPanel]::SetDock($avatar, [System.Windows.Controls.Dock]::Left)
    }

    # Bubble
    $bubble = New-Object System.Windows.Controls.Border
    $bubble.CornerRadius = "12"
    $bubble.Padding = "12,10"
    $bubble.MaxWidth = "560"

    if ($Role -eq "user") {
        $bubble.Background = "#E8653A"
        [System.Windows.Controls.DockPanel]::SetDock($bubble, [System.Windows.Controls.Dock]::Right)
    } else {
        $bubble.Background = "#FFFFFF"
        $bubble.BorderBrush = "#E5E5E5"
        $bubble.BorderThickness = "1"
    }

    # Render content
    $contentPanel = New-Object System.Windows.Controls.StackPanel

    # Simple markdown-to-XAML rendering
    $blocks = Render-MarkdownToBlocks -Text $Text -IsUser ($Role -eq "user")

    foreach ($block in $blocks) {
        $contentPanel.Children.Add($block) | Out-Null
    }

    $bubble.Child = $contentPanel

    $row.Children.Add($avatar) | Out-Null
    $row.Children.Add($bubble) | Out-Null

    if ($Role -eq "user") {
        $row.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    } else {
        $row.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
    }

    $container.Children.Add($row) | Out-Null
    $msgPanel.Children.Add($container) | Out-Null

    # Scroll to bottom
    $msgScroll.Dispatcher.Invoke([Action]{
        $msgScroll.ScrollToEnd()
    }, [System.Windows.Threading.DispatcherPriority]::Background)
}

function Render-MarkdownToBlocks {
    param([string]$Text, [bool]$IsUser = $false)

    $blocks = @()
    $lines = $Text -split "`n"
    $i = 0
    $inCodeBlock = $false
    $codeLines = @()

    while ($i -lt $lines.Count) {
        $line = $lines[$i]

        # Code block start/end
        if ($line -match '^```') {
            if ($inCodeBlock) {
                # End code block
                $codeBlock = New-Object System.Windows.Controls.Border
                $codeBlock.Background = "#F5F5F5"
                $codeBlock.BorderBrush = "#E5E5E5"
                $codeBlock.BorderThickness = "1"
                $codeBlock.CornerRadius = "8"
                $codeBlock.Padding = "10"
                $codeBlock.Margin = "0,4"

                $codeText = New-Object System.Windows.Controls.TextBlock
                $codeText.Text = ($codeLines -join "`n")
                $codeText.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
                $codeText.FontSize = "12"
                $codeText.Foreground = "#1A1A1A"
                $codeText.TextWrapping = [System.Windows.TextWrapping]::Wrap

                $codeBlock.Child = $codeText
                $blocks += $codeBlock

                $codeLines = @()
                $inCodeBlock = $false
            } else {
                $inCodeBlock = $true
            }
            $i++
            continue
        }

        if ($inCodeBlock) {
            $codeLines += $line
            $i++
            continue
        }

        # Skip empty lines
        if ($line.Trim() -eq "") {
            $i++
            continue
        }

        # Headings
        if ($line -match '^### (.+)') {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = $Matches[1]
            $tb.FontSize = "14"
            $tb.FontWeight = "SemiBold"
            $tb.Foreground = "#1A1A1A"
            $tb.Margin = "0,8,0,2"
            $blocks += $tb
            $i++
            continue
        }
        if ($line -match '^## (.+)') {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = $Matches[1]
            $tb.FontSize = "15"
            $tb.FontWeight = "SemiBold"
            $tb.Foreground = "#1A1A1A"
            $tb.Margin = "0,8,0,2"
            $blocks += $tb
            $i++
            continue
        }

        # List items
        if ($line -match '^[-*]\s+(.+)') {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = "• $($Matches[1])"
            $tb.FontSize = "13"
            $tb.Foreground = if ($IsUser) { "#FFFFFF" } else { "#1A1A1A" }
            $tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
            $tb.Margin = "2,1"
            $blocks += $tb
            $i++
            continue
        }

        if ($line -match '^\d+\.\s+(.+)') {
            $tb = New-Object System.Windows.Controls.TextBlock
            $tb.Text = $line
            $tb.FontSize = "13"
            $tb.Foreground = if ($IsUser) { "#FFFFFF" } else { "#1A1A1A" }
            $tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
            $tb.Margin = "2,1"
            $blocks += $tb
            $i++
            continue
        }

        # Regular text (strip markdown bold/italic markers for display)
        $display = $line -replace '\*\*(.+?)\*\*', '$1'
        $display = $display -replace '\*(.+?)\*', '$1'
        $display = $display -replace '`(.+?)`', '$1'

        $tb = New-Object System.Windows.Controls.TextBlock
        $tb.Text = $display
        $tb.FontSize = "13"
        $tb.Foreground = if ($IsUser) { "#FFFFFF" } else { "#6B6B6B" }
        $tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $tb.Margin = "0,1"
        $blocks += $tb
        $i++
    }

    # Unclosed code block
    if ($inCodeBlock -and $codeLines.Count -gt 0) {
        $codeBlock = New-Object System.Windows.Controls.Border
        $codeBlock.Background = "#F5F5F5"
        $codeBlock.BorderBrush = "#E5E5E5"
        $codeBlock.BorderThickness = "1"
        $codeBlock.CornerRadius = "8"
        $codeBlock.Padding = "10"
        $codeBlock.Margin = "0,4"

        $codeText = New-Object System.Windows.Controls.TextBlock
        $codeText.Text = ($codeLines -join "`n")
        $codeText.FontFamily = New-Object System.Windows.Media.FontFamily("Consolas")
        $codeText.FontSize = "12"
        $codeText.Foreground = "#1A1A1A"
        $codeText.TextWrapping = [System.Windows.TextWrapping]::Wrap

        $codeBlock.Child = $codeText
        $blocks += $codeBlock
    }

    return $blocks
}

function Set-Processing {
    param([bool]$On)
    $btnSend.IsEnabled = -not $On
    $inputBox.IsEnabled = -not $On

    if ($On) {
        $lblStatus.Text = "思考中..."
        $lblStatus.Foreground = "#E8A030"
        $typingPanel.Visibility = [System.Windows.Visibility]::Visible
    } else {
        $lblStatus.Text = "就绪"
        $lblStatus.Foreground = "#2EAE6D"
        $typingPanel.Visibility = [System.Windows.Visibility]::Collapsed
    }
}

# ============================================================
# Chat Logic
# ============================================================

$script:IsProcessing = $false

function Send-ChatMessage {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message) -or $script:IsProcessing) { return }

    $script:IsProcessing = $true
    Set-Processing $true

    # Add user message
    Add-MessageBubble -Role "user" -Text $Message

    $script:Conversation += @{ role = "user"; content = $Message }

    # Process in background
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $runspace.SessionStateProxy.SetVariable("Settings", $Settings)
    $runspace.SessionStateProxy.SetVariable("Conversation", $script:Conversation)
    $runspace.SessionStateProxy.SetVariable("RootDir", $RootDir)

    $ps = [powershell]::Create()
    $ps.Runspace = $runspace

    $ps.AddScript({
        $maxRounds = 8
        $round = 0
        $toolEvents = @()
        $assistantMsg = ""
        $conv = $Conversation

        while ($round -lt $maxRounds) {
            $round++
            $result = Invoke-CrabbyChat -Settings $Settings -Conversation $conv -SupportTools $true

            if ($result.ToolCalls) {
                $conv += @{ role = "assistant"; content = $result.Content; tool_calls = $result.ToolCalls }

                foreach ($toolCall in $result.ToolCalls) {
                    $toolName = $toolCall.function.name
                    $toolArgs = $toolCall.function.arguments

                    $toolResult = Invoke-CrabbyTool -Name $toolName -Arguments $toolArgs -RootDir $RootDir

                    $shortResult = if ($toolResult.Length -gt 300) { $toolResult.Substring(0, 300) + "..." } else { $toolResult }
                    $toolEvents += @{ name = $toolName; result = $shortResult }

                    $conv += @{
                        role = "tool"
                        tool_call_id = $toolCall.id
                        content = $toolResult
                    }
                }
            } else {
                $assistantMsg = $result.Content
                $conv += @{ role = "assistant"; content = $assistantMsg }
                break
            }
        }

        if ($round -ge $maxRounds -and -not $assistantMsg) {
            $assistantMsg = "[Max tool rounds reached]"
        }

        return @{ message = $assistantMsg; tools = $toolEvents; conversation = $conv }
    }) | Out-Null

    $asyncResult = $ps.BeginInvoke()

    # Poll for completion on UI thread
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(100)

    $timer.Add_Tick({
        if ($asyncResult.IsCompleted) {
            $timer.Stop()

            try {
                $result = $ps.EndInvoke($asyncResult)

                $msg = $result[0].message
                $tools = $result[0].tools
                $script:Conversation = $result[0].conversation

                Add-MessageBubble -Role "assistant" -Text $msg -Tools $tools

                # Save conversation
                Save-CrabbyConversation -RootDir $RootDir -UserMessage $Message -AssistantResponse $msg

                # Trim conversation if too long
                if ($script:Conversation.Count -gt 30) {
                    $systemMsg = $script:Conversation[0]
                    $recent = $script:Conversation | Select-Object -Last 28
                    $script:Conversation = @($systemMsg) + $recent
                }
            }
            catch {
                Add-MessageBubble -Role "assistant" -Text "❌ 出错了: $($_.Exception.Message)"
            }
            finally {
                $ps.Dispose()
                $runspace.Close()
                $runspace.Dispose()
                $script:IsProcessing = $false
                Set-Processing $false
                $inputBox.Focus()
            }
        }
    })

    $timer.Start()
}

# ============================================================
# Event Bindings
# ============================================================

# Send button
$btnSend.Add_Click({
    Send-ChatMessage -Message $inputBox.Text
    $inputBox.Text = ""
})

# Enter to send
$inputBox.Add_KeyDown({
    if ($_.Key -eq "Enter" -and -not $_.ShiftKey) {
        $_.Handled = $true
        Send-ChatMessage -Message $inputBox.Text
        $inputBox.Text = ""
    }
})

# Focus highlight
$inputBox.Add_GotFocus({
    $inputBorder.BorderBrush = "#E8653A"
})
$inputBox.Add_LostFocus({
    $inputBorder.BorderBrush = "#E5E5E5"
})

# New chat
$btnNewChat.Add_Click({
    $script:Conversation = @(
        @{ role = "system"; content = $script:Conversation[0].content }
    )
    $msgPanel.Children.Clear()
    $msgPanel.Children.Add($welcomePanel) | Out-Null
    $welcomePanel.Visibility = [System.Windows.Visibility]::Visible
})

# Reset context
$btnReset.Add_Click({
    $script:Conversation = @(
        @{ role = "system"; content = $script:Conversation[0].content }
    )
    $msgPanel.Children.Clear()
    $msgPanel.Children.Add($welcomePanel) | Out-Null
    $welcomePanel.Visibility = [System.Windows.Visibility]::Visible
})

# Quick actions
$quickSysInfo.Add_Click({ Send-ChatMessage -Message "查看当前系统信息" })
$quickDoc.Add_Click({ Send-ChatMessage -Message "帮我创建一个待办事项文档" })
$quickWeather.Add_Click({ Send-ChatMessage -Message "今天天气怎么样" })
$quickFiles.Add_Click({ Send-ChatMessage -Message "列出桌面上的文件" })

# ============================================================
# Run
# ============================================================

$inputBox.Focus()
$window.ShowDialog() | Out-Null
