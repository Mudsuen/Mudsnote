# 2026-07-03 - Note-list Row Separators

## Context

The note list already had Notes-like selected cards, hover feedback, and drag support, but unselected rows still lacked Apple Notes' quiet row dividers. In the side-by-side visual QA, that made the middle pane feel less dense and less scannable than the reference.

## Change

- Added faint inset separators to normal note rows in `LibraryNoteRowView`.
- Kept date/year group rows separator-free so they continue reading as section headers.
- Kept selected rows separator-free so the golden card remains the primary state.
- Added regression coverage for the separator inset and opacity contract.
- iOS real-device validation is excluded from the current goal; this iteration is macOS-only.

## Verification

- `swift test --filter libraryWindowUsesNotesLikeSplitAndLoadsFirstNote` passed.
- `swift test` passed with 81 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- `./scripts/visual_notes_qa.sh` passed and generated `/tmp/mudsnote-visual-qa/apple-notes-vs-mudsnote.png`.
- Visual QA confirmed unselected note rows show quiet separators without cutting through the selected card.
- `git diff --check` passed.
