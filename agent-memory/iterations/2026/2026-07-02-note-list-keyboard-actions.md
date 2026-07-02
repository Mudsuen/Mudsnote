# 2026-07-02 note-list keyboard actions

## Request

Continue iterating Mudsnote toward Apple Notes UI, functionality, interaction, and performance parity.

## Baseline

- Branch: main
- Dirty files before work: none
- Active scope: macOS Apple Notes-style library/editor parity.
- Current roadmap gap: note-list keyboard navigation polish.

## Changes

- Added `LibraryNoteTableView`, a lightweight `NSTableView` subclass for high-intent note-list key commands.
- Return/Enter opens the selected note through the existing separate-window action.
- Delete/Forward Delete runs the existing note lifecycle path:
  - normal scopes move the note to local Trash;
  - the trash scope permanently deletes the note.
- Unhandled keys still fall through to AppKit, preserving native table selection/navigation behavior.
- Added regression coverage for keyboard open, delete-to-trash, and permanent delete from the trash list.

## Verification

- `swift test` passed with 68 tests.
- `git diff --check` passed.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app smoke launched `/Applications/Mudsnote.app` directly and showed the `Mudsnote 笔记` main window at `1040x764`.
- Visual smoke screenshot: `/tmp/mudsnote-note-list-keyboard-smoke.png`.

## Decisions

- Keep keyboard actions mapped to existing lifecycle functions instead of creating separate code paths.
- Leave broader keyboard polish for later: focus restoration, full row navigation behavior, multi-selection, and shortcut documentation.

## Next

- Continue with exact note-list row spacing, thumbnail previews, richer empty/loading states, toolbar disabled states, and side-by-side visual QA.
