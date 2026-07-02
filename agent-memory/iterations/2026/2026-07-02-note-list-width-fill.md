# 2026-07-02 note-list width fill

## Request

Continue iterating Mudsnote toward Apple Notes UI, functionality, interaction, and performance parity, with iOS real-device validation removed from the active goal.

## Baseline

- Branch: main
- Dirty files before work: none after `aadee6e`.
- Active scope: macOS Apple Notes-style library/editor parity.
- Current visual gap: the packaged app showed the middle note list as a narrow right-pinned table with the scrollbar covering note text.

## Changes

- Added `LibraryNoteScrollView`, a focused `NSScrollView` subclass for the note list.
- The scroll view keeps the table document view left-aligned and at least as wide as the visible list column.
- The note-list table now disables conflicting automatic column resizing and lets the scroll view own the single-column width contract.
- The sidebar stack explicitly pins the note-list header and list container to the stack width.
- Added regression coverage for the document view x-origin and single-column visible-width behavior.

## Verification

- `swift test` passed with 69 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app smoke launched `/Applications/Mudsnote.app` directly and showed the `Mudsnote 笔记` main window at `1040x764`.
- Visual smoke screenshot: `/tmp/mudsnote-note-list-width-smoke.png`.

## Decisions

- Keep this as a layout contract fix, not a broader row redesign.
- Continue to leave exact Apple Notes row spacing, thumbnail previews, and broader keyboard navigation for later iterations.

## Next

- Continue with exact note-list row spacing, thumbnail previews, toolbar disabled states, source-list spacing, and side-by-side visual QA.
