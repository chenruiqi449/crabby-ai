<#
.SYNOPSIS
    Crabby AI — Web Server
.DESCRIPTION
    HTTP server for Crabby's web UI. Serves static files and handles chat API.
    Uses System.Net.HttpListener (built-in, no dependencies).
#>

param(
    [string]$RootDir = "",
    [int]$Port = 8420
)

if (-not $RootDir) { $RootDir = $PSScriptRoot | Split-Path -Parent }
$ErrorActionPreference = "Stop"

# Load modules
. "$RootDir\src\LLM.ps1"
. "$RootDir\src\Memory.ps1"
. "$RootDir\src\Tools.ps1"
. "$RootDir\src\Skills.ps1"

# Load configuration
$Settings = Get-CrabbySettings -RootDir $RootDir
$Soul = Get-CrabbySoul -RootDir $RootDir
$UserProfile = Get-CrabbyUserProfile -RootDir $RootDir

# ============================================================
# Conversation State
# ============================================================

$script:Conversations = @{}

function Get-SystemPrompt {
    return @"
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
- The shell tool maintains a persistent session: working directory, variables, and imports persist across commands. Use `cd` freely, set variables, import modules — they'll stick.
- When the user asks you to do something, DO IT directly using shell/file tools. Don't just give instructions — execute them.
- For dangerous operations (deleting files recursively, formatting drives, etc.), you will get a confirmation prompt. Tell the user what you're about to do and ask before using shell_confirm.
- Keep responses concise and natural, like chatting with a friend.
- Respond in the same language the user uses.
"@
}

function Get-Conversation {
    param([string]$SessionId)
    if (-not $script:Conversations.ContainsKey($SessionId)) {
        $script:Conversations[$SessionId] = @(
            @{ role = "system"; content = (Get-SystemPrompt) }
        )
    }
    return $script:Conversations[$SessionId]
}

function Reset-Conversation {
    param([string]$SessionId)
    $script:Conversations[$SessionId] = @(
        @{ role = "system"; content = (Get-SystemPrompt) }
    )
}

# ============================================================
# Chat Processing
# ============================================================

function Process-ChatMessage {
    param(
        [string]$SessionId,
        [string]$UserMessage
    )
    
    $conversation = Get-Conversation -SessionId $SessionId
    $conversation += @{ role = "user"; content = $UserMessage }
    
    $toolEvents = @()
    $maxRounds = 8
    $round = 0
    $assistantMsg = ""
    
    while ($round -lt $maxRounds) {
        $round++
        $result = Invoke-CrabbyChat -Settings $Settings -Conversation $conversation -SupportTools $true
        
        if ($result.ToolCalls) {
            $conversation += @{ role = "assistant"; content = $result.Content; tool_calls = $result.ToolCalls }
            
            foreach ($toolCall in $result.ToolCalls) {
                $toolName = $toolCall.function.name
                $toolArgs = $toolCall.function.arguments
                
                $toolEvents += @{
                    name = $toolName
                    args = $toolArgs
                    status = "running"
                }
                
                $toolResult = Invoke-CrabbyTool -Name $toolName -Arguments $toolArgs -RootDir $RootDir
                
                $toolEvents[-1].status = "done"
                $toolEvents[-1].result = if ($toolResult.Length -gt 2000) { $toolResult.Substring(0, 2000) + "..." } else { $toolResult }
                
                $conversation += @{
                    role = "tool"
                    tool_call_id = $toolCall.id
                    content = $toolResult
                }
            }
        } else {
            $assistantMsg = $result.Content
            $conversation += @{ role = "assistant"; content = $assistantMsg }
            break
        }
    }
    
    if ($round -ge $maxRounds -and -not $assistantMsg) {
        $assistantMsg = "[Max tool rounds reached]"
    }
    
    # Save conversation
    Save-CrabbyConversation -RootDir $RootDir -UserMessage $UserMessage -AssistantResponse $assistantMsg
    
    # Trim conversation if too long
    if ($conversation.Count -gt 30) {
        $systemMsg = $conversation[0]
        $recent = $conversation | Select-Object -Last 28
        $conversation = @($systemMsg) + $recent
    }
    
    $script:Conversations[$SessionId] = $conversation
    
    return @{
        message = $assistantMsg
        tools = $toolEvents
    }
}

# ============================================================
# HTTP Server
# ============================================================

$prefix = "http://localhost:$Port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
}
catch {
    Write-Host "❌ Failed to start server on port $Port. Try a different port: .\crabby-web.ps1 -Port 8080" -ForegroundColor Red
    Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor DarkGray
    return
}

