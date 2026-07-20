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

[System.Windows.Forms.Application]::EnableVisualStyles()

# --- Layout constants ---
$pad     = 16                        # window edge padding
$lblW    = 150                       # label column width
$browseW = 84                        # Browse... button width
$fullW   = 490                       # input column width
$ctlW    = $fullW - $browseW - 6     # input width when a button sits beside it
$gap     = 8                         # vertical gap between rows
$secGap  = 14                        # extra gap above section headers
$clientW = $pad + $lblW + 8 + $fullW + $pad

$form                  = New-Object System.Windows.Forms.Form
$form.Text             = "SP-MembershipManager Build Wizard"
$form.StartPosition    = 'CenterScreen'
$form.FormBorderStyle  = 'Sizable'
$form.MaximizeBox      = $true
$form.MinimizeBox      = $true
$form.Font             = New-Object System.Drawing.Font('Segoe UI', 9)
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
$form.AutoScaleMode    = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.ClientSize       = New-Object System.Drawing.Size($clientW, 700)   # height finalized after layout

# Vertical layout cursor: every row/section advances $script:y, so the form
# height is derived from the content instead of hand-counted row math.
$script:y = $pad

function Add-Section {
    param([string]$Title)
    if ($script:y -gt $pad) { $script:y += $secGap }
    $lbl          = New-Object System.Windows.Forms.Label
    $lbl.Text     = $Title
    $lbl.Font     = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
    $lbl.Location = New-Object System.Drawing.Point($pad, $script:y)
    $lbl.AutoSize = $true
    $form.Controls.Add($lbl)
    $script:y += 26
}

function Add-Row {
    param([string]$Label, [System.Windows.Forms.Control]$Control, [int]$Height = 26, [int]$Width = -1)
    if ($Width -lt 0) { $Width = $fullW }
    $lbl          = New-Object System.Windows.Forms.Label
    $lbl.Text     = $Label
    $lbl.Location = New-Object System.Drawing.Point($pad, ($script:y + 4))
    $lbl.Size     = New-Object System.Drawing.Size($lblW, 20)
    $Control.Location = New-Object System.Drawing.Point(($pad + $lblW + 8), $script:y)
    $Control.Size     = New-Object System.Drawing.Size($Width, $Height)
    $Control.Anchor   = [System.Windows.Forms.AnchorStyles]::Top -bor
                        [System.Windows.Forms.AnchorStyles]::Left -bor
                        [System.Windows.Forms.AnchorStyles]::Right
    if ($Control -is [System.Windows.Forms.TextBox]) {
        # WinForms doesn't always repaint PlaceholderText when focus leaves an
        # empty field; force a repaint so the hint reappears.
        $Control.Add_LostFocus({ param($s, $e) $s.Invalidate() })
    }
    $form.Controls.AddRange(@($lbl, $Control))
    $script:y += $Height + $gap
}

# --- Certificate section ---
Add-Section "Certificate (embed in EXE for zero-config deployment)"

$certRowY = $script:y
$txtCertPath = New-Object System.Windows.Forms.TextBox
$txtCertPath.PlaceholderText = "Leave blank to require app-config.json at runtime"
Add-Row "Certificate (.pfx)" $txtCertPath -Width $ctlW

$btnBrowseCert = New-Object System.Windows.Forms.Button
$btnBrowseCert.Text     = "Browse..."
$btnBrowseCert.Size     = New-Object System.Drawing.Size($browseW, 26)
$btnBrowseCert.Location = New-Object System.Drawing.Point(($pad + $lblW + 8 + $ctlW + 6), $certRowY)
$btnBrowseCert.Anchor   = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
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

$txtAppClientId = New-Object System.Windows.Forms.TextBox
$txtAppClientId.PlaceholderText = "App registration (client) ID  (required if certificate is specified)"
Add-Row "App Client ID" $txtAppClientId

# --- Tenant lock section ---
Add-Section "Tenant Lock"

$txtLockedAdminUrl = New-Object System.Windows.Forms.TextBox
$txtLockedAdminUrl.PlaceholderText = "https://contoso-admin.sharepoint.com  (optional)"
Add-Row "Locked Admin URL" $txtLockedAdminUrl

# --- Gate section ---
Add-Section "Sign-In Gate (overrides app-config.json)"

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
Add-Section "Critical Sites"

