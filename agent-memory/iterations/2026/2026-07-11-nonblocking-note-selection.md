# 2026-07-11 nonblocking note selection

## Request

Continue Apple Notes parity while keeping the architecture lightweight and making visible note navigation as responsive as possible.

## Baseline

- Branch: `main`
- macOS HEAD before work: `6d51486 Persist Notes workspace layout`
- The bounded 32-entry cache and adjacent utility-priority prefetch already removed repeated reads for nearby notes.
- A visible cache miss still called `noteStore.loadNote(at:)` synchronously from `load(note:)`, so Markdown file reading blocked the main thread.
- Prior same-height visual QA had already established the current `44pt` source rows and `108pt` note rows; the earlier compact values were too dense, so this iteration did not revert list geometry.

## Changes

- Added a cancellable user-initiated load task and monotonically increasing load generation for visible-window cache misses.
- Kept cache hits immediate and file-backed freshness validation unchanged.
- Showed the existing lightweight title/date loading shell while an uncached note is read.
- Applied a result only when its generation and selected Markdown path still match the latest selection.
- Cancelled active loads when creating or removing a note and when closing the window.
- Cancelled lower-priority adjacent prefetch when the user selects a note, then restarted prefetch around the successfully loaded selection.
- Kept hidden-window tests and deterministic visual-QA selection synchronous so verification remains stable without changing production behavior.

## Verification

- Commands run:
  - `swift test --filter visibleLibraryLoadsUncachedNotesOffMainAndIgnoresStaleResults`
  - focused cache, keyboard-navigation, visual-QA, autosave, and missing-recent regression tests
  - `swift test`
  - `git diff --check`
  - `./scripts/package_app.sh`
  - `codesign --verify --deep --strict --verbose=2 /Applications/Mudsnote.app`
  - `MUDSNOTE_VISUAL_QA_SELECTED_FIXTURE=content ./scripts/visual_notes_qa.sh /tmp/mudsnote-async-load-visual-20260711`
- Result:
  - Full suite passed: 118 tests across 2 suites.
  - The regression test delayed an older load by `450ms`, selected another uncached note immediately, and confirmed the older completion never replaced the latest title or body.
  - Final installed-app QA used a roughly 13 MB uncached Markdown note: Accessibility selection returned in `1.32ms`, the immediate target reselection returned in `0.53ms`, and after three seconds the editor still showed `Target 4 / Target body 4`.
  - The final content-state screenshot remained byte-identical to the pre-change package: SHA-256 `0f25ff7f1cfffdc5babb7fb77ed8e162a7475b8b0d266652a297f7f6fdec63a7`.
  - Comparison output: `/tmp/mudsnote-async-load-visual-20260711/apple-notes-vs-mudsnote.png`.
  - Strict code-signature verification passed.

## Decisions

- Preserve measured source/note geometry and the approved compact toolbar.
- Keep the existing bounded cache instead of introducing a database or duplicate document model.
- Give active selection higher scheduling priority than speculative adjacent prefetch.
- Use latest-request-wins generation checks rather than allowing completion order to control the editor.

## Next

- Continue from the next largest measured visual or everyday editing gap without regressing the nonblocking navigation path.
