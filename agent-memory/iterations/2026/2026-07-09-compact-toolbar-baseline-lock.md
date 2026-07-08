# 2026-07-09 compact toolbar baseline lock

## Request

Continue the Apple Notes parity goal after the user confirmed the earlier compact toolbar version looked closer than the larger-button direction.

## Baseline

- Branch: `main`
- HEAD before work: `a68b4c2 Deduplicate weekday in Notes list previews`
- Dirty files before work: none
- User reference: the early editor-tools toolbar crop with a compact dark capsule and no obvious light rim.
- Historical baseline: keep the `a925b48` no-rim capsule direction and the `86ce4c7` compact toolbar scale, without returning the whole library window to the earlier undersized visual-QA shell.

## Changes

- Tightened custom share/export and more toolbar menu buttons from `32x30` to `30x28` so they do not read as oversized standalone buttons.
- Hardened the editor-tools capsule no-rim path by using a clear border color whenever rim alpha is zero.
- Clipped the editor-tools capsule layer to its rounded bounds and disabled focus rings on custom toolbar buttons.
- Extended toolbar regression coverage for the smaller menu-button constants and clipped capsule layer.
- Updated the Apple Notes parity roadmap to preserve the compact no-rim toolbar baseline.

## Verification

- Passed: `swift test --filter MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote`
- Passed: `swift test`
- Passed: `git diff --check`
- Passed: `./scripts/package_app.sh`
- Passed: `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-compact-toolbar-baseline-lock-final`
- Visual QA metadata confirmed `frontmost_before_capture=Mudsnote` and `mudsnote_window_bounds=x=46,y=78,width=1420,height=860`.
- Visual inspection confirmed the packaged app keeps the compact toolbar capsule without an obvious light rim; remaining visible deltas are source/list/editor proportions rather than oversized toolbar controls.

## Decisions

- Do not revert the whole UI to the early tiny-window visual QA state; it made the shell and editor less like the supplied Apple Notes reference.
- Treat the early toolbar's compact, dark, no-obvious-rim behavior as the fixed toolbar baseline for later UI passes.

## Next

- Continue visual tuning on toolbar icon placement, selected-row color, and source/list typography without enlarging the custom toolbar controls.
