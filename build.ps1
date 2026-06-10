#Requires -Version 5.1

<#
.SYNOPSIS
    Packages SP-MembershipManager.ps1 into a standalone Windows executable.

.DESCRIPTION
    Uses ps2exe to compile SP-MembershipManager.ps1 into a .exe that runs
    without requiring PowerShell to be explicitly invoked. PnP.PowerShell still
    needs to be installed on the end-user machine.

.NOTES
    Run this script once from your dev machine to produce a distributable build.
    Requires ps2exe: Install-Module -Name ps2exe -Scope CurrentUser
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root    = $PSScriptRoot
$src     = Join-Path $root 'SP-MembershipManager.ps1'
$outDir  = Join-Path $root 'build\output'
$outExe  = Join-Path $outDir 'SP-MembershipManager.exe'
$iconFile = Join-Path $root 'assets\icon.ico'

# Prefer PS12EXE (PS7-capable fork) over ps2exe
if (Get-Module -ListAvailable -Name PS12EXE) {
    Import-Module PS12EXE
} elseif (Get-Module -ListAvailable -Name ps2exe) {
    Import-Module ps2exe
} else {
    Write-Host "Installing PS12EXE..." -ForegroundColor Yellow
    Install-Module -Name PS12EXE -Scope CurrentUser -Force
    Import-Module PS12EXE
}

# Create output directory
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

Write-Host "Building $outExe..." -ForegroundColor Cyan

$params = @{
    inputFile  = $src
    outputFile = $outExe
    noConsole  = $true
    x64        = $true
    verbose    = $true
}

# Include icon if it exists
if (Test-Path $iconFile) {
    $params['iconFile'] = $iconFile
}

if (Get-Module PS12EXE) {
    # -pwsh targets the PS7 runtime instead of Windows PowerShell 5.1
    $params['pwsh'] = $true
    ps12exe @params
} else {
    Invoke-ps2exe @params
}

if (Test-Path $outExe) {
    $size = [math]::Round((Get-Item $outExe).Length / 1KB, 1)
    Write-Host "Build complete: $outExe ($size KB)" -ForegroundColor Green
} else {
    Write-Error "Build failed - output file not found."
}
