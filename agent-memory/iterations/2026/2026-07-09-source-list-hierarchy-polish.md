# 2026-07-09 source list hierarchy polish

## Request

Continue the active Apple Notes parity goal, with UI alignment first and performance preserved.

## Baseline

- Branch: `main`
- HEAD before work: `b55dfe2 Tune Notes editor date title rhythm`
- Dirty files before work: none
- Prior visual QA: `/tmp/mudsnote-visual-qa-editor-date-title-rhythm-final/apple-notes-vs-mudsnote.png`

## Changes

- Reduced the source-list top inset from `18` to `12` so the first smart-source row sits closer to the Notes toolbar rhythm.
- Tightened folder disclosure geometry by reducing the disclosure symbol from `11` to `10`, the disclosure control width from the previous hardcoded `16` to `14`, and the disclosure-to-label gap from `2` to `1`.
- Added explicit source-list constants for folder indent, disclosure control size, count trailing inset, count width, and row corner radius.
- Reduced count width/trailing from hardcoded values to `38` and `8` to keep counts more restrained inside the row.
- Unified source selected-row, hover, and drag corner radius through `sourceRowCornerRadius`.
- Updated regression tests to cover the new source-list hierarchy constants and selected-row corner radius.
- Updated the Apple Notes parity roadmap with the tightened source-list geometry state.

## Verification

- Passed: `swift test --filter MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote`
- Passed: `swift test`
- Passed: `git diff --check`
- Passed: `./scripts/package_app.sh`
- Passed: `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-source-list-hierarchy-polish-final`
- Visual QA metadata confirmed `frontmost_before_capture=Mudsnote` and `mudsnote_window_bounds=x=46,y=78,width=1420,height=860`.
- Visual inspection confirmed the source-list first row sits closer to the toolbar, folder disclosures and source counts are tighter, and the edit does not increase the overall sidebar weight.

## Decisions

- Keep this pass geometry-only; do not touch note loading, count calculation, drag/drop behavior, or source-list data flow.
- Prefer shared constants over hardcoded row geometry so future visual passes can tune the source list without searching implementation details.

## Next

- Continue source-list hierarchy visual tuning, then revisit toolbar icon placement after another side-by-side QA pass.
