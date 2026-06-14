<#
.SYNOPSIS
    Crabby AI - Self-extracting installer
.DESCRIPTION
    Run this script on your Windows machine to create the full crabby-ai project.
#>

$Dest = "D:\Desktop\crabby-ai"
Write-Host "" -NoNewline
Write-Host "  🦀 Installing Crabby AI to: $Dest" -ForegroundColor DarkCyan

New-Item -Path "$Dest\src" -ItemType Directory -Force | Out-Null
New-Item -Path "$Dest\config" -ItemType Directory -Force | Out-Null
New-Item -Path "$Dest\memory\conversations" -ItemType Directory -Force | Out-Null
New-Item -Path "$Dest\skills" -ItemType Directory -Force | Out-Null

Set-Content -Path "$Dest\crabby.ps1" -Value @'
<#
.SYNOPSIS
    Crabby AI — Main entry point
.DESCRIPTION
    Your personal AI assistant, the crab way. 🦀
    Pure PowerShell, Windows native.
#>

param(
    [string]$Message = "",
    [switch]$Heartbeat = $false,
    [switch]$Debug = $false,
    [string]$ConfigPath = ""
)

# ============================================================
# Bootstrap
# ============================================================

$ErrorActionPreference = "Stop"
$RootDir = $PSScriptRoot

if ($ConfigPath -and (Test-Path $ConfigPath)) {
    $RootDir = Split-Path $ConfigPath -Parent
}

# Load modules
. "$RootDir\src\LLM.ps1"
. "$RootDir\src\Memory.ps1"
. "$RootDir\src\Tools.ps1"
. "$RootDir\src\Skills.ps1"

# Load configuration
$Settings = Get-CrabbySettings -RootDir $RootDir
$Soul = Get-CrabbySoul -RootDir $RootDir
$UserProfile = Get-CrabbyUserProfile -RootDir $RootDir

# Banner
function Show-Banner {
    Write-Host ""
    Write-Host "  🦀 Crabby AI v1.0" -ForegroundColor DarkCyan
    Write-Host "  ─────────────────────────────" -ForegroundColor DarkGray
    Write-Host "  Model: $($Settings.llm.model)" -ForegroundColor Gray
    Write-Host "  Provider: $($Settings.llm.provider)" -ForegroundColor Gray
    Write-Host "  Type 'exit' to quit, 'clear' to reset context" -ForegroundColor DarkGray
    Write-Host ""
}

# ============================================================
# Heartbeat Mode
# ============================================================

if ($Heartbeat) {
    $heartbeatFile = "$RootDir\memory\heartbeat.md"
    if (-not (Test-Path $heartbeatFile)) {
        Write-Host "[Heartbeat] No heartbeat.md found. Nothing to check."
        return
    }
    
    $checks = Get-Content $heartbeatFile -Raw
    $systemPrompt = @"
You are Crabby, a personal AI assistant running in heartbeat mode.
Your task is to check the following items and report any that need attention.
If everything is fine, respond with exactly: NO_REPLY

Checks:
$checks
"@
    
    $response = Invoke-CrabbyLLM -Settings $Settings -SystemPrompt $systemPrompt -UserMessage "Run heartbeat check now. Current time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    
    if ($response -ne "NO_REPLY" -and $response.Trim() -ne "") {
        Write-Host "[Heartbeat] $response"
        # Append to memory if significant
        Add-CrabbyMemory -RootDir $RootDir -Entry "[Heartbeat $(Get-Date -Format 'yyyy-MM-dd HH:mm')] $response"
    }
    
    return
}

# ============================================================
# Interactive / One-shot Mode
# ============================================================

# Build system prompt
$systemPrompt = @"
$Soul

## User Profile
$UserProfile

## Memory
$(Get-CrabbyMemoryContent -RootDir $RootDir)

## Available Tools
$(Get-CrabbyToolsDescription)

## Instructions
- You are Crabby, a helpful AI assistant running locally on the user's Windows machine.
- When you need to perform actions, use the tool calling format.
- Keep responses concise and natural, like chatting with a friend.
- Respond in the same language the user uses.
"@

