#Requires -Version 5.1

<#
.SYNOPSIS
    SP-MembershipManager - Manage SharePoint Online site membership via a simple GUI.

.DESCRIPTION
    Lets authorized users search for employees and manage their SharePoint site
    access without needing training on the SharePoint admin UI.
    Uses PnP.PowerShell for SharePoint operations and WinForms for the UI.

.NOTES
    License: MIT
    Repository: https://github.com/TrogdorTheMan/SP-MembershipManager
#>

param(
    # Passed by the C# launcher so the script can locate app-config.json
    # next to the exe rather than in the temp folder it was extracted to.
    [string]$LauncherDir = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

function Ensure-PnPModule {
    if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
        Write-Host "PnP.PowerShell module not found. Installing..." -ForegroundColor Yellow
        Install-Module -Name PnP.PowerShell -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module PnP.PowerShell -ErrorAction Stop
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

$script:LogDir  = "C:\temp\SP-MembershipManager\Logs"
$script:LogFile = Join-Path $script:LogDir "log_$(Get-Date -Format 'yyyy-MM-dd').txt"

function Write-Log {
    param([string]$Message)
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $Message"
    try {
        if (-not (Test-Path $script:LogDir)) { New-Item -ItemType Directory -Path $script:LogDir | Out-Null }
        Add-Content -Path $script:LogFile -Value $line
    } catch { }
    return $line
}

# ---------------------------------------------------------------------------
# DPAPI helpers
# ---------------------------------------------------------------------------

function Protect-String {
    param([string]$Plaintext)
    Add-Type -AssemblyName System.Security
    $bytes     = [System.Text.Encoding]::UTF8.GetBytes($Plaintext)
    $protected = [System.Security.Cryptography.ProtectedData]::Protect(
                     $bytes, $null,
                     [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    return [Convert]::ToBase64String($protected)
}

function Unprotect-String {
    param([string]$Base64)
    Add-Type -AssemblyName System.Security
    $bytes      = [Convert]::FromBase64String($Base64)
    $plainBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
                      $bytes, $null,
                      [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    return [System.Text.Encoding]::UTF8.GetString($plainBytes)
}

# ---------------------------------------------------------------------------
# App registration
#
# Client ID is public and safe to commit. The client secret is loaded from a
# local config file (app-config.json) that is gitignored and must be created
# before running. See README for setup instructions.
#
# If you fork this repo, replace AppClientId with your own app registration
# and create your own app-config.json with your secret.
# ---------------------------------------------------------------------------

$script:AppClientId       = "630f7dac-df2b-4586-a6b4-e83acbf4e91e"
$script:TenantName        = ""
$script:CertPath          = ""
$script:CertPassword      = $null
$script:CertPasswordPlain = ""

# When running via the C# launcher, $LauncherDir is the exe's directory.
# When running directly as a .ps1, use $PSScriptRoot.
$script:ScriptRoot = if ($LauncherDir) {
    $LauncherDir
} elseif ($PSScriptRoot) {
    $PSScriptRoot
} else {
    [System.AppDomain]::CurrentDomain.BaseDirectory.TrimEnd('\')
}

$script:ConfigFile  = Join-Path $script:ScriptRoot "app-config.json"
$script:LastUrlFile = Join-Path $script:ScriptRoot "last-url.txt"

function Load-AppConfig {
    if (-not (Test-Path $script:ConfigFile)) {
        [System.Windows.Forms.MessageBox]::Show(
            "app-config.json not found next to the script.`n`nSee app-config.example.json for the required format.",
            "Configuration Missing", 'OK', 'Error') | Out-Null
        exit
    }
    $cfg = Get-Content $script:ConfigFile -Raw | ConvertFrom-Json
    if (-not $cfg.CertificatePath -or -not $cfg.CertificatePassword) {
        [System.Windows.Forms.MessageBox]::Show(
            "app-config.json is missing CertificatePath or CertificatePassword.",
            "Configuration Error", 'OK', 'Error') | Out-Null
        exit
    }
    if (-not $cfg.Tenant) {
        [System.Windows.Forms.MessageBox]::Show(
            "app-config.json is missing Tenant (e.g. `"contoso.onmicrosoft.com`").",
            "Configuration Error", 'OK', 'Error') | Out-Null
        exit
    }
    $certPath = $cfg.CertificatePath
    if (-not [System.IO.Path]::IsPathRooted($certPath)) {
        $certPath = Join-Path $script:ScriptRoot $certPath
    }
    if (-not (Test-Path $certPath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Certificate file not found: $certPath",
            "Configuration Error", 'OK', 'Error') | Out-Null
        exit
    }
    $script:CertPath = $certPath

    # DPAPI: if password is plaintext, encrypt it in place and save back to disk.
    # On subsequent runs the encrypted blob is decrypted transparently.
    # Encryption is CurrentUser-scoped -- tied to the Windows account that first ran the tool.
    $isEncrypted = $cfg.PSObject.Properties.Item('CertificatePasswordEncrypted') -and
                   $cfg.CertificatePasswordEncrypted -eq $true
    if ($isEncrypted) {
        try {
            $plainPassword = Unprotect-String -Base64 $cfg.CertificatePassword
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Could not decrypt the certificate password in app-config.json.`n`n" +
                "This usually means the config was created on a different machine or user account.`n`n" +
                "Set CertificatePasswordEncrypted to false and restore the plaintext password, then re-run to re-encrypt for this account.",
                "Decryption Failed", 'OK', 'Error') | Out-Null
            exit
        }
    } else {
        $plainPassword = $cfg.CertificatePassword
        $encrypted     = Protect-String -Plaintext $plainPassword
        $cfg.CertificatePassword = $encrypted
        if ($cfg.PSObject.Properties.Item('CertificatePasswordEncrypted')) {
            $cfg.CertificatePasswordEncrypted = $true
        } else {
            $cfg | Add-Member -MemberType NoteProperty -Name 'CertificatePasswordEncrypted' -Value $true
        }
        $cfg | ConvertTo-Json | Set-Content $script:ConfigFile -Encoding UTF8
        Write-Log "Certificate password encrypted with DPAPI and saved to app-config.json."
    }

    $script:CertPasswordPlain = $plainPassword
    $script:CertPassword      = ConvertTo-SecureString $plainPassword -AsPlainText -Force
    $script:TenantName        = $cfg.Tenant
}

function Get-LastUrl {
    if (Test-Path $script:LastUrlFile) {
        return (Get-Content $script:LastUrlFile -Raw).Trim()
    }
    return ""
}

function Save-LastUrl {
    param([string]$Url)
    try { Set-Content $script:LastUrlFile $Url } catch { }
}

# ---------------------------------------------------------------------------
# SharePoint operations
# ---------------------------------------------------------------------------

function Connect-Site {
    param([string]$Url)
    Connect-PnPOnline -Url $Url `
        -ClientId $script:AppClientId `
        -CertificatePath $script:CertPath `
        -CertificatePassword $script:CertPassword `
        -Tenant $script:TenantName `
        -WarningAction SilentlyContinue
}

function Connect-Tenant {
    param([string]$AdminUrl)
    Connect-Site -Url $AdminUrl
}

function Get-AllSites {
    $sites = [System.Collections.Generic.List[PSCustomObject]]::new()
    $url = "sites?`$select=displayName,webUrl&`$top=200"
    do {
        $response = Invoke-PnPGraphMethod -Url $url -Method Get
        foreach ($s in $response.value) {
            # Skip OneDrive personal sites and root tenant site
            if ($s.webUrl -notlike "*/personal/*" -and $s.webUrl -match "/sites/") {
                $sites.Add([PSCustomObject]@{
                    Title = $s.displayName
                    Url   = $s.webUrl
                })
            }
        }
        $nextLink = $response.PSObject.Properties.Item('@odata.nextLink')
        $url = if ($nextLink) { $nextLink.Value } else { $null }
    } while ($url)
    return $sites
}

function Search-Users {
    param([string]$Query)
    # If query looks like an email address use $filter on mail/UPN (no special headers needed).
    # Otherwise use $search on displayName with ConsistencyLevel: eventual, with an email-prefix
    # fallback so that "timm" also finds "timm@domain.com" when display name search returns nothing.
    if ($Query -match '@') {
        # Use the local part (before @) for a flexible prefix match on mail/UPN.
        # This way "tim@" finds "timm@domain.com", "timothy@domain.com", etc.
        $localPart = $Query.Split('@')[0]
        $encoded = [Uri]::EscapeDataString($localPart)
        $url = "users?`$filter=startswith(mail,'$encoded') or startswith(userPrincipalName,'$encoded')&`$select=displayName,mail,userPrincipalName&`$top=20"
        $response = Invoke-PnPGraphMethod -Url $url -Method Get
        $users = @(foreach ($u in $response.value) {
            [PSCustomObject]@{
                DisplayName = $u.displayName
                Email       = if ($u.mail) { $u.mail } else { $u.userPrincipalName }
                Account     = $u.userPrincipalName
            }
        })
    } else {
        # Display name search (handles "Tim Miller", "Tina", etc.)
        $url = "users?`$search=`"displayName:$Query`"&`$select=displayName,mail,userPrincipalName&`$top=20&`$count=true"
        $response = Invoke-PnPGraphMethod -Url $url -Method Get -AdditionalHeaders @{ "ConsistencyLevel" = "eventual" }
        $users = @(foreach ($u in $response.value) {
            [PSCustomObject]@{
                DisplayName = $u.displayName
                Email       = if ($u.mail) { $u.mail } else { $u.userPrincipalName }
                Account     = $u.userPrincipalName
            }
        })
        # Fallback: if display name found nothing, try the query as an email prefix.
        # This catches cases like "timm" matching "timm@miller-nicholson.com".
        if ($users.Count -eq 0) {
            $encoded = [Uri]::EscapeDataString($Query)
            $url2 = "users?`$filter=startswith(mail,'$encoded') or startswith(userPrincipalName,'$encoded')&`$select=displayName,mail,userPrincipalName&`$top=20"
            $response2 = Invoke-PnPGraphMethod -Url $url2 -Method Get
            $users = @(foreach ($u in $response2.value) {
                [PSCustomObject]@{
                    DisplayName = $u.displayName
                    Email       = if ($u.mail) { $u.mail } else { $u.userPrincipalName }
                    Account     = $u.userPrincipalName
                }
            })
        }
    }
    return $users | Where-Object { $_.Email }
}

function Get-UserSiteMemberships {
    param(
        [string]$UserEmail,
        [array]$AllSites,
        [System.Windows.Forms.RichTextBox]$LogBox
    )

    $line = Write-Log "Checking $($AllSites.Count) sites in parallel (up to 8 at once)..."
    if ($LogBox) {
        $LogBox.Invoke([Action]{ $LogBox.AppendText("$line`n"); $LogBox.ScrollToCaret() })
    }

    $scriptBlock = {
        param($SiteTitle, $SiteUrl, $UserEmail, $ClientId, $CertPath, $CertPasswordPlain, $Tenant)
        try {
            Import-Module PnP.PowerShell -ErrorAction Stop -WarningAction SilentlyContinue
            $secPass = ConvertTo-SecureString $CertPasswordPlain -AsPlainText -Force
            Connect-PnPOnline -Url $SiteUrl `
                -ClientId $ClientId `
                -CertificatePath $CertPath `
                -CertificatePassword $secPass `
                -Tenant $Tenant `
                -WarningAction SilentlyContinue `
                -ErrorAction Stop

            $groups = Get-PnPGroup
            foreach ($group in $groups) {
                $role = $null
                if ($group.Title -like '* Owners')        { $role = 'Owner'   }
                elseif ($group.Title -like '* Members')   { $role = 'Member'  }
                elseif ($group.Title -like '* Visitors')  { $role = 'Visitor' }
                if (-not $role) { continue }

                $members = Get-PnPGroupMember -Group $group
                if ($members | Where-Object { $_.Email -eq $UserEmail }) {
                    return [PSCustomObject]@{
                        SiteName = $SiteTitle
                        SiteUrl  = $SiteUrl
                        Role     = $role
                    }
                }
            }
        } catch { }
        return $null
    }

    $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, 8)
    $pool.Open()

    $jobs = foreach ($site in $AllSites) {
        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.RunspacePool = $pool
        [void]$ps.AddScript($scriptBlock)
        [void]$ps.AddArgument($site.Title)
        [void]$ps.AddArgument($site.Url)
        [void]$ps.AddArgument($UserEmail)
        [void]$ps.AddArgument($script:AppClientId)
        [void]$ps.AddArgument($script:CertPath)
        [void]$ps.AddArgument($script:CertPasswordPlain)
        [void]$ps.AddArgument($script:TenantName)
        [PSCustomObject]@{ PS = $ps; Handle = $ps.BeginInvoke() }
    }

    $memberships = [System.Collections.Generic.List[PSCustomObject]]::new()
    $pending = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($job in $jobs) { $pending.Add($job) }

    while ($pending.Count -gt 0) {
        $completed = @($pending | Where-Object { $_.Handle.IsCompleted })
        foreach ($job in $completed) {
            try {
                $result = $job.PS.EndInvoke($job.Handle)
                foreach ($r in $result) {
                    if ($r) { $memberships.Add($r) }
                }
            } catch {
                Write-Log "Warning: runspace error - $_" | Out-Null
            } finally {
                $job.PS.Dispose()
            }
            [void]$pending.Remove($job)
        }
        if ($pending.Count -gt 0) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 100
        }
    }

    $pool.Close()
    $pool.Dispose()

    return $memberships
}

function Add-UserToSite {
    param([string]$SiteUrl, [string]$UserEmail, [string]$Role)
    Connect-Site -Url $SiteUrl
    $groups = Get-PnPGroup
    $group  = $groups | Where-Object { $_.Title -like "* $Role`s" -or $_.Title -like "* ${Role}s" } | Select-Object -First 1
    if (-not $group) { throw "Could not find $Role group for site." }
    # Use claims identity format to ensure the user is resolved correctly
    # even if they haven't previously visited the site
    Add-PnPGroupMember -Group $group -LoginName "i:0#.f|membership|$UserEmail"
}

function Remove-UserFromSite {
    param([string]$SiteUrl, [string]$UserEmail, [string]$Role)
    Connect-Site -Url $SiteUrl
    $groups = Get-PnPGroup
    $group  = $groups | Where-Object { $_.Title -like "* $Role`s" -or $_.Title -like "* ${Role}s" } | Select-Object -First 1
    if (-not $group) { throw "Could not find $Role group for site." }
    Remove-PnPGroupMember -Group $group -LoginName "i:0#.f|membership|$UserEmail"
}

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

function Show-CountdownDialog {
    param(
        [string]$Message,
        [string]$Title   = 'Success',
        [int]$Seconds    = 5
    )

    $dlg                  = New-Object System.Windows.Forms.Form
    $dlg.Text             = $Title
    $dlg.Size             = New-Object System.Drawing.Size(400, 165)
    $dlg.StartPosition    = 'CenterScreen'
    $dlg.FormBorderStyle  = 'FixedDialog'
    $dlg.MaximizeBox      = $false
    $dlg.MinimizeBox      = $false
    # Use Tag to store remaining seconds — avoids closure scoping issues
    $dlg.Tag              = $Seconds

    $ico              = New-Object System.Windows.Forms.PictureBox
    $ico.Image        = [System.Drawing.SystemIcons]::Information.ToBitmap()
    $ico.Size         = New-Object System.Drawing.Size(32, 32)
    $ico.Location     = New-Object System.Drawing.Point(16, 20)
    $ico.SizeMode     = 'AutoSize'

    $lbl              = New-Object System.Windows.Forms.Label
    $lbl.Text         = $Message
    $lbl.Location     = New-Object System.Drawing.Point(58, 16)
    $lbl.Size         = New-Object System.Drawing.Size(320, 60)
    $lbl.AutoSize     = $false

    $btn              = New-Object System.Windows.Forms.Button
    $btn.Text         = "OK ($Seconds)"
    $btn.Size         = New-Object System.Drawing.Size(110, 28)
    $btn.Location     = New-Object System.Drawing.Point(270, 95)
    $btn.Enabled      = $false
    $btn.Add_Click({ $dlg.Close() })

    $timer            = New-Object System.Windows.Forms.Timer
    $timer.Interval   = 1000
    $timer.Add_Tick({
        $rem = [int]$dlg.Tag - 1
        $dlg.Tag = $rem
        if ($rem -le 0) {
            $timer.Stop()
            $btn.Text    = 'OK'
            $btn.Enabled = $true
        } else {
            $btn.Text = "OK ($rem)"
        }
    })

    $dlg.Controls.AddRange(@($ico, $lbl, $btn))
    $dlg.Add_Shown({ $timer.Start() })
    $dlg.ShowDialog() | Out-Null
    $timer.Stop()
    $timer.Dispose()
    $dlg.Dispose()
}

function Show-AboutDialog {
    param([System.Windows.Forms.Form]$Owner = $null)

    $about = New-Object System.Windows.Forms.Form
    $about.Text            = "About SP Membership Manager"
    $about.Size            = New-Object System.Drawing.Size(480, 220)
    $about.FormBorderStyle = 'FixedDialog'
    $about.StartPosition   = if ($Owner) { 'CenterParent' } else { 'CenterScreen' }
    $about.MaximizeBox     = $false
    $about.MinimizeBox     = $false

    $lblName = New-Object System.Windows.Forms.Label
    $lblName.Text      = "SP Membership Manager"
    $lblName.Font      = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $lblName.Location  = New-Object System.Drawing.Point(20, 20)
    $lblName.AutoSize  = $true

    $lblAuthor = New-Object System.Windows.Forms.Label
    $lblAuthor.Text     = "Cory `"TrogdorTheMan`" Francis"
    $lblAuthor.Location = New-Object System.Drawing.Point(20, 52)
    $lblAuthor.AutoSize = $true

    $lblYear = New-Object System.Windows.Forms.Label
    $lblYear.Text      = "$(Get-Date -Format 'yyyy')  |  MIT License"
    $lblYear.Location  = New-Object System.Drawing.Point(20, 74)
    $lblYear.AutoSize  = $true
    $lblYear.ForeColor = [System.Drawing.Color]::DimGray

    $lnkRepo = New-Object System.Windows.Forms.LinkLabel
    $lnkRepo.Text     = "https://github.com/TrogdorTheMan/SP-MembershipManager"
    $lnkRepo.Location = New-Object System.Drawing.Point(20, 104)
    $lnkRepo.AutoSize = $true
    $lnkRepo.Add_LinkClicked({ Start-Process $lnkRepo.Text })

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text         = "Close"
    $btnClose.Location     = New-Object System.Drawing.Point(375, 148)
    $btnClose.Size         = New-Object System.Drawing.Size(75, 28)
    $btnClose.DialogResult = 'OK'

    $about.AcceptButton = $btnClose
    $about.Controls.AddRange(@($lblName, $lblAuthor, $lblYear, $lnkRepo, $btnClose))
    if ($Owner) { [void]$about.ShowDialog($Owner) } else { [void]$about.ShowDialog() }
}

function Show-LoadingForm {
    param([string]$AdminUrl)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $loading = New-Object System.Windows.Forms.Form
    $loading.Text            = "SP Membership Manager"
    $loading.Size            = New-Object System.Drawing.Size(320, 118)
    $loading.FormBorderStyle = 'FixedDialog'
    $loading.StartPosition   = 'CenterScreen'
    $loading.MaximizeBox     = $false
    $loading.MinimizeBox     = $false
    $loading.ControlBox      = $false

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text     = "SP Membership Manager"
    $lblTitle.Font     = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $lblTitle.Location = New-Object System.Drawing.Point(20, 20)
    $lblTitle.AutoSize = $true

    $lblSpinner = New-Object System.Windows.Forms.Label
    $lblSpinner.Text      = "|"
    $lblSpinner.Location  = New-Object System.Drawing.Point(20, 56)
    $lblSpinner.Size      = New-Object System.Drawing.Size(18, 20)
    $lblSpinner.Font      = New-Object System.Drawing.Font('Courier New', 10)
    $lblSpinner.ForeColor = [System.Drawing.Color]::DimGray

    $lblStatus = New-Object System.Windows.Forms.Label
    $lblStatus.Text      = "Please wait..."
    $lblStatus.Location  = New-Object System.Drawing.Point(42, 56)
    $lblStatus.Size      = New-Object System.Drawing.Size(248, 20)
    $lblStatus.ForeColor = [System.Drawing.Color]::DimGray

    $loading.Controls.AddRange(@($lblTitle, $lblSpinner, $lblStatus))
    $loading.Show()
    [System.Windows.Forms.Application]::DoEvents()

    # Run the slow Connect + GetAllSites work in a background runspace so the
    # spinner can animate on the main thread via DoEvents polling.
    $syncHash = [System.Collections.Hashtable]::Synchronized(@{
        Sites = $null
        Error = $null
    })

    $bgScript = {
        param($AdminUrl, $ClientId, $CertPath, $CertPasswordPlain, $TenantName, $SyncHash)
        try {
            Import-Module PnP.PowerShell -ErrorAction Stop -WarningAction SilentlyContinue
            $secPass = ConvertTo-SecureString $CertPasswordPlain -AsPlainText -Force
            Connect-PnPOnline -Url $AdminUrl `
                -ClientId $ClientId `
                -CertificatePath $CertPath `
                -CertificatePassword $secPass `
                -Tenant $TenantName `
                -WarningAction SilentlyContinue `
                -ErrorAction Stop
            $sites = [System.Collections.Generic.List[PSCustomObject]]::new()
            $url = "sites?`$select=displayName,webUrl&`$top=200"
            do {
                $response = Invoke-PnPGraphMethod -Url $url -Method Get
                foreach ($s in $response.value) {
                    if ($s.webUrl -notlike "*/personal/*" -and $s.webUrl -match "/sites/") {
                        $sites.Add([PSCustomObject]@{ Title = $s.displayName; Url = $s.webUrl })
                    }
                }
                $nextLink = $response.PSObject.Properties.Item('@odata.nextLink')
                $url = if ($nextLink) { $nextLink.Value } else { $null }
            } while ($url)
            $SyncHash.Sites = $sites
        } catch {
            $SyncHash.Error = $_.ToString()
        }
    }

    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.Open()
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($bgScript)
    [void]$ps.AddArgument($AdminUrl)
    [void]$ps.AddArgument($script:AppClientId)
    [void]$ps.AddArgument($script:CertPath)
    [void]$ps.AddArgument($script:CertPasswordPlain)
    [void]$ps.AddArgument($script:TenantName)
    [void]$ps.AddArgument($syncHash)
    $handle = $ps.BeginInvoke()

    $frames = @('|', '/', '-', '\')
    $frameIdx = 0
    while (-not $handle.IsCompleted) {
        $lblSpinner.Text = $frames[$frameIdx % 4]
        $frameIdx++
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 100
    }

    try { $ps.EndInvoke($handle) } catch { }
    $ps.Dispose()
    $rs.Close()
    $rs.Dispose()

    if ($syncHash.Error) {
        $loading.Close()
        $loading.Dispose()
        throw $syncHash.Error
    }

    # Re-establish the PnP connection in the main runspace so the main form can use it.
    Connect-Tenant -AdminUrl $AdminUrl

    $loading.Close()
    $loading.Dispose()
    return $syncHash.Sites
}

function Show-AdminUrlDialog {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = "SP Membership Manager"
    $dlg.Size            = New-Object System.Drawing.Size(440, 150)
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.StartPosition   = 'CenterScreen'
    $dlg.MaximizeBox     = $false
    $dlg.MinimizeBox     = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text     = "SharePoint Admin URL:"
    $lbl.Location = New-Object System.Drawing.Point(12, 16)
    $lbl.AutoSize = $true

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location        = New-Object System.Drawing.Point(12, 36)
    $txt.Size            = New-Object System.Drawing.Size(398, 23)
    $txt.PlaceholderText = "https://yourtenant-admin.sharepoint.com"
    $txt.Text            = Get-LastUrl

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text         = "Connect"
    $btnOk.Location     = New-Object System.Drawing.Point(254, 72)
    $btnOk.Size         = New-Object System.Drawing.Size(75, 28)
    $btnOk.DialogResult = 'OK'

    $btnCx = New-Object System.Windows.Forms.Button
    $btnCx.Text         = "Cancel"
    $btnCx.Location     = New-Object System.Drawing.Point(335, 72)
    $btnCx.Size         = New-Object System.Drawing.Size(75, 28)
    $btnCx.DialogResult = 'Cancel'

    $btnAboutDlg = New-Object System.Windows.Forms.Button
    $btnAboutDlg.Text     = "About"
    $btnAboutDlg.Location = New-Object System.Drawing.Point(12, 72)
    $btnAboutDlg.Size     = New-Object System.Drawing.Size(75, 28)
    $btnAboutDlg.Add_Click({ Show-AboutDialog -Owner $dlg })

    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCx
    $dlg.Controls.AddRange(@($lbl, $txt, $btnOk, $btnCx, $btnAboutDlg))

    if ($dlg.ShowDialog() -eq 'OK') {
        $url = $txt.Text.Trim()
        Save-LastUrl $url
        return $url
    }
    return $null
}

function Show-MainForm {
    param(
        [string]$AdminUrl,
        [array]$PreloadedSites = $null
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $script:AllSites     = @()
    $script:UserResults  = @()
    $script:Memberships  = @()
    $script:SelectedUser = $null

    # Form
    $form                = New-Object System.Windows.Forms.Form
    $form.Text           = "SP Membership Manager"
    $form.Size           = New-Object System.Drawing.Size(1000, 660)
    $form.MinimumSize    = New-Object System.Drawing.Size(900, 620)
    $form.StartPosition  = 'CenterScreen'
    $form.Font           = New-Object System.Drawing.Font('Segoe UI', 9)

    # Signed-in label
    $lblSignedIn          = New-Object System.Windows.Forms.Label
    $lblSignedIn.Location = New-Object System.Drawing.Point(12, 9)
    $lblSignedIn.AutoSize = $true
    $lblSignedIn.Font     = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Italic)
    $lblSignedIn.ForeColor = [System.Drawing.Color]::Gray
    $lblSignedIn.Text     = "Connecting..."

    # Left panel - user search
    $lblSearch            = New-Object System.Windows.Forms.Label
    $lblSearch.Text       = "Search Employee"
    $lblSearch.Location   = New-Object System.Drawing.Point(12, 38)
    $lblSearch.AutoSize   = $true
    $lblSearch.Font       = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)

    $txtSearch            = New-Object System.Windows.Forms.TextBox
    $txtSearch.Location   = New-Object System.Drawing.Point(12, 60)
    $txtSearch.Size       = New-Object System.Drawing.Size(190, 23)
    $txtSearch.PlaceholderText = "Name or email..."

    $btnSearch            = New-Object System.Windows.Forms.Button
    $btnSearch.Text       = "Search"
    $btnSearch.Location   = New-Object System.Drawing.Point(208, 59)
    $btnSearch.Size       = New-Object System.Drawing.Size(65, 25)

    $btnRefreshSearch     = New-Object System.Windows.Forms.Button
    $btnRefreshSearch.Text    = "↻"
    $btnRefreshSearch.Location = New-Object System.Drawing.Point(279, 59)
    $btnRefreshSearch.Size    = New-Object System.Drawing.Size(30, 25)
    $btnRefreshSearch.Enabled = $false

    $lstUsers             = New-Object System.Windows.Forms.ListBox
    $lstUsers.Location    = New-Object System.Drawing.Point(12, 92)
    $lstUsers.Size        = New-Object System.Drawing.Size(311, 340)

    # Divider
    $divider              = New-Object System.Windows.Forms.Panel
    $divider.BackColor    = [System.Drawing.Color]::LightGray
    $divider.Location     = New-Object System.Drawing.Point(335, 38)
    $divider.Size         = New-Object System.Drawing.Size(1, 410)

    # Right panel - site access
    $lblSites             = New-Object System.Windows.Forms.Label
    $lblSites.Text        = "Site Access"
    $lblSites.Location    = New-Object System.Drawing.Point(348, 38)
    $lblSites.AutoSize    = $true
    $lblSites.Font        = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)

    $lblSelectedUser      = New-Object System.Windows.Forms.Label
    $lblSelectedUser.Location = New-Object System.Drawing.Point(348, 60)
    $lblSelectedUser.Size = New-Object System.Drawing.Size(520, 20)
    $lblSelectedUser.ForeColor = [System.Drawing.Color]::DimGray

    $dgv                  = New-Object System.Windows.Forms.DataGridView
    $dgv.Location         = New-Object System.Drawing.Point(348, 88)
    $dgv.Size             = New-Object System.Drawing.Size(626, 304)
    $dgv.AllowUserToAddRows    = $false
    $dgv.AllowUserToDeleteRows = $false
    $dgv.ReadOnly              = $true
    $dgv.SelectionMode         = 'FullRowSelect'
    $dgv.MultiSelect           = $false
    $dgv.RowHeadersVisible     = $false
    $dgv.AutoSizeColumnsMode   = 'Fill'
    [void]$dgv.Columns.Add('Site', 'Site')
    [void]$dgv.Columns.Add('Role', 'Role')
    [void]$dgv.Columns.Add('URL', 'URL')
    $dgv.Columns['Site'].FillWeight = 40
    $dgv.Columns['Role'].FillWeight = 15
    $dgv.Columns['URL'].FillWeight  = 45

    $btnAdd               = New-Object System.Windows.Forms.Button
    $btnAdd.Text          = "Add to Site..."
    $btnAdd.Location      = New-Object System.Drawing.Point(348, 400)
    $btnAdd.Size          = New-Object System.Drawing.Size(110, 30)
    $btnAdd.Enabled       = $false

    $btnRemove            = New-Object System.Windows.Forms.Button
    $btnRemove.Text       = "Remove from Site"
    $btnRemove.Location   = New-Object System.Drawing.Point(466, 400)
    $btnRemove.Size       = New-Object System.Drawing.Size(130, 30)
    $btnRemove.Enabled    = $false

    $btnRefreshSites      = New-Object System.Windows.Forms.Button
    $btnRefreshSites.Text     = "↻ Refresh"
    $btnRefreshSites.Location = New-Object System.Drawing.Point(604, 400)
    $btnRefreshSites.Size     = New-Object System.Drawing.Size(85, 30)
    $btnRefreshSites.Enabled  = $false

    $btnAbout             = New-Object System.Windows.Forms.Button
    $btnAbout.Text        = "About"
    $btnAbout.Location    = New-Object System.Drawing.Point(897, 400)
    $btnAbout.Size        = New-Object System.Drawing.Size(75, 30)
    $btnAbout.Anchor      = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right

    # Log box
    $rtbLog               = New-Object System.Windows.Forms.RichTextBox
    $rtbLog.Location      = New-Object System.Drawing.Point(12, 450)
    $rtbLog.Size          = New-Object System.Drawing.Size(962, 130)
    $rtbLog.ReadOnly      = $true
    $rtbLog.BackColor     = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $rtbLog.ForeColor     = [System.Drawing.Color]::LightGreen
    $rtbLog.Font          = New-Object System.Drawing.Font('Consolas', 8)
    $rtbLog.ScrollBars    = 'Vertical'
    $rtbLog.Anchor        = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

    # Status strip
    $status               = New-Object System.Windows.Forms.StatusStrip
    $lblStatus            = New-Object System.Windows.Forms.ToolStripStatusLabel
    $lblStatus.Text       = "Initializing..."
    [void]$status.Items.Add($lblStatus)

    # Add controls
    $form.Controls.AddRange(@(
        $lblSignedIn, $lblSearch, $txtSearch, $btnSearch, $btnRefreshSearch, $lstUsers,
        $divider, $lblSites, $lblSelectedUser, $dgv,
        $btnAdd, $btnRemove, $btnRefreshSites, $btnAbout, $rtbLog, $status
    ))

    # Helper: update status bar and log
    $SetStatus = {
        param([string]$Msg)
        $line = Write-Log $Msg
        $lblStatus.Text = $Msg
        $rtbLog.AppendText("$line`n")
        $rtbLog.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }

    # Helper: refresh site grid
    $RefreshGrid = {
        $dgv.Rows.Clear()
        foreach ($m in $script:Memberships) {
            [void]$dgv.Rows.Add($m.SiteName, $m.Role, $m.SiteUrl)
        }
    }

    # On load: use pre-loaded sites if available (from loading screen), otherwise connect fresh.
    $form.Add_Load({
        if ($null -ne $PreloadedSites) {
            $script:AllSites      = $PreloadedSites
            $lblSignedIn.Text     = "Connected to: $AdminUrl"
            & $SetStatus "Ready. Search for an employee to manage their site access."
            $btnAdd.Enabled = $false
        } else {
            & $SetStatus "Connecting to tenant..."
            try {
                Connect-Tenant -AdminUrl $AdminUrl
                $lblSignedIn.Text = "Connected to: $AdminUrl"
                & $SetStatus "Loading site list..."
                $script:AllSites = Get-AllSites
                & $SetStatus "Ready. Search for an employee to manage their site access."
                $btnAdd.Enabled = $false
            } catch {
                & $SetStatus "Connection failed: $_"
                [System.Windows.Forms.MessageBox]::Show("Could not connect:`n$_", "Error", 'OK', 'Error') | Out-Null
            }
        }
    })

    # Search button
    $btnSearch.Add_Click({
        $query = $txtSearch.Text.Trim()
        if (-not $query) { return }
        & $SetStatus "Searching users..."
        $lstUsers.Items.Clear()
        $dgv.Rows.Clear()
        $lblSelectedUser.Text = ""
        $script:UserResults = @()
        try {
            # Re-connect to admin URL for search (PnP context may have shifted to a site URL)
            Connect-Tenant -AdminUrl $AdminUrl
            $script:UserResults = @(Search-Users -Query $query)
            foreach ($u in $script:UserResults) {
                [void]$lstUsers.Items.Add("$($u.DisplayName) ($($u.Email))")
            }
            $count = $script:UserResults.Count
            & $SetStatus "$count user(s) found. Select one to view their site access."
            $btnRefreshSearch.Enabled = ($count -gt 0)
        } catch {
            & $SetStatus "Search failed: $_"
            [System.Windows.Forms.MessageBox]::Show($_.ToString(), "Error", 'OK', 'Error') | Out-Null
        }
    })

    # Enter key triggers search
    $txtSearch.Add_KeyDown({
        if ($_.KeyCode -eq 'Return') { $btnSearch.PerformClick() }
    })

    # User selected
    $lstUsers.Add_SelectedIndexChanged({
        $idx = $lstUsers.SelectedIndex
        if ($idx -lt 0 -or $idx -ge $script:UserResults.Count) { return }
        $script:SelectedUser = $script:UserResults[$idx]
        $lblSelectedUser.Text = "$($script:SelectedUser.DisplayName)  |  $($script:SelectedUser.Email)"
        $dgv.Rows.Clear()
        $btnRemove.Enabled = $false
        & $SetStatus "Loading site memberships for $($script:SelectedUser.DisplayName)..."

        try {
            $script:Memberships = @(Get-UserSiteMemberships -UserEmail $script:SelectedUser.Email -AllSites $script:AllSites -LogBox $rtbLog)
            & $RefreshGrid
            $count = $script:Memberships.Count
            if ($count -eq 0) {
                & $SetStatus "$($script:SelectedUser.DisplayName) has no site access."
            } else {
                & $SetStatus "$($script:SelectedUser.DisplayName) is a member of $count site(s)."
            }
            $btnAdd.Enabled          = $true
            $btnRefreshSites.Enabled = $true
        } catch {
            & $SetStatus "Failed to load memberships: $_"
            [System.Windows.Forms.MessageBox]::Show($_.ToString(), "Error", 'OK', 'Error') | Out-Null
        }
    })

    # Grid selection enables remove button
    $dgv.Add_SelectionChanged({
        $btnRemove.Enabled = ($script:SelectedUser -and $dgv.SelectedRows.Count -gt 0)
    })

    # Add to site
    $btnAdd.Add_Click({
        if (-not $script:SelectedUser) { return }

        $dlgForm = New-Object System.Windows.Forms.Form
        $dlgForm.Text = "Add User to Site"
        $dlgForm.Size = New-Object System.Drawing.Size(420, 190)
        $dlgForm.FormBorderStyle = 'FixedDialog'
        $dlgForm.StartPosition = 'CenterParent'
        $dlgForm.MaximizeBox = $false; $dlgForm.MinimizeBox = $false

        $lblS = New-Object System.Windows.Forms.Label; $lblS.Text = "Site:"; $lblS.Location = New-Object System.Drawing.Point(12,16); $lblS.AutoSize = $true
        $cmbS = New-Object System.Windows.Forms.ComboBox; $cmbS.Location = New-Object System.Drawing.Point(80,12); $cmbS.Size = New-Object System.Drawing.Size(310,23); $cmbS.DropDownStyle = 'DropDownList'
        foreach ($s in $script:AllSites) { [void]$cmbS.Items.Add($s.Title) }
        if ($cmbS.Items.Count -gt 0) { $cmbS.SelectedIndex = 0 }

        $lblR = New-Object System.Windows.Forms.Label; $lblR.Text = "Role:"; $lblR.Location = New-Object System.Drawing.Point(12,52); $lblR.AutoSize = $true
        $cmbR = New-Object System.Windows.Forms.ComboBox; $cmbR.Location = New-Object System.Drawing.Point(80,48); $cmbR.Size = New-Object System.Drawing.Size(160,23); $cmbR.DropDownStyle = 'DropDownList'
        [void]$cmbR.Items.AddRange(@('Member','Owner','Visitor')); $cmbR.SelectedIndex = 0

        $btnOk  = New-Object System.Windows.Forms.Button; $btnOk.Text = "Add"; $btnOk.Location = New-Object System.Drawing.Point(220,110); $btnOk.Size = New-Object System.Drawing.Size(75,28); $btnOk.DialogResult = 'OK'
        $btnCx  = New-Object System.Windows.Forms.Button; $btnCx.Text = "Cancel"; $btnCx.Location = New-Object System.Drawing.Point(305,110); $btnCx.Size = New-Object System.Drawing.Size(75,28); $btnCx.DialogResult = 'Cancel'
        $dlgForm.AcceptButton = $btnOk; $dlgForm.CancelButton = $btnCx
        $dlgForm.Controls.AddRange(@($lblS,$cmbS,$lblR,$cmbR,$btnOk,$btnCx))

        if ($dlgForm.ShowDialog() -eq 'OK') {
            $site = $script:AllSites[$cmbS.SelectedIndex]
            $role = $cmbR.SelectedItem
            $conf = [System.Windows.Forms.MessageBox]::Show(
                "Add $($script:SelectedUser.DisplayName) to $($site.Title) as $($role)?",
                "Confirm", 'YesNo', 'Warning')
            if ($conf -ne 'Yes') { return }
            & $SetStatus "Adding $($script:SelectedUser.DisplayName) to $($site.Title) as $role..."
            try {
                Add-UserToSite -SiteUrl $site.Url -UserEmail $script:SelectedUser.Email -Role $role
                & $SetStatus "Added $($script:SelectedUser.DisplayName) to $($site.Title). Use Refresh to verify."
                Show-CountdownDialog `
                    -Message "$($script:SelectedUser.DisplayName) was added to $($site.Title) as $role.`n`nSharePoint needs a moment to propagate the change. Wait for the countdown before refreshing." `
                    -Title 'Success'
            } catch {
                & $SetStatus "Failed to add user: $_"
                [System.Windows.Forms.MessageBox]::Show($_.ToString(), "Error", 'OK', 'Error') | Out-Null
            }
        }
    })

    # Remove from site
    $btnRemove.Add_Click({
        if (-not $script:SelectedUser -or $dgv.SelectedRows.Count -eq 0) { return }
        $idx  = $dgv.SelectedRows[0].Index
        $mem  = $script:Memberships[$idx]
        $conf = [System.Windows.Forms.MessageBox]::Show(
            "Remove $($script:SelectedUser.DisplayName) from $($mem.SiteName)?",
            "Confirm", 'YesNo', 'Warning')
        if ($conf -ne 'Yes') { return }

        & $SetStatus "Removing $($script:SelectedUser.DisplayName) from $($mem.SiteName)..."
        $removeError = $null
        try {
            Remove-UserFromSite -SiteUrl $mem.SiteUrl -UserEmail $script:SelectedUser.Email -Role $mem.Role
        } catch {
            $removeError = $_
        }
        if ($removeError) {
            & $SetStatus "Failed to remove user: $removeError"
            [System.Windows.Forms.MessageBox]::Show($removeError.ToString(), "Error", 'OK', 'Error') | Out-Null
        } else {
            & $SetStatus "Removed $($script:SelectedUser.DisplayName) from $($mem.SiteName). Use Refresh to verify."
            Show-CountdownDialog `
                -Message "$($script:SelectedUser.DisplayName) was removed from $($mem.SiteName).`n`nSharePoint needs a moment to propagate the change. Wait for the countdown before refreshing." `
                -Title 'Success'
        }
    })

    # Refresh employee search (re-runs last query)
    $btnRefreshSearch.Add_Click({
        if ($txtSearch.Text.Trim()) { $btnSearch.PerformClick() }
    })

    # Refresh site access (re-scans for currently selected user)
    $btnRefreshSites.Add_Click({
        if (-not $script:SelectedUser) { return }
        & $SetStatus "Refreshing site memberships for $($script:SelectedUser.DisplayName)..."
        try {
            $script:Memberships = @(Get-UserSiteMemberships -UserEmail $script:SelectedUser.Email -AllSites $script:AllSites -LogBox $rtbLog)
            & $RefreshGrid
            $count = $script:Memberships.Count
            & $SetStatus "$($script:SelectedUser.DisplayName) is a member of $count site(s)."
        } catch {
            & $SetStatus "Refresh failed: $_"
            [System.Windows.Forms.MessageBox]::Show($_.ToString(), "Error", 'OK', 'Error') | Out-Null
        }
    })

    # About dialog
    $btnAbout.Add_Click({ Show-AboutDialog -Owner $form })

    [void]$form.ShowDialog()
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

Ensure-PnPModule

Add-Type -AssemblyName System.Windows.Forms

Load-AppConfig

$adminUrl = Show-AdminUrlDialog
if (-not $adminUrl) { exit }

try {
    $sites = Show-LoadingForm -AdminUrl $adminUrl
    Show-MainForm -AdminUrl $adminUrl -PreloadedSites $sites
} catch {
    [System.Windows.Forms.MessageBox]::Show(
        "Could not connect to tenant:`n$_",
        "Connection Failed", 'OK', 'Error') | Out-Null
}
