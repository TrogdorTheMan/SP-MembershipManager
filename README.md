# SP-MembershipManager

A Windows GUI tool that lets authorized users manage SharePoint Online site membership without needing SharePoint admin training. Point it at any Microsoft 365 tenant and it handles the rest.

## What it does

- Search for any employee by name or email
- See every SharePoint site they have access to and what role they hold
- Add them to a site as Owner, Member, or Visitor
- Remove them from a site
- Logs every action to `C:\temp\SP-MembershipManager\Logs\`

## Architecture

```mermaid
flowchart LR
    subgraph exe["SP-MembershipManager.exe (end user machine)"]
        UI["PowerShell + WinForms UI"]
        PnP["PnP.PowerShell"]
        CFG["app-config.json"]
        CERT["sp-mm.pfx (cert)"]
    end

    subgraph your["TrogdorTheMan's Azure Tenant"]
        APP["Entra ID App Registration\nClient ID + Certificate\n(multi-tenant, registered once)"]
    end

    subgraph client["Client Tenant (autonw)"]
        SP_svc["Service Principal\n(created by one-time admin consent)"]
        SPO["SharePoint Online\nSites.FullControl.All"]
        GRAPH["Microsoft Graph\nUser.ReadBasic.All"]
    end

    exe -- "cert auth" --> APP
    APP -. "trust" .-> SP_svc
    SP_svc --> SPO
    SP_svc --> GRAPH
    exe -- "PnP operations" --> client
```

## Requirements

- Windows 10/11
- PowerShell 5.1+
- [PnP.PowerShell](https://pnp.github.io/powershell/) (installed automatically on first run)

No SharePoint Administrator role is required for the end user running the tool. Authentication is handled via an app-only service principal with pre-granted permissions.

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
https://login.microsoftonline.com/common/adminconsent?client_id=630f7dac-df2b-4586-a6b4-e83acbf4e91e
```

They will see a consent prompt listing the permissions the app is requesting (SharePoint read/write across all sites, basic user directory access). After they click Accept, the tool will work for anyone in that tenant with no further setup.

## Using your own app registration

If you fork this repo, you can substitute your own multi-tenant Entra ID app registration. Register an app at [portal.azure.com](https://portal.azure.com) with:

- Supported account types: Accounts in any organizational directory (Multitenant)
- Application permissions: `SharePoint > Sites.FullControl.All`, `Microsoft Graph > User.ReadBasic.All`

Then replace `$script:AppClientId` and `$script:AppClientSecret` near the top of `SP-MembershipManager.ps1` with your own values.

## License

MIT. See [LICENSE](LICENSE).