# Initialize conversation
$conversation = @(
    @{ role = "system"; content = $systemPrompt }
)

Show-Banner

# One-shot mode
if ($Message -ne "") {
    $conversation += @{ role = "user"; content = $Message }
    $response = Invoke-CrabbyChat -Settings $Settings -Conversation $conversation
    Write-Host "`n🦀 $response`n"
    Save-CrabbyConversation -RootDir $RootDir -UserMessage $Message -AssistantResponse $response
    return
}

# Interactive loop
while ($true) {
    Write-Host "You> " -NoNewline -ForegroundColor Green
    $userInput = Read-Host
    
    if ($userInput -eq "exit" -or $userInput -eq "quit") {
        Write-Host "🦀 See you later!" -ForegroundColor DarkCyan
        break
    }
    
    if ($userInput -eq "clear") {
        $conversation = @(
            @{ role = "system"; content = $systemPrompt }
        )
        # Reload memory
        $conversation[0].content = $systemPrompt
        Write-Host "🦀 Context cleared." -ForegroundColor DarkGray
        continue
    }
    
    if ($userInput -eq "memory") {
        Write-Host "`n$(Get-CrabbyMemoryContent -RootDir $RootDir)`n" -ForegroundColor DarkGray
        continue
    }
    
    if ($userInput -eq "help") {
        Write-Host ""
        Write-Host "  exit   — Quit Crabby" -ForegroundColor Gray
        Write-Host "  clear  — Reset conversation context" -ForegroundColor Gray
        Write-Host "  memory — View current memory" -ForegroundColor Gray
        Write-Host "  skills — List installed skills" -ForegroundColor Gray
        Write-Host "  help   — Show this help" -ForegroundColor Gray
        Write-Host ""
        continue
    }
    
    if ($userInput -eq "skills") {
        $skills = Get-CrabbySkills -RootDir $RootDir
        if ($skills.Count -eq 0) {
            Write-Host "🦀 No skills installed yet." -ForegroundColor DarkGray
        } else {
            Write-Host ""
            foreach ($skill in $skills) {
                Write-Host "  🧩 $($skill.Name) — $($skill.Description)" -ForegroundColor Gray
            }
            Write-Host ""
        }
        continue
    }
    
    if ([string]::IsNullOrWhiteSpace($userInput)) {
        continue
    }
    
    # Add user message
    $conversation += @{ role = "user"; content = $userInput }
    
    # Call LLM with tool support
    $maxRounds = 5
    $round = 0
    
    while ($round -lt $maxRounds) {
        $round++
        $result = Invoke-CrabbyChat -Settings $Settings -Conversation $conversation -SupportTools $true
        
        if ($result.ToolCalls) {
            # Process tool calls
            $conversation += @{ role = "assistant"; content = $result.Content; tool_calls = $result.ToolCalls }
            
            foreach ($toolCall in $result.ToolCalls) {
                $toolName = $toolCall.function.name
                $toolArgs = $toolCall.function.arguments
                
                Write-Host "  ⚙️ Calling tool: $toolName" -ForegroundColor DarkYellow
                
                $toolResult = Invoke-CrabbyTool -Name $toolName -Arguments $toolArgs -RootDir $RootDir
                
                $conversation += @{ 
                    role = "tool"
                    tool_call_id = $toolCall.id
                    content = $toolResult
                }
            }
            # Continue loop to get LLM's next response
        } else {
            # No tool calls, display response
            $assistantMsg = $result.Content
            Write-Host "`n🦀 $assistantMsg`n"
            
            # Save conversation
            $conversation += @{ role = "assistant"; content = $assistantMsg }
            Save-CrabbyConversation -RootDir $RootDir -UserMessage $userInput -AssistantResponse $assistantMsg
            
            # Trim conversation if too long (keep system + last 20 messages)
            if ($conversation.Count -gt 22) {
                $systemMsg = $conversation[0]
                $recent = $conversation | Select-Object -Last 20
                $conversation = @($systemMsg) + $recent
            }
            
            break
        }
    }
    
    if ($round -ge $maxRounds) {
        Write-Host "🦀 [Max tool rounds reached. Final response above.]" -ForegroundColor DarkGray
    }
}

