# 2026-06-29 modern icon and three-column library

## Request

Install the iOS companion on the connected phone, make the phone icon more modern and simple, validate functionality, and continue moving the macOS app closer to Notes while keeping Mudsnote lightweight.

## Baseline

- Branch: main
- Previous completed work was checkpointed first in commit `c1f8c8d Add Notes-style library and continuous iOS capture`.
- Dirty files before this slice: none after the checkpoint.

## Changes

- Added `scripts/generate_ios_companion_icon.sh` so the iOS companion icon can be regenerated reproducibly from source.
- Regenerated all app icon PNGs in `iOS/MudsnoteCompanion/Assets.xcassets/AppIcon.appiconset/` with a simple dark background, centered note sheet, fold, lines, and blue accent.
- Reworked `LibraryWindowController` from a two-pane browser/editor into a three-column Notes-like layout:
  - source list with all notes, recent notes, Inbox, and tag scopes
  - middle note list with search
  - right-side title field, rich Markdown editor, save, and open-in-editor action
- Added scope-aware filtering for recent notes, Inbox notes, exact tags, and search.
- Extended the library window test to assert the three split panes and tag-scope filtering path.
- Hardened `scripts/device_smoke.sh` so it resolves the CoreDevice id, preflights Developer Disk Image services, and fails fast with an unlock/trust prompt when the phone is still locked.

## Verification

- `swift test` passed with 57 macOS SwiftPM tests.
- XcodeBuildMCP `test_sim` passed 4 iOS companion tests on the `iPhone 17` simulator with `CODE_SIGNING_ALLOWED=NO`.
- `xcodebuild -project iOS/MudsnoteCompanion.xcodeproj -scheme MudsnoteCompanion -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath build/DeviceDerivedData CODE_SIGNING_ALLOWED=NO build` passed, including iPhoneOS app icon asset compilation.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged macOS smoke launched `/Applications/Mudsnote.app --args --library`; the extra smoke process was closed afterward and the pre-existing resident app process was left running.
- `xcrun devicectl list devices` found the connected phone `MudsPhone` (`2C558043-5D29-531D-878B-F07C4F288D5D`, destination `00008150-001C204022E2401C`).
- Device details showed Developer Mode enabled and the phone paired over a wired tunnel.
- `bash -n scripts/device_smoke.sh` passed.
- `./scripts/device_smoke.sh` now reaches the DDI preflight and exits with a clear unlock prompt instead of continuing into build/install while the phone is reported locked.
- A later rerun of `./scripts/device_smoke.sh` at 2026-06-29 13:44 still failed at the same DDI preflight with `kAMDMobileImageMounterDeviceLocked`.
- After reconnecting the phone, `./scripts/device_smoke.sh` was retried again at 2026-06-29 13:49 and failed at the same DDI preflight with `kAMDMobileImageMounterDeviceLocked`. `devicectl device info details` still showed `developerModeStatus: enabled`, `pairingState: paired`, `tunnelState: connected`, and `ddiServicesAvailable: false`.
- After the phone was reported unlocked and bright, `lockState` briefly showed `passcodeRequired: false`, but the immediate DDI retry still failed with `kAMDMobileImageMounterDeviceLocked`. A follow-up 90-second poll never saw `passcodeRequired: false` again, so the Mac side still treated the phone as locked for developer mounting.
- On 2026-06-30 at 14:30, the phone was visible as `available (paired)` in `devicectl list devices`, but `lockState` still reported `passcodeRequired: true`. A direct-ID `./scripts/device_smoke.sh` retry reached the DDI preflight and failed again with `kAMDMobileImageMounterDeviceLocked`.

## Not Verified

- Real-device iOS install and launch are currently blocked because `devicectl` cannot mount the developer disk image while the phone is reported as locked: `kAMDMobileImageMounterDeviceLocked`.
- The earlier `scripts/device_smoke.sh` run exited with code 137 before producing output; the script now has a DDI preflight, but installation still cannot proceed until the phone allows DDI mounting.

## Decisions

- Keep the iOS companion as a fast capture surface and avoid expanding it into a full editor.
- Continue making the macOS side more Notes-like through a stable source list, note list, and editor rather than replacing the quick-capture workflow.
- Store the icon source as a script instead of committing only opaque PNG output.

## Next

- Retry real-device build, install, and launch after MudsPhone is unlocked and kept awake.
- Add light note actions to the macOS library list, such as pin/favorite, Finder reveal, and copy path, only after the three-column browsing flow is stable.
