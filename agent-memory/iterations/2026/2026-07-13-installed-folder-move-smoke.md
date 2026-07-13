# Installed folder move smoke

## Request

Continue Apple Notes parity and expand installed-app evidence across the core note lifecycle.

## Baseline

- Branch: `main`
- HEAD: `0bf9f04`
- Dirty files before work: none

## Changes

- Added a state-validated File-menu submenu for moving selected notes into the current library folders.
- Reused the library controller's existing dynamic move targets and handlers instead of duplicating folder traversal or move behavior.
- Extended the isolated installed-app smoke to move the restored note into `Smoke Folder` and verify the corresponding filesystem transition.

## Verification

- Focused main-menu and nested-folder tests passed.
- `swift test`, `bash -n scripts/library_smoke.sh`, and `git diff --check` passed.
- Packaged and strictly signature-verified `/Applications/Mudsnote.app`.
- Final smoke: `/tmp/mudsnote-installed-library-smoke-183-final`, including `folder_move=.../Notes/Smoke Folder/2026-07-13-installed-smoke-note.md`.
- Visual QA: `/tmp/mudsnote-folder-move-visual-183/apple-notes-vs-mudsnote.png`; no visible toolbar or layout regression.

## Decisions

- Keep move-to-folder in the native File menu and contextual actions, not the toolbar.
- Rebuild the submenu on demand so it follows the current folder hierarchy and command state.

## Next

- Extend installed smoke coverage to attachment rendering.
