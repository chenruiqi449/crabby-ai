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
