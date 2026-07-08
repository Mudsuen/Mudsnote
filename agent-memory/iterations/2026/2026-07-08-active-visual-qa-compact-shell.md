# 2026-07-08 active visual QA compact shell

## Request

Continue the active Mudsnote Apple Notes parity goal, using the earlier compact toolbar/window direction as the visual baseline while keeping the app lightweight and performant.

## Baseline

- Branch: `main`
- HEAD before work: `27ac542 Show zero counts for Notes folders`
- Dirty files before work: none
- Visual baseline: `/tmp/mudsnote-visual-qa-active-capture-probe/mudsnote-library.png` showed the source/list columns still taking too much of the window, while the editor-tools toolbar already matched the earlier compact borderless direction.

## Changes

- Hardened `scripts/visual_notes_qa.sh` so Mudsnote is explicitly activated before window discovery, after launch delay, and immediately before capture.
- Added `frontmost_before_capture` metadata so each visual QA artifact can prove whether the captured window state was active.
- Restored the library shell to the earlier compact `1420x860` presentation size instead of the larger `1600x940` canvas.
- Reduced source and note-list columns to `340pt`, the note table to `304pt`, source rows to `300pt`, and the toolbar search wrapper to `360pt`.
- Kept the editor-tools capsule on the existing compact, borderless toolbar baseline.
- Added regression expectations for the compact shell constants.
- Updated the parity roadmap with the active-capture QA and compact-shell decisions.

## Verification

- Commands run:
  - `bash -n scripts/visual_notes_qa.sh`
  - `./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-active-capture-probe`
  - `swift test --filter 'MarkdownRichEditorTests/libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|MarkdownRichEditorTests/libraryToolbarUsesNotesLikeDisabledStates|MarkdownRichEditorTests/appControllerVisualQAModeUsesIsolatedNoteStore|MarkdownRichEditorTests/librarySourceListShowsZeroCountsForEmptyFoldersLikeAppleNotes'`
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh && ./scripts/visual_notes_qa.sh /tmp/mudsnote-visual-qa-active-compact-shell-final`
- App/package actually opened:
  - `/Applications/Mudsnote.app` via the visual QA probe, before the compact-shell code was packaged.
  - `/Applications/Mudsnote.app` via the final visual QA harness after packaging.
- Result:
  - Shell syntax passed.
  - Probe visual QA captured `/tmp/mudsnote-visual-qa-active-capture-probe/apple-notes-vs-mudsnote.png`.
  - Probe metadata recorded `frontmost_before_capture=Mudsnote`.
  - Focused layout/toolbar/visual-QA tests passed.
  - Full `swift test` passed with 98 tests.
  - `git diff --check` passed.
  - Packaged app refreshed at `/Applications/Mudsnote.app`.
  - Final visual QA captured `/tmp/mudsnote-visual-qa-active-compact-shell-final/apple-notes-vs-mudsnote.png`.
  - Final metadata recorded `mudsnote_window_bounds=x=46,y=78,width=1420,height=860` and `frontmost_before_capture=Mudsnote`.
- Not verified:
  - iOS real-device validation remains intentionally out of scope for the current macOS Notes-parity goal.

## Decisions

- Visual QA should prove frontmost active capture; screenshots without this evidence can mislead toolbar/titlebar color and density comparisons.
- Keep the earlier compact, borderless editor-tools capsule as the toolbar baseline.
- Prefer compact Notes-like geometry over the enlarged canvas when the user flags buttons/window scale as oversized.

## Next

- Continue source-list typography/row rhythm and editor title/date spacing after the compact active-state baseline is verified.
