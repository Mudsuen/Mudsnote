# 2026-07-02 deferred source folders and tags

## Request

Remove iOS verification from the current goal scope and continue the remaining macOS Apple Notes parity work.

## Baseline

- Branch: main
- Dirty files before work: `LibraryWindowController.swift` and `MarkdownRichEditorTests.swift` already had in-progress deferred tag-row changes.
- Active scope: macOS Apple Notes-style library/editor parity only.
- Explicitly excluded: iOS real-device install and smoke verification.

## Changes

- Added deferred tag source rows after the library shell is visible.
- Normalized sidebar tag titles so the row shows one `#` symbol plus the bare tag name, while selected list titles and note metadata still show `#tag`.
- Changed source folder startup behavior from synchronous recursive directory scanning to a shell-first model:
  - root folder rows render immediately during window construction;
  - full folder rows are computed after the window is shown;
  - disclosure and folder-management actions refresh the current tree when needed.
- Kept nested folder disclosure behavior session-local and lightweight.
- Updated library tests to explicitly load full source folders when a test needs folder hierarchy.

## Verification

- `swift test` passed with 67 tests.
- `git diff --check` passed.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app smoke launched `/Applications/Mudsnote.app` directly and showed the `Mudsnote 笔记` main window at `1040x764`.
- Visual smoke screenshot: `/tmp/mudsnote-apple-notes-deferred-folders-tags.png`.

## Decisions

- The goal tool cannot edit the paused historical objective text, but the working scope is now macOS-only for this iteration.
- Keep direct launch shell-first; optional tag discovery and deeper filesystem traversal should not block the main window.
- Do not add a folder index database yet. A background/deferred source-list load is enough for the current lightweight Notes clone target.

## Next

- Continue Apple Notes visual parity: editor date/title placement, exact column spacing, toolbar disabled states, keyboard navigation, attachment indicators, and empty/loading states.
