# 2026-07-09 editor date title rhythm

## Request

Continue the active Apple Notes parity goal, prioritizing visible desktop UI alignment while keeping the app lightweight and performant.

## Baseline

- Branch: `main`
- HEAD before work: `93c1f1f Tighten Notes library column density`
- Dirty files before work: none
- Prior visual QA: `/tmp/mudsnote-visual-qa-notes-column-density-final/apple-notes-vs-mudsnote.png`

## Changes

- Moved the editor date row slightly upward by reducing `editorTopInset` from `18` to `12`.
- Increased the date-to-title spacing from `28` to `42` so loaded-note titles sit farther below the centered date, closer to the Apple Notes reference.
- Kept title-to-body spacing and editor horizontal inset unchanged to avoid disturbing the editing surface.
- Updated layout regression coverage for the new editor vertical rhythm.
- Updated the Apple Notes parity roadmap with the current editor date/title rhythm state.

## Verification

- Passed: `swift test --filter MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote`
- Passed: `swift test`
- Passed: `git diff --check`
- Passed: `./scripts/package_app.sh`
- Passed: `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-editor-date-title-rhythm-final`
- Visual QA metadata confirmed `frontmost_before_capture=Mudsnote`, `mudsnote_window_bounds=x=77,y=102,width=1354,height=821`, and the captured Mudsnote image size as `1532x972 pt`.
- Visual inspection confirmed the editor date sits higher and the loaded-note title has a more Notes-like gap below the centered date without squeezing the body text.

## Decisions

- Tune editor rhythm through shared layout constants only; do not add custom layout code or new view structure for this pass.
- Preserve the existing editor body and serialization behavior.

## Next

- Use final visual QA to decide whether the next UI pass should target source-list hierarchy or toolbar icon placement.
