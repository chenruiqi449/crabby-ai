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
