# SP-MembershipManager

A Windows GUI tool that lets authorized users manage SharePoint Online site membership without needing SharePoint admin training. Point it at any Microsoft 365 tenant and it handles the rest.

## What it does

- Search for any employee by name or email
- See every SharePoint site they have access to and what role they hold
- Add them to a site as Owner, Member, or Visitor
- Remove them from a site
- Logs every action to `C:\temp\SP-MembershipManager\Logs\`

## Requirements

- Windows 10/11
- PowerShell 5.1+
- [PnP.PowerShell](https://pnp.github.io/powershell/) (installed automatically on first run)
- An account with SharePoint Administrator role in the target tenant

## Running from source

```powershell
.\SP-MembershipManager.ps1
```

You will be prompted for your SharePoint Admin URL (e.g. `https://yourtenant-admin.sharepoint.com`) and then asked to sign in interactively.

## Building a standalone .exe

Install [ps2exe](https://github.com/MScholtes/PS2EXE) and then run:

```powershell
.\build.ps1
```

The compiled executable is written to `build\output\SP-MembershipManager.exe`. End users still need PnP.PowerShell installed.

## Deploying to a new tenant

1. Have a tenant admin sign in when prompted on first launch. PnP.PowerShell will handle the interactive login flow and prompt for admin consent if needed.
2. No app registrations or config files required.

## License

MIT. See [LICENSE](LICENSE).
