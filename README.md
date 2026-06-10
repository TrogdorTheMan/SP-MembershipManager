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
- PowerShell 5.1+
- [PnP.PowerShell](https://pnp.github.io/powershell/) (installed automatically on first run)

No SharePoint Administrator role is required for the end user running the tool. Authentication is handled via an app-only service principal with pre-granted permissions.

Site membership lookups run in parallel (up to 8 concurrent connections) using PowerShell runspaces, keeping scan times low even across large tenants.

## Running from source

```powershell
.\SP-MembershipManager.ps1
```

A dialog will prompt for your SharePoint Admin URL (e.g. `https://yourtenant-admin.sharepoint.com`).

## Building a standalone .exe

Install [ps2exe](https://github.com/MScholtes/PS2EXE) and then run:

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

- **DPAPI credential storage** — encrypt the cert password in `app-config.json` using Windows DPAPI, tied to the machine/user that set it up
- **Email search** — extend user search to match on email address in addition to display name
- **First-run consent check** — detect when admin consent hasn't been granted in the target tenant and surface the consent URL directly in the error dialog
- **Critical site flagging** — designate sensitive sites in config so they render with a red background in the site access grid as a visual warning
- **Per-client build config** — bake a locked admin URL, critical site list, and feature flags into each compiled exe at build time so a client's exe can't be pointed at the wrong tenant
- **User auth gate** — MSAL interactive login on launch with M365 security group membership check, preventing unauthorized use if the exe reaches the wrong hands; group ID baked in per-client at build time

## License

MIT. See [LICENSE](LICENSE).
