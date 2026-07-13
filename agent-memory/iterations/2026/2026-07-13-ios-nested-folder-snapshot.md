# 2026-07-13 iOS nested folder snapshot

## Request

Continue the iPhone Apple Notes core-parity goal while preserving Mudsnote's New
Note, Quick Note, and Markdown-specific capabilities.

## Baseline

- Branch: `main`
- HEAD: `71c7d64`
- Pre-existing/concurrent dirty files were limited to macOS source, tests, roadmap,
  changelog, handoff, and visual-QA work. They were not edited or staged here.

## Changes

- Added a first-class immutable nested folder tree to each iOS library snapshot.
- Included empty directories and implicit parent folders derived from Markdown file
  paths.
- Excluded `Daily`, `Attachments`, hidden directories, and symbolic-link traversal
  from the user-folder projection.
- Added direct and recursive note counts with an indexed parent-child build instead
  of repeated whole-tree scans.
- Published folder state transactionally through `AppModel` with the rest of the
  active library revision.
- Added a Notes-style Folders section, nested navigation, empty-folder state, and
  direct note opening.
- Added reviewed Simplified Chinese localization for the Folders heading.

## Verification

- Generic iOS Simulator SDK build: passed without booting a simulator.
- Focused folder tests on one iPhone 17 Pro / iOS 26.5 simulator: 2 passed.
- Full App and UI suite on that same simulator with parallel testing disabled:
  42 passed, 0 failed, 0 skipped.
- Result bundle: `/tmp/MudsnoteFolderTreeFull.xcresult`.
- All simulators were shut down after verification.

## Decisions

- Folder discovery belongs to the immutable library snapshot, not SwiftUI views.
- Empty folders are product state and must remain visible even without Markdown
  descendants.
- System storage directories are not presented as user folders.

## Next

- Add atomic folder creation/rename/delete and note move/trash/restore operations.
- Make those operations publish a new snapshot revision immediately.
- Continue P0 lifecycle work before adding more toolbar chrome.
