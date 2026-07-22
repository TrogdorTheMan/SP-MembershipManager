# Using SP Membership Manager

This guide covers day-to-day usage and known behaviors to be aware of when managing SharePoint site membership.

## Basic Workflow

1. Launch `SP-MembershipManager.exe`
2. If the sign-in gate is enabled, a browser window opens for you to sign in. You must be a member of the approved security group to continue; if you are not, the tool shows an Access Denied message and closes. You sign in each time you launch the tool.
3. Enter your SharePoint Admin URL (e.g. `https://yourtenant-admin.sharepoint.com`) and click **Connect**
4. Search for an employee by name or email in the left panel
5. Select them from the results list — the tool will scan all sites and show every site they have access to and what role they hold
6. Use **Add direct member access** or **Remove direct member access** to make changes

## Known Behaviors

### Membership counts may appear off immediately after a change

After adding or removing a user, clicking **Refresh** right away can show an unexpected number of sites — for example, a user going from 8 sites to 10 instead of 9, or still showing a site they were just removed from.

**This is not a bug.** SharePoint Online does not apply membership changes instantly across all of its servers. Changes typically propagate within a few seconds, but during that window the tool may read stale or inaccurate data.

The success dialog that appears after an add or remove includes a short countdown for this reason. Once the countdown finishes and you dismiss the dialog, click **Refresh** and the count will be accurate.

**In short:** if the count looks wrong after a change, wait a few seconds and refresh again. If it continues beyond 2 or 3 refreshes, contact your help desk or whomever provided the tool to you.

### The Access column shows where access comes from

The grid includes an **Access** column that shows how a user's access was granted. Common values:

- **Direct** — the user was explicitly added to the site's Owners, Members, or Visitors group
- **via GroupName** — access comes from an Entra ID security group (e.g. "via SharePoint Power Users")
- **Site Admin** — the user is a site collection administrator, the highest SharePoint role
- When a user has both a direct entry and group-based access on the same site, the Access column shows the group name and the **Direct & Group** column shows ✓; these rows are highlighted in blue

Rows highlighted in **amber** indicate site collection administrators.

Rows highlighted in **light red** are critical sites designated when the tool was built (e.g. HR or Finance). If the Add/Remove buttons are disabled on a red row with a note saying *"This is a critical site — contact an administrator to manage access"*, access to that site is restricted to a designated admin group and you'll need to contact whoever provided the tool.

You can only remove access that is directly assigned. If the Access column shows only group or admin sources, the Remove button will be disabled. To remove group-based access, the security group membership itself needs to change.

### Site collection administrators can't be granted (or removed) with this tool

The Add dialog offers **Member**, **Owner**, and **Visitor** — these correspond to a site's three standard SharePoint groups, which is what this tool manages. **Site collection administrator** is a different kind of assignment that lives outside those groups. The tool *shows* site admins (amber rows, "Site Admin" in the Access column) but cannot grant or revoke that role — use the SharePoint admin center (**Sites → Active sites → [site] → Membership → Site admins**) for that.

### PnP.PowerShell installs on first run

The tool requires the PnP.PowerShell module. If it is not already installed on the machine, the tool will install it automatically before connecting. This is a one-time step and may take a minute or two the first time.

### Certificate renewal

The tool authenticates using a certificate registered in Entra ID. Certificates expire (typically after 1–2 years). See [CERT-RENEWAL.md](CERT-RENEWAL.md) for step-by-step renewal instructions.

### Certificate password is encrypted after first run

The first time the tool runs successfully, it encrypts the certificate password in `app-config.json` using Windows DPAPI and replaces the plaintext value with an encrypted blob. This is expected — the plaintext is never stored on disk after that point.

If you copy `app-config.json` to a different machine or a different Windows user account, decryption will fail. To fix this, set `CertificatePasswordEncrypted` back to `false` in `app-config.json`, restore the plaintext password, and run the tool again on the new machine to re-encrypt it.

## Logging

The tool writes a timestamped log file to `C:\temp\SP-MembershipManager\Logs\` for every session. Each add and remove action is recorded with a timestamp. These logs can be useful for auditing who changed what and when.
