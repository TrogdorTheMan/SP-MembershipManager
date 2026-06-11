# Certificate Renewal

The tool authenticates to Microsoft 365 using an app-only certificate registered in Entra ID. Certificates expire — typically after 1 or 2 years depending on how the certificate was generated. This document covers how to tell when renewal is needed, how to generate a new certificate, and how to update the tool.

## How to tell when the cert is expiring

The certificate expiry date is visible in the Entra ID portal:

1. Go to [portal.azure.com](https://portal.azure.com) and sign in with a Global Admin account
2. Navigate to **Entra ID → App registrations → SP-MembershipManager** (or search by the client ID in `app-config.json`)
3. Click **Certificates & secrets → Certificates**
4. The expiry date is listed in the **Expires** column

The tool will start failing to connect once the certificate expires. If users report connection errors, check here first.

## Generating a new certificate

You can use PowerShell to generate a self-signed certificate. Run this on a Windows machine:

```powershell
$cert = New-SelfSignedCertificate `
    -Subject "CN=SP-MembershipManager" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyExportPolicy Exportable `
    -KeySpec Signature `
    -KeyLength 2048 `
    -KeyAlgorithm RSA `
    -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddYears(2)

# Export the .pfx (private key — keep this secure)
$password = Read-Host "Enter a password for the pfx" -AsSecureString
Export-PfxCertificate -Cert $cert -FilePath "sp-mm-new.pfx" -Password $password

# Export the .cer (public key — upload this to Entra ID)
Export-Certificate -Cert $cert -FilePath "sp-mm-new.cer"
```

This creates two files:
- `sp-mm-new.pfx` — the private key file the tool uses; treat it like a password
- `sp-mm-new.cer` — the public key to upload to Entra ID

## Uploading the new certificate to Entra ID

1. Go to **Entra ID → App registrations → SP-MembershipManager → Certificates & secrets → Certificates**
2. Click **Upload certificate**
3. Select `sp-mm-new.cer` and add a description (e.g. "Renewed 2027-06")
4. Click **Add**

You can upload the new certificate before removing the old one so there is no downtime window during the transition.

5. Once the new certificate is in place and the tool is working, delete the old (expired) certificate entry.

## Updating app-config.json

Replace the `sp-mm.pfx` file alongside the tool with the new `sp-mm-new.pfx` (rename it to match whatever `CertificatePath` says in `app-config.json`, or update `CertificatePath` to point to the new filename).

Because the certificate password is DPAPI-encrypted in `app-config.json` after the first run, you need to reset it:

1. Open `app-config.json`
2. Set `"CertificatePasswordEncrypted": false`
3. Set `"CertificatePassword"` to the plaintext password you chose when exporting the pfx
4. Launch the tool — it will re-encrypt the password on first successful connect and replace the plaintext

```json
{
  "CertificatePath": "sp-mm.pfx",
  "CertificatePassword": "your-plaintext-password-here",
  "CertificatePasswordEncrypted": false,
  ...
}
```

## Deploying to end users

If the tool is deployed as a standalone `.exe` alongside `app-config.json` and the pfx, you only need to:

1. Replace the pfx file on each machine (or on a shared path if you're using one)
2. Reset the password fields in `app-config.json` as described above

If you are building a new exe with the cert baked in (once the per-client build config feature is implemented), rebuild and redeploy the exe instead.

## Summary checklist

- [ ] Generate new certificate (`New-SelfSignedCertificate`)
- [ ] Export `.pfx` (private key) and `.cer` (public key)
- [ ] Upload `.cer` to Entra ID app registration
- [ ] Verify new cert appears in portal with correct expiry
- [ ] Replace `.pfx` file alongside the tool
- [ ] Reset `CertificatePasswordEncrypted` to `false` and restore plaintext password in `app-config.json`
- [ ] Launch tool and confirm it connects successfully
- [ ] Delete the old certificate entry from Entra ID
