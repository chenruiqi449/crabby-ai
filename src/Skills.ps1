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