Write-Host ""
Write-Host "  🦀 Crabby AI Web Server" -ForegroundColor DarkCyan
Write-Host "  ─────────────────────────────" -ForegroundColor DarkGray
Write-Host "  URL: http://localhost:$Port" -ForegroundColor Green
Write-Host "  Model: $($Settings.llm.model)" -ForegroundColor Gray
Write-Host "  Press Ctrl+C to stop" -ForegroundColor DarkGray
Write-Host ""

# Open browser
Start-Process "http://localhost:$Port"

$webDir = Join-Path $RootDir "web"

function Send-JsonResponse {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [object]$Data,
        [int]$StatusCode = 200
    )
    
    $json = $Data | ConvertTo-Json -Depth 10 -Compress
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
    
    $Response.StatusCode = $StatusCode
    $Response.ContentType = "application/json; charset=utf-8"
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.OutputStream.Close()
}

function Send-StaticFile {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [string]$FilePath
    )
    
    if (-not (Test-Path $FilePath)) {
        $Response.StatusCode = 404
        $Response.Close()
        return
    }
    
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
    $contentTypes = @{
        ".html" = "text/html; charset=utf-8"
        ".css"  = "text/css; charset=utf-8"
        ".js"   = "application/javascript; charset=utf-8"
        ".json" = "application/json; charset=utf-8"
        ".png"  = "image/png"
        ".jpg"  = "image/jpeg"
        ".jpeg" = "image/jpeg"
        ".gif"  = "image/gif"
        ".svg"  = "image/svg+xml"
        ".ico"  = "image/x-icon"
        ".woff" = "font/woff"
        ".woff2" = "font/woff2"
    }
    
    $contentType = if ($contentTypes.ContainsKey($ext)) { $contentTypes[$ext] } else { "application/octet-stream" }
    
    $buffer = [System.IO.File]::ReadAllBytes($FilePath)
    
    $Response.StatusCode = 200
    $Response.ContentType = $contentType
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.OutputStream.Close()
}

# Main loop
try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        
        # CORS headers
        $response.Headers.Add("Access-Control-Allow-Origin", "*")
        $response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        $response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
        
        # Handle preflight
        if ($request.HttpMethod -eq "OPTIONS") {
            $response.StatusCode = 204
            $response.Close()
            continue
        }
        
        $url = $request.Url.AbsolutePath
        
        try {
            switch ($url) {
                "/api/chat" {
                    if ($request.HttpMethod -ne "POST") {
                        Send-JsonResponse -Response $response -Data @{ error = "POST only" } -StatusCode 405
                        continue
                    }
                    
                    # Read request body
                    $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
                    $body = $reader.ReadToEnd()
                    $reader.Close()
                    
                    $data = $body | ConvertFrom-Json
                    $sessionId = if ($data.session_id) { $data.session_id } else { "default" }
                    $message = $data.message
                    
                    if ([string]::IsNullOrWhiteSpace($message)) {
                        Send-JsonResponse -Response $response -Data @{ error = "Message is required" } -StatusCode 400
                        continue
                    }
                    
                    $result = Process-ChatMessage -SessionId $sessionId -UserMessage $message
                    Send-JsonResponse -Response $response -Data $result
                }
                
                "/api/reset" {
                    if ($request.HttpMethod -ne "POST") {
                        Send-JsonResponse -Response $response -Data @{ error = "POST only" } -StatusCode 405
                        continue
                    }
                    
                    $reader = New-Object System.IO.StreamReader($request.InputStream, $request.ContentEncoding)
                    $body = $reader.ReadToEnd()
                    $reader.Close()
                    
                    $data = $body | ConvertFrom-Json
                    $sessionId = if ($data.session_id) { $data.session_id } else { "default" }
                    
                    Reset-Conversation -SessionId $sessionId
                    Send-JsonResponse -Response $response -Data @{ status = "ok" }
                }
                
                "/api/status" {
                    $status = @{
                        model = $Settings.llm.model
                        provider = $Settings.llm.provider
                        version = "1.2"
                        sessions = $script:Conversations.Count
                    }
                    Send-JsonResponse -Response $response -Data $status
                }
                
                default {
                    # Serve static files
                    if ($url -eq "/") { $url = "/index.html" }
                    
                    $filePath = Join-Path $webDir $url.TrimStart("/")
                    
                    # Security: prevent path traversal
                    $fullPath = [System.IO.Path]::GetFullPath($filePath)
                    if (-not $fullPath.StartsWith($webDir)) {
                        $response.StatusCode = 403
                        $response.Close()
                        continue
                    }
                    
                    Send-StaticFile -Response $response -FilePath $fullPath
                }
            }
        }
        catch {
            try {
                Send-JsonResponse -Response $response -Data @{ error = $_.Exception.Message } -StatusCode 500
            }
            catch {
                try { $response.Close() } catch {}
            }
        }
    }
}
finally {
    $listener.Stop()
    Write-Host "`n🦀 Server stopped." -ForegroundColor DarkCyan
}
