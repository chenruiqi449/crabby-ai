<#
.SYNOPSIS
    Crabby AI — Setup Dependencies
.DESCRIPTION
    Install required tools for file creation (pandoc, ImportExcel, wkhtmltopdf).
    Run once: .\setup-tools.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "  🦀 Crabby AI — Dependency Setup" -ForegroundColor DarkCyan
Write-Host "  ─────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# ============================================================
# 1. Pandoc (docx, pptx, pdf)
# ============================================================

Write-Host "  [1/3] Checking pandoc..." -ForegroundColor Gray

$pandocInstalled = $false
try {
    $pandocVer = pandoc --version 2>$null | Select-Object -First 1
    if ($pandocVer) {
        Write-Host "  ✓ pandoc already installed: $pandocVer" -ForegroundColor Green
        $pandocInstalled = $true
    }
} catch {}

if (-not $pandocInstalled) {
    Write-Host "  Installing pandoc..." -ForegroundColor Yellow
    
    $pandocUrl = "https://github.com/jgm/pandoc/releases/download/3.6.4/pandoc-3.6.4-windows-x86_64.zip"
    $tempZip = "$env:TEMP\pandoc.zip"
    $tempDir = "$env:TEMP\pandoc-extract"
    
    try {
        Invoke-WebRequest -Uri $pandocUrl -OutFile $tempZip -UseBasicParsing
        Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force
        
        # Find pandoc.exe
        $pandocExe = Get-ChildItem $tempDir -Recurse -Filter "pandoc.exe" | Select-Object -First 1
        
        if ($pandocExe) {
            # Copy to a permanent location
            $installDir = "$env:LOCALAPPDATA\CrabbyAI\tools"
            New-Item -Path $installDir -ItemType Directory -Force | Out-Null
            Copy-Item $pandocExe.FullName "$installDir\pandoc.exe" -Force
            
            # Add to PATH if not already there
            $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
            if ($currentPath -notlike "*$installDir*") {
                [Environment]::SetEnvironmentVariable("Path", "$currentPath;$installDir", "User")
                $env:Path = "$env:Path;$installDir"
            }
            
            Write-Host "  ✓ pandoc installed to $installDir" -ForegroundColor Green
        }
        
        # Cleanup
        Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "  ✗ Failed to install pandoc: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "    Please install manually: https://pandoc.org/installing.html" -ForegroundColor DarkGray
    }
}

# ============================================================
# 2. ImportExcel PowerShell Module (xlsx)
# ============================================================

Write-Host "  [2/3] Checking ImportExcel module..." -ForegroundColor Gray

if (Get-Module -ListAvailable -Name ImportExcel) {
    Write-Host "  ✓ ImportExcel module already installed" -ForegroundColor Green
} else {
    Write-Host "  Installing ImportExcel module..." -ForegroundColor Yellow
    try {
        Install-Module -Name ImportExcel -Scope CurrentUser -Force -AllowClobber
        Write-Host "  ✓ ImportExcel installed" -ForegroundColor Green
    }
    catch {
        Write-Host "  ✗ Failed to install ImportExcel: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "    Try manually: Install-Module ImportExcel -Scope CurrentUser" -ForegroundColor DarkGray
    }
}

# ============================================================
# 3. wkhtmltopdf (PDF generation)
# ============================================================

Write-Host "  [3/3] Checking wkhtmltopdf (for PDF generation)..." -ForegroundColor Gray

$wkInstalled = $false
try {
    $wkVer = wkhtmltopdf --version 2>$null
    if ($wkVer) {
        Write-Host "  ✓ wkhtmltopdf already installed: $wkVer" -ForegroundColor Green
        $wkInstalled = $true
    }
} catch {}

if (-not $wkInstalled) {
    Write-Host "  Installing wkhtmltopdf..." -ForegroundColor Yellow
    
    $wkUrl = "https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox-0.12.6.1-3.msvc2015-win64.exe"
    $wkInstaller = "$env:TEMP\wkhtmltopdf_installer.exe"
    
    try {
        Invoke-WebRequest -Uri $wkUrl -OutFile $wkInstaller -UseBasicParsing
        Start-Process -FilePath $wkInstaller -ArgumentList "/S" -Wait
        Write-Host "  ✓ wkhtmltopdf installed" -ForegroundColor Green
        
        # Add to PATH
        $wkPath = "C:\Program Files\wkhtmltopdf\bin"
        if (Test-Path $wkPath) {
            $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
            if ($currentPath -notlike "*$wkPath*") {
                [Environment]::SetEnvironmentVariable("Path", "$currentPath;$wkPath", "User")
                $env:Path = "$env:Path;$wkPath"
            }
        }
        
        Remove-Item $wkInstaller -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host "  ✗ Failed to install wkhtmltopdf: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "    PDF generation will fall back to HTML output." -ForegroundColor DarkGray
        Write-Host "    Install manually: https://wkhtmltopdf.org/downloads.html" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "  🦀 Setup complete! All file creation tools are ready." -ForegroundColor DarkCyan
Write-Host "  Run .\crabby.ps1 to start." -ForegroundColor Gray
Write-Host ""
