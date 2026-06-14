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
