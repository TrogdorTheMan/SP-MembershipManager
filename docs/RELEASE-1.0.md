# 1.0.0 Release Checklist

Working notes for shipping v1.0.0. Delete this file once the release is tagged.

## Done (07-05-26, laptop)

- [x] Pester suite green (19/19); `build.ps1 -ConfigOnly` dry run works
- [x] Version stamped 1.0.0: `launcher/Launcher.csproj` + `$script:AppVersion` in the PS1 (About dialog + startup log line)
- [x] `#Requires` corrected 5.1 → 7.0 (launcher enforces PS 7; script never parsed under 5.1)
- [x] Unconfigured build compiles; EXE properties report 1.0.0
- [x] AT-9b passed (runtime half-gate guard)
- [x] AT-11 passed (wizard validation, all three paths)
- [x] Wizard UI rebuilt: sized-to-content, DPI-aware, resizable/anchored, min/max buttons, placeholder repaint fix
- [x] Docs refreshed: USAGE.md button names + critical-site (red row) explanation

## Remaining (needs the main PC — real .pfx + tenant values live there)

- [ ] **Build A** (fully loaded): cert + tenant + `-LockedAdminUrl` + gate + critical sites
  - [ ] AT-2 locked admin URL (read-only prompt)
  - [ ] AT-3 self-contained EXE in empty folder
  - [ ] AT-4 critical row red (power user sign-in)
  - [ ] AT-5 power user can manage critical row
  - [ ] AT-6 standard user blocked on critical row (buttons disabled + warning)
  - [ ] AT-7 standard user unaffected on normal rows
  - [ ] AT-8 outsider gets Access Denied (gate from baked config)
- [ ] **AT-1 remainder** (unconfigured build): confirm a user *without* access is denied
- [ ] **AT-10**: full wizard build with cert produces a working EXE
- [ ] **AT-12**: hand-edit `app-config.json` to drop `AppClientId` → startup error dialog, app exits
- [ ] **AT-13**: wizard with cert but blank App Client ID → validation error, no build
- [ ] **Rotate app registration**: create a fresh app registration by following SETUP.md verbatim
  (doubles as the SETUP.md acceptance pass); set the new `AppClientId` in local `app-config.json`;
  smoke-test a from-source launch; then delete the old registration in Entra so the client ID in
  old git history is a dead identifier. Log any SETUP.md friction as doc fixes.
- [ ] Record pass dates in `docs/ACCEPTANCE-TESTS.md`
- [ ] Tag and push: `git tag v1.0.0 && git push origin main v1.0.0`
- [ ] Optional: GitHub Release from the tag — **source/tag only**; never attach a configured EXE (they bake tenant config and certs)
- [ ] Delete this file

## Migration (breaking change — include in the GitHub Release notes)

**`AppClientId` is now required in `app-config.json`.** The tool no longer ships a hardcoded
app registration client ID in source — each deployer supplies their own, so a personal/default
identity is never inherited. On startup the tool now refuses to run (friendly dialog) if no
client ID is configured.

Upgrading an existing deployment:

- **From-source / plain builds:** add `"AppClientId": "<your-app-registration-client-id>"` to
  each `app-config.json` (see `app-config.example.json`). Nothing else changes.
- **Self-contained (embedded-cert) EXEs:** rebuild with the new required `-AppClientId`
  parameter — `build.ps1 -CertPath … -CertPassword … -Tenant … -AppClientId …` (or the new
  **App Client ID** box in the build wizard). Older self-contained EXEs won't carry the value.
- Setup for a fresh tenant is now code-edit-free — see **SETUP.md**.

## Notes

- Test personas needed: power user (gate + critical group), standard user (gate only), outsider (neither)
- Build artifacts (`build/output/`, `launcher/bin|obj/`, `*.pfx`, `app-config.json`) are all gitignored — verified 07-05-26
