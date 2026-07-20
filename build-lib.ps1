#Requires -Version 7.0

<#
.SYNOPSIS
    Build-time helper functions for build.ps1, factored out so they can be unit
    tested headlessly (see tests/build.Tests.ps1) without running a full publish.

    This file is dot-sourced by build.ps1 at build time only. It is NOT embedded
    in the EXE and never runs inside the shipping app.
#>

# Returns the both-or-neither gate validation result.
#   $null            -> gate config is consistent (both supplied, or neither)
#   @{Have;Need}     -> exactly one supplied; .Have is the param given, .Need the missing one
#
# NOTE: the runtime guard in SP-MembershipManager.ps1 (~line 1967) enforces the
# same both-or-neither rule independently. Keep the two in sync if the rule changes.
function Test-GateConfigComplete {
    param(
        [string]$GateClientId = '',
        [string]$GateGroupId  = ''
    )
    if ([bool]$GateClientId -eq [bool]$GateGroupId) { return $null }
    if ($GateClientId) { return @{ Have = 'GateClientId'; Need = 'GateGroupId' } }
    return @{ Have = 'GateGroupId'; Need = 'GateClientId' }
}

# Validates the all-or-nothing / both-or-neither build parameter rules.
# Throws with the same messages build.ps1 historically used, so existing
# acceptance-test expectations (AT-9) and callers are unchanged.
function Assert-BuildParams {
    param(
        [string]$CertPath     = '',
        [string]$CertPassword = '',
        [string]$Tenant       = '',
        [string]$AppClientId  = '',
        [string]$GateClientId = '',
        [string]$GateGroupId  = ''
    )

    # Cert params: all-or-nothing. A self-contained EXE has no app-config.json,
    # so AppClientId must be baked in alongside the cert password and tenant.
    if ($CertPath -and (-not $CertPassword -or -not $Tenant -or -not $AppClientId)) {
        throw '-CertPath requires -CertPassword, -Tenant, and -AppClientId to be specified.'
    }
    if ($CertPath -and -not (Test-Path $CertPath)) {
        throw "Certificate file not found: $CertPath"
    }

    # Gate params: both-or-neither. A half-configured gate bakes a broken EXE
    # that fails at startup, so reject it at build time instead.
    $gate = Test-GateConfigComplete -GateClientId $GateClientId -GateGroupId $GateGroupId
    if ($gate) {
        throw "-$($gate.Have) was supplied without -$($gate.Need). The sign-in gate requires both (or neither)."
    }
}

# True when any per-client parameter warrants generating a client-config.json.
function Test-HasClientConfig {
    param(
        [string]$LockedAdminUrl      = '',
        [string[]]$CriticalSiteUrls  = @(),
        [string]$CriticalSiteGroupId = '',
        [string]$GateClientId        = '',
        [string]$GateGroupId         = '',
        [string]$GateRequestContact  = '',
        [string]$CertPath            = ''
    )
    return [bool]($LockedAdminUrl -or $CriticalSiteUrls.Count -gt 0 -or
                  $CriticalSiteGroupId -or $GateClientId -or $GateGroupId -or
                  $GateRequestContact -or $CertPath)
}

# Builds the ordered client-config hashtable that build.ps1 serializes and embeds.
# Returns $null when no per-client config is needed (a plain, gate-less build).
# Cert fields (plaintext password + tenant) are included only when -CertPath is set,
# matching the embed contract in SP-MembershipManager.ps1's Load-ClientConfig.
function New-ClientConfig {
    param(
        [string]$LockedAdminUrl      = '',
        [string[]]$CriticalSiteUrls  = @(),
        [string]$CriticalSiteGroupId = '',
        [string]$GateClientId        = '',
        [string]$GateGroupId         = '',
        [string]$GateRequestContact  = '',
        [string]$CertPath            = '',
        [string]$CertPassword        = '',
        [string]$Tenant              = '',
        [string]$AppClientId         = ''
    )

    $hasConfig = Test-HasClientConfig `
        -LockedAdminUrl $LockedAdminUrl -CriticalSiteUrls $CriticalSiteUrls `
        -CriticalSiteGroupId $CriticalSiteGroupId -GateClientId $GateClientId `
        -GateGroupId $GateGroupId -GateRequestContact $GateRequestContact -CertPath $CertPath
    if (-not $hasConfig) { return $null }

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
        $cfg['AppClientId']  = $AppClientId
    }
    return $cfg
}
