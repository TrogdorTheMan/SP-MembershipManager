# Setting up SP-MembershipManager for a tenant

This is the start-to-finish guide for getting the tool running against a Microsoft 365
tenant. It assumes **no prior experience** with Entra ID (Azure AD) app registrations or
certificates — if you can follow numbered steps and paste a few commands, you can do this.

There are two paths. Pick the one that matches your situation:

- **[Part A — Set up your own app registration](#part-a--set-up-your-own-app-registration)**
  You cloned or forked the repo and want to run the tool against your own tenant using
  **your own** Entra ID app registration. This is the full from-scratch path.
- **[Part B — Deploy to another tenant with an existing app](#part-b--deploy-to-another-tenant-with-an-existing-app)**
  You already have the app registration set up (yours, or the one shipped with this repo)
  and just need to light it up in a **new** tenant. Much shorter: grant consent + drop in a
  config file.

If you're not sure, you almost certainly want **Part A**.

> **Just want to build the EXE?** Setup (this guide) is about connecting the tool to a
> tenant. Packaging it into a distributable `.exe` is a separate step covered in
> **[BUILDING.md](BUILDING.md)**. You can do the whole of Part A running from source first,
> then build later.

---

## What you'll end up with

By the end of Part A you'll have:

- An **app registration** in your tenant that the tool signs in as (app-only, no user needed)
- A **certificate** — a `.pfx` (private key, stays with the tool) and a `.cer` (public key,
  uploaded to Entra)
- A filled-in **`app-config.json`** pointing the tool at your tenant and cert
- **Admin consent** granted once, so the tool works for anyone you let run it

Then you run `.\SP-MembershipManager.ps1` and it just connects.

---

## Before you start

You need these on your machine:

| Requirement | How to check | How to get it |
|-------------|--------------|---------------|
| **Windows 10 or 11** | You're on it | — |
| **PowerShell 7+** | `pwsh --version` | [Install PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows) |
| **A Global Administrator** in the target tenant | You, or someone who can click "Accept" once | Needed for the one-time consent step (Step 8) |

You do **not** need the .NET SDK for this guide — that's only for building the EXE
([BUILDING.md](BUILDING.md)).

Open a **PowerShell 7** window (`pwsh`) and `cd` into the project folder before running any
command below.

---

# Part A — Set up your own app registration

## Step 1 — Get the code

Clone (or download) the repo and open a PowerShell 7 terminal in the folder:

```powershell
git clone https://github.com/TrogdorTheMan/SP-MembershipManager.git
cd SP-MembershipManager
```

## Step 2 — Create the app registration in Entra ID

This is the identity the tool signs in as.

1. Go to [portal.azure.com](https://portal.azure.com) and sign in with a **Global Admin**
   account.
2. Navigate to **Entra ID → App registrations → + New registration**.
3. Fill in:
   - **Name:** `SP-MembershipManager` (anything you like)
   - **Supported account types:** *Accounts in any organizational directory (Multitenant)*
   - **Redirect URI:** leave blank for now.
4. Click **Register.**
5. On the app's **Overview** page, copy the **Application (client) ID** — you'll need it in
   Step 5. This is a GUID like `630f7dac-df2b-4586-a6b4-e83acbf4e91e`.

### Add the API permissions

The tool needs read/write access to SharePoint and read access to users and groups.

6. Go to **API permissions → + Add a permission** and add each of these as
   **Application permissions** (not Delegated):

   | API | Permission |
   |-----|------------|
   | **SharePoint** | `Sites.FullControl.All` |
   | **Microsoft Graph** | `User.ReadBasic.All` |
   | **Microsoft Graph** | `Sites.Read.All` |
   | **Microsoft Graph** | `GroupMember.Read.All` |

7. Don't click "Grant admin consent" here yet — you'll do the consent step properly in
   **Step 8** (it's the same thing, but the tool gives you a link that lands on a friendly
   confirmation page).

### Register the consent redirect URI

The consent step (Step 8) sends the admin to a small "you're all set" web page after they
approve. That page's address has to be registered on your app or Entra will reject the
redirect.

8. Go to **Authentication → + Add a platform → Web**, and add this redirect URI:

   ```
   https://trogdortheman.github.io/SP-MembershipManager/consent-complete.html
   ```

   That's a public confirmation page shipped with this project — you can use it as-is. (If
   you'd rather host your own, change the `redirect_uri` in the consent URL that
   `SP-MembershipManager.ps1` builds — search the script for `consent-complete.html` — and
   register your own URL here instead.)
9. Click **Save.**

## Step 3 — Generate a certificate

The tool authenticates with a certificate instead of a password. Run this in PowerShell 7 to
create a fresh self-signed cert (valid 2 years):

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

# Private key — this is what the tool uses. Keep it secret; treat it like a password.
$password = Read-Host "Choose a password for the pfx" -AsSecureString
Export-PfxCertificate -Cert $cert -FilePath ".\sp-mm.pfx" -Password $password

# Public key — this is what you upload to Entra.
Export-Certificate -Cert $cert -FilePath ".\sp-mm.cer"
```

Remember the password you typed — it goes into `app-config.json` in Step 6. You now have two
files in the project folder:

- `sp-mm.pfx` — private key (stays with the tool; **never** commit it or email it)
- `sp-mm.cer` — public key (safe to upload; you'll do that next)

> Renewing an expiring cert later? See **[CERT-RENEWAL.md](CERT-RENEWAL.md)**.

## Step 4 — Upload the public key to your app registration

1. Back in the portal: **Entra ID → App registrations → SP-MembershipManager →
   Certificates & secrets → Certificates tab → Upload certificate.**
2. Select the **`sp-mm.cer`** file (the public one — never upload the `.pfx`).
3. Add a description like `Created 2026-07` and click **Add.**

## Step 5 — Point the tool at your app registration

Open `SP-MembershipManager.ps1` and find this line near the top (around line 114):

```powershell
$script:AppClientId       = "630f7dac-df2b-4586-a6b4-e83acbf4e91e"
```

Replace the GUID with **your** Application (client) ID from Step 2:

```powershell
$script:AppClientId       = "<your-application-client-id>"
```

Save the file.

## Step 6 — Fill in `app-config.json`

Copy the example and open the copy:

```powershell
Copy-Item app-config.example.json app-config.json
```

Edit `app-config.json` so it looks like this (leave the `Gate*` fields empty for now — they're
the optional sign-in gate, covered at the end):

```json
{
  "CertificatePath": ".\\sp-mm.pfx",
  "CertificatePassword": "the-password-you-chose-in-step-3",
  "CertificatePasswordEncrypted": false,
  "Tenant": "yourtenant.onmicrosoft.com",
  "GateClientId": "",
  "GateGroupId": "",
  "GateRequestContact": ""
}
```

- **`CertificatePath`** — path to your `.pfx`. `.\sp-mm.pfx` is right if it's in the same
  folder.
- **`CertificatePassword`** — the plaintext password from Step 3. This is temporary: on the
  first successful connect the tool encrypts it with Windows DPAPI and overwrites this field
  with a ciphertext blob, and flips `CertificatePasswordEncrypted` to `true`. The plaintext
  never stays on disk.
- **`Tenant`** — your tenant, e.g. `contoso.onmicrosoft.com`.

## Step 7 — Grant admin consent

The app needs a one-time approval so it's allowed to use those permissions in the tenant.

The easiest way: launch the tool (Step 8). If consent is missing, it detects that, opens the
consent page in your browser automatically, and offers a **Relaunch** button once you're done.

If you'd rather do it up front, have a **Global Admin** open this URL (swap in **your** client
ID) and sign in:

```
https://login.microsoftonline.com/common/adminconsent?client_id=<your-application-client-id>&redirect_uri=https://trogdortheman.github.io/SP-MembershipManager/consent-complete.html
```

They'll see the list of permissions (SharePoint read/write, basic user + group read). After
they click **Accept**, they land on the confirmation page and you're done — this holds for
everyone in the tenant, no per-user setup.

## Step 8 — Run it

```powershell
.\SP-MembershipManager.ps1
```

A dialog asks for your **SharePoint Admin URL** — e.g. `https://yourtenant-admin.sharepoint.com`.
Enter it and the tool connects, loads your site list, and opens the main window.

That's it — you're set up. Day-to-day usage is in **[USAGE.md](USAGE.md)**.

---

# Part B — Deploy to another tenant with an existing app

Use this when the app registration already exists (you completed Part A once, or someone
handed you a configured build) and you just want the tool working in a **different** tenant.
No new app registration, no new certificate.

Because the app is registered as **multitenant**, the only per-tenant requirements are (1) a
Global Admin in that tenant grants consent once, and (2) a config file pointing at that tenant.

## Step 1 — Grant admin consent in the new tenant

A **Global Admin of the target tenant** opens this URL and signs in (swap in the Application
(client) ID of your app registration — the same one set as `$script:AppClientId` in
`SP-MembershipManager.ps1`):

```
https://login.microsoftonline.com/common/adminconsent?client_id=<your-application-client-id>&redirect_uri=https://trogdortheman.github.io/SP-MembershipManager/consent-complete.html
```

They click **Accept** on the permissions list and land on the confirmation page. That's the
only tenant-side action needed.

> **Already consented before, but group access isn't showing?** If the tenant consented
> before `GroupMember.Read.All` was added to the app, have the admin visit the URL again to
> pick up the new permission. The tool still works without it — group-based access just won't
> appear.

## Step 2 — Supply the config for that tenant

How the client gets configured depends on how you're delivering the tool:

- **Running from source or a plain EXE:** place `app-config.json` (with that tenant's `Tenant`
  value) and the `.pfx` next to the script/EXE. Same config shape as
  [Part A, Step 6](#step-6--fill-in-app-configjson).
- **Self-contained EXE** (built with the cert + tenant baked in via
  [BUILDING.md](BUILDING.md)): nothing to copy — the tenant and cert are already inside the
  EXE. Just hand over the single file.

## Step 3 — Run it

Launch the tool, enter the target tenant's SharePoint Admin URL when prompted (or, for a
build made with `-LockedAdminUrl`, it's already pre-filled and locked), and you're connected.

---

## Optional — restrict who can run the tool (sign-in gate)

By default, anyone who can launch the tool inherits its SharePoint access. The optional
**sign-in gate** makes each user sign in interactively and only lets through members of an
Entra security group you choose. It needs a second (public-client) app registration and a
couple of config values.

That's its own short setup — see
**[Restricting who can use the app](README.md#restricting-who-can-use-the-app-sign-in-gate)**
in the README. Everything above works fine without it; you can add the gate later.

---

## Where to go next

- **[BUILDING.md](BUILDING.md)** — package everything into a single distributable `.exe`
- **[USAGE.md](USAGE.md)** — day-to-day use once it's connected
- **[CERT-RENEWAL.md](CERT-RENEWAL.md)** — when the certificate is nearing expiry
- **[docs/ACCEPTANCE-TESTS.md](docs/ACCEPTANCE-TESTS.md)** — verify a build behaves correctly
