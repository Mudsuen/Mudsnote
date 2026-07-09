# 2026-07-09 source list count hierarchy

## Request

Continue the Apple Notes parity goal after source-list font hierarchy tuning. The selected `All iCloud` row still made the count use the same warm gold as the title/icon, while Apple Notes keeps counts more restrained and secondary.

## Baseline

- Branch: `main`
- HEAD before work: `598c120 Tune Notes source list hierarchy`
- Dirty files before work: none
- Prior visual QA: `/tmp/mudsnote-visual-qa-source-list-font-hierarchy-final/apple-notes-vs-mudsnote.png`

## Changes

- Added `LibrarySourceSelectionPalette.selectedCountColor`.
- Kept selected source titles/icons warm gold.
- Changed selected source counts to a subdued label-color alpha instead of the selected title/icon color.
- Kept unselected counts on `panelTertiaryTextColor()`.
- Updated regression coverage for selected and unselected source count colors.
- Updated the Apple Notes parity roadmap.

## Verification

- Passed: `swift test --filter MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote`
- Passed: `swift test --filter MarkdownRichEditorTests/libraryCallRecordingsSourceFiltersExistingSnapshot`
- Passed: `swift test`
- Passed: `git diff --check`
- Passed: `./scripts/package_app.sh`
- Passed: `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=empty ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-source-list-count-hierarchy-final`
- Visual QA metadata confirmed `frontmost_before_capture=Mudsnote`, `selected_fixture=empty`, and `mudsnote_window_bounds=x=46,y=78,width=1420,height=860`.
- Visual inspection confirmed the selected source row count is restrained gray instead of competing with the warm selected title/icon color.

## Decisions

- Keep this presentation-only and performance-neutral. Source count computation and snapshot refresh behavior are unchanged.
- Do not change source row height, source column width, selected-row fill, or source row ordering.

## Next

- Continue with source-list disclosure spacing/count alignment or note-list visual parity.