'@ -Encoding UTF8

Set-Content -Path "$Dest\install.ps1" -Value @'
<#
.SYNOPSIS
    Crabby AI — Installation & Setup Script
.DESCRIPTION
    One-command setup wizard and optional heartbeat scheduling.
#>

param(
    [switch]$ScheduleHeartbeat = $false,
    [switch]$Uninstall = $false
)

$RootDir = $PSScriptRoot

# ============================================================
# Uninstall
# ============================================================

if ($Uninstall) {
    Write-Host "🦀 Uninstalling Crabby AI..." -ForegroundColor Yellow
    
    # Remove scheduled task if exists
    $taskName = "CrabbyAI-Heartbeat"
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    
    if ($task) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "  ✓ Removed scheduled task" -ForegroundColor Green
    }
    
    Write-Host "  🦀 Crabby AI uninstalled. Your config and memory files are preserved." -ForegroundColor DarkCyan
    return
}

# ============================================================
# Schedule Heartbeat
# ============================================================

if ($ScheduleHeartbeat) {
    $taskName = "CrabbyAI-Heartbeat"
    
    # Remove existing task if any
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
    
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$RootDir\crabby.ps1`" -Heartbeat" -WorkingDirectory $RootDir
    
    $trigger = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 30) -At (Get-Date) -Once
    
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType S4U -RunLevel Limited
    
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Crabby AI Heartbeat - runs every 30 minutes" | Out-Null
    
    Write-Host "🦀 Heartbeat scheduled! Crabby will check in every 30 minutes." -ForegroundColor DarkCyan
    Write-Host "  Edit memory\heartbeat.md to configure what Crabby checks." -ForegroundColor Gray
    return
}

# ============================================================
# Normal Install / Setup
# ============================================================

Write-Host ""
Write-Host "  🦀 Crabby AI Setup" -ForegroundColor DarkCyan
Write-Host "  ─────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# Create directories
$dirs = @("config", "memory\conversations", "skills")
foreach ($dir in $dirs) {
    $path = Join-Path $RootDir $dir
    if (-not (Test-Path $path)) {
        New-Item -Path $path -ItemType Directory -Force | Out-Null
        Write-Host "  ✓ Created $dir/" -ForegroundColor Green
    }
}

# Create default heartbeat.md
$heartbeatPath = Join-Path $RootDir "memory\heartbeat.md"
if (-not (Test-Path $heartbeatPath)) {
    $defaultHeartbeat = @"
# Heartbeat Checks

- Check if there are any unread emails
- Check system disk space and warn if below 10%
- Check for any important news in AI/tech
"@
    Set-Content $heartbeatPath $defaultHeartbeat -Encoding UTF8
    Write-Host "  ✓ Created memory/heartbeat.md" -ForegroundColor Green
}

# Check if settings already exist
$settingsPath = Join-Path $RootDir "config\settings.json"
if (Test-Path $settingsPath) {
    Write-Host "  ✓ Settings already configured." -ForegroundColor Green
    Write-Host ""
    Write-Host "  🦀 Run .\crabby.ps1 to start chatting!" -ForegroundColor DarkCyan
    Write-Host ""
    return
}

# Run onboard wizard (called from LLM.ps1)
. "$RootDir\src\LLM.ps1"
$settings = Invoke-CrabbyOnboard -RootDir $RootDir

Write-Host ""
Write-Host "  Want to set up Heartbeat (30-min auto-check)? (y/n)" -ForegroundColor Gray
$hbChoice = Read-Host "  "
if ($hbChoice -eq "y" -or $hbChoice -eq "Y") {
    & $PSCommandPath -ScheduleHeartbeat
}

'@ -Encoding UTF8

Set-Content -Path "$Dest\src\LLM.ps1" -Value @'
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
        "1" = @{ name = "siliconflow"; base_url = "https://api.siliconflow.cn/v1"; model = "Qwen/Qwen2.5-7B-Instruct" }
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
            max_tokens = 2048
            temperature = 0.7
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

'@ -Encoding UTF8

Set-Content -Path "$Dest\src\Memory.ps1" -Value @'
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

'@ -Encoding UTF8

Set-Content -Path "$Dest\src\Tools.ps1" -Value @'
<#
.SYNOPSIS
    Crabby AI — Built-in Tools
.DESCRIPTION
    Tool definitions and execution for shell, file I/O, and web operations.
#>

# ============================================================
# Tool Schema (OpenAI function calling format)
# ============================================================

function Get-CrabbyToolsSchema {
    return @(
        @{
            type = "function"
            function = @{
                name = "shell"
                description = "Execute a PowerShell command on the local machine. Use for system operations, running scripts, or any command-line task."
                parameters = @{
                    type = "object"
                    properties = @{
                        command = @{
                            type = "string"
                            description = "The PowerShell command to execute"
                        }
                        timeout = @{
                            type = "integer"
                            description = "Timeout in seconds (default 30)"
                        }
                    }
                    required = @("command")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "file_read"
                description = "Read the contents of a file from the local filesystem."
                parameters = @{
                    type = "object"
                    properties = @{
                        path = @{
                            type = "string"
                            description = "Absolute path to the file"
                        }
                        lines = @{
                            type = "integer"
                            description = "Number of lines to read (default: all)"
                        }
                    }
                    required = @("path")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "file_write"
                description = "Write content to a file on the local filesystem. Creates the file if it doesn't exist."
                parameters = @{
                    type = "object"
                    properties = @{
                        path = @{
                            type = "string"
                            description = "Absolute path to the file"
                        }
                        content = @{
                            type = "string"
                            description = "Content to write to the file"
                        }
                        append = @{
                            type = "boolean"
                            description = "If true, append to file instead of overwriting (default: false)"
                        }
                    }
                    required = @("path", "content")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "file_list"
                description = "List files and directories in a given path."
                parameters = @{
                    type = "object"
                    properties = @{
                        path = @{
                            type = "string"
                            description = "Directory path to list (default: current directory)"
                        }
                        pattern = @{
                            type = "string"
                            description = "File pattern to filter (e.g. '*.txt', '*.ps1')"
                        }
                    }
                    required = @()
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "web_fetch"
                description = "Fetch the content of a web page by URL."
                parameters = @{
                    type = "object"
                    properties = @{
                        url = @{
                            type = "string"
                            description = "The URL to fetch"
                        }
                    }
                    required = @("url")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "web_search"
                description = "Search the web using a search query. Returns top results with titles and snippets."
                parameters = @{
                    type = "object"
                    properties = @{
                        query = @{
                            type = "string"
                            description = "Search query"
                        }
                        count = @{
                            type = "integer"
                            description = "Number of results (default 5)"
                        }
                    }
                    required = @("query")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "memory_save"
                description = "Save an important piece of information to persistent memory for future reference."
                parameters = @{
                    type = "object"
                    properties = @{
                        entry = @{
                            type = "string"
                            description = "The information to save to memory"
                        }
                    }
                    required = @("entry")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "skill_run"
                description = "Run a named skill with optional arguments."
                parameters = @{
                    type = "object"
                    properties = @{
                        name = @{
                            type = "string"
                            description = "Name of the skill to run"
                        }
                        arguments = @{
                            type = "string"
                            description = "JSON string of arguments to pass to the skill"
                        }
                    }
                    required = @("name")
                }
            }
        }
    )
}

function Get-CrabbyToolsDescription {
    return @"
- **shell** — Execute PowerShell commands
- **file_read** — Read file contents
- **file_write** — Write or append to files
- **file_list** — List directory contents
- **web_fetch** — Fetch web page content
- **web_search** — Search the web
- **memory_save** — Save information to persistent memory
- **skill_run** — Run an installed skill
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
    
    # Parse arguments
    $args = @{}
    if (-not [string]::IsNullOrWhiteSpace($Arguments)) {
        try {
            $args = $Arguments | ConvertFrom-Json -AsHashtable
        }
        catch {
            # Try as simple string args
            $args = @{ _raw = $Arguments }
        }
    }
    
    try {
        switch ($Name) {
            "shell" {
                $cmd = $args["command"]
                $timeout = if ($args["timeout"]) { $args["timeout"] } else { 30 }
                
                $output = PowerShell -Command $cmd -NoProfile 2>&1 | Out-String
                $output = $output.Trim()
                
                if ($output.Length -gt 5000) {
                    $output = $output.Substring(0, 5000) + "`n... (output truncated)"
                }
                
                return $output
            }
            
            "file_read" {
                $path = $args["path"]
                $lines = $args["lines"]
                
                if (-not (Test-Path $path)) {
                    return "File not found: $path"
                }
                
                if ($lines) {
                    $content = Get-Content $path -TotalCount $lines -Encoding UTF8 | Out-String
                } else {
                    $content = Get-Content $path -Raw -Encoding UTF8
                }
                
                if ($content.Length -gt 10000) {
                    $content = $content.Substring(0, 10000) + "`n... (content truncated)"
                }
                
                return $content
            }
            
            "file_write" {
                $path = $args["path"]
                $content = $args["content"]
                $append = $args["append"]
                
                $dir = Split-Path $path -Parent
                if ($dir -and -not (Test-Path $dir)) {
                    New-Item -Path $dir -ItemType Directory -Force | Out-Null
                }
                
                if ($append) {
                    Add-Content $path $content -Encoding UTF8
                } else {
                    Set-Content $path $content -Encoding UTF8
                }
                
                return "File written successfully: $path"
            }
            
            "file_list" {
                $path = if ($args["path"]) { $args["path"] } else { "." }
                $pattern = if ($args["pattern"]) { $args["pattern"] } else { "*" }
                
                $items = Get-ChildItem -Path $path -Filter $pattern | Select-Object Mode, LastWriteTime, Length, Name
                $result = ($items | Format-Table -AutoSize | Out-String).Trim()
                
                return $result
            }
            
            "web_fetch" {
                $url = $args["url"]
                
                try {
                    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
                    $content = $response.Content
                    
                    # Strip HTML tags for a cleaner result
                    $content = $content -replace '<[^>]+>', ' '
                    $content = $content -replace '\s+', ' '
                    $content = $content.Trim()
                    
                    if ($content.Length -gt 8000) {
                        $content = $content.Substring(0, 8000) + "... (content truncated)"
                    }
                    
                    return $content
                }
                catch {
                    return "Failed to fetch URL: $($_.Exception.Message)"
                }
            }
            
            "web_search" {
                $query = $args["query"]
                $count = if ($args["count"]) { $args["count"] } else { 5 }
                
                # Use DuckDuckGo HTML search (no API key needed)
                $searchUrl = "https://html.duckduckgo.com/html/?q=$([Uri]::EscapeDataString($query))"
                
                try {
                    $response = Invoke-WebRequest -Uri $searchUrl -UseBasicParsing -TimeoutSec 15
                    $html = $response.Content
                    
                    # Parse results (simple regex)
                    $results = @()
                    $regex = '<a rel="nofollow" class="result__a" href="([^"]+)">(.*?)</a>.*?<a class="result__snippet"[^>]*>(.*?)</a>'
                    $matches = [regex]::Matches($html, $regex, [System.Text.RegularExpressions.RegexOptions]::Singleline)
                    
                    foreach ($m in $matches | Select-Object -First $count) {
                        $title = $m.Groups[2].Value -replace '<[^>]+>', '' -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>'
                        $snippet = $m.Groups[3].Value -replace '<[^>]+>', '' -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>'
                        $link = $m.Groups[1].Value
                        $results += "- **$title**`n  $snippet`n  $link"
                    }
                    
                    if ($results.Count -eq 0) {
                        return "No results found for: $query"
                    }
                    
                    return ($results -join "`n`n")
                }
                catch {
                    return "Search failed: $($_.Exception.Message)"
                }
            }
            
            "memory_save" {
                $entry = $args["entry"]
                Add-CrabbyMemory -RootDir $RootDir -Entry $entry
                return "Saved to memory: $entry"
            }
            
            "skill_run" {
                $skillName = $args["name"]
                $skillArgs = $args["arguments"]
                
                return Invoke-CrabbySkillByName -Name $skillName -Arguments $skillArgs -RootDir $RootDir
            }
            
            default {
                return "Unknown tool: $Name"
            }
        }
    }
    catch {
        return "Tool error ($Name): $($_.Exception.Message)"
    }
}

