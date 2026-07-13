# 2026-07-13 iOS folder move

## Request

Continue matching Apple Notes' iPhone folder-management model while preserving
Mudsnote's local Markdown storage and quick-capture behavior.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `76ada59`
- Concurrent macOS, documentation, and folder-projection work was preserved and
  excluded.

## Evidence

- Apple Support documents moving a folder by touching and holding it, selecting
  Move, and choosing a destination:
  `https://support.apple.com/en-ie/guide/iphone/ipha61270292/ios`.
- Mudsnote already supported creating, renaming, and deleting folders, but did
  not provide a folder move transaction or destination UI.

## Changes

- Folder context menus and the active-folder menu now expose Move Folder.
- Nested folders can move to Top Level; folders can move to any valid folder
  outside their own subtree.
- Moving into the same parent is a safe no-op, and moving a folder into itself or
  one of its descendants is rejected.
- Name collisions use the same non-destructive numbered destination policy as
  folder creation and rename.
- The filesystem move, Recently Deleted original paths, and pinned note paths are
  updated as one transaction with rollback on metadata failure.
- An open note inside the moved folder is reloaded from its new path.
- Added Simplified Chinese copy for folder move commands and completion state.

## Verification

- Focused storage automation moved `Archive` beneath `Projects`, verified pinned
  state, restored a deleted note into the new hierarchy, and rejected a move into
  a descendant.
- Focused UI automation created `Projects/Launch`, long-pressed Launch, selected
  Move Folder and Top Level, then verified the root `Launch` row.
- Final full App and UI suite: 82 passed, 0 failed, 0 skipped (62 unit/integration
  and 20 UI tests).
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled;
  no iPad or additional simulator was used, and it was shut down afterward.
- Full result bundle:
  `/tmp/MudsnoteFolderMoveFullTests/Logs/Test/Test-MudsnoteCompanion-2026.07.13_18-22-13-+0800.xcresult`.
- Signed Release build passed and strict code-sign verification succeeded at
  `/tmp/MudsnoteFolderMoveDevice/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
- Physical installation was attempted, but CoreDevice still reports MudsPhone as
  `unavailable`; install and launch therefore remain unverified.

## Next

- Install the validated Release artifact when the physical iPhone data connection
  becomes available.
- Continue Notes-parity work on folder navigation polish and editor/list gaps.
