# 2026-07-09 note list row density

## Request

Continue the active Apple Notes parity goal, prioritizing visible UI alignment while preserving the lightweight local-first implementation.

## Baseline

- Branch: `main`
- HEAD before work: `79afb07 Polish Notes source list hierarchy`
- Dirty files before work: none
- Prior visual QA: `/tmp/mudsnote-visual-qa-source-list-hierarchy-polish-final/apple-notes-vs-mudsnote.png`

## Changes

- Reduced note-list recency group row height from `54` to `48`.
- Reduced note row height from `106` to `96`.
- Tightened note-cell vertical padding from `12/12` to `10/10`.
- Tightened note-cell internal text row spacing from `3` to `2`.
- Kept title/snippet/meta font sizes and thumbnail dimensions unchanged to preserve readability and attachment affordances.
- Updated layout regression coverage for the denser note-list rhythm.
- Updated the Apple Notes parity roadmap with the denser note-list state.

## Verification

- Passed: `swift test --filter MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote`
- Passed: `swift test`
- Passed: `git diff --check`
- Passed: `./scripts/package_app.sh`
- Passed: `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-note-list-row-density-final`
- Visual QA metadata confirmed `frontmost_before_capture=Mudsnote` and `mudsnote_window_bounds=x=46,y=78,width=1420,height=860`.
- Visual inspection confirmed the note list is denser, selected rows and three-line metadata remain readable, and the thumbnail/attachment affordance space is not compressed.

## Decisions

- Keep this pass visual-only: no note loading, grouping, drag/drop, search, or serialization behavior changes.
- Prefer tighter row geometry over reducing font size; Apple Notes parity should still preserve quick scanning.

## Next

- Use visual QA to decide whether toolbar icon placement or note-list selected-row color should be tuned next.
