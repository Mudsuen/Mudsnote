# 2026-07-09 toolbar icon state

## Request

Continue the active Apple Notes parity goal after restoring the earlier compact toolbar direction. The user called out that the older toolbar pass looked closer because the button row did not have an obvious white rim and later UI passes became too large.

## Baseline

- Branch: `main`
- HEAD before work: `51e2aa3 Tune Notes editor body size`
- Dirty files before work: none
- Prior visual QA: `/tmp/mudsnote-visual-qa-editor-body-size-final/apple-notes-vs-mudsnote.png`

## Changes

- Kept the compact `184x32` editor-tools capsule, `30x28` menu buttons, and no-rim border treatment unchanged.
- Added explicit toolbar icon tint alpha constants for enabled and disabled custom toolbar controls.
- Changed disabled custom toolbar buttons from whole-control alpha fading to icon-level tinting with stable `alphaValue = 1`.
- Kept disabled editor tool controls non-interactive while preserving the capsule's dark fill instead of fading the entire group.
- Extended toolbar-state regression tests to cover editor tool button tint, share/export tint, and more-menu tint across empty, new-note, selected-note, and trash states.
- Updated the Apple Notes parity roadmap with the icon-level toolbar state contract.

## Verification

- Passed: `swift test --filter MarkdownRichEditorTests/libraryToolbarUsesNotesLikeDisabledStates`
- Passed: `swift test`
- Passed: `git diff --check`
- Passed: `./scripts/package_app.sh`
- Passed: `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=empty ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-toolbar-icon-state-final`
- Visual QA metadata confirmed `frontmost_before_capture=Mudsnote`, `selected_fixture=empty`, and `mudsnote_window_bounds=x=46,y=78,width=1420,height=860`.
- Visual inspection confirmed the compact toolbar and no-rim editor-tools capsule baseline stayed intact. The selected empty-note fixture still enables editing actions, so disabled icon tint is verified by the toolbar-state regression test rather than that screenshot alone.

## Decisions

- Do not re-enlarge toolbar buttons or the window shell; the accepted direction is the earlier compact Notes-like toolbar baseline.
- Avoid adding new toolbar wrapper views or visual effects. This pass only changes existing button state presentation.
- Keep behavior unchanged: disabled buttons remain disabled, menus and validation rules are not relaxed.

## Next

- Continue with per-symbol toolbar alignment or source-list hierarchy tuning after visual QA.
