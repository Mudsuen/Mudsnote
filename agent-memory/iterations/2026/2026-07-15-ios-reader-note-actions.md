# 2026-07-15 iOS complete reader note actions

## Request

Continue the iPhone Apple Notes parity target so an opened note supports the
complete organization workflow without returning to the list.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `ab4ba33`
- Worktree was clean before this iteration.

## Changes

- Expanded the saved-note reader's Notes-style options menu from share and rename
  to share, pin or unpin, move, duplicate, rename, and move to Recently Deleted.
- Added a Top Level destination so notes inside folders can move back to the library
  root instead of requiring a filesystem workaround.
- Kept the half-sheet reader open after a move and updated its live document path,
  preventing later edits from targeting the stale source path.
- Added a destructive confirmation before moving an opened note to Recently Deleted.
- Waited for the coordinated trash mutation to succeed before dismissing the reader;
  failed mutations now keep the note visible with the existing recovery toast.
- Refactored single-note move and trash AppModel flows into awaitable operations while
  preserving existing list swipe and context-menu behavior.
- Added Simplified Chinese copy for the new destructive confirmation.

## Verification

- Generic iOS Simulator build, String Catalog validation, and `git diff --check`
  passed.
- Two focused reader-action UI tests passed, including moving to Top Level, staying
  in the reader, deleting, and finding the note in Recently Deleted.
- Retained visual evidence of the complete one-column opened-note menu:
  `/tmp/mudsnote-reader-actions-attachments/405668A9-811B-4CAB-9CFE-149AE36AD457.png`.
- Final full App and UI suite: 102 passed, 0 failed, 0 skipped (73 unit/performance
  tests and 29 UI tests).
- Only iPhone 17 Pro / iOS 26.5 simulator
  `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5` was used, with parallel testing disabled.
  It was shut down after verification.
- Final result bundle:
  `/tmp/MudsnoteReaderActionsFullTests/Logs/Test/Test-MudsnoteCompanion-2026.07.15_02-04-04-+0800.xcresult`.
- Signed Release build passed at
  `/tmp/MudsnoteReaderActionsRelease/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
  Strict code-sign verification passed for the app and embedded widget.
- MudsPhone remained visible over USB but unavailable to CoreDevice. `xcdevice`
  reported local-network browsing with `available: false`; installation failed with
  CoreDevice error 1011 because the device could not be located.

## Decisions

- Reader and list actions share AppModel lifecycle operations rather than duplicating
  filesystem work in SwiftUI views.
- Moving an open note is an in-place reader transition; deleting it is the only
  lifecycle action that closes the reader.
- Destructive deletion remains recoverable through Recently Deleted and is visually
  separated from ordinary actions by the system menu style.

## Next

- Restore MudsPhone CoreDevice availability, then install and launch the signed
  Release for a physical menu, move, delete, and edit-after-move smoke check.
- Continue the next Notes-parity gap in retrieval, organization, or editor polish.
