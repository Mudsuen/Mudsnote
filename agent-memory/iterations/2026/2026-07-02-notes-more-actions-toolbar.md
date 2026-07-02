# 2026-07-02 Notes more actions toolbar

## Request

Continue toward full Apple Notes parity for the macOS library while keeping Mudsnote local-first and lightweight.

## Baseline

- Branch: main
- HEAD: 2a76ee5
- Dirty files before work: none

## Changes

- Replaced default top-level file/lifecycle toolbar clutter with a single Notes-style `更多` toolbar item.
- Kept common editing actions visible in the toolbar:
  - format
  - checklist
  - table
  - link
  - attachment
- Moved less frequent actions into the more-actions menu:
  - open in separate window
  - move to folder
  - save
  - reveal in Finder
  - copy Markdown path
  - delete
  - restore and permanent delete in trash
- Added selected-note file helpers for reveal and path copy while preserving plain Markdown files as the source of truth.
- Replaced the system `textformat.size` toolbar symbol with the app's own `Aa` template image so the format button visually matches Notes more closely.

## Verification

- `swift test` passed with 64 tests.
- Regression coverage now verifies:
  - the default toolbar shows `更多` and no longer shows the old top-level save/move/delete/restore items
  - the format toolbar image exposes the `格式` accessibility description
  - the more-actions menu contains open, move, save, reveal, copy-path, delete, restore, and permanent-delete states
  - copying the Markdown path writes the selected file path to the pasteboard
- `git diff --check` passed.
- XcodeBuildMCP `build_sim` passed for `MudsnoteCompanion` on the configured iPhone 17 simulator.
- `./scripts/device_smoke.sh` still reports `MudsPhone` as paired but unavailable to CoreDevice with local Xcode 26.5 / iPhoneOS SDK 26.5.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged smoke relaunched `/Applications/Mudsnote.app` with no arguments and showed `Mudsnote 笔记` at `1040x764`.
- Visual QA screenshot: `/tmp/mudsnote-window-notes-more-actions-toolbar.png`

## Decisions

- Common editing controls stay visible in the toolbar.
- File and lifecycle actions should be available but grouped behind a compact menu.
- Reveal/copy use the underlying Markdown file path directly; no app-specific database indirection was added.

## Next

- Run the remaining verification ladder.
- Continue with search scope/highlight and folder hierarchy disclosure.
