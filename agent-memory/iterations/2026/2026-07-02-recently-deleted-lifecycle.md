# 2026-07-02 Recently Deleted lifecycle

## Request

Continue toward full Apple Notes function and UI parity for the Mudsnote macOS library, while keeping the app lightweight and local-first.

## Baseline

- Branch: main
- HEAD: 84bec4d
- Dirty files before work: none

## Changes

- Added a local Trash directory under Mudsnote app support.
- Added encoded Trash metadata so deleted notes can restore to their original paths.
- Added `NoteStore` APIs for:
  - delete note to Trash
  - list trashed notes
  - restore trashed notes
  - permanently delete trashed notes
- Added a `最近删除` source-list row to the library window.
- Added toolbar delete and restore actions.
- Made trashed notes read-only in the editor pane.
- Kept Markdown files as the source of truth; Trash is a reversible local file move, not a database migration.

## Verification

- `swift test` passed with 61 tests.
- `git diff --check` passed.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged smoke launched `/Applications/Mudsnote.app` and showed a visible `Mudsnote 笔记` window at `1040x764`.
- Visual QA screenshot: `/tmp/mudsnote-window-recently-deleted-lifecycle.png`
  - `最近删除` source row is visible.
  - Delete and restore toolbar actions are visible.
- Installed-app smoke did not delete a real user note; destructive behavior is covered by isolated App and Core tests.

## Decisions

- Use app-support Trash plus original-path metadata for reversible deletion.
- Keep trashed notes read-only until restored.
- Permanent deletion is only available while viewing `最近删除`.

## Next

- Add folder create/rename/delete and move-note workflows next.
- Revisit toolbar grouping so delete/restore live closer to Apple Notes' more-actions model once formatting/table/attachment controls are added.
