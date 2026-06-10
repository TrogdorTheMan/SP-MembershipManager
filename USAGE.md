# Using SP Membership Manager

This guide covers day-to-day usage and known behaviors to be aware of when managing SharePoint site membership.

## Basic Workflow

1. Launch `SP-MembershipManager.exe`
2. Enter your SharePoint Admin URL (e.g. `https://yourtenant-admin.sharepoint.com`) and click **Connect**
3. Search for an employee by name or email in the left panel
4. Select them from the results list — the tool will scan all sites and show every site they have access to and what role they hold
5. Use **Add to Site** or **Remove from Site** to make changes

## Known Behaviors

### Membership counts may appear off immediately after a change

After adding or removing a user, clicking **Refresh** right away can show an unexpected number of sites — for example, a user going from 8 sites to 10 instead of 9, or still showing a site they were just removed from.

**This is not a bug.** SharePoint Online does not apply membership changes instantly across all of its servers. Changes typically propagate within a few seconds, but during that window the tool may read stale or inaccurate data.

The success dialog that appears after an add or remove includes a short countdown for this reason. Once the countdown finishes and you dismiss the dialog, click **Refresh** and the count will be accurate.

**In short:** if the count looks wrong after a change, wait a few seconds and refresh again. If it continues beyond 2 or 3 refreshes, contact your help desk or whomever provided the tool to you.

### Users with access via security groups are not shown

If a user has SharePoint access because they belong to an Entra ID security group (e.g. "SharePoint Power Users"), the tool will not currently detect that access. Only users listed directly on a site's Owner, Member, or Visitor group are shown.

This is a known limitation and is on the roadmap to address.

### PnP.PowerShell installs on first run

The tool requires the PnP.PowerShell module. If it is not already installed on the machine, the tool will install it automatically before connecting. This is a one-time step and may take a minute or two the first time.

### Certificate password is encrypted after first run

The first time the tool runs successfully, it encrypts the certificate password in `app-config.json` using Windows DPAPI and replaces the plaintext value with an encrypted blob. This is expected — the plaintext is never stored on disk after that point.

If you copy `app-config.json` to a different machine or a different Windows user account, decryption will fail. To fix this, set `CertificatePasswordEncrypted` back to `false` in `app-config.json`, restore the plaintext password, and run the tool again on the new machine to re-encrypt it.

## Logging

The tool writes a timestamped log file to `C:\temp\SP-MembershipManager\Logs\` for every session. Each add and remove action is recorded with a timestamp. These logs can be useful for auditing who changed what and when.
