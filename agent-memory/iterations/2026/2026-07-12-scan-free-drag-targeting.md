# Scan-free drag targeting

## Baseline

- Started from `de99b15 Match Notes group spacing`.
- Preserved the unrelated iOS UI-test worktree change.

## Change

- Removed the lazy movable-note cache that synchronously called `listNotes(limit: 10_000)` during the first drag hit test.
- Removed nine cache-invalidating mutation hooks that existed only to support that scan.
- Replaced membership lookup with configured-library-root containment, preserving file existence, Markdown extension, current-folder, trash, external-file, and attachment-directory rejection.
- Added attachment-directory Markdown coverage to the existing multi-note drag lifecycle test.

## Verification

- The focused folder/drag lifecycle test passed.
- `rg` confirms the 10,000-note movable-path scan and cache are absent from `LibraryWindowController`.
- The full Swift test suite passed.
- Final packaging, signing, and installed-app checks are recorded in the completion commit.
- Iteration 152 visual confirmation remains independently pending while the desktop frontmost process is `loginwindow`.