'@ -Encoding UTF8

Set-Content -Path "$Dest\src\Skills.ps1" -Value @'
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

'@ -Encoding UTF8

Set-Content -Path "$Dest\config\SOUL.md" -Value @'
# Crabby Soul

You are Crabby 🦀, a personal AI assistant.
You are helpful, witty, and slightly snarky — like a clever crab who's always got your back.
You speak concisely and naturally, avoiding robotic phrases.
You adapt your tone to the user's mood: supportive when they're stuck, celebratory when they succeed, and gently honest when they need a reality check.

## Personality
- Smart and efficient, not chatty for the sake of it
- Loves a good pun, especially crab-related ones 🦀
- Gets things done rather than explaining why things can't be done
- Protective of the user's time and resources

## Communication Style
- Short, direct responses
- Use markdown formatting when it helps readability
- Code blocks for technical content
- Emoji sparingly, not in every sentence

'@ -Encoding UTF8

Set-Content -Path "$Dest\config\USER.md" -Value @'
## User Profile
- Name: (set during onboarding)

'@ -Encoding UTF8

Set-Content -Path "$Dest\config\settings.json" -Value @'
{
    "llm": {
        "provider": "siliconflow",
        "api_key": "YOUR_API_KEY_HERE",
        "model": "Qwen/Qwen2.5-7B-Instruct",
        "base_url": "https://api.siliconflow.cn/v1",
        "max_tokens": 2048,
        "temperature": 0.7
    },
    "user": {
        "name": "User"
    }
}

