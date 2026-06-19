#Requires -Version 7.0

<#
.SYNOPSIS
    GUI wizard for building a per-client SP-MembershipManager executable.

.DESCRIPTION
    Presents a WinForms interface to collect all per-client build parameters,
    then calls build.ps1 with the assembled arguments.
    For scripted/CI builds, call build.ps1 directly with command-line parameters.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$root = $PSScriptRoot

$form                  = New-Object System.Windows.Forms.Form
$form.Text             = "SP-MembershipManager Build Wizard"
$form.Size             = New-Object System.Drawing.Size(620, 660)
$form.StartPosition    = 'CenterScreen'
$form.FormBorderStyle  = 'FixedDialog'
$form.MaximizeBox      = $false
$form.MinimizeBox      = $false
$form.Font             = New-Object System.Drawing.Font('Segoe UI', 9)

$pad  = 16
$lblW = 160
$ctlW = 390
$row  = 0

function Add-Row {
    param([string]$Label, [System.Windows.Forms.Control]$Control, [int]$Height = 26)
    $y = $pad + $row * 38
    $lbl          = New-Object System.Windows.Forms.Label
    $lbl.Text     = $Label
    $lbl.Location = New-Object System.Drawing.Point($pad, ($y + 4))
    $lbl.Size     = New-Object System.Drawing.Size($lblW, 20)
    $Control.Location = New-Object System.Drawing.Point(($pad + $lblW), $y)
    $Control.Size     = New-Object System.Drawing.Size($ctlW, $Height)
    $form.Controls.AddRange(@($lbl, $Control))
    $script:row++
}

# --- Certificate section ---
$lblCertSection          = New-Object System.Windows.Forms.Label
$lblCertSection.Text     = "Certificate (embed in EXE for zero-config deployment)"
$lblCertSection.Font     = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$lblCertSection.Location = New-Object System.Drawing.Point($pad, $pad)
$lblCertSection.Size     = New-Object System.Drawing.Size(560, 20)
$form.Controls.Add($lblCertSection)
$row = 1

$txtCertPath = New-Object System.Windows.Forms.TextBox
$txtCertPath.PlaceholderText = "Leave blank to require app-config.json at runtime"
Add-Row "Certificate (.pfx)" $txtCertPath

$btnBrowseCert = New-Object System.Windows.Forms.Button
$btnBrowseCert.Text     = "Browse..."
$btnBrowseCert.Size     = New-Object System.Drawing.Size(80, 26)
$btnBrowseCert.Location = New-Object System.Drawing.Point(($pad + $lblW + $ctlW + 6), ($pad + 1 * 38 + $pad))
$btnBrowseCert.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "PFX Certificate (*.pfx)|*.pfx"
    if ($dlg.ShowDialog() -eq 'OK') { $txtCertPath.Text = $dlg.FileName }
})
$form.Controls.Add($btnBrowseCert)

$txtCertPassword = New-Object System.Windows.Forms.TextBox
$txtCertPassword.UseSystemPasswordChar = $true
$txtCertPassword.PlaceholderText = "Required if certificate is specified"
Add-Row "Certificate Password" $txtCertPassword

$txtTenant = New-Object System.Windows.Forms.TextBox
$txtTenant.PlaceholderText = "contoso.onmicrosoft.com  (required if certificate is specified)"
Add-Row "Tenant" $txtTenant

# --- Tenant lock section ---
$lblLockSection          = New-Object System.Windows.Forms.Label
$lblLockSection.Text     = "Tenant Lock"
$lblLockSection.Font     = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$lblLockSection.Location = New-Object System.Drawing.Point($pad, ($pad + $row * 38 + 4))
$lblLockSection.Size     = New-Object System.Drawing.Size(560, 20)
$form.Controls.Add($lblLockSection)
$row++

$txtLockedAdminUrl = New-Object System.Windows.Forms.TextBox
$txtLockedAdminUrl.PlaceholderText = "https://contoso-admin.sharepoint.com  (optional)"
Add-Row "Locked Admin URL" $txtLockedAdminUrl

# --- Gate section ---
$lblGateSection          = New-Object System.Windows.Forms.Label
$lblGateSection.Text     = "Sign-In Gate (overrides app-config.json)"
$lblGateSection.Font     = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$lblGateSection.Location = New-Object System.Drawing.Point($pad, ($pad + $row * 38 + 4))
$lblGateSection.Size     = New-Object System.Drawing.Size(560, 20)
$form.Controls.Add($lblGateSection)
$row++

$txtGateClientId = New-Object System.Windows.Forms.TextBox
$txtGateClientId.PlaceholderText = "Application (client) ID of the gate app registration"
Add-Row "Gate Client ID" $txtGateClientId

$txtGateGroupId = New-Object System.Windows.Forms.TextBox
$txtGateGroupId.PlaceholderText = "Entra group object ID — members may use the app"
Add-Row "Gate Group ID" $txtGateGroupId

