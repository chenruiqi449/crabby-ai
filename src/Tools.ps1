<#
.SYNOPSIS
    Crabby AI — Built-in Tools
.DESCRIPTION
    Tool definitions and execution for shell, file I/O, and web operations.
    v2.0: Persistent PowerShell session, safety guardrails, proper timeout.
#>

# ============================================================
# Persistent PowerShell Session
# ============================================================

# Global runspace for persistent shell session
$script:CrabbyRunspace = $null
$script:CrabbyPipeline = $null

function Initialize-CrabbyShell {
    <#
    .SYNOPSIS
        Create a persistent PowerShell runspace so state (cwd, variables, modules) survives across tool calls.
    #>
    if ($script:CrabbyRunspace -and $script:CrabbyRunspace.RunspaceStateInfo.State -eq 'Opened') {
        return
    }
    
    $script:CrabbyRunspace = [runspacefactory]::CreateRunspace()
    $script:CrabbyRunspace.Open()
    
    # Set initial working directory to user's home
    $script:CrabbyRunspace.SessionStateProxy.SetVariable('crabby_cwd', $env:USERPROFILE)
}

function Invoke-CrabbyShellCommand {
    param(
        [string]$Command,
        [int]$TimeoutSeconds = 30
    )
    
    Initialize-CrabbyShell
    
    # Dangerous command patterns — require confirmation
    $dangerousPatterns = @(
        'rm\s+(-r|-rf|-recurse|/s)',
        'Remove-Item.*-Recurse',
        'del\s+(/s|/q|-recurse)',
        'rmdir\s+(/s|/q)',
        'Format-Volume',
        'format\s+[a-z]:',
        'Stop-Computer',
        'Restart-Computer',
        'Shutdown',
        'net\s+(user|localgroup)',
        'reg\s+(delete|add)',
        'Remove-Service',
        'Set-ExecutionPolicy.*Unrestricted'
    )
    
    $isDangerous = $false
    foreach ($pattern in $dangerousPatterns) {
        if ($Command -match $pattern) {
            $isDangerous = $true
            break
        }
    }
    
    if ($isDangerous) {
        return "⚠️ DANGEROUS_COMMAND_DETECTED`nThe command may cause irreversible changes:`n  $Command`n`nPlease confirm: type 'yes' to proceed, or rephrase your request."
    }
    
    # Wrap command to capture cwd changes
    $wrappedCommand = @"
try {
    $Command
    `$crabby_cwd = (Get-Location).Path
} catch {
    Write-Error `$_.Exception.Message
}
"@
    
    # Create pipeline in the runspace
    $pipeline = $script:CrabbyRunspace.CreatePipeline($wrappedCommand)
    
    # Set initial location if we have a tracked cwd
    $trackedCwd = $script:CrabbyRunspace.SessionStateProxy.GetVariable('crabby_cwd')
    if ($trackedCwd -and (Test-Path $trackedCwd)) {
        $pipeline.Commands.Insert(0, [System.Management.Automation.Runspaces.Command]::new("Set-Location"))
        $pipeline.Commands[0].Parameters.Add("Path", $trackedCwd)
    }
    
    # Execute with timeout
    $pipeline.InvokeAsync()
    
    $startTime = Get-Date
    $timeoutMs = $TimeoutSeconds * 1000
    
    while (-not $pipeline.Output.EndOfPipeline) {
        if (((Get-Date) - $startTime).TotalMilliseconds -gt $timeoutMs) {
            $pipeline.Stop()
            return "⏱️ Command timed out after $TimeoutSeconds seconds: $Command"
        }
        Start-Sleep -Milliseconds 100
    }
    
    # Collect output
    $output = @()
    foreach ($item in $pipeline.Output) {
        $output += $item.ToString()
    }
    
    $errors = @()
    foreach ($err in $pipeline.Error) {
        $errors += $err.ToString()
    }
    
    $result = ""
    if ($output.Count -gt 0) {
        $result = ($output -join "`n").Trim()
    }
    if ($errors.Count -gt 0) {
        $errText = ($errors -join "`n").Trim()
        if ($errText) {
            $result += "`n❌ $errText"
        }
    }
    
    if ($result.Length -gt 8000) {
        $result = $result.Substring(0, 8000) + "`n... (output truncated)"
    }
    
    # Update tracked cwd
    $newCwd = $script:CrabbyRunspace.SessionStateProxy.GetVariable('crabby_cwd')
    if ($newCwd) {
        $script:CrabbyRunspace.SessionStateProxy.SetVariable('crabby_cwd', $newCwd)
    }
    
    if ([string]::IsNullOrWhiteSpace($result)) {
        return "✅ Command completed (no output). CWD: $(if($newCwd){$newCwd}else{$trackedCwd})"
    }
    
    # Append current working directory info
    $cwdInfo = if ($newCwd) { $newCwd } elseif ($trackedCwd) { $trackedCwd } else { "unknown" }
    $result += "`n📂 CWD: $cwdInfo"
    
    return $result
}

# ============================================================
# Tool Schema (OpenAI function calling format)
# ============================================================

