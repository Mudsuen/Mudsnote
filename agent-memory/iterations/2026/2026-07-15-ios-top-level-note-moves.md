# 2026-07-15 iOS top-level note moves

## Request

Continue the iPhone Apple Notes parity target by making note organization
consistent across the reader, list context menus, and multi-selection mode.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `81dd722`
- Worktree was clean before this iteration.

## Changes

- Added Top Level as a move destination for selected notes, allowing several notes
  to leave a folder in one Notes-style multi-selection operation.
- Added the same Top Level destination to note-row context menus.
- Filtered destinations dynamically: a folder is omitted when every selected note
  is already there, while mixed-location selections retain useful destinations.
- Disabled the move control only when no real destination exists instead of using
  the presence of user folders as a proxy.
- Refactored batch AppModel movement to accept an optional folder path so root and
  user-folder moves share the same coordinated store mutation and refresh path.
- Preserved the existing reader move behavior and all protected Inbox/Daily rules.

## Verification

- Generic iOS Simulator build and `git diff --check` passed.
- Focused multi-selection UI test moved two real fixture notes from `Projects/` to
  the library root and verified both resulting paths.
- Retained visual evidence of the single-row selection toolbar and Top Level menu:
  `/tmp/mudsnote-top-level-move-attachments/DE8F4168-6CC0-414C-8AA2-DA009D9C88BA.png`.
- Final full App and UI suite: 103 passed, 0 failed, 0 skipped (73 unit/performance
  tests and 30 UI tests), confirmed from the xcresult summary.
- Only iPhone 17 Pro / iOS 26.5 simulator
  `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5` was used, with parallel testing disabled.
  It was shut down after verification.
- Final result bundle:
  `/tmp/MudsnoteTopLevelMoveFullTests/Logs/Test/Test-MudsnoteCompanion-2026.07.15_02-18-06-+0800.xcresult`.
- Signed Release build passed at
  `/tmp/MudsnoteTopLevelMoveRelease/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
  Strict code-sign verification passed for the app and embedded widget.
- MudsPhone remained visible over USB but unavailable to CoreDevice. `xcdevice`
  reported local-network browsing with `available: false`; installation failed with
  CoreDevice error 1011 because the device could not be located.

## Decisions

- Root is a first-class move destination represented by a nil folder path, matching
  the existing store contract instead of inventing a synthetic folder.
- Move menus expose only state-changing destinations, reducing accidental no-op
  actions while preserving useful mixed-selection moves.
- Single-note, batch, and reader movement all remain AppModel-owned; SwiftUI views
  do not perform filesystem operations.

## Next

- Restore MudsPhone CoreDevice availability, then install and launch the signed
  Release for a physical multi-select and path-update smoke check.
- Continue the next Notes-parity retrieval or editor interaction gap.
