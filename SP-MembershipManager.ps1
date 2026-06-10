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
# App registration
#
# Client ID is public and safe to commit. The client secret is loaded from a
# local config file (app-config.json) that is gitignored and must be created
# before running. See README for setup instructions.
#
# If you fork this repo, replace AppClientId with your own app registration
# and create your own app-config.json with your secret.
# ---------------------------------------------------------------------------

$script:AppClientId  = "630f7dac-df2b-4586-a6b4-e83acbf4e91e"
$script:TenantName   = ""
$script:CertPath     = ""
$script:CertPassword = $null

$script:ConfigFile   = Join-Path $PSScriptRoot "app-config.json"
$script:LastUrlFile  = Join-Path $PSScriptRoot "last-url.txt"

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
        $certPath = Join-Path $PSScriptRoot $certPath
    }
    if (-not (Test-Path $certPath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Certificate file not found: $certPath",
            "Configuration Error", 'OK', 'Error') | Out-Null
        exit
    }
    $script:CertPath     = $certPath
    $script:CertPassword = ConvertTo-SecureString $cfg.CertificatePassword -AsPlainText -Force
    $script:TenantName   = $cfg.Tenant
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
    $results = Submit-PnPSearchQuery -Query "$Query" -SourceId "b09a7990-05ea-4af9-81ef-edfab16c4e31" -SelectProperties "AccountName,PreferredName,WorkEmail" -MaxResults 20
    $users = foreach ($row in $results.ResultRows) {
        [PSCustomObject]@{
            DisplayName = $row['PreferredName']
            Email       = $row['WorkEmail']
            Account     = $row['AccountName']
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

    $memberships = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($site in $AllSites) {
        $line = Write-Log "Checking $($site.Title)..."
        if ($LogBox) {
            $LogBox.Invoke([Action]{ $LogBox.AppendText("$line`n"); $LogBox.ScrollToCaret() })
        }

        try {
            Connect-Site -Url $site.Url

            $groups = Get-PnPGroup
            foreach ($group in $groups) {
                $role = $null
                if ($group.Title -like '* Owners')   { $role = 'Owner'   }
                elseif ($group.Title -like '* Members')  { $role = 'Member'  }
                elseif ($group.Title -like '* Visitors') { $role = 'Visitor' }
                if (-not $role) { continue }

                $members = Get-PnPGroupMember -Group $group
                if ($members | Where-Object { $_.Email -eq $UserEmail }) {
                    $memberships.Add([PSCustomObject]@{
                        SiteName = $site.Title
                        SiteUrl  = $site.Url
                        Role     = $role
                    })
                    break
                }
            }
        } catch {
            Write-Log "Warning: could not check $($site.Title) - $_" | Out-Null
        }
    }

    return $memberships
}

function Add-UserToSite {
    param([string]$SiteUrl, [string]$UserEmail, [string]$Role)
    Connect-Site -Url $SiteUrl
    $groups = Get-PnPGroup
    $group  = $groups | Where-Object { $_.Title -like "* $Role`s" -or $_.Title -like "* ${Role}s" } | Select-Object -First 1
    if (-not $group) { throw "Could not find $Role group for site." }
    Add-PnPGroupMember -Group $group -EmailAddress $UserEmail
}

function Remove-UserFromSite {
    param([string]$SiteUrl, [string]$UserEmail, [string]$Role)
    Connect-Site -Url $SiteUrl
    $groups = Get-PnPGroup
    $group  = $groups | Where-Object { $_.Title -like "* $Role`s" -or $_.Title -like "* ${Role}s" } | Select-Object -First 1
    if (-not $group) { throw "Could not find $Role group for site." }
    Remove-PnPGroupMember -Group $group -LoginName $UserEmail
}

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

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

    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCx
    $dlg.Controls.AddRange(@($lbl, $txt, $btnOk, $btnCx))

    if ($dlg.ShowDialog() -eq 'OK') {
        $url = $txt.Text.Trim()
        Save-LastUrl $url
        return $url
    }
    return $null
}

function Show-MainForm {
    param([string]$AdminUrl)

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
    $txtSearch.Size       = New-Object System.Drawing.Size(230, 23)
    $txtSearch.PlaceholderText = "Name or email..."

    $btnSearch            = New-Object System.Windows.Forms.Button
    $btnSearch.Text       = "Search"
    $btnSearch.Location   = New-Object System.Drawing.Point(248, 59)
    $btnSearch.Size       = New-Object System.Drawing.Size(75, 25)

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

    # Log box
    $rtbLog               = New-Object System.Windows.Forms.RichTextBox
    $rtbLog.Location      = New-Object System.Drawing.Point(12, 450)
    $rtbLog.Size          = New-Object System.Drawing.Size(962, 130)
    $rtbLog.ReadOnly      = $true
    $rtbLog.BackColor     = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $rtbLog.ForeColor     = [System.Drawing.Color]::LightGreen
    $rtbLog.Font          = New-Object System.Drawing.Font('Consolas', 8)
    $rtbLog.ScrollBars    = 'Vertical'

    # Status strip
    $status               = New-Object System.Windows.Forms.StatusStrip
    $lblStatus            = New-Object System.Windows.Forms.ToolStripStatusLabel
    $lblStatus.Text       = "Initializing..."
    [void]$status.Items.Add($lblStatus)

    # Add controls
    $form.Controls.AddRange(@(
        $lblSignedIn, $lblSearch, $txtSearch, $btnSearch, $lstUsers,
        $divider, $lblSites, $lblSelectedUser, $dgv,
        $btnAdd, $btnRemove, $rtbLog, $status
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

    # On load: connect and pre-load sites
    $form.Add_Load({
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
            $btnAdd.Enabled = $true
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
        $dlgForm.Size = New-Object System.Drawing.Size(420, 160)
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
            & $SetStatus "Adding $($script:SelectedUser.DisplayName) to $($site.Title) as $role..."
            try {
                Add-UserToSite -SiteUrl $site.Url -UserEmail $script:SelectedUser.Email -Role $role
                & $SetStatus "Added $($script:SelectedUser.DisplayName) to $($site.Title)."
                # Refresh memberships
                $script:Memberships = @(Get-UserSiteMemberships -UserEmail $script:SelectedUser.Email -AllSites $script:AllSites -LogBox $rtbLog)
                & $RefreshGrid
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
        try {
            Remove-UserFromSite -SiteUrl $mem.SiteUrl -UserEmail $script:SelectedUser.Email -Role $mem.Role
            & $SetStatus "Removed $($script:SelectedUser.DisplayName) from $($mem.SiteName)."
            $script:Memberships = @(Get-UserSiteMemberships -UserEmail $script:SelectedUser.Email -AllSites $script:AllSites -LogBox $rtbLog)
            & $RefreshGrid
        } catch {
            & $SetStatus "Failed to remove user: $_"
            [System.Windows.Forms.MessageBox]::Show($_.ToString(), "Error", 'OK', 'Error') | Out-Null
        }
    })

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

Show-MainForm -AdminUrl $adminUrl
