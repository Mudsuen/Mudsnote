# 2026-07-09 note list type weight

## Request

Continue the active Apple Notes parity goal after the selected-row gold pass, focusing next on source/list typography without enlarging the toolbar or window.

## Baseline

- Branch: `main`
- HEAD before work: `bab7670 Tune Notes selected row gold`
- Dirty files before work: none
- Prior visual QA: `/tmp/mudsnote-visual-qa-selection-gold-final2/apple-notes-vs-mudsnote.png`

## Changes

- Added explicit note-list font-weight constants to `LibraryNotesLayout`.
- Strengthened note-list note titles from semibold to bold.
- Strengthened note-list preview text from regular to medium.
- Kept row height, font sizes, column widths, toolbar scale, and selected-row geometry unchanged.
- Added regression coverage for the font-weight constants.
- Updated the Apple Notes parity roadmap with the stronger title/preview hierarchy.

## Verification

- Passed: `swift test --filter MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote`
- Passed: `swift test`
- Passed: `git diff --check`
- Passed: `./scripts/package_app.sh`
- Passed: `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-note-list-type-weight-final`
- Visual QA metadata confirmed `frontmost_before_capture=Mudsnote` and `mudsnote_window_bounds=x=46,y=78,width=1420,height=860`.
- Visual inspection confirmed the note-list title and preview hierarchy reads stronger while toolbar size, row height, and window sizing remain unchanged.

## Decisions

- Keep this as a typography hierarchy change rather than a scale change; the user already pushed back on oversized toolbar/window treatment.
- Preserve the compact row rhythm while making the middle pane read closer to Apple Notes at a glance.

## Next

- Continue with source-list hierarchy or editor date/title rhythm after this visual QA.
