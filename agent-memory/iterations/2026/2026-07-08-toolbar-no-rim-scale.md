# 2026-07-08 toolbar no-rim scale

## Request

Continue the active Apple Notes parity goal after the user confirmed the earlier toolbar version looked closer, especially the editor-tools group without a prominent white rim.

## Baseline

- Branch: `main`
- HEAD before work: `7b67067 Tighten Notes editor inset`
- Dirty files before work: none
- Visual baseline: keep the earlier compact/no-rim toolbar direction while preserving the current compact `1420x860` Notes shell and the newer source/list/editor refinements.

## Changes

- Tightened the editor-tools group from `192x34` to `184x32`.
- Reduced each editor tool button from `37x28` to `35x26`.
- Reduced shared toolbar symbols from `20pt` to `19pt` and scaled the custom `Aa` image with it.
- Replaced the editor-tools capsule backing view with a plain layer-backed `NSView` so AppKit visual-effect material no longer adds a bright rim.
- Reduced enabled/disabled capsule fill alpha from `0.48/0.26` to `0.40/0.22`.
- Updated tests and the Apple Notes parity roadmap to lock this compact no-rim toolbar baseline.

## Verification

- Commands run:
  - `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryToolbarUsesNotesLikeDisabledStates|MarkdownRichEditorTests/libraryWindowEditorToolbarInsertsRichMarkdownTools'`
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh`
  - `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-toolbar-no-rim-scale-final`
- App/package actually opened:
  - `/Applications/Mudsnote.app` via the visual QA harness.
- Result:
  - Focused toolbar/editor tests passed.
  - Full `swift test` passed with 100 tests in 2 suites.
  - `git diff --check` passed.
  - Packaged app refreshed at `/Applications/Mudsnote.app`.
  - Visual QA captured `/tmp/mudsnote-visual-qa-toolbar-no-rim-scale-final/apple-notes-vs-mudsnote.png`.
  - Visual QA metadata recorded `mudsnote_window_bounds=x=46,y=78,width=1420,height=860`, `selected_fixture=content`, and `frontmost_before_capture=Mudsnote`.
  - Visual inspection confirmed the editor-tools capsule no longer has the obvious bright rim and reads lighter than the previous toolbar pass.

## Decisions

- Treat the earlier compact, borderless toolbar as the visual target, but do not roll back later source-list, note-list, editor, or launch-flow work.
- Keep the main library window on the compact `1420x860` shell; this slice only lowers toolbar visual weight.

## Next

- Continue toolbar icon-state tuning against Notes after visual QA.
- Continue source/list density and selected-row parity without re-enlarging the toolbar.
