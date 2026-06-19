# SP-MembershipManager — Manual Acceptance Tests

Run these tests after building a new EXE to verify per-client build config and critical site flagging work correctly.

---

## AT-1: Unconfigured build (regression baseline)

**Setup:** `.\build.ps1` (no parameters)

1. Launch the EXE.
2. Admin URL dialog appears — text box is editable.
3. Enter your admin URL and connect.
4. Search a user with SharePoint access.
5. Add and Remove buttons function normally.
6. No rows have a red background.

**Pass:** Behavior is identical to pre-feature baseline. No regressions.
- 06-18-26: Passes all tests when using a user with proper access. Still need to validate user without access is denied.

---

## AT-2: Locked admin URL

**Setup:** `.\build.ps1 -LockedAdminUrl "https://yourtenant-admin.sharepoint.com"`

1. Launch the EXE.
2. Admin URL dialog appears with the baked-in URL pre-filled.
3. The text box is grayed out and read-only (cannot be edited).
4. OK button is enabled.

**Pass:** URL is locked; user cannot change the tenant.

---

## AT-3: Fully self-contained EXE (embedded cert)

**Setup:**
```powershell
.\build.ps1 `
    -CertPath ".\sp-mm.pfx" `
    -CertPassword "yourpassword" `
    -Tenant "yourtenant.onmicrosoft.com" `
    -LockedAdminUrl "https://yourtenant-admin.sharepoint.com"
```

1. Copy the resulting EXE to an empty folder (no `app-config.json`, no `.pfx`).
2. Launch the EXE from that folder.
3. App launches and connects to SharePoint without any external files.

**Pass:** App works with zero external configuration files.

---

## AT-4: Critical site red highlighting

**Setup:** `.\build.ps1 -CriticalSiteUrls @("https://yourtenant.sharepoint.com/sites/HR")`

1. Launch the EXE (with app-config.json next to it).
2. Search a user who has access to the HR site.
3. The HR site row appears with a light red background.
4. Other rows remain white, amber (site admin), or blue (layered access) as appropriate.

**Pass:** Only the designated critical site rows are red.

---

## AT-5: Critical site — power user CAN manage

**Setup:**
```powershell
.\build.ps1 `
    -CriticalSiteUrls @("https://yourtenant.sharepoint.com/sites/HR") `
    -CriticalSiteGroupId "<power-users-group-object-id>"
```

> **Prerequisite:** The power users Entra group must be assigned to the gate application under **Enterprise Applications → [gate app] → Users and groups** so it appears in the id_token groups claim.

1. Sign in as a user who is a member of the power users group.
2. Search a user who has access to the HR site.
3. Select the red HR site row.

**Pass:** Add to Site and Remove from Site buttons are enabled. No red warning label is shown.

---

## AT-6: Critical site — standard user CANNOT manage

**Setup:** Same build as AT-5.

1. Sign in as a user who is in `GateGroupId` but NOT in `CriticalSiteGroupId`.
2. Search a user who has access to the HR site.
3. Select the red HR site row.

**Pass:** Add to Site and Remove from Site buttons are **disabled**. A red label reads: *"This is a critical site — contact an administrator to manage access."*

---

## AT-7: Critical site — non-critical rows unaffected

**Setup:** Same build as AT-5, signed in as the standard (non-power) user from AT-6.

1. Select any non-critical site row for the same user.

**Pass:** Add and Remove buttons are enabled normally (subject to the usual CanRemove logic). No warning label.

---

## AT-8: Gate config baked into EXE

**Setup:** Build with `-GateClientId` and `-GateGroupId`. Use an `app-config.json` that has NO GateClientId or GateGroupId keys.

1. Launch the EXE.
2. Sign in as a user who is NOT in the gate group.

**Pass:** Access Denied dialog appears — gate enforced from baked-in config, not from app-config.json.

---

## AT-9: Half-config rejected at build time

**Setup:** `.\build.ps1 -GateClientId "some-client-id"` (no `-GateGroupId`).

1. Run the build.

**Pass:** The build aborts immediately with: *"-GateClientId was supplied without -GateGroupId. The sign-in gate requires both (or neither)."* No EXE is produced.

---

## AT-9b: Half-config guard at runtime (defense in depth)

**Setup:** Build a normal EXE, then hand-edit the runtime `app-config.json` to add `GateClientId` but no `GateGroupId`.

1. Launch the EXE.

**Pass:** Error dialog on startup: *"GateClientId is configured but GateGroupId is missing."* App does not continue. (This guard covers configs that bypass `build.ps1`.)

---

## AT-10: Build wizard

1. Run `.\build-wizard.ps1`.
2. A WinForms window opens with labeled fields for all build parameters.
3. Fill in at minimum: CertPath, CertPassword, Tenant, LockedAdminUrl.
4. Click **Build**.
5. Progress output appears in the output panel.
6. EXE is produced at `build\output\SP-MembershipManager.exe`.

**Pass:** Wizard produces a working EXE equivalent to the corresponding `build.ps1` command-line invocation.

---

## AT-11: Wizard gate validation

1. Run `.\build-wizard.ps1`.
2. Fill in **Gate Client ID** but leave **Gate Group ID** blank. Click **Build**.
   - **Pass:** Validation error: *"Gate Group ID is required..."* No build runs.
3. Clear both gate fields. Click **Build**.
   - **Pass:** Warning dialog: *"This build has NO sign-in gate..."* with Yes/No. Clicking **No** cancels; clicking **Yes** proceeds with a gate-less build.
4. Fill in both gate fields. Click **Build**.
   - **Pass:** Build runs with no validation prompts.
