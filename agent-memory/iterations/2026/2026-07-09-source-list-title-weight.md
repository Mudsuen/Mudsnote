# 2026-07-09 source list title weight

## Request

Continue the active Apple Notes parity goal after the note-list typography pass, focusing on the source-list hierarchy while keeping the compact toolbar/window baseline.

## Baseline

- Branch: `main`
- HEAD before work: `e885bd7 Strengthen Notes list typography`
- Dirty files before work: none
- Prior visual QA: `/tmp/mudsnote-visual-qa-note-list-type-weight-final/apple-notes-vs-mudsnote.png`

## Changes

- Added explicit source-list title and symbol weight constants to `LibraryNotesLayout`.
- Strengthened source-list row titles from medium to semibold.
- Strengthened source-list SF Symbols from regular to medium.
- Preserved source-list row height, font size, column width, counts, selection tint, toolbar scale, and window size.
- Added regression coverage for the new source-list weight constants and icon configuration.
- Updated the Apple Notes parity roadmap with the stronger source-list title/icon hierarchy.

## Verification

- Passed: `swift test --filter MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote`
- Passed: `swift test`
- Passed: `git diff --check`
- Passed: `./scripts/package_app.sh`
- Passed: `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-source-list-title-weight-final`
- Visual QA metadata confirmed `frontmost_before_capture=Mudsnote` and `mudsnote_window_bounds=x=46,y=78,width=1420,height=860`.
- Visual inspection confirmed the source-list title/icon hierarchy reads clearer while row height, font size, window size, and toolbar scale remain unchanged.

## Decisions

- Keep the change local to presentation constants; do not add source-list data loading, count refresh, or filesystem work.
- Use weight rather than size to improve Notes-like scan hierarchy without reintroducing oversized controls.

## Next

- Continue with editor date/title rhythm or remaining source-list hierarchy details after visual QA.
