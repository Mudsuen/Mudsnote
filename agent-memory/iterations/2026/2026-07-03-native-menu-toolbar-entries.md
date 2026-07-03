# 2026-07-03 - Native Menu Toolbar Entries

## Context

After adding system sharing, the toolbar share and more actions entries still used ordinary toolbar buttons plus manual menu popup code. Apple Notes presents those controls as native menu-style toolbar controls.

## Changes

- Replaced the share/export toolbar button with `NSMenuToolbarItem`.
- Replaced the more-actions toolbar button with `NSMenuToolbarItem`.
- Rebuild each menu during toolbar state refresh so selected-note and trash disabled states stay current.
- Removed the now-unused manual popup path for those two toolbar entries.
- Added regression coverage that the default toolbar uses native menu toolbar items and keeps the share menu ordering stable.

## Verification

- `swift test --filter 'libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|libraryToolbarUsesNotesLikeDisabledStates|libraryWindowDeletesRestoresAndPermanentlyDeletesNotes'` passed.
- `swift test` passed with 82 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged app smoke passed: `/Applications/Mudsnote.app --args --library` opened one `Mudsnote 笔记` window at `1420x860`.
- `./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-menu-toolbar` passed and generated the side-by-side comparison image.

## Notes

- This is macOS-only Notes parity work. iOS real-device validation remains out of scope for the active goal.
