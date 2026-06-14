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