$txtGateRequestContact = New-Object System.Windows.Forms.TextBox
$txtGateRequestContact.PlaceholderText = "Email or URL shown on Access Denied dialog (optional)"
Add-Row "Request Access Contact" $txtGateRequestContact

# --- Critical sites section ---
$lblCritSection          = New-Object System.Windows.Forms.Label
$lblCritSection.Text     = "Critical Sites"
$lblCritSection.Font     = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$lblCritSection.Location = New-Object System.Drawing.Point($pad, ($pad + $row * 38 + 4))
$lblCritSection.Size     = New-Object System.Drawing.Size(560, 20)
$form.Controls.Add($lblCritSection)
$row++

$txtCriticalSiteGroupId = New-Object System.Windows.Forms.TextBox
$txtCriticalSiteGroupId.PlaceholderText = "Entra group object ID — members may manage critical sites"
Add-Row "Critical Site Group ID" $txtCriticalSiteGroupId

$txtCriticalSiteUrls          = New-Object System.Windows.Forms.TextBox
$txtCriticalSiteUrls.Multiline = $true
$txtCriticalSiteUrls.ScrollBars = 'Vertical'
$txtCriticalSiteUrls.PlaceholderText = "One SharePoint site URL per line"
Add-Row "Critical Site URLs" $txtCriticalSiteUrls 60
$row++   # extra row for the taller text area

# --- Output section ---
$lblOutput          = New-Object System.Windows.Forms.Label
$lblOutput.Text     = "Build Output"
$lblOutput.Font     = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$lblOutput.Location = New-Object System.Drawing.Point($pad, ($pad + $row * 38 + 4))
$lblOutput.Size     = New-Object System.Drawing.Size(560, 20)
$form.Controls.Add($lblOutput)
$row++

$rtbOutput          = New-Object System.Windows.Forms.RichTextBox
$rtbOutput.ReadOnly = $true
$rtbOutput.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$rtbOutput.ForeColor = [System.Drawing.Color]::LightGreen
$rtbOutput.Font      = New-Object System.Drawing.Font('Consolas', 8)
$rtbOutput.Location  = New-Object System.Drawing.Point($pad, ($pad + $row * 38))
$rtbOutput.Size      = New-Object System.Drawing.Size(($form.ClientSize.Width - $pad * 2), 80)
$form.Controls.Add($rtbOutput)

$btnBuild          = New-Object System.Windows.Forms.Button
$btnBuild.Text     = "Build"
$btnBuild.Size     = New-Object System.Drawing.Size(100, 30)
$btnBuild.Location = New-Object System.Drawing.Point(($form.ClientSize.Width - $pad - 100), ($form.ClientSize.Height - $pad - 30))
$btnBuild.Anchor   = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($btnBuild)

$btnBuild.Add_Click({
    $rtbOutput.Clear()

    # Validate cert params
    if ($txtCertPath.Text.Trim() -and (-not $txtCertPassword.Text -or -not $txtTenant.Text.Trim())) {
        [System.Windows.Forms.MessageBox]::Show(
            "Certificate Password and Tenant are required when a certificate is specified.",
            "Validation Error", 'OK', 'Error') | Out-Null
        return
    }

    # Build param array
    $params = @{}
    if ($txtCertPath.Text.Trim())            { $params['CertPath']            = $txtCertPath.Text.Trim() }
    if ($txtCertPassword.Text)               { $params['CertPassword']        = $txtCertPassword.Text }
    if ($txtTenant.Text.Trim())              { $params['Tenant']              = $txtTenant.Text.Trim() }
    if ($txtLockedAdminUrl.Text.Trim())      { $params['LockedAdminUrl']      = $txtLockedAdminUrl.Text.Trim() }
    if ($txtGateClientId.Text.Trim())        { $params['GateClientId']        = $txtGateClientId.Text.Trim() }
    if ($txtGateGroupId.Text.Trim())         { $params['GateGroupId']         = $txtGateGroupId.Text.Trim() }
    if ($txtGateRequestContact.Text.Trim())  { $params['GateRequestContact']  = $txtGateRequestContact.Text.Trim() }
    if ($txtCriticalSiteGroupId.Text.Trim()) { $params['CriticalSiteGroupId'] = $txtCriticalSiteGroupId.Text.Trim() }

    $urls = @($txtCriticalSiteUrls.Lines | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })
    if ($urls.Count -gt 0) { $params['CriticalSiteUrls'] = $urls }

    $btnBuild.Enabled = $false
    $rtbOutput.AppendText("Building...`n")
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $buildScript = Join-Path $root 'build.ps1'
        $output = & $buildScript @params 2>&1
        foreach ($line in $output) { $rtbOutput.AppendText("$line`n") }
        $rtbOutput.AppendText("`nDone.`n")
    } catch {
        $rtbOutput.AppendText("`nERROR: $_`n")
    } finally {
        $btnBuild.Enabled = $true
    }
})

[void]$form.ShowDialog()
