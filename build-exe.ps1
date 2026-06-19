<#
.SYNOPSIS
    Crabby AI — Build EXE
.DESCRIPTION
    Bundles all source files into a single script and compiles to CrabbyAI.exe using PS2EXE.
    Run this script in the crabby-ai project root directory.
#>

param(
    [string]$OutputDir = ".\build"
)

$ErrorActionPreference = "Stop"
$RootDir = $PSScriptRoot

Write-Host ""
Write-Host "  🦀 Crabby AI — Build EXE" -ForegroundColor DarkCyan
Write-Host "  ─────────────────────────" -ForegroundColor DarkGray
Write-Host ""

# ============================================================
# Step 1: Install PS2EXE
# ============================================================
Write-Host "  [1/3] Checking PS2EXE..." -ForegroundColor Gray
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "        Installing PS2EXE (first time only)..." -ForegroundColor Gray
    Install-Module -Name ps2exe -Scope CurrentUser -Force -ErrorAction Stop
}
Import-Module ps2exe
Write-Host "        OK" -ForegroundColor Green

# ============================================================
# Step 2: Create bundled script
# ============================================================
Write-Host "  [2/3] Bundling source files..." -ForegroundColor Gray

$srcFiles = @(
    @{ Path = "$RootDir\src\LLM.ps1";    Tag = "LLM" },
    @{ Path = "$RootDir\src\Memory.ps1"; Tag = "Memory" },
    @{ Path = "$RootDir\src\Tools.ps1";  Tag = "Tools" },
    @{ Path = "$RootDir\src\Skills.ps1"; Tag = "Skills" }
)

$srcBundle = ""
foreach ($file in $srcFiles) {
    if (-not (Test-Path $file.Path)) {
        Write-Host "        Missing: $($file.Path)" -ForegroundColor Red
        exit 1
    }
    $content = Get-Content $file.Path -Raw -Encoding UTF8
    # Remove param blocks and function re-definitions are fine since dot-sourcing would do the same
    $srcBundle += "#region ===== $($file.Tag) =====`n$content`n#endregion ===== $($file.Tag) =====`n`n"
}

# Read the GUI script
$guiPath = "$RootDir\crabby-gui.ps1"
if (-not (Test-Path $guiPath)) {
    Write-Host "        Missing: $guiPath" -ForegroundColor Red
    exit 1
}
$guiContent = Get-Content $guiPath -Raw -Encoding UTF8

# Replace dot-source lines with inline code
$bundle = $guiContent
$bundle = $bundle -replace '\. "\$RootDir\\src\\LLM\.ps1"', $srcBundle.Substring(0, $srcBundle.IndexOf("#region ===== LLM")) + ($srcBundle -split "#region ===== LLM =====`n", 2)[1] -split "#endregion ===== LLM =====", 2 | Select-Object -First 1

# Simpler approach: just remove all dot-source lines and prepend all source code
$bundle = $guiContent
$bundle = $bundle -replace '(?m)^\. "\$RootDir\\src\\LLM\.ps1"\s*$', ""
$bundle = $bundle -replace '(?m)^\. "\$RootDir\\src\\Memory\.ps1"\s*$', ""
$bundle = $bundle -replace '(?m)^\. "\$RootDir\\src\\Tools\.ps1"\s*$', ""
$bundle = $bundle -replace '(?m)^\. "\$RootDir\\src\\Skills\.ps1"\s*$', ""

# Insert all source code right after the param block and RootDir setup
$insertPoint = '# Load WPF assemblies'
$bundle = $bundle -replace [regex]::Escape($insertPoint), "$srcBundle`n$insertPoint"

# Fix RootDir: in PS2EXE, $PSScriptRoot points to a temp dir.
# We want config/memory/skills next to the .exe file.
$bundle = $bundle -replace 'if \(-not \$RootDir\) \{ \$RootDir = \$PSScriptRoot \}', @'
if (-not $RootDir) {
    # When running as compiled .exe, use the exe's directory
    $exePath = [Environment]::GetCommandLineArgs()[0]
    if ($exePath -and (Test-Path $exePath)) {
        $RootDir = Split-Path -Parent $exePath
    } else {
        $RootDir = $PSScriptRoot
    }
}
'@

# Add data directory auto-creation after RootDir
$autoCreateDirs = @'

# Auto-create data directories if missing
@("$RootDir\config", "$RootDir\memory", "$RootDir\memory\conversations", "$RootDir\skills") | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item -Path $_ -ItemType Directory -Force | Out-Null }
}

'@
$bundle = $bundle -replace ([regex]::Escape('# Load WPF assemblies')), "$autoCreateDirs`n# Load WPF assemblies"

# Save bundled script
if (-not (Test-Path $OutputDir)) { New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null }
$bundlePath = Join-Path $OutputDir "crabby-bundle.ps1"
Set-Content $bundlePath $bundle -Encoding UTF8
Write-Host "        Bundle: $bundlePath" -ForegroundColor Green

# ============================================================
# Step 3: Compile to EXE
# ============================================================
Write-Host "  [3/3] Compiling to EXE..." -ForegroundColor Gray
$exePath = Join-Path $OutputDir "CrabbyAI.exe"

# PS2EXE compile (noConsole for WPF GUI app)
Invoke-PS2EXE `
    -InputFile $bundlePath `
    -OutputFile $exePath `
    -noConsole `
    -title "Crabby AI" `
    -product "Crabby AI" `
    -version "1.3.0" `
    -requireAdmin:$false

if (Test-Path $exePath) {
    $size = [math]::Round((Get-Item $exePath).Length / 1MB, 1)
    Write-Host "        OK: $exePath ($size MB)" -ForegroundColor Green
} else {
    Write-Host "        FAILED: EXE not created" -ForegroundColor Red
    exit 1
}

# ============================================================
# Step 4: Copy default data files
# ============================================================
Write-Host "  [+] Copying default data files..." -ForegroundColor Gray

# Copy config defaults if they exist
if (Test-Path "$RootDir\config") {
    $destConfig = Join-Path $OutputDir "config"
    if (-not (Test-Path $destConfig)) { New-Item -Path $destConfig -ItemType Directory -Force | Out-Null }
    Copy-Item "$RootDir\config\*" $destConfig -Recurse -Force -ErrorAction SilentlyContinue
}

# Copy skills
if (Test-Path "$RootDir\skills") {
    $destSkills = Join-Path $OutputDir "skills"
    if (-not (Test-Path $destSkills)) { New-Item -Path $destSkills -ItemType Directory -Force | Out-Null }
    Copy-Item "$RootDir\skills\*" $destSkills -Recurse -Force -ErrorAction SilentlyContinue
}

# Ensure memory dirs
$destMem = Join-Path $OutputDir "memory\conversations"
if (-not (Test-Path $destMem)) { New-Item -Path $destMem -ItemType Directory -Force | Out-Null }

Write-Host ""
Write-Host "  🦀 Build complete!" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  Output:" -ForegroundColor Gray
Write-Host "    $exePath" -ForegroundColor White
Write-Host "    $OutputDir\config\" -ForegroundColor White
Write-Host "    $OutputDir\memory\" -ForegroundColor White
Write-Host "    $OutputDir\skills\" -ForegroundColor White
Write-Host ""
Write-Host "  Usage: Copy the entire build/ folder anywhere and run CrabbyAI.exe" -ForegroundColor Gray
Write-Host ""
