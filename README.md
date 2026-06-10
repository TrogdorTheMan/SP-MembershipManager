# SP-MembershipManager

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

```powershell
.\SP-MembershipManager.ps1
```

A dialog will prompt for your SharePoint Admin URL (e.g. `https://yourtenant-admin.sharepoint.com`).

## Building a standalone .exe

Every push to `main` and every release is built automatically by GitHub Actions. Download the artifact from the [Actions tab](https://github.com/TrogdorTheMan/SP-MembershipManager/actions) or grab the `.exe` attached to any [release](https://github.com/TrogdorTheMan/SP-MembershipManager/releases).

To build locally, install [PS12EXE](https://github.com/steve02081504/PS12EXE) and run:

```powershell
.\build.ps1
```

The compiled executable is written to `build\output\SP-MembershipManager.exe`. End users still need PnP.PowerShell installed.

## Deploying to a new tenant

Before first use, a Global Admin in the target tenant needs to grant consent for the app. This is a one-time step per tenant.

Have the Global Admin visit this URL and sign in with their admin account:

```
https://login.microsoftonline.com/common/adminconsent?client_id=630f7dac-df2b-4586-a6b4-e83acbf4e91e&redirect_uri=https://login.microsoftonline.com/common/oauth2/nativeclient
```

They will see a consent prompt listing the permissions the app is requesting (SharePoint read/write across all sites, basic user directory access). After they click Accept, the tool will work for anyone in that tenant with no further setup.

## Using your own app registration

If you fork this repo, you can substitute your own multi-tenant Entra ID app registration. Register an app at [portal.azure.com](https://portal.azure.com) with:

- Supported account types: Accounts in any organizational directory (Multitenant)
- Application permissions: `SharePoint > Sites.FullControl.All`, `Microsoft Graph > User.ReadBasic.All`, `Microsoft Graph > Sites.Read.All`

Then replace `$script:AppClientId` near the top of `SP-MembershipManager.ps1` with your own Client ID, generate a certificate for your app registration, and update `app-config.json` with the cert path and your tenant name.

## Roadmap

- **First-run consent check** — detect when admin consent hasn't been granted in the target tenant and surface the consent URL directly in the error dialog
- **Critical site flagging** — designate sensitive sites in config so they render with a red background in the site access grid as a visual warning
- **Per-client build config** — bake a locked admin URL, critical site list, and feature flags into each compiled exe at build time so a client's exe can't be pointed at the wrong tenant
- **User auth gate** — MSAL interactive login on launch with M365 security group membership check, preventing unauthorized use if the exe reaches the wrong hands; group ID baked in per-client at build time

## Code Signing

An application for free code signing through the [SignPath Foundation](https://signpath.org) open source program was submitted on 2026-06-09 and is pending review. Once approved, releases will be signed.

Until signing is in place, Windows Defender may flag the executable as a false positive when building locally. This is a known issue with PowerShell-compiled executables and does not affect builds produced by GitHub Actions.

**Option 1 — Build via GitHub Actions**

This repo includes a workflow at `.github/workflows/build.yml` that builds the exe on a GitHub-hosted Windows runner. To use it on a fork:

1. Fork the repo and go to **Actions** in your fork — enable workflows if prompted
2. Push a commit to `main` (or trigger the workflow manually via **Run workflow**)
3. Once the run completes, click into it and download the `SP-MembershipManager` artifact

Creating a release will also attach the exe directly to the release assets.

**Option 2 — Local build with Defender exclusion**

Add an exclusion for the PS12EXE module folder before running `build.ps1`:

**Windows Security → Virus & threat protection → Manage settings → Add or remove exclusions → Add folder → `%USERPROFILE%\Documents\PowerShell\Modules\PS12EXE`**

## License

MIT. See [LICENSE](LICENSE).
