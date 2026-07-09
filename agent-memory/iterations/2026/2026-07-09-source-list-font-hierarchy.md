# 2026-07-09 source list font hierarchy

## Request

Continue the Apple Notes parity goal after the toolbar luminance pass. The next visible mismatch is source-list hierarchy: rows should stay compact and readable without every unselected source reading as heavily as the selected row.

## Baseline

- Branch: `main`
- HEAD before work: `77b0a52 Tune Notes toolbar luminance`
- Dirty files before work: none
- Prior visual QA: `/tmp/mudsnote-visual-qa-toolbar-icon-luminance-final/apple-notes-vs-mudsnote.png`

## Changes

- Added separate source-list font-weight constants for selected and unselected rows.
- Kept selected source rows at `semibold`.
- Changed unselected source rows to `medium`, while preserving the existing source-row font size, row height, icon size, tint, counts, column width, and data loading behavior.
- Updated source-list regression coverage to assert selected rows are visually heavier than unselected rows.
- Updated the Apple Notes parity roadmap with the source-list font hierarchy contract.

## Verification

- Passed: `swift test --filter MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote`
- Passed: `swift test`
- Passed: `git diff --check`
- Passed: `./scripts/package_app.sh`
- Passed: `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=empty ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-source-list-font-hierarchy-final`
- Visual QA metadata confirmed `frontmost_before_capture=Mudsnote`, `selected_fixture=empty`, and `mudsnote_window_bounds=x=46,y=78,width=1420,height=860`.
- Visual inspection confirmed source-list row weight hierarchy changed without altering window, source-column, row-height, or toolbar proportions.

## Decisions

- Do not change source-list row height, column width, or window size; the goal is visual hierarchy, not a larger shell.
- Keep this presentation-only and performance-neutral. No search, indexing, folder traversal, or persistence behavior changes.

## Next

- Continue with source-list disclosure/count alignment or note-list drag edge-state polish.
