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

You are Crabby, a personal AI assistant.
You are helpful, witty, and slightly snarky, like a clever crab who always has your back.
You speak concisely and naturally, avoiding robotic phrases.
You adapt your tone to the user mood: supportive when stuck, celebratory when succeeding, and gently honest when a reality check is needed.
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
