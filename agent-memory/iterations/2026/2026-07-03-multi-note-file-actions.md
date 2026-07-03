# 2026-07-03 - Multi-Note File Actions

## Context

Continue the active macOS Apple Notes parity goal with iOS real-device validation out of scope. After adding system share and native menu toolbar entries, the next roadmap gap was richer multi-note share/export and multi-item note-list behavior.

## Changes

- Enabled multiple selection in the library note list.
- Added multi-selection Markdown URL helpers while preserving the currently loaded note during additive multi-selection.
- Extended sharing to pass all selected Markdown file URLs to `NSSharingServicePicker`.
- Extended path copy and full Markdown content copy to all selected notes.
- Added multi-file Markdown export into a chosen folder with conflict-safe destination names.
- Extended delete/trash and permanent delete handling to all selected notes.
- Added regression coverage for multi-select share/copy/export/delete behavior.

## Verification

- `swift test --filter 'libraryWindowSharesExportsAndDeletesMultipleSelectedNotes|libraryToolbarUsesNotesLikeDisabledStates|libraryWindowDeletesRestoresAndPermanentlyDeletesNotes|libraryWindowUsesNotesLikeSplitAndLoadsFirstNote'` passed.
- `swift test` passed with 83 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged app smoke passed: `/Applications/Mudsnote.app --args --library` opened one `Mudsnote 笔记` window at `1420x860`.
- `./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-multi-note-actions` passed and generated the side-by-side comparison image.

## Notes

- This keeps the storage model local-first: selected notes are still plain `.md` files on disk.