function Get-CrabbyToolsSchema {
    return @(
        @{
            type = "function"
            function = @{
                name = "shell"
                description = "Execute a PowerShell command on the local machine. Maintains a persistent session — variables, working directory, and module imports persist across calls. Use for system operations, running scripts, installing software, managing services, or any command-line task."
                parameters = @{
                    type = "object"
                    properties = @{
                        command = @{
                            type = "string"
                            description = "The PowerShell command to execute"
                        }
                        timeout = @{
                            type = "integer"
                            description = "Timeout in seconds (default 30, max 300)"
                        }
                    }
                    required = @("command")
                }
            }
        },
        @{
            type = "function"
            function = @{
                name = "shell_confirm"
                description = "Confirm execution of a previously blocked dangerous command. Only use when the user explicitly says 'yes' to proceed."
                parameters = @{
                    type = "object"
                    properties = @{
                        command = @{
                            type = "string"
                            description = "The dangerous command to confirm and execute"
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
                        offset = @{
                            type = "integer"
                            description = "Line number to start reading from (0-based, default: 0)"
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
                description = "Write content to a file on the local filesystem. Creates the file and parent directories if they don't exist."
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
                        recurse = @{
                            type = "boolean"
                            description = "If true, list recursively (default: false)"
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
- **shell** — Execute PowerShell commands (persistent session, cwd & variables preserved)
- **shell_confirm** — Confirm and execute a blocked dangerous command
- **file_read** — Read file contents (supports offset/lines)
- **file_write** — Write or append to files (auto-creates directories)
- **file_list** — List directory contents (optional recursive)
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
            $args = @{ _raw = $Arguments }
        }
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
                # Execute without safety check since user confirmed
                Initialize-CrabbyShell
                
                $pipeline = $script:CrabbyRunspace.CreatePipeline($cmd)
                $trackedCwd = $script:CrabbyRunspace.SessionStateProxy.GetVariable('crabby_cwd')
                if ($trackedCwd -and (Test-Path $trackedCwd)) {
                    $pipeline.Commands.Insert(0, [System.Management.Automation.Runspaces.Command]::new("Set-Location"))
                    $pipeline.Commands[0].Parameters.Add("Path", $trackedCwd)
                }
                
                $output = $pipeline.Invoke() | Out-String
                $errors = @()
                foreach ($err in $pipeline.Error) {
                    $errors += $err.ToString()
                }
                
                $result = $output.Trim()
                if ($errors.Count -gt 0) {
                    $errText = ($errors -join "`n").Trim()
                    if ($errText) { $result += "`n❌ $errText" }
                }
                
                # Update cwd
                try {
                    $newCwd = $pipeline.Output | Where-Object { $_ -is [System.IO.DirectoryInfo] } | Select-Object -First 1
                    if (-not $newCwd) {
                        $newCwd = (Get-Location).Path
                    }
                } catch {}
                
                return $result
            }
            
            "file_read" {
                $path = $args["path"]
                $lines = $args["lines"]
                $offset = if ($args["offset"]) { $args["offset"] } else { 0 }
                
                if (-not (Test-Path $path)) {
                    return "File not found: $path"
                }
                
                $content = Get-Content $path -Encoding UTF8
                
                if ($offset -gt 0) {
                    $content = $content | Select-Object -Skip $offset
                }
                if ($lines) {
                    $content = $content | Select-Object -First $lines
                }
                
                $result = ($content | Out-String).Trim()
                
                if ($result.Length -gt 10000) {
                    $result = $result.Substring(0, 10000) + "`n... (content truncated, use offset to read more)"
                }
                
                return $result
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
                    Set-Content $path $content -Encoding UTF8 -NoNewline
                }
                
                return "✅ File written: $path ($($content.Length) chars)"
            }
            
            "file_list" {
                $path = if ($args["path"]) { $args["path"] } else { "." }
                $pattern = if ($args["pattern"]) { $args["pattern"] } else { "*" }
                $recurse = $args["recurse"]
                
                $params = @{
                    Path = $path
                    Filter = $pattern
                }
                if ($recurse) {
                    $params.Recurse = $true
                }
                
                $items = Get-ChildItem @params | Select-Object Mode, LastWriteTime, @{N='Size';E={if($_.PSIsContainer){'<DIR>'}else{$_.Length}}}, Name
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
                    return "❌ Failed to fetch: $($_.Exception.Message)"
                }
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
                    return "❌ Search failed: $($_.Exception.Message)"
                }
            }
            
            "memory_save" {
                $entry = $args["entry"]
                Add-CrabbyMemory -RootDir $RootDir -Entry $entry
                return "💾 Saved to memory: $entry"
            }
            
            "skill_run" {
                $skillName = $args["name"]
                $skillArgs = $args["arguments"]
                
                return Invoke-CrabbySkillByName -Name $skillName -Arguments $skillArgs -RootDir $RootDir
            }
            
            default {
                return "❌ Unknown tool: $Name"
            }
        }
    }
    catch {
        return "❌ Tool error ($Name): $($_.Exception.Message)"
    }
}

# Initialize shell on module load
Initialize-CrabbyShell
