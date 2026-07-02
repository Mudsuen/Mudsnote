# 2026-07-02 Notes toolbar shell

## Request

Continue toward the full Apple Notes parity goal. The current visible gap is that Mudsnote still feels far from Apple Notes, so this slice targets the P0 shell.

## Baseline

- Branch: main
- HEAD: 8cc39de
- Dirty files before work: none

## Changes

- Added a native `NSToolbar` to the library window.
- Moved search from the note-list column into the right side of the toolbar.
- Moved global actions into toolbar items:
  - add folder
  - toggle source list
  - new note
  - open separately
  - save
  - search
- Added folder scopes backed by `NoteStore.preferredDirectories`.
- Kept folder scopes local-first: folders are filesystem directories and notes remain Markdown files.
- Centered the editor status/date label above the title to move closer to Apple Notes' editor header.
- Changed the launch path to avoid synchronous tag scans and file-attribute reads before the library window is visible.
- Changed recent note titles and fallback dates to derive readable metadata from stored Markdown paths without opening files.
- Added lightweight recent-file metadata so save/update dates are available without synchronous file-attribute reads.
- Extended the library regression test to cover toolbar items, toolbar search, folder counts, and centered status alignment.
- Added a core regression test proving stale recent paths do not block recent-list construction while preserving filename-derived dates.

## Verification

- `swift test` passed with 59 tests.
- `git diff --check` passed.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged smoke launched `/Applications/Mudsnote.app` with no arguments and showed a visible `Mudsnote 笔记` window at `1040x764`.
- Visual QA screenshot: `/tmp/mudsnote-window-notes-toolbar-shell-windowid.png`
  - native toolbar is visible
  - search is in the toolbar
  - source list includes folder rows
  - direct-open library appears without hanging on recent metadata or tag scans

## Decisions

- Use native `NSToolbar` for the Notes-like shell instead of custom content chrome.
- Keep toolbar actions connected to real behavior; do not add decorative inert toolbar icons.
- Defer tag side-list restoration until there is an asynchronous index/cache path; do not synchronously scan tags during launch.

## Next

- Restore tag rows through an asynchronous local index/cache.
- Continue P0 with trash/recently deleted source behavior and more Notes-like toolbar grouping.
- Hydrate recent-backed list metadata asynchronously from the filesystem after the shell is visible.