'@ -Encoding UTF8

Set-Content -Path "$Dest\memory\MEMORY.md" -Value @'
# Crabby Memory

'@ -Encoding UTF8

Set-Content -Path "$Dest\memory\heartbeat.md" -Value @'
# Heartbeat Checks

- Check if there are any unread emails
- Check system disk space and warn if below 10%
- Check for any important news in AI/tech

'@ -Encoding UTF8

Set-Content -Path "$Dest\skills\system-info.ps1" -Value @'
<#
.SkillName system-info
.Description 获取系统信息（CPU、内存、磁盘、OS版本）
.Trigger 系统信息|system info|电脑状态|系统状态
#>
param()

$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"

$output = @"
## System Information

**OS:** $($os.Caption) ($($os.Version))
**CPU:** $($cpu.Name)
**RAM:** $([Math]::Round($os.TotalVisibleMemorySize / 1MB, 1)) GB total, $([Math]::Round($os.FreePhysicalMemory / 1MB, 1)) GB free
**Uptime:** $((Get-Date) - $os.LastBootUpTime | ForEach-Object { "$($_.Days)d $($_.Hours)h $($_.Minutes)m" })
"@

foreach ($disk in $disks) {
    $free = [Math]::Round($disk.FreeSpace / 1GB, 1)
    $total = [Math]::Round($disk.Size / 1GB, 1)
    $pct = [Math]::Round(($disk.FreeSpace / $disk.Size) * 100, 1)
    $output += "`n**Disk $($disk.DeviceID)** $free GB free / $total GB ($pct% free)"
}

