# 2026-07-08 visual QA canonical window size

## Request

Continue the active Apple Notes parity goal, prioritizing desktop UI alignment while keeping the app lightweight and performant.

## Baseline

- Branch: `main`
- HEAD before work: `5aa2e4c Match Notes call recordings icon`
- Dirty files before work: none
- Visual baseline: `/tmp/mudsnote-visual-qa-active-next-baseline/apple-notes-vs-mudsnote.png`
- Baseline metadata showed `mudsnote_window_bounds=x=426,y=198,width=1040,height=740`, which is the minimum shell after `presentedWindowSize(in:)` clamped to the current small visible frame.
- The smaller QA window caused toolbar overflow and invalidated side-by-side comparison against the Apple Notes reference.

## Changes

- Added `LibraryNotesLayout.presentedWindowSize(in:usesCanonicalSize:)`.
- Added a `usesCanonicalWindowSize` option to `LibraryWindowController`.
- Added `--visual-qa-canonical-window-size` parsing in `AppController`.
- Updated `scripts/visual_notes_qa.sh` to pass the QA-only canonical sizing flag.
- Added regression coverage proving normal launch still clamps to the visible frame while visual QA can request the canonical `1420x860` Notes shell.
- Updated the parity roadmap with the canonical visual-QA capture rule.

## Verification

- Commands run:
  - `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/defaultLaunchOpensLibraryUnlessAnotherSurfaceIsRequested|MarkdownRichEditorTests/appControllerVisualQAModeUsesIsolatedNoteStore'`
  - `bash -n scripts/visual_notes_qa.sh`
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh`
  - `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-canonical-window-size-final`
- App/package actually opened:
  - `/Applications/Mudsnote.app` via the final visual QA harness.
- Result:
  - Focused visual-QA/layout tests passed.
  - Visual QA script syntax passed.
  - Full `swift test` passed with 100 tests in 2 suites.
  - `git diff --check` passed.
  - Packaged app refreshed at `/Applications/Mudsnote.app`.
  - Final visual QA captured `/tmp/mudsnote-visual-qa-canonical-window-size-final/apple-notes-vs-mudsnote.png`.
  - Final metadata recorded `mudsnote_window_bounds=x=46,y=78,width=1420,height=860`, `selected_fixture=content`, and `frontmost_before_capture=Mudsnote`.
  - Visual inspection confirmed the toolbar overflow caused by the prior `1040x740` capture is gone.

## Decisions

- Keep ordinary user-facing windows screen-clamped for small displays.
- Use the canonical size only for visual QA, because side-by-side parity checks need a stable comparable window state.

## Next

- Resume toolbar menu-button visual tuning after QA window sizing is stable again.
