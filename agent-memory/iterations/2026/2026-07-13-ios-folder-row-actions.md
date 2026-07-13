# 2026-07-13 iOS folder row actions

## Request

Continue matching Apple Notes' iPhone folder interaction model while preserving
Mudsnote's filesystem safety boundaries.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `4895727`
- Concurrent macOS source changes were preserved and excluded.

## Evidence

- Apple Support documents folder-list creation plus touch-and-hold rename/move/
  delete behavior, and left-swipe deletion:
  `https://support.apple.com/en-ie/guide/iphone/ipha61270292/ios`.
- Mudsnote previously exposed folder lifecycle commands mainly after entering a
  folder, leaving root and child rows without the direct Notes interaction.

## Changes

- Root and nested folder rows now share a row-level action system.
- Touch and hold exposes New Subfolder, Rename Folder, and Delete Folder.
- Folder rows inside native lists expose trailing swipe-to-delete with an explicit
  confirmation instead of destructive full swipe.
- New subfolders are created directly beneath the selected row.
- Rename and delete reuse the existing validated filesystem operations, snapshot
  refresh, selected-folder safety, and user-facing failure states.
- Folder deletion continues moving Markdown notes to Recently Deleted and refuses
  to erase folders containing unsupported user files.
- Added stable row identifiers for root and nested folder UI verification and
  Simplified Chinese copy for New Subfolder.

## Verification

- Focused UI automation long-pressed the root Projects row, selected New
  Subfolder, created `Projects/Launch`, entered Projects, and found the nested row.
- Final full App and UI suite: 80 passed, 0 failed, 0 skipped (61 unit/integration
  and 19 UI tests).
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled;
  no iPad or additional simulator was used, and it was shut down afterward.
- Full result bundle:
  `/tmp/MudsnoteFolderActionsTests/Logs/Test/Test-MudsnoteCompanion-2026.07.13_18-11-11-+0800.xcresult`.
- Signed Release build passed and strict code-sign verification succeeded at
  `/tmp/MudsnoteFolderActionsDevice/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
- Physical installation was attempted again, but CoreDevice could not locate the
  still-`unavailable` MudsPhone; install/launch remains unverified.

## Next

- Build and validate the signed Release artifact, then install when the physical
  iPhone data connection returns.
- Continue folder-row visual density and remaining folder move/reorder parity.
