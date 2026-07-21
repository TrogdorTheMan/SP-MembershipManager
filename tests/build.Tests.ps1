#Requires -Version 7.0

<#
    Headless unit tests for build.ps1's validation and config-generation logic.
    These never connect to SharePoint, never authenticate, and never modify any
    tenant or user. They exercise the build-time helpers in build-lib.ps1 only.

    Run:  Invoke-Pester -Path .\tests\build.Tests.ps1
    Requires Pester 5+.

    Coverage maps to docs/ACCEPTANCE-TESTS.md:
      AT-9        -> build-time half-gate rejection
      AT-2/4/8    -> per-client params baked into client-config correctly
      AT-3        -> cert fields embedded only when -CertPath set
      AT-9b       -> the same gate rule the runtime guard enforces
      AT-12       -> source ships no app identity (AppClientId is per-deployer)
      AT-13       -> cert requires -AppClientId (build.ps1 half of the wizard rule)
#>

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    . (Join-Path $script:Root 'build-lib.ps1')
}

Describe 'Test-GateConfigComplete' {
    It 'returns $null when both gate values are present' {
        Test-GateConfigComplete -GateClientId 'cid' -GateGroupId 'gid' | Should -BeNullOrEmpty
    }
    It 'returns $null when neither gate value is present' {
        Test-GateConfigComplete | Should -BeNullOrEmpty
    }
    It 'flags a missing group id when only the client id is given' {
        $r = Test-GateConfigComplete -GateClientId 'cid'
        $r.Have | Should -Be 'GateClientId'
        $r.Need | Should -Be 'GateGroupId'
    }
    It 'flags a missing client id when only the group id is given' {
        $r = Test-GateConfigComplete -GateGroupId 'gid'
        $r.Have | Should -Be 'GateGroupId'
        $r.Need | Should -Be 'GateClientId'
    }
}

Describe 'Assert-BuildParams' {
    Context 'gate rules (AT-9)' {
        It 'throws the exact AT-9 message for -GateClientId without -GateGroupId' {
            { Assert-BuildParams -GateClientId 'cid' } |
                Should -Throw '-GateClientId was supplied without -GateGroupId. The sign-in gate requires both (or neither).'
        }
        It 'throws for -GateGroupId without -GateClientId' {
            { Assert-BuildParams -GateGroupId 'gid' } |
                Should -Throw '-GateGroupId was supplied without -GateClientId. The sign-in gate requires both (or neither).'
        }
        It 'does not throw when both gate values are present' {
            { Assert-BuildParams -GateClientId 'cid' -GateGroupId 'gid' } | Should -Not -Throw
        }
        It 'does not throw when neither gate value is present' {
            { Assert-BuildParams } | Should -Not -Throw
        }
    }

    Context 'cert rules' {
        It 'throws when -CertPath is set without password, tenant, or client id' {
            { Assert-BuildParams -CertPath 'C:\nope.pfx' } |
                Should -Throw '-CertPath requires -CertPassword, -Tenant, and -AppClientId to be specified.'
        }
        It 'throws when -CertPath has password + tenant but no -AppClientId' {
            { Assert-BuildParams -CertPath 'C:\nope.pfx' -CertPassword 'pw' -Tenant 'contoso.onmicrosoft.com' } |
                Should -Throw '-CertPath requires -CertPassword, -Tenant, and -AppClientId to be specified.'
        }
        It 'throws when the cert file does not exist' {
            { Assert-BuildParams -CertPath 'C:\does-not-exist.pfx' -CertPassword 'pw' -Tenant 'contoso.onmicrosoft.com' -AppClientId 'cid' } |
                Should -Throw 'Certificate file not found: C:\does-not-exist.pfx'
        }
        It 'accepts a cert when the file exists and password + tenant + client id are given' {
            $pfx = Join-Path $TestDrive 'cert.pfx'
            Set-Content -Path $pfx -Value 'not-a-real-cert'
            { Assert-BuildParams -CertPath $pfx -CertPassword 'pw' -Tenant 'contoso.onmicrosoft.com' -AppClientId 'cid' } | Should -Not -Throw
        }
    }
}