$txtCriticalSiteGroupId = New-Object System.Windows.Forms.TextBox
$txtCriticalSiteGroupId.PlaceholderText = "Entra group object ID — members may manage critical sites"
Add-Row "Critical Site Group ID" $txtCriticalSiteGroupId

$txtCriticalSiteUrls          = New-Object System.Windows.Forms.TextBox
$txtCriticalSiteUrls.Multiline = $true
$txtCriticalSiteUrls.ScrollBars = 'Vertical'
$txtCriticalSiteUrls.PlaceholderText = "One SharePoint site URL per line"
Add-Row "Critical Site URLs" $txtCriticalSiteUrls 56

# --- Output section ---
Add-Section "Build Output"

$rtbOutput          = New-Object System.Windows.Forms.RichTextBox
$rtbOutput.ReadOnly = $true
$rtbOutput.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$rtbOutput.ForeColor = [System.Drawing.Color]::LightGreen
$rtbOutput.Font      = New-Object System.Drawing.Font('Consolas', 9)
$rtbOutput.Location  = New-Object System.Drawing.Point($pad, $script:y)
$rtbOutput.Size      = New-Object System.Drawing.Size(($clientW - $pad * 2), 120)
$rtbOutput.Anchor    = [System.Windows.Forms.AnchorStyles]::Top -bor
                       [System.Windows.Forms.AnchorStyles]::Bottom -bor
                       [System.Windows.Forms.AnchorStyles]::Left -bor
                       [System.Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($rtbOutput)
$script:y += 120 + $gap + 4

$btnBuild          = New-Object System.Windows.Forms.Button
$btnBuild.Text     = "Build"
$btnBuild.Size     = New-Object System.Drawing.Size(100, 30)
$btnBuild.Location = New-Object System.Drawing.Point(($clientW - $pad - 100), $script:y)
$btnBuild.Anchor   = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($btnBuild)

$form.ClientSize   = New-Object System.Drawing.Size($clientW, ($script:y + 30 + $pad))
# Don't let the window shrink below the fully laid-out size.
$form.MinimumSize  = $form.Size

$btnBuild.Add_Click({
    $rtbOutput.Clear()

    # Validate cert params. A self-contained EXE has no app-config.json at runtime,
    # so App Client ID must be supplied alongside the cert password and tenant.
    if ($txtCertPath.Text.Trim() -and (-not $txtCertPassword.Text -or -not $txtTenant.Text.Trim() -or -not $txtAppClientId.Text.Trim())) {
        [System.Windows.Forms.MessageBox]::Show(
            "Certificate Password, Tenant, and App Client ID are required when a certificate is specified.",
            "Validation Error", 'OK', 'Error') | Out-Null
        return
    }

    # Validate gate params: both-or-neither. A half-configured gate produces an EXE
    # that fails at startup.
    $gateClient = $txtGateClientId.Text.Trim()
    $gateGroup  = $txtGateGroupId.Text.Trim()
    if ([bool]$gateClient -ne [bool]$gateGroup) {
        $missing = if ($gateClient) { 'Gate Group ID' } else { 'Gate Client ID' }
        [System.Windows.Forms.MessageBox]::Show(
            "$missing is required. The sign-in gate needs both Gate Client ID and Gate Group ID (or leave both blank to disable it).",
            "Validation Error", 'OK', 'Error') | Out-Null
        return
    }

    # No gate at all -> anyone in the tenant can use the tool. Require explicit confirmation.
    if (-not $gateClient -and -not $gateGroup) {
        $proceed = [System.Windows.Forms.MessageBox]::Show(
            "This build has NO sign-in gate.`n`nAny user who can run the EXE will be able to use it — there is no authorization check. Build anyway?",
            "No Sign-In Gate", 'YesNo', 'Warning')
        if ($proceed -ne 'Yes') { return }
    }

    # Build param array
    $params = @{}
    if ($txtCertPath.Text.Trim())            { $params['CertPath']            = $txtCertPath.Text.Trim() }
    if ($txtCertPassword.Text)               { $params['CertPassword']        = $txtCertPassword.Text }
    if ($txtTenant.Text.Trim())              { $params['Tenant']              = $txtTenant.Text.Trim() }
    if ($txtAppClientId.Text.Trim())         { $params['AppClientId']         = $txtAppClientId.Text.Trim() }
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
