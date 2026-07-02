# 2026-07-02 Note-list arrow navigation

## Context

The Apple Notes parity roadmap still listed broader note-list keyboard navigation as a gap. The library note list already supported Return to open separately and Delete/Forward Delete for trash actions, but Up/Down still relied on default table behavior around recency group rows.

## Change

- Added explicit Up/Down key commands to `LibraryNoteTableView`.
- Keyboard navigation now:
  - skips recency group rows,
  - clamps at the first and last note rows,
  - scrolls the selected note row into view,
  - saves pending edits before switching notes,
  - loads the selected note into the editor immediately.
- Added regression coverage for moving between notes and starting from a programmatically selected group row.

## Verification

- `swift test --filter 'libraryWindowNoteListArrowKeysSkipGroupRowsAndLoadNotes|libraryWindowNoteListKeyboardOpensAndDeletesNotes'` passed.
- `swift test` passed with 79 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- `./scripts/visual_notes_qa.sh` generated `/tmp/mudsnote-visual-qa/apple-notes-vs-mudsnote.png`.
