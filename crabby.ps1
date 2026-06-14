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
