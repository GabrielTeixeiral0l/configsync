# MountSync Windows 1-Click Installer (PowerShell)
param(
    [string]$Branch = "test-windows"
)

$ErrorActionPreference = "Continue"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "       MountSync Windows 1-Click Installer                  " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# Configure PowerShell script execution policy automatically
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue

$localBin = "$env:USERPROFILE\.local\bin"
$installDir = "$env:USERPROFILE\.local\share\mountsync"
$configDir = "$env:USERPROFILE\.config\mosy"

New-Item -ItemType Directory -Force -Path $localBin | Out-Null
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
New-Item -ItemType Directory -Force -Path $configDir | Out-Null

# 1. Copy or Download Source Files
$localRepo = if ($PSScriptRoot) { $PSScriptRoot } else { "" }
if ($localRepo -and (Test-Path "$localRepo\mosy") -and ($localRepo -ne $installDir)) {
    Write-Host "Copying files from local repository..." -ForegroundColor Yellow
    Copy-Item -Path "$localRepo\mosy" -Destination "$installDir\mosy" -Force
    if (Test-Path "$localRepo\src") {
        Copy-Item -Path "$localRepo\src" -Destination "$installDir\src" -Recurse -Force
    }
} elseif (!(Test-Path "$installDir\mosy")) {
    Write-Host "Downloading MountSync from GitHub ($Branch branch)..." -ForegroundColor Yellow
    $zipUrl = "https://github.com/GabrielTeixeiral0l/MountSync/archive/refs/heads/$Branch.zip"
    $tempZip = "$env:TEMP\mountsync-$Branch.zip"
    $tempExtract = "$env:TEMP\mountsync-extract-$Branch"
    Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing
    Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force
    $extractedFolder = Get-ChildItem -Path $tempExtract | Where-Object { $_.PSIsContainer } | Select-Object -First 1
    if ($extractedFolder) {
        Copy-Item -Path "$($extractedFolder.FullName)\mosy" -Destination "$installDir\mosy" -Force
        Copy-Item -Path "$($extractedFolder.FullName)\src" -Destination "$installDir\src" -Recurse -Force
    }
    Remove-Item -Recurse -Force $tempZip, $tempExtract -ErrorAction SilentlyContinue
}

# 2. Check and Install Dependencies via winget if missing
$hasBash = (Get-Command bash.exe -ErrorAction SilentlyContinue) -or (Test-Path "C:\Program Files\Git\bin\bash.exe") -or (Test-Path "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe")
if (!$hasBash -and (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    Write-Host "Git for Windows is required. Installing automatically via winget..." -ForegroundColor Yellow
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
}

$hasRclone = (Get-Command rclone.exe -ErrorAction SilentlyContinue)
if (!$hasRclone -and (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    Write-Host "Installing rclone automatically via winget..." -ForegroundColor Yellow
    winget install --id Rclone.Rclone -e --source winget --accept-package-agreements --accept-source-agreements
}

# 3. Create CLI Shims in ~/.local/bin
Write-Host "Creating CLI shims (mosy.cmd & mosy.ps1)..." -ForegroundColor Yellow

$posixMosy = $installDir.Replace('\', '/').Replace('C:', '/c').Replace('c:', '/c') + '/mosy'

$cmdLines = @(
    '@echo off',
    'if exist "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" (',
    '    "%LOCALAPPDATA%\Programs\Git\bin\bash.exe" "' + $posixMosy + '" %*',
    ') else if exist "C:\Program Files\Git\bin\bash.exe" (',
    '    "C:\Program Files\Git\bin\bash.exe" "' + $posixMosy + '" %*',
    ') else (',
    '    bash "' + $posixMosy + '" %*',
    ')'
)
$cmdLines | Set-Content -Path "$localBin\mosy.cmd" -Encoding ASCII

$psLines = @(
    '$ErrorActionPreference = "Stop"',
    '$gitBash = if (Test-Path "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe") {',
    '    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"',
    '} elseif (Test-Path "C:\Program Files\Git\bin\bash.exe") {',
    '    "C:\Program Files\Git\bin\bash.exe"',
    '} else {',
    '    "bash.exe"',
    '}',
    '& $gitBash "' + $posixMosy + '" @args'
)
$psLines | Set-Content -Path "$localBin\mosy.ps1" -Encoding UTF8

# 4. Add ~/.local/bin to Windows User PATH
$userPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)
if ($userPath -notlike "*$localBin*") {
    Write-Host "Adding $localBin to User PATH..." -ForegroundColor Yellow
    $newPath = if ($userPath) { "$userPath;$localBin" } else { $localBin }
    [Environment]::SetEnvironmentVariable("Path", $newPath, [EnvironmentVariableTarget]::User)
    $env:Path = "$env:Path;$localBin"
}

# 5. Create default config if missing
$configFile = "$configDir\config"
if (!(Test-Path $configFile)) {
    $cfgLines = @(
        'MOSY_REMOTE_NAME=GoogleDrive',
        'MOSY_MOUNT_POINT=' + ($env:USERPROFILE + '/GoogleDrive').Replace('\', '/'),
        'MOSY_CLOUD_DIR=' + ($env:USERPROFILE + '/GoogleDrive/mosy_vault').Replace('\', '/')
    )
    $cfgLines | Set-Content -Path $configFile -Encoding UTF8
}

Write-Host "============================================================" -ForegroundColor Green
Write-Host "MountSync installed successfully on Windows!" -ForegroundColor Green
Write-Host "Open a new CMD or PowerShell window and run: mosy" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
