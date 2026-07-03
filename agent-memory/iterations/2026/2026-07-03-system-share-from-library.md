# 2026-07-03 - System Share From Library

## Context

Continue the active macOS Apple Notes parity goal with iOS real-device validation out of scope. The roadmap still called out richer system share destinations as a visible toolbar gap.

## Changes

- Changed the library toolbar share icon from a direct Markdown export action into a share/export menu.
- Added a system `分享...` action that saves pending edits and hands the current Markdown file URL to `NSSharingServicePicker`.
- Kept local-first Markdown actions in the same compact menu: copy full Markdown content and export a Markdown file.
- Added the same share action to the note context menu and more-actions menu, with trash-state disabling.
- Added regression coverage for menu contents, enabled states, and share-file preparation saving dirty editor content.

## Verification

- `swift test --filter 'libraryToolbarUsesNotesLikeDisabledStates|libraryWindowDeletesRestoresAndPermanentlyDeletesNotes'` passed.
- `swift test` passed with 82 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged app smoke passed: `/Applications/Mudsnote.app --args --library` opened one `Mudsnote 笔记` window at `1420x860`.
- `./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-system-share` passed and generated the side-by-side comparison image.

## Notes

- This does not add account sync, Apple Notes collaboration, or iOS verification. The system share picker uses the selected local Markdown file as the durable source.
