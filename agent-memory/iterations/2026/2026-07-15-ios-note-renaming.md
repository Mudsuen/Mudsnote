# 2026-07-15 iOS safe note renaming

## Request

Continue the iPhone Apple Notes parity target with complete note actions and
reader/list interactions, while preserving Markdown as the portable source of truth.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `1215686`
- The unrelated concurrent macOS editor test change was preserved and excluded.

## Changes

- Added end-to-end Markdown note renaming from both the Notes-style reader options
  menu and each note row's context menu.
- Kept the half-sheet reader open after a successful rename and updated its live
  document path and rendered content state.
- Preserved note contents and pin metadata across the filesystem move.
- Added collision-safe names such as `Roadmap 2.md`, accepted optional `.md`
  suffixes, and rejected hidden, path-like, empty, or otherwise invalid names.
- Protected the special Inbox and Daily documents from renaming.
- Replaced the saved-note reader's standalone share icon with a Notes-style
  options menu containing local system sharing and rename actions.
- Added English and Simplified Chinese copy for the new interactions and errors.
- Added store and UI regression coverage for collision handling, pin preservation,
  protected paths, reader continuity, and list entry points.

## Verification

- Generic iOS Simulator build, String Catalog validation, and `git diff --check`
  passed.
- Focused store and two UI tests passed.
- Retained visual evidence of the half-sheet reader options menu:
  `/tmp/mudsnote-rename-attachments/B23E751A-7A69-4137-A5BD-88EF2F846B71.png`.
- Final full App and UI suite: 101 passed, 0 failed, 0 skipped (73 unit/performance
  tests and 28 UI tests).
- Only iPhone 17 Pro / iOS 26.5 simulator
  `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5` was used, with parallel testing disabled.
  It was shut down after verification.
- Final result bundle:
  `/tmp/MudsnoteRenameFullTests/Logs/Test/Test-MudsnoteCompanion-2026.07.15_01-48-29-+0800.xcresult`.
- Signed Release build passed at
  `/tmp/MudsnoteRenameRelease/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
  Strict code-sign verification passed for the app and embedded widget.
- MudsPhone remained unavailable to CoreDevice even though `xcdevice` saw its USB
  interface. It reported local-network browsing with `available: false`; installation
  failed with CoreDevice error 1011 because the device could not be located.

## Decisions

- Rename is a coordinated filesystem move rather than display-only metadata, so
  file names remain truthful in iCloud Drive and other Markdown tools.
- Existing paths are never overwritten; name collisions receive the same numbered
  suffix behavior as note creation.
- System sharing remains local and supported, while collaboration/share-link
  features stay outside the product boundary.

## Next

- Restore MudsPhone CoreDevice availability, then install and launch the signed
  Release for a physical rename, keyboard, and reader-continuity smoke check.
- Continue the next Notes-parity gap in list organization, retrieval, or note actions.
