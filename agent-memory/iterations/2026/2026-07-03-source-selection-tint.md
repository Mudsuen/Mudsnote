# 2026-07-03 - Source Selection Tint

## Context

The source list selected row still used the system accent color. In the active visual QA image that read as blue, while the Apple Notes reference uses a quieter dark selected row with warm yellow emphasis in the sidebar.

## Change

- Added `LibrarySourceSelectionPalette` for library source rows only.
- Changed selected source row background from system accent fill to a dark local fill.
- Changed selected source button and count tint to a warm Notes-like foreground color.
- Kept `panelAccentColor()` unchanged so editor, toolbar, and other app surfaces remain system-native.
- Added regression coverage for the selected source button and count tint.

## Verification

- `swift test` passed with 81 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- `./scripts/visual_notes_qa.sh` passed and generated `/tmp/mudsnote-visual-qa/apple-notes-vs-mudsnote.png`.
- Visual QA confirmed the selected source row now uses warm tint instead of system blue.
- `git diff --check` passed.
- iOS real-device validation is explicitly excluded from this goal.