Describe 'New-ClientConfig' {
    It 'returns $null for a plain build with no per-client params' {
        New-ClientConfig | Should -BeNullOrEmpty
    }

    It 'bakes a locked admin url (AT-2)' {
        $cfg = New-ClientConfig -LockedAdminUrl 'https://contoso-admin.sharepoint.com'
        $cfg.LockedAdminUrl | Should -Be 'https://contoso-admin.sharepoint.com'
    }

    It 'bakes critical site urls as an array (AT-4)' {
        $cfg = New-ClientConfig -CriticalSiteUrls @('https://contoso.sharepoint.com/sites/HR')
        $cfg.CriticalSiteUrls | Should -Be @('https://contoso.sharepoint.com/sites/HR')
    }

    It 'bakes gate config (AT-8)' {
        $cfg = New-ClientConfig -GateClientId 'cid' -GateGroupId 'gid'
        $cfg.GateClientId | Should -Be 'cid'
        $cfg.GateGroupId  | Should -Be 'gid'
    }

    It 'includes cert password, tenant, and client id only when -CertPath is set (AT-3)' {
        $cfg = New-ClientConfig -CertPath 'C:\sp-mm.pfx' -CertPassword 'pw' -Tenant 'contoso.onmicrosoft.com' -AppClientId 'cid'
        $cfg.Contains('CertPassword') | Should -BeTrue
        $cfg.CertPassword | Should -Be 'pw'
        $cfg.Tenant       | Should -Be 'contoso.onmicrosoft.com'
        $cfg.AppClientId  | Should -Be 'cid'
    }

    It 'omits cert fields when no cert is supplied' {
        $cfg = New-ClientConfig -LockedAdminUrl 'https://contoso-admin.sharepoint.com'
        $cfg.Contains('CertPassword') | Should -BeFalse
        $cfg.Contains('Tenant')       | Should -BeFalse
        $cfg.Contains('AppClientId')  | Should -BeFalse
    }
}

Describe 'build.ps1 -ConfigOnly (dry run)' {
    BeforeAll {
        $script:BuildScript = Join-Path $script:Root 'build.ps1'
        $script:PreviewPath = Join-Path $script:Root 'build\output\client-config.preview.json'
    }

    It 'writes a preview config without compiling and never touches launcher\client-config.json' {
        & $script:BuildScript -GateClientId 'cid' -GateGroupId 'gid' -ConfigOnly
        Test-Path $script:PreviewPath | Should -BeTrue
        $written = Get-Content $script:PreviewPath -Raw | ConvertFrom-Json
        $written.GateClientId | Should -Be 'cid'
        $written.GateGroupId  | Should -Be 'gid'

        # The real embed source must not be created by a dry run.
        Test-Path (Join-Path $script:Root 'launcher\client-config.json') | Should -BeFalse
    }

    It 'still enforces validation in dry-run mode (AT-9)' {
        { & $script:BuildScript -GateClientId 'cid' -ConfigOnly } |
            Should -Throw '*The sign-in gate requires both (or neither).*'
    }

    It 'bakes AppClientId into the preview config for an embedded-cert build (AT-3)' {
        $pfx = Join-Path $TestDrive 'cert.pfx'
        Set-Content -Path $pfx -Value 'not-a-real-cert'
        & $script:BuildScript -CertPath $pfx -CertPassword 'pw' -Tenant 'contoso.onmicrosoft.com' -AppClientId 'cid' -ConfigOnly
        $written = Get-Content $script:PreviewPath -Raw | ConvertFrom-Json
        $written.AppClientId | Should -Be 'cid'
        $written.Tenant      | Should -Be 'contoso.onmicrosoft.com'
    }
}

Describe 'Source hygiene: no baked-in app identity (AT-12)' {
    It 'ships an empty $script:AppClientId in SP-MembershipManager.ps1' {
        $src = Get-Content (Join-Path $script:Root 'SP-MembershipManager.ps1') -Raw
        $src | Should -Match '\$script:AppClientId\s*=\s*""'
        $src | Should -Not -Match '\$script:AppClientId\s*=\s*["''][0-9a-fA-F][0-9a-fA-F-]+["'']'
    }
    It 'app-config.example.json carries a placeholder, not a real client id' {
        $cfg = Get-Content (Join-Path $script:Root 'app-config.example.json') -Raw | ConvertFrom-Json
        $cfg.AppClientId | Should -Not -Match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    }
}
