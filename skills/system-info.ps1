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
