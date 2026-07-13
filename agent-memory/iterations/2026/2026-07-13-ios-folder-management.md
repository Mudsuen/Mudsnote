# 2026-07-13 iOS folder management

## Request

Continue Notes-style iPhone library management while retaining Mudsnote capture and
Markdown features.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `f7c1261`
- Concurrent macOS source changes were preserved and not staged with iOS work.

## Changes

- Reassigned the home folder-plus button from library selection to actual folder
  creation; library selection remains in Settings.
- Added root and nested folder creation, rename, and deletion.
- Added collision-safe Markdown note moves through the note context menu.
- Folder deletion moves Markdown notes to Recently Deleted and refuses to delete
  directories containing unsupported files or symbolic links.
- Folder rename transactionally updates recovery paths for notes already in Recently
  Deleted and rolls metadata back on failure.
- Pending capture state blocks structural folder mutations to prevent stale queued
  destinations from recreating renamed or deleted paths.
- Added bilingual labels, confirmations, recovery messages, and error states.

## Verification

- Generic iOS Simulator SDK build passed without booting a simulator.
- Focused create/rename/move/delete/path-safety tests: 3 passed.
- Full App and UI suite: 48 passed, 0 failed, 0 skipped.
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled.
- All simulators were shut down afterward.
- Result bundles:
  - `/tmp/MudsnoteFolderLifecycleFocused.xcresult`
  - `/tmp/MudsnoteFolderLifecycleFull.xcresult`

## Decisions

- Structural mutations are actor-serialized and publish through a fresh immutable
  library snapshot.
- Unknown files are preserved; Mudsnote never recursively deletes a mixed-content
  local folder.
- Move and rename collisions receive a numbered destination instead of overwriting.

## Next

- Add durable pin state and keep it consistent across move, rename, trash, and
  restore operations.
- Continue Notes-style list organization and editor parity after P0 closes.
