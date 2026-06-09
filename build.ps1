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

# Ensure ps2exe is available
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Installing ps2exe..." -ForegroundColor Yellow
    Install-Module -Name ps2exe -Scope CurrentUser -Force
}
Import-Module ps2exe

# Create output directory
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

Write-Host "Building $outExe..." -ForegroundColor Cyan

$params = @{
    inputFile   = $src
    outputFile  = $outExe
    title       = 'SP Membership Manager'
    product     = 'SP-MembershipManager'
    description = 'Manage SharePoint Online site membership'
    copyright   = 'Copyright (c) 2026 Cory Francis - MIT License'
    version     = '1.0.0'
    requireAdmin = $false
    noConsole   = $true      # WinForms app - suppress console window
    x64         = $true
}

# Include icon if it exists
if (Test-Path $iconFile) {
    $params['iconFile'] = $iconFile
}

Invoke-ps2exe @params

if (Test-Path $outExe) {
    $size = [math]::Round((Get-Item $outExe).Length / 1KB, 1)
    Write-Host "Build complete: $outExe ($size KB)" -ForegroundColor Green
} else {
    Write-Error "Build failed - output file not found."
}
