# Existing macOS PR verification blockers

During the macOS overview map/outline change, `./scripts/verify macos pr`
encountered existing blockers unrelated to the new presentation. They reproduce on
unchanged `78ca90e185f703052901542c90134bb8a48c01e3` in a detached temporary worktree:

- `librarySplitLayoutPersistsAcrossWindows` restores a 238-point sidebar instead
  of the test's requested 300 points (two expectations differ by 62 points).
- `libraryNavigationDoesNotWaitForMatchingBackgroundAutosave` blocks while
  selecting the other row. A process sample on the modified checkout shows
  `beginLibraryPageNavigation` calling `commitOverviewEditor`, which drains the
  deliberately blocked background writer. The unchanged baseline also remains
  blocked and was terminated after 25 seconds.
- A supplementary run excluding those two tests also blocks in
  `failedAutosaveAfterNavigationBlocksExitAndKeepsRecoverableEdit`, with the same
  sampled navigation/drain path. The unchanged baseline reproduces that block
  as well (terminated after 12 seconds).

The new hierarchy, switch/fold/save, note creation, navigation, and pointer
checks pass via `./scripts/verify macos ui` (18 tests). Delivery uses these scoped
checks and synthetic-window acceptance; do not describe the full PR gate as
passing. No verification controller or unrelated navigation code was changed.

## Resolution — 2026-11-04

The startup-update delivery work repaired both blockers rather than publishing
another scoped-only bundle. Ordinary navigation no longer calls the synchronous
overview editor drain; existing background handoff and failed-write exit tests
pass. The embedded split view retains a low-priority width preference after
programmatic divider changes, so Auto Layout no longer resets it to minimum
width. The unmodified split persistence test passes. `verify macos pr` passes
402 Swift tests plus 18 synthetic Python updater tests.
