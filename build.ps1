#Requires -Version 7.0

<#
.SYNOPSIS
    Packages SP-MembershipManager into a standalone Windows executable.

.DESCRIPTION
    Uses dotnet publish to compile the C# launcher (which embeds SP-MembershipManager.ps1)
    into a self-contained single-file exe. Requires the .NET 8 SDK.

.NOTES
    Install the .NET 8 SDK from https://dotnet.microsoft.com/download
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root   = $PSScriptRoot
$outDir = Join-Path $root 'build\output'
$outExe = Join-Path $outDir 'SP-MembershipManager.exe'
$proj   = Join-Path $root 'launcher\Launcher.csproj'

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw 'dotnet not found. Install the .NET 8 SDK from https://dotnet.microsoft.com/download'
}

Write-Host "Building $outExe..." -ForegroundColor Cyan

dotnet publish $proj `
    -c Release `
    -r win-x64 `
    --self-contained true `
    -o $outDir

if (Test-Path $outExe) {
    $size = [math]::Round((Get-Item $outExe).Length / 1MB, 1)
    Write-Host "Build complete: $outExe ($size MB)" -ForegroundColor Green
} else {
    throw 'Build failed - output file not found.'
}
