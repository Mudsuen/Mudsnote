# 2026-07-11 stale recent launch recovery

## Request

Continue the Apple Notes parity goal with a reliable direct-launch experience and no regression to lightweight startup behavior.

## Baseline

- The installed app's normal defaults contained `/Users/Donald/Documents/Mudsnote/2026-04-17-codex-smoke-1776417818.md` as the first recent path even though the file no longer existed.
- Directly opening `/Applications/Mudsnote.app` showed the library plus a modal `无法打开笔记` warning.
- `listRecentFiles` intentionally avoids synchronous metadata reads, so filtering every recent path during shell construction would have weakened the launch-performance contract.

## Changes

- Added `NoteStore.removeRecentFileReference(at:)` to remove a stale path and its derived timestamp without touching the filesystem.
- Recognized Cocoa missing-file and POSIX `ENOENT` errors only in asynchronous initial-note hydration.
- On a confirmed missing file, removed the stale recent reference, rebuilt the current lightweight rows, and asynchronously loaded the next available note.
- Preserved normal error reporting for permission, decoding, and other load failures.
- Added core coverage for derived recent-reference removal and app coverage for missing-first-recent recovery without a modal alert.

## Verification

- Commands run:
  - `swift test --filter 'MudsnoteCoreTests/recentFilesAreListedWithoutSynchronousFileMetadataReads|MarkdownRichEditorTests/libraryWindowDeferredShowSkipsMissingRecentNoteWithoutAlert'`
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh`
  - `codesign --verify --deep --strict --verbose=2 /Applications/Mudsnote.app`
- Result:
  - Focused recovery tests passed.
  - Full suite passed: 117 tests across 2 suites.
  - Relaunching the installed app against the real default library produced one `AXStandardWindow` titled `Mudsnote 笔记`, one accessible Notes search field, and no `AXDialog`.
  - The real missing recent path was absent from `mudsnote.recentFiles` after launch.
  - Strict code-signature verification passed.

## Decisions

- Keep recent-list shell construction metadata-free.
- Repair only confirmed missing-file failures; do not hide actionable load errors.
- Continue initial note loading asynchronously after recovery.

## Next

- Continue Notes shell and editor parity from the clean direct-launch state.
