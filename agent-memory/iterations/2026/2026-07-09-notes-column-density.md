# 2026-07-09 Notes column density

## Request

Continue the active Apple Notes parity goal. The user pointed out that an earlier UI version looked closer to Apple Notes and that the newer version had oversized window/button proportions.

## Baseline

- Branch: `main`
- HEAD before work: `370f0cd Lighten Notes toolbar menu buttons`
- Dirty files before work: none
- Prior visual QA: `/tmp/mudsnote-visual-qa-borderless-toolbar-menu-buttons-final/apple-notes-vs-mudsnote.png`

## Changes

- Narrowed the library source column from `340` to `320`.
- Narrowed the note-list column from `340` to `304`, keeping the source column slightly wider like the Apple Notes reference.
- Reduced the note-list table width, toolbar title width, source row width, and source-list insets to keep the columns internally consistent.
- Reduced note-list selected and hover horizontal insets from `24` to `10` so selected notes read less like separate cards and more like Apple Notes rows.
- Tightened note-cell text leading/trailing insets to match the narrower row geometry.
- Updated regression tests to lock the new column arithmetic and row-selection geometry.
- Updated the Apple Notes parity roadmap with the narrower column and less-card-like selected-row state.

## Verification

- Passed: `swift test --filter MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote`
- Passed: `swift test`
- Passed: `git diff --check`
- Passed: `./scripts/package_app.sh`
- Passed: `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-notes-column-density-final`
- Visual QA metadata confirmed `frontmost_before_capture=Mudsnote` and `mudsnote_window_bounds=x=46,y=78,width=1420,height=860`.
- Visual inspection confirmed the source and note-list columns no longer take equal oversized space, the editor pane has more room, and selected note rows read closer to Apple Notes' list highlight.

## Decisions

- Keep the default `1420x860` visual-QA shell but adjust pane proportions inside it, rather than making the whole window larger.
- Keep the Notes-like source/list relationship at source column slightly wider than the note-list column.

## Next

- Use the visual QA output to decide whether the next pass should tune source-list hierarchy spacing or editor title/date rhythm.
