# 2026-07-09 toolbar icon luminance

## Request

Continue the active Apple Notes parity goal with the compact toolbar direction preserved. The latest side-by-side crop showed the Mudsnote toolbar controls were structurally close but the enabled custom toolbar symbols still read brighter and more custom than Notes.

## Baseline

- Branch: `main`
- HEAD before work: `b603cb9 Tune Notes toolbar icon states`
- Dirty files before work: none
- Prior visual QA: `/tmp/mudsnote-visual-qa-toolbar-icon-state-final/apple-notes-vs-mudsnote.png`

## Changes

- Reduced the enabled custom toolbar icon tint alpha from `0.86` to `0.76`.
- Kept disabled icon alpha, toolbar capsule dimensions, menu-button dimensions, no-rim border behavior, and all toolbar validation/menu behavior unchanged.
- Updated the toolbar-state regression expectation and Apple Notes parity roadmap.

## Verification

- Passed: `swift test --filter MarkdownRichEditorTests/libraryToolbarUsesNotesLikeDisabledStates`
- Passed: `swift test`
- Passed: `git diff --check`
- Passed: `./scripts/package_app.sh`
- Passed: `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=empty ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-toolbar-icon-luminance-final`
- Visual QA metadata confirmed `frontmost_before_capture=Mudsnote`, `selected_fixture=empty`, and `mudsnote_window_bounds=x=46,y=78,width=1420,height=860`.
- Visual inspection confirmed the toolbar remains compact and no-rim while enabled custom toolbar symbols read calmer against the Notes reference.

## Decisions

- Tune symbol luminance instead of enlarging or re-spacing controls, because the user called out that the earlier smaller toolbar was closer to Notes.
- Keep this as a presentation-only change; it does not alter note loading, editing, search, or file I/O.

## Next

- Continue with source-list hierarchy visual tuning or remaining toolbar per-symbol polish.