Write-Output $output

'@ -Encoding UTF8

Set-Content -Path "$Dest\skills\weather-check.ps1" -Value @'
<#
.SkillName weather-check
.Description 查询指定城市的实时天气（使用wttr.in）
.Trigger 天气|weather|温度|气温
#>
param([string]$City = "Shanghai")

$result = Invoke-RestMethod -Uri "https://wttr.in/$City?format=4&lang=zh" -TimeoutSec 10 2>$null
if ($result) {
    Write-Output "🌤️ $result"
} else {
    Write-Output "无法获取天气信息，请检查网络连接。"
}

'@ -Encoding UTF8

Set-Content -Path "$Dest\.gitignore" -Value @'
node_modules/
config/settings.json
memory/conversations/
*.log
.env

'@ -Encoding UTF8

Set-Content -Path "$Dest\LICENSE" -Value @'
MIT License

Copyright (c) 2026 chenruiqi449

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

'@ -Encoding UTF8

Set-Content -Path "$Dest\README.md" -Value @'
# 🦀 Crabby AI

> Your personal AI assistant, the crab way. Pure PowerShell, Windows native.

Crabby AI is a self-hosted personal AI assistant that runs entirely in PowerShell on Windows. No WSL, no Node.js, no Python — just PowerShell and an LLM API key.

