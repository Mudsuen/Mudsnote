# 2026-07-03 - Note-list Selected Card Inset

## Context

The visual QA comparison showed the note-list selected row still looked closer to a generic full-width table selection than the inset card used by Apple Notes.

## Change

- Increased the custom selected-row horizontal inset from 6 to 14 points.
- Increased selected-row vertical inset and corner radius to make the selection read as a card.
- Shifted note-row content padding inward so text sits inside the selected card rather than near its edge.
- Added a layout contract test for the selected-card inset and radius values.

## Verification

- `swift test` passed with 80 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- `./scripts/visual_notes_qa.sh` passed and generated `/tmp/mudsnote-visual-qa/apple-notes-vs-mudsnote.png`; visual inspection confirmed the selected note now reads as a more inset card.
- `git diff --check` passed.
- iOS real-device validation was intentionally excluded from this macOS Notes-parity iteration.
