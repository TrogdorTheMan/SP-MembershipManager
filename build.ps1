#Requires -Version 7.0

<#
.SYNOPSIS
    Packages SP-MembershipManager into a standalone Windows executable.

.DESCRIPTION
    Uses dotnet publish to compile the C# launcher (which embeds SP-MembershipManager.ps1)
    into a self-contained single-file exe. Requires the .NET 8 SDK.

    Per-client parameters (all optional) bake tenant-specific configuration into the EXE
    so it can only connect to the intended tenant. When -CertPath is supplied the PFX is
    also embedded and no app-config.json is needed at runtime.

.PARAMETER LockedAdminUrl
    SharePoint admin URL to pre-fill and lock (e.g. https://contoso-admin.sharepoint.com).
    When set, the admin URL dialog shows the value read-only and cannot be changed.

.PARAMETER CriticalSiteUrls
    Array of SharePoint site URLs that should be flagged as sensitive (red row highlight).
    Users not in CriticalSiteGroupId will have Add/Remove disabled on these sites.

.PARAMETER CriticalSiteGroupId
    Entra security group object ID whose members may manage critical sites.
    Must also be assigned to the gate application in Azure so it appears in the id_token.

.PARAMETER GateClientId
    Application (client) ID of the public-client Entra app used for the sign-in gate.
    Overrides the value in app-config.json at runtime.

.PARAMETER GateGroupId
    Object ID of the Entra security group that may use the app (sign-in gate).
    Overrides the value in app-config.json at runtime.

.PARAMETER GateRequestContact
    Email or URL shown on the Access Denied dialog. Overrides app-config.json.

.PARAMETER CertPath
    Path to the .pfx certificate file to embed in the EXE. When set, CertPassword and
    Tenant are also required. The resulting EXE needs no external files to run.
    SECURITY: the private key and password are stored in the EXE binary — treat the EXE
    with the same access controls as the PFX itself.

.PARAMETER CertPassword
    Plaintext password for the certificate. Required when CertPath is set.

.PARAMETER Tenant
    Tenant name (e.g. contoso.onmicrosoft.com). Required when CertPath is set.

.NOTES
    Install the .NET 8 SDK from https://dotnet.microsoft.com/download
    For a guided UI, run build-wizard.ps1 instead.
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingPlainTextForPassword', 'CertPassword',
    Justification = 'The cert password is written verbatim into the embedded client-config.json so the EXE is self-contained; it must be plaintext at build time. A SecureString would be converted straight back to plaintext at the embed step, adding no protection.')]
param(
    [string]$LockedAdminUrl      = '',
    [string[]]$CriticalSiteUrls  = @(),
    [string]$CriticalSiteGroupId = '',
    [string]$GateClientId        = '',
    [string]$GateGroupId         = '',
    [string]$GateRequestContact  = '',
    [string]$CertPath            = '',
    [string]$CertPassword        = '',
    [string]$Tenant              = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root   = $PSScriptRoot
$outDir = Join-Path $root 'build\output'
$outExe = Join-Path $outDir 'SP-MembershipManager.exe'
$proj   = Join-Path $root 'launcher\Launcher.csproj'

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw 'dotnet not found. Install the .NET 8 SDK from https://dotnet.microsoft.com/download'
}

# Validate cert params: all-or-nothing
if ($CertPath -and (-not $CertPassword -or -not $Tenant)) {
    throw '-CertPath requires both -CertPassword and -Tenant to be specified.'
}
if ($CertPath -and -not (Test-Path $CertPath)) {
    throw "Certificate file not found: $CertPath"
}

# Validate gate params: both-or-neither. A half-configured gate bakes a broken
# EXE that fails at startup, so reject it at build time instead.
if ([bool]$GateClientId -ne [bool]$GateGroupId) {
    $have = if ($GateClientId) { '-GateClientId' } else { '-GateGroupId' }
    $need = if ($GateClientId) { '-GateGroupId' } else { '-GateClientId' }
    throw "$have was supplied without $need. The sign-in gate requires both (or neither)."
}

# Determine whether to generate embedded resources
$clientConfigDest = Join-Path $root 'launcher\client-config.json'
$embeddedCertDest = Join-Path $root 'launcher\embedded-cert.pfx'
$wroteClientConfig = $false
$wroteEmbeddedCert = $false

$hasClientConfig = $LockedAdminUrl -or $CriticalSiteUrls.Count -gt 0 -or
                   $CriticalSiteGroupId -or $GateClientId -or $GateGroupId -or
                   $GateRequestContact -or $CertPath

if ($hasClientConfig) {
    $cfg = [ordered]@{
        LockedAdminUrl      = $LockedAdminUrl
        CriticalSiteUrls    = $CriticalSiteUrls
        CriticalSiteGroupId = $CriticalSiteGroupId
        GateClientId        = $GateClientId
        GateGroupId         = $GateGroupId
        GateRequestContact  = $GateRequestContact
    }
    if ($CertPath) {
        $cfg['CertPassword'] = $CertPassword
        $cfg['Tenant']       = $Tenant
    }
    $cfg | ConvertTo-Json | Set-Content $clientConfigDest -Encoding UTF8
    $wroteClientConfig = $true
}

if ($CertPath) {
    Copy-Item $CertPath $embeddedCertDest -Force
    $wroteEmbeddedCert = $true
}

Write-Host "Building $outExe..." -ForegroundColor Cyan

try {
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
} finally {
    if ($wroteClientConfig -and (Test-Path $clientConfigDest)) { Remove-Item $clientConfigDest -Force }
    if ($wroteEmbeddedCert -and (Test-Path $embeddedCertDest)) { Remove-Item $embeddedCertDest -Force }
}
