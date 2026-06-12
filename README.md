# SP-MembershipManager

> [!WARNING]
> **Known issue — first-time deployment on a new tenant**
>
> If admin consent has not yet been granted for the tenant you're deploying to, the tool will fail on the first launch with a connection error. Grant consent when prompted, then **relaunch the tool** — it will work correctly on the second run. This is a workflow handling bug actively being worked on. See the [Deploying to a new tenant](#deploying-to-a-new-tenant) section for the full first-run steps.

A Windows GUI tool that lets authorized users manage SharePoint Online site membership without needing SharePoint admin training. Point it at any Microsoft 365 tenant and it handles the rest.

## What it does

- Search for any employee by name or email
- See every SharePoint site they have access to and what role they hold
- Add them to a site as Owner, Member, or Visitor
- Remove them from a site
- Logs every action to `C:\temp\SP-MembershipManager\Logs\`

## Architecture

![Architecture](docs/architecture.svg)

## Requirements

- Windows 10/11
- PowerShell 7+
- [PnP.PowerShell](https://pnp.github.io/powershell/) (installed automatically on first run)

No SharePoint Administrator role is required for the end user running the tool. Authentication is handled via an app-only service principal with pre-granted permissions.

Startup shows a loading screen while the tool connects and fetches the site list in the background, so the main window opens ready to use.

The certificate password in `app-config.json` is encrypted with Windows DPAPI on first run and replaced with a ciphertext blob. The plaintext password never persists on disk after that point. Encryption is tied to the Windows user account that performed the first run — the password cannot be decrypted by a different user or on a different machine.

Site membership lookups run in parallel (up to 8 concurrent connections) using PowerShell runspaces, keeping scan times low even across large tenants. The UI stays responsive during scans.

## Running from source

Before running, make sure `app-config.json` and `sp-mm.pfx` are in the same directory as the script. Copy `app-config.example.json` to `app-config.json` and fill in your tenant details.

```powershell
.\SP-MembershipManager.ps1
```

A dialog will prompt for your SharePoint Admin URL (e.g. `https://yourtenant-admin.sharepoint.com`).

## Building a standalone .exe

