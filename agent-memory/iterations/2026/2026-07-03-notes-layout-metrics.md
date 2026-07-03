# 2026-07-03 - Notes-like Layout Metrics

## Context

Side-by-side Apple Notes tuning was starting to depend on repeated width and window constants spread across the library controller. That made future visual changes risky because the source list, note list, toolbar search, and scroll-table width could drift independently.

## Change

- Added `LibraryNotesLayout` as the shared layout spec for the library window.
- Routed initial window size, presented window size, minimum size, source column width, note column width, note table widths, source row width, and toolbar search widths through the shared spec.
- Updated note-list scroll layout to use the shared minimum table width.
- Added regression coverage for split column widths, toolbar search width, source row width, and note-list scroll resizing.

## Verification

- `swift test` passed with 81 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- `./scripts/visual_notes_qa.sh` passed and generated `/tmp/mudsnote-visual-qa/apple-notes-vs-mudsnote.png`.
- `git diff --check` passed.
- iOS real-device validation is explicitly excluded from this goal.
