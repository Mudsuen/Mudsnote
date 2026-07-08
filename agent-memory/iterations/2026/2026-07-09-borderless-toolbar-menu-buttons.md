# 2026-07-09 borderless toolbar menu buttons

## Request

Continue the active Apple Notes parity goal, prioritizing desktop UI alignment while keeping the app lightweight and performant.

## Baseline

- Branch: `main`
- HEAD before work: `adaa050 Stabilize Notes visual QA window size`
- Dirty files before work: none
- Visual baseline: `/tmp/mudsnote-visual-qa-canonical-window-size-final/apple-notes-vs-mudsnote.png`
- After canonical visual-QA sizing was fixed, the remaining toolbar mismatch was that share/export and more actions still used `NSMenuToolbarItem`, which adds a heavier system menu-button treatment than the lighter Apple Notes toolbar icons.

## Changes

- Replaced the share/export and more toolbar entries with borderless custom `NSButton` toolbar views.
- Kept the existing menu-building functions and actions, so clicking the buttons still opens the same share/export and more-actions menus.
- Switched the more icon from `ellipsis.circle` to the lighter `ellipsis` symbol.
- Added shared menu-button layout constants for width, height, and disabled alpha.
- Updated toolbar state refresh to enable/disable the custom menu buttons directly.
- Added regression coverage for borderless share/more toolbar button views and unchanged share/export menu ordering.
- Updated the Apple Notes parity roadmap with the borderless icon-menu toolbar rule.

## Verification

- Passed: `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryToolbarUsesNotesLikeDisabledStates|MarkdownRichEditorTests/libraryWindowSharesExportsAndDeletesMultipleSelectedNotes'`
- Passed: `swift test`
- Passed: `git diff --check`
- Passed: `./scripts/package_app.sh`
- Passed: `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-borderless-toolbar-menu-buttons-final`
- Visual QA metadata confirmed `frontmost_before_capture=Mudsnote` and `mudsnote_window_bounds=x=46,y=78,width=1420,height=860`.
- Visual inspection confirmed share/export and more buttons no longer use heavy menu-button chrome; the remaining parity gaps are source-list sizing, note-list selected-row geometry, and overall split proportions.

## Decisions

- Keep menu content local and generated on click; this avoids stale menus without storing additional toolbar menu state.
- Do not reintroduce system menu toolbar chrome for share/more unless Apple Notes parity evidence changes.

## Next

- Continue source-list hierarchy and note-list selected-row geometry tuning from the final visual QA output.