## Features

- 🧠 **Multi-LLM Support** — SiliconFlow, Zhipu, DeepSeek, OpenAI, or any OpenAI-compatible API
- 💾 **Persistent Memory** — Markdown-based memory system (MEMORY.md, USER.md)
- 🎭 **Configurable Personality** — Define your assistant's soul in SOUL.md
- 🔧 **Built-in Tools** — Shell execution, file I/O, web search & fetch
- 🧩 **Skills System** — Extend with PowerShell scripts
- ⏰ **Heartbeat Scheduling** — Windows Task Scheduler integration for 24/7 automation
- 🔒 **Privacy First** — Everything runs locally, your data stays on your machine

## Quick Start

```powershell
# 1. Clone the repo
git clone https://github.com/chenruiqi449/crabby-ai.git
cd crabby-ai

# 2. Run setup
.\install.ps1

# 3. Start chatting
.\crabby.ps1
```

## Configuration

Edit `config/settings.json` to set your API key and preferred model:

```json
{
  "llm": {
    "provider": "siliconflow",
    "api_key": "your-api-key-here",
    "model": "Qwen/Qwen2.5-7B-Instruct",
    "base_url": "https://api.siliconflow.cn/v1"
  }
}
```

### Supported Providers

| Provider | Base URL | Free Tier |
|----------|----------|-----------|
| SiliconFlow | `https://api.siliconflow.cn/v1` | 2000万 tokens |
| Zhipu (智谱) | `https://open.bigmodel.cn/api/paas/v4/` | 2000万 tokens |
| DeepSeek | `https://api.deepseek.com/v1` | 200万 tokens/7天 |
| OpenAI | `https://api.openai.com/v1` | Paid |

## Project Structure

```
crabby-ai/
├── crabby.ps1          # Main entry point
├── install.ps1         # Setup & onboarding wizard
├── src/
│   ├── LLM.ps1         # LLM API client (OpenAI-compatible)
│   ├── Memory.ps1      # Memory & conversation management
│   ├── Tools.ps1       # Built-in tools (shell, file, web)
│   └── Skills.ps1      # Skills loader & executor
├── config/
│   ├── SOUL.md         # Assistant personality
│   ├── USER.md         # User profile
│   └── settings.json   # API & model settings
├── memory/
│   ├── MEMORY.md       # Persistent memory
│   └── conversations/  # Chat history
├── skills/             # Custom skills (PowerShell scripts)
└── README.md
```

## Usage

### Chat Mode
```powershell
.\crabby.ps1                    # Interactive chat
.\crabby.ps1 -Message "你好"    # One-shot query
```

### Heartbeat Mode
```powershell
.\crabby.ps1 -Heartbeat         # Run heartbeat check
```

### Install as Scheduled Task
```powershell
.\install.ps1 -ScheduleHeartbeat  # Register 30-min heartbeat
```

## Skills

Skills are PowerShell scripts placed in the `skills/` directory. Each skill is a `.ps1` file with a comment-based help header:

```powershell
<#
.SkillName weather-check
.Description 查询指定城市的实时天气
.Trigger 天气|weather|温度
#>
param([string]$City = "上海")
# ... skill logic
```

## License

MIT License

'@ -Encoding UTF8

Write-Host ""
Write-Host "  ✅ Crabby AI installed!" -ForegroundColor Green
Write-Host "  📂 Project location: $Dest" -ForegroundColor Gray
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Gray
Write-Host "  1. cd D:\Desktop\crabby-ai" -ForegroundColor White
Write-Host "  2. .\install.ps1     # Run setup wizard" -ForegroundColor White
Write-Host "  3. .\crabby.ps1      # Start chatting!" -ForegroundColor White
Write-Host ""