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

There's also an optional
**[Part C — the sign-in gate](#part-c--restrict-who-can-run-the-tool-sign-in-gate-optional)**,
which restricts who can run the tool to a security group you choose. Do it after Part A,
or skip it entirely.

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
| **A Global Administrator** in the target tenant | You, or someone who can click "Accept" once | Needed for the one-time consent step (Step 6) |

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

> **Downloaded a ZIP instead of cloning?** Windows marks downloaded files as untrusted and
> will refuse to run the script later (*"…is not digitally signed"*). After extracting, run
> this once from the project folder to clear the block:
>
> ```powershell
> Get-ChildItem -Recurse | Unblock-File
> ```

## Step 2 — Create the app registration in Entra ID

This is the identity the tool signs in as.

1. Go to [portal.azure.com](https://portal.azure.com) and sign in with a **Global Admin**
   account.
2. In the **search bar at the top**, type `App registrations` and open it (this works the
   same whether your org uses portal.azure.com or entra.microsoft.com). Click
   **+ New registration**.
3. Fill in:
   - **Name:** `SP-MembershipManager` (anything you like)
   - **Supported account types:** *Accounts in any organizational directory (Multitenant)*
   - **Redirect URI:** leave blank for now.
4. Click **Register.**
5. On the app's **Overview** page, copy the **Application (client) ID** and paste it
   somewhere handy — you'll need it in **Step 5 — Fill in `app-config.json`**. It's a GUID
   like `a1b2c3d4-0000-1111-2222-333344445555`.

### Add the API permissions

The tool needs read/write access to SharePoint and read access to users and groups. You'll
add four **Application** permissions — three from Microsoft Graph, one from SharePoint:

1. On your new app's page, go to **API permissions → + Add a permission**.
2. Pick the big **Microsoft Graph** tile, then choose **Application permissions** (not
   Delegated — this choice only appears *after* you pick the API).
3. Use the search box to find each of these and tick its checkbox — you can tick all three
   before moving on:
   - `User.ReadBasic.All`
   - `Sites.Read.All`
   - `GroupMember.Read.All`
4. Click **Add permissions** at the bottom.
5. Click **+ Add a permission** again. This time **scroll down past Microsoft Graph** and
   pick **SharePoint**, then **Application permissions**, tick `Sites.FullControl.All`, and
   click **Add permissions**.
6. **Checkpoint** — the permissions list should now show these four rows, each with
   **Type = Application**:

   | API | Permission | Type |
   |-----|------------|------|
   | **Microsoft Graph** | `User.ReadBasic.All` | Application |
   | **Microsoft Graph** | `Sites.Read.All` | Application |
   | **Microsoft Graph** | `GroupMember.Read.All` | Application |
   | **SharePoint** | `Sites.FullControl.All` | Application |

   (You'll also see a Delegated `User.Read` row — Entra adds that to every new registration
   by default. Leave it; it's harmless.)

7. Don't click "Grant admin consent" here yet — you'll do the consent step properly in
   **Step 6** (it's the same thing, but the tool gives you a link that lands on a friendly
   confirmation page).

### Register the consent redirect URI

The consent step (Step 6) sends the admin to a small "you're all set" web page after they
approve. That page's address has to be registered on your app or Entra will reject the
redirect.

1. Go to **Authentication**. The portal has two versions of this page, and which one you
   get varies — the steps differ slightly:
   - **New experience** (page titled *Authentication (Preview)*, with a "new and improved
     experience" banner): on the **Redirect URI configuration** tab, click
     **Add Redirect URI**, pick **Web** as the platform, and paste the URI below.
   - **Classic experience**: click **+ Add a platform → Web** and paste the URI below.

   ```
   https://trogdortheman.github.io/SP-MembershipManager/consent-complete.html
   ```

   That's a public confirmation page shipped with this project — you can use it as-is. (If
   you'd rather host your own, change the `redirect_uri` in the consent URL that
   `SP-MembershipManager.ps1` builds — search the script for `consent-complete.html` — and
   register your own URL here instead.)
2. Confirm/save, and check the URI now appears in the redirect URI list.

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

Remember the password you typed — it goes into `app-config.json` in Step 5. You now have two
files in the project folder:

- `sp-mm.pfx` — private key (stays with the tool; **never** commit it or email it)
- `sp-mm.cer` — public key (safe to upload; you'll do that next)

> Renewing an expiring cert later? See **[CERT-RENEWAL.md](CERT-RENEWAL.md)**.

## Step 4 — Upload the public key to your app registration

1. Back in the portal: **Entra ID → App registrations → SP-MembershipManager →
   Certificates & secrets → Certificates tab → Upload certificate.**
2. Select the **`sp-mm.cer`** file (the public one — never upload the `.pfx`).
3. Add a description like `Created 2026-07` and click **Add.**

## Step 5 — Fill in `app-config.json`

This is where you point the tool at **your** app registration and tenant — no code editing
required. Copy the example and open the copy in Notepad:

```powershell
Copy-Item app-config.example.json app-config.json
notepad app-config.json
```

Edit `app-config.json` so it looks like this (leave the `Gate*` fields empty for now — they're
the optional sign-in gate, covered at the end):

```json
{
  "AppClientId": "<your-application-client-id>",
  "CertificatePath": ".\\sp-mm.pfx",
  "CertificatePassword": "the-password-you-chose-in-step-3",
  "CertificatePasswordEncrypted": false,
  "Tenant": "yourtenant.onmicrosoft.com",
  "GateClientId": "",
  "GateGroupId": "",
  "GateRequestContact": ""
}
```

- **`AppClientId`** — the **Application (client) ID** you copied in Step 2. This is what makes
  the tool sign in as *your* app registration. (It ships empty; the tool won't run until you
  set it.) Paste **just the GUID — no `<` `>` brackets**. A finished value looks like:
  `"AppClientId": "a1b2c3d4-0000-1111-2222-333344445555"`
- **`CertificatePath`** — path to your `.pfx`. `.\sp-mm.pfx` is right if it's in the same
  folder. The doubled backslash (`.\\sp-mm.pfx`) is **not a typo** — JSON uses `\` as an
  escape character, so every backslash in a path has to be written twice.
- **`CertificatePassword`** — yes, type the real password from Step 3 here, as plain text.
  It doesn't stay that way: on the first successful connect the tool encrypts it with
  Windows DPAPI, overwrites this field with the encrypted version, and flips
  `CertificatePasswordEncrypted` to `true` on its own. Leave that flag set to `false` —
  it describes what's in the field right now (plaintext), and the tool manages it from
  there. Setting it to `true` by hand would make the tool try to decrypt your plaintext
  and fail.
- **`Tenant`** — your tenant's `.onmicrosoft.com` name, e.g. `contoso.onmicrosoft.com`.
  Not sure what yours is? In the portal, search for **Microsoft Entra ID** and look at
  **Overview → Primary domain**. If your org signs in with a custom domain (e.g.
  `contoso.com`), don't use that — use the `.onmicrosoft.com` name listed under
  **Custom domain names** instead.

> **JSON is picky.** Keep every quote mark and comma exactly as in the example, and edit in
> Notepad — word processors replace straight quotes with curly ones, which breaks the file.

## Step 6 — Grant admin consent

The app needs a one-time approval so it's allowed to use those permissions in the tenant.

The easiest way: launch the tool (Step 7). If consent is missing, it detects that, opens the
consent page in your browser automatically, and offers a **Relaunch** button once you're done.

If you'd rather do it up front, have a **Global Admin** open this URL (swap in **your** client
ID — just the GUID, no `<` `>` brackets) and sign in:

```
https://login.microsoftonline.com/common/adminconsent?client_id=<your-application-client-id>&redirect_uri=https://trogdortheman.github.io/SP-MembershipManager/consent-complete.html
```

They'll see the list of permissions (SharePoint read/write, basic user + group read). After
they click **Accept**, they land on the confirmation page and you're done — this holds for
everyone in the tenant, no per-user setup.

> **Consent can take a few minutes to propagate.** If the tool gets an authorization error
> right after the admin clicks Accept, nothing is wrong — wait five minutes and relaunch.

## Step 7 — Run it

Run this **from a PowerShell 7 window** — don't double-click the `.ps1` in Explorer.
(Windows hands double-clicked scripts to the old built-in PowerShell 5.1, which this tool
doesn't support — the window just flashes and closes.)

```powershell
.\SP-MembershipManager.ps1
```

The **first launch may pause for a minute or two** while it installs the PnP.PowerShell
module (`PnP.PowerShell module not found. Installing...`). That's normal, needs internet
access, and only happens once.

A dialog asks for your **SharePoint Admin URL**. That's your tenant name (the part before
`.onmicrosoft.com`) with `-admin` attached — for tenant `contoso.onmicrosoft.com` it's:

```
https://contoso-admin.sharepoint.com
```

Enter it and the tool connects, loads your site list, and opens the main window.

That's it — you're set up. Day-to-day usage is in **[USAGE.md](USAGE.md)**. Working, and
ready to package it for your company as a single EXE? Head to **[BUILDING.md](BUILDING.md)**.

---

# Part B — Deploy to another tenant with an existing app

Use this when the app registration already exists (you completed Part A once, or someone
handed you a configured build) and you just want the tool working in a **different** tenant.
No new app registration, no new certificate.

Because the app is registered as **multitenant**, the only per-tenant requirements are (1) a
Global Admin in that tenant grants consent once, and (2) a config file pointing at that tenant.

## Step 1 — Grant admin consent in the new tenant

A **Global Admin of the target tenant** opens this URL and signs in (swap in the Application
(client) ID of your app registration — the same `AppClientId` you set in `app-config.json`, or
baked into the EXE with `build.ps1 -AppClientId`):

```
https://login.microsoftonline.com/common/adminconsent?client_id=<your-application-client-id>&redirect_uri=https://trogdortheman.github.io/SP-MembershipManager/consent-complete.html
```

They click **Accept** on the permissions list and land on the confirmation page.

> **Using the sign-in gate?** The gate app needs its **own** admin consent in the new
> tenant as well — same URL shape with the gate's client ID, or just launch the tool and
> use the consent dialog it shows. See [Part C, Step 6](#step-6--grant-admin-consent-for-the-gate-app).

> **Already consented before, but group access isn't showing?** If the tenant consented
> before `GroupMember.Read.All` was added to the app, have the admin visit the URL again to
> pick up the new permission. The tool still works without it — group-based access just won't
> appear.

## Step 2 — Supply the config for that tenant

How the client gets configured depends on how you're delivering the tool:

- **Running from source or a plain EXE:** place `app-config.json` (with that tenant's `Tenant`
  value, plus your `AppClientId`) and the `.pfx` next to the script/EXE. Same config shape as
  [Part A, Step 5](#step-5--fill-in-app-configjson).

  > **Handing this to someone else?** Their copy of the config must start with the
  > **plaintext** cert password and `CertificatePasswordEncrypted: false` — an encrypted
  > value from *your* machine won't decrypt on theirs (it re-encrypts for their account on
  > first run). Send the password through a password manager or other secure channel, never
  > in the same email as the files.
- **Self-contained EXE** (built with the cert + tenant baked in via
  [BUILDING.md](BUILDING.md)): nothing to copy — the tenant and cert are already inside the
  EXE. Just hand over the single file.

## Step 3 — Run it

Launch the tool, enter the target tenant's SharePoint Admin URL when prompted (or, for a
build made with `-LockedAdminUrl`, it's already pre-filled and locked), and you're connected.

---

# Part C — Restrict who can run the tool (sign-in gate, optional)

By default, anyone who can launch the tool inherits its full SharePoint access. The
**sign-in gate** closes that gap: each user must sign in interactively, and only members of
an Entra security group you choose get through. Everything in Parts A and B works fine
without it — you can add the gate any time.

The gate needs one security group, one extra (public-client) app registration, and two
config values.

## Step 1 — Pick the security group

1. In the portal, search for **Groups** and open it. Choose an existing security group or
   click **New group** (type: **Security**) and add the people allowed to run the tool.
2. Open the group and copy its **Object ID** — a GUID. This goes in `GateGroupId` later.
   Only members of this group will get past the sign-in.

## Step 2 — Create the gate app registration

This is a second, separate registration — don't reuse the one from Part A (that one holds
the certificate; this one only identifies the sign-in prompt).

1. **App registrations → + New registration.**
   - **Name:** `SP-MembershipManager Gate` (anything you like)
   - **Supported account types:** *Accounts in any organizational directory (Multitenant)*
2. Click **Register**, then copy the **Application (client) ID** from the Overview page —
   this goes in `GateClientId` later.
3. **Authentication** → add a platform of type **Mobile and desktop applications** and
   tick/enter the redirect URI `http://localhost`. (On the new *Authentication (Preview)*
   page: **Add Redirect URI → Mobile and desktop applications → `http://localhost`**.)
4. **API permissions**: the default delegated `User.Read` is fine to leave as-is — the gate
   only needs `openid` and `profile`, which sign-in includes automatically. No Graph data
   permissions are needed; group membership is read from the sign-in token.

## Step 3 — Emit the groups claim

The gate checks group membership from the ID token, so the token has to carry it:

1. On the gate app: **Token configuration → + Add groups claim.**
2. Select **Groups assigned to the application** (recommended — keeps the token small; the
   alternative *Security groups* option breaks for users in more than ~200 groups).
3. Under **ID**, make sure the claim is emitted in the **ID token**. Save.

## Step 4 — Assign the group to the gate app

Because the claim is "groups **assigned** to the application," the authorizing group must
actually be assigned, or the token never carries it and everyone is denied:

1. Search the portal for **Enterprise applications** and open the gate app's entry
   (same name as the registration).
2. **Users and groups → + Add user/group** → select the security group from Step 1 → Assign.

## Step 5 — Configure the tool

Both values, or neither — setting only one blocks startup so the gate can never silently
fail open.

- **Running from source / plain EXE:** in `app-config.json`, set `GateClientId` (Step 2)
  and `GateGroupId` (Step 1). Optionally set `GateRequestContact` to an email or URL —
  denied users then get a **Request Access** button that opens it.
- **Distributable EXE:** bake the same values in at build time with
  `build.ps1 -GateClientId … -GateGroupId …` (or the wizard's Sign-In Gate fields) —
  baked values override `app-config.json`, so the gate can't be stripped by editing a
  text file next to the EXE. See [BUILDING.md](BUILDING.md).

## Step 6 — Grant admin consent for the gate app

Like the Part A app, the gate app needs a one-time admin consent **in each tenant where
people sign in**. Easiest path: just launch the tool — if consent is missing, it shows a
consent dialog with the URL and a **Copy URL** button for your Global Admin. To do it up
front instead, the admin opens (gate client ID from Step 2, no `<` `>` brackets):

```
https://login.microsoftonline.com/common/adminconsent?client_id=<your-gate-client-id>&redirect_uri=https://trogdortheman.github.io/SP-MembershipManager/consent-complete.html
```

> This is a **second, separate consent** from the Part A / Part B one — consenting the
> certificate app does not cover the gate app.

## Step 7 — Verify the gate

Don't skip this — it's the security boundary:

1. Launch as a **member** of the group → sign-in succeeds, the tool opens.
2. Launch as someone **not in the group** → the Access Denied dialog appears (with the
   Request Access button if you set a contact) and the tool exits.

If a group member is denied: check Step 4 (group actually assigned to the enterprise app)
and Step 3 (claim emitted in the **ID** token) — those two cover nearly every gate failure.

---

## If something goes wrong

The predictable snags, and what each one means:

| What you see | What it means | Fix |
|--------------|---------------|-----|
| A terminal window flashes open and instantly closes, no error shown | The script was double-clicked, so it ran in the old Windows PowerShell 5.1 | Open **PowerShell 7** (`pwsh`), `cd` to the project folder, and run `.\SP-MembershipManager.ps1` from there (Step 7) |
| *"…is not digitally signed"* or *"running scripts is disabled"* | Windows blocked the downloaded files | From the project folder run `Get-ChildItem -Recurse \| Unblock-File`, then relaunch (see Step 1) |
| Authorization/permission error right after granting consent | Consent hasn't propagated yet | Nothing is wrong — wait ~5 minutes and relaunch |
| *"app-config.json is missing AppClientId"* | The `AppClientId` field is empty | Paste your app registration's Application (client) ID — just the GUID (Step 5) |
| Config error dialog as soon as it launches | `app-config.json` isn't valid JSON | Re-copy `app-config.example.json` and re-edit in Notepad; look for a missing comma, leftover `<` `>` brackets, or curly “smart quotes” |
| Certificate/password error when connecting | Wrong `.pfx` password in the config | Set `CertificatePasswordEncrypted` to `false` and re-enter the password from Step 3 |
| *"Could not decrypt the certificate password"* | The config was encrypted on a different machine or user account | Set `CertificatePasswordEncrypted` to `false`, restore the plaintext password, relaunch |
| First launch sits on `Installing...` | It's downloading the PnP.PowerShell module | Give it a minute or two; it needs internet access and only happens once |

---

## Where to go next

- **[BUILDING.md](BUILDING.md)** — package everything into a single distributable `.exe`
- **[USAGE.md](USAGE.md)** — day-to-day use once it's connected
- **[CERT-RENEWAL.md](CERT-RENEWAL.md)** — when the certificate is nearing expiry
- **[docs/ACCEPTANCE-TESTS.md](docs/ACCEPTANCE-TESTS.md)** — verify a build behaves correctly