Every push to `main` and every release is built automatically by GitHub Actions. Download the artifact from the [Actions tab](https://github.com/TrogdorTheMan/SP-MembershipManager/actions) or grab the `.exe` attached to any [release](https://github.com/TrogdorTheMan/SP-MembershipManager/releases).

To build locally, install the [.NET 8 SDK](https://dotnet.microsoft.com/download) and run:

```powershell
.\build.ps1
```

The compiled executable is written to `build\output\SP-MembershipManager.exe`. You will still need `app-config.json` and `sp-mm.pfx` in the same folder as the exe — see the Deploying section below. PnP.PowerShell is installed automatically on first run if not already present.

## Deploying to a new tenant

Place the following three files in the same folder:

- `SP-MembershipManager.exe` — download from the [Actions tab](https://github.com/TrogdorTheMan/SP-MembershipManager/actions) or a [release](https://github.com/TrogdorTheMan/SP-MembershipManager/releases)
- `app-config.json` — copy from `app-config.example.json` and fill in your tenant details; the `CertificatePath` field should be the filename of your pfx (e.g. `sp-mm.pfx`)
- `sp-mm.pfx` — the certificate for your Entra ID app registration (filename must match `CertificatePath` in `app-config.json`)

Before first use, a Global Admin in the target tenant needs to grant consent for the app. This is a one-time step per tenant.

Have the Global Admin visit this URL and sign in with their admin account:

```
https://login.microsoftonline.com/common/adminconsent?client_id=630f7dac-df2b-4586-a6b4-e83acbf4e91e&redirect_uri=https://trogdortheman.github.io/SP-MembershipManager/consent-complete.html
```

They will see a consent prompt listing the permissions the app is requesting (SharePoint read/write across all sites, basic user directory and group membership read access). After they click Accept, the tool will work for anyone in that tenant with no further setup.

> **Existing tenants:** if you previously consented before `GroupMember.Read.All` was added, have the Global Admin visit the consent URL again to grant the new permission. The tool will still work without it — group-based access just won't appear in results.

## Using your own app registration

If you fork this repo, you can substitute your own multi-tenant Entra ID app registration. Register an app at [portal.azure.com](https://portal.azure.com) with:

- Supported account types: Accounts in any organizational directory (Multitenant)
- Application permissions: `SharePoint > Sites.FullControl.All`, `Microsoft Graph > User.ReadBasic.All`, `Microsoft Graph > Sites.Read.All`, `Microsoft Graph > GroupMember.Read.All`

Then replace `$script:AppClientId` near the top of `SP-MembershipManager.ps1` with your own Client ID, generate a certificate for your app registration, and update `app-config.json` with the cert path and your tenant name.

## Restricting who can use the app (sign-in gate)

By default the tool runs with the app-only certificate, so anyone who can launch the exe inherits its access. The optional sign-in gate closes that gap: on every launch the user must sign in interactively, and access continues only if they belong to a security group you designate in Microsoft Entra. The gate runs before any SharePoint connection, so an unauthorized user never reaches the privileged session.

The gate is **off until you configure it** (the `GateClientId` and `GateGroupId` fields in `app-config.json` are empty by default). To turn it on:

**1. Pick the Microsoft Entra security group that authorizes use.** In Entra ID, choose or create a security group whose members are allowed to run the tool, then copy its **Object ID**. This is the single most important step — only members of this group will be allowed past the sign-in. Put the Object ID in `GateGroupId`.

**2. Create a dedicated public-client app registration** (keep this separate from the certificate app-only registration above). At [portal.azure.com](https://portal.azure.com) → App registrations → New registration:

- Supported account types: Accounts in any organizational directory (Multitenant)
- **Authentication → Add a platform → Mobile and desktop applications**, add the redirect URI `http://localhost`
- **API permissions → Microsoft Graph → Delegated:** `openid` and `profile` (no Graph data permissions are needed — group membership is read from the sign-in token, not from Graph)
- **Token configuration → Add groups claim:** emit groups in the **ID token**. Choose **Groups assigned to the application** (recommended — it keeps the claim small and avoids the 200-group overage that would otherwise block users in many groups), then assign your authorizing group to the app under Enterprise applications. If you instead choose **Security groups**, users who belong to more than ~200 groups will be denied with guidance to switch to the assigned-groups option.

**3. Fill in `app-config.json`.** Set `GateClientId` to the new registration's Application (client) ID and `GateGroupId` to the group Object ID from step 1. Provide both or neither — setting only one is treated as a misconfiguration and blocks startup so the gate can never silently fail open. Optionally set `GateRequestContact` to an email address or URL; a denied user then gets a **Request Access** button that opens it (a bare email becomes a pre-filled `mailto:`).

Once configured, users outside the group see a friendly Access Denied dialog (with the Request Access button when a contact is set) and the tool exits; cancelling the sign-in also exits.

## Usage

See [USAGE.md](USAGE.md) for day-to-day usage instructions and known behaviors.

## Roadmap

- **First-run consent flow** *(in progress)* — the tool already detects missing admin consent and shows a guided dialog; auto-relaunch after consent is being stabilized
- **Critical site flagging** — designate sensitive sites in config so they render with a red background in the site access grid as a visual warning
- **Per-client build config** — bake a locked admin URL, critical site list, and feature flags into each compiled exe at build time so a client's exe can't be pointed at the wrong tenant
- **Admin URL validation** — clicking Continue on the admin URL prompt with no input currently closes the app silently; will show a validation message instead

## Code Signing

An application for free code signing through the [SignPath Foundation](https://signpath.org) open source program was submitted on 2026-06-09 and is pending review. If approved, releases will be signed. If not, we'll figure out next steps.

Until signing is in place, Windows Defender may flag the executable as a false positive. This is a known issue with executables that embed and run scripts. To work around it, add a Defender exclusion for the exe after downloading:

**Windows Security → Virus & threat protection → Manage settings → Add or remove exclusions → Add file → select SP-MembershipManager.exe**

## License

GPLv3. See [LICENSE](LICENSE).
