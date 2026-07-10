# 2026-07-11 persistent split layout

## Request

Continue moving the macOS library toward Apple Notes while keeping the approved compact toolbar baseline and lightweight local-first architecture.

## Baseline

- Branch: `main`
- HEAD before work: `54bd355 Persist sidebar disclosure state`
- The source and note panes used required `320` and `304` point width constraints, so their split dividers could not retain user adjustments.
- Separate iOS reliability changes were already present in the worktree and were left untouched by this iteration.

## Changes

- Made the three-pane library use native draggable `NSSplitView` dividers instead of required width constraints.
- Kept startup defaults at `320 / 304`, bounded the source pane to `320...440`, the note pane to `304...480`, and preserved at least `360` points for the editor.
- Made the editor the only pane that absorbs ordinary whole-window resizing.
- Persisted source width, note width, and source-list visibility in `UserDefaults`.
- Coalesced continuous divider-resize notifications into one preference update after dragging settles; window close still persists immediately.
- Restored the saved layout after the window has its final presented size and when the source list is shown again.
- Added a real AppKit regression test that drags both dividers, hides the source list, creates a second library window, and verifies exact restoration.
- The persistence path does not parse notes, touch the search index, or add filesystem reads.

## Verification

- Commands run:
  - `swift test --filter 'MarkdownRichEditorTests/(libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|librarySplitLayoutPersistsAcrossWindows)'`
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh`
  - `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-split-layout-qa-20260711`
  - `codesign --verify --deep --strict --verbose=2 /Applications/Mudsnote.app`
- Result:
  - Full test run passed after the adjacent startup-recovery regression was added: 117 tests across 2 suites.
  - The installed app's Accessibility splitters were changed from `320 / 304` to `384 / 396`; the isolated defaults suite immediately recorded both values.
  - After terminating and relaunching the installed app with the same isolated library, both splitters restored to `384 / 396`.
  - Hiding the source list wrote `mudsnote.library.sourceListVisible = 0`; after another restart, the toolbar exposed `显示资料库`, proving the hidden state restored.
  - Showing the source list restored the same `384 / 396` divider values.
  - After resize writes were coalesced, the final installed package was adjusted to `400 / 410`; the preferences updated after the debounce window and a fresh process restored both exact values.
  - Installed-app screenshot: `/tmp/mudsnote-split-layout-qa-20260711/mudsnote-resized-restored.png`.
  - Strict code-signature verification passed.

## Decisions

- Keep layout state in tiny preferences rather than the note index or filesystem metadata.
- Preserve the existing default widths and compact toolbar; this iteration adds user control instead of enlarging the shell.
- Allow normal window resizing to change editor width first so navigation density remains stable.

## Next

- Continue the next measured Apple Notes visual delta from installed side-by-side evidence without changing the compact toolbar geometry.
