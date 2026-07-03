# 2026-07-03 - Note-list Hover Feedback

## Context

The note list already had Notes-like selected cards and keyboard navigation, but pointer movement over a note row had no visible feedback. The roadmap still called out richer pointer/drag interactions for the note list.

## Change

- Added pointer tracking to `LibraryNoteRowView`.
- Added a subtle inset hover fill for note rows that are not selected.
- Kept group headers non-hoverable so date/year separators still read as section labels, not list items.
- Added regression coverage for note-row hover state and group-row hover suppression.

## Verification

- `swift test` passed with 81 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- `./scripts/visual_notes_qa.sh` passed and generated `/tmp/mudsnote-visual-qa/apple-notes-vs-mudsnote.png`.
- `git diff --check` passed.
- iOS real-device validation is explicitly excluded from this goal.
