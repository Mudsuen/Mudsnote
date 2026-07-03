# 2026-07-03 - Note-list File Drag-out

## Context

The note list had keyboard open/delete, context menus, selected cards, and hover feedback, but dragging a note row did not expose a useful native payload. Apple Notes-style desktop behavior should let notes participate in platform drag workflows while preserving the local-first Markdown model.

## Change

- Enabled external copy dragging from the library note table.
- Added a pasteboard writer for note rows that exposes the note's backing Markdown file URL.
- Kept group rows non-draggable so date/year separators remain section labels.
- Added regression coverage for note-row drag payloads and group-row drag suppression.

## Verification

- `swift test` passed with 81 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- `./scripts/visual_notes_qa.sh` passed and generated `/tmp/mudsnote-visual-qa/apple-notes-vs-mudsnote.png`.
- `git diff --check` passed.
- iOS real-device validation is explicitly excluded from this goal.
