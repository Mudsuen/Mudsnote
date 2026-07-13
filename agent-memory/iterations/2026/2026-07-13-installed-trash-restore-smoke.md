# Installed trash and restore smoke

## Request

Continue Apple Notes parity and expand installed-app evidence across the core note lifecycle.

## Baseline

- Branch: `main`
- HEAD: `b7d327a`
- Dirty files before work: none

## Changes

- Added state-validated File-menu actions for moving selected notes to Recently Deleted and restoring selected trashed notes.
- Extended the isolated installed-app smoke to execute both menu actions and verify the corresponding filesystem transitions.

## Verification

- Focused main-menu and trash lifecycle tests passed.
- `swift test`, `bash -n scripts/library_smoke.sh`, and `git diff --check` passed.
- Packaged and strictly signature-verified `/Applications/Mudsnote.app`.
- Final smoke: `/tmp/mudsnote-installed-library-smoke-182-final`, including `trash_restore=passed`.
- Visual QA: `/tmp/mudsnote-trash-menu-visual-182/apple-notes-vs-mudsnote.png`; no visible toolbar or layout regression.

## Decisions

- Keep delete/restore in the native File menu and context menus, not the toolbar.
- Enable each menu command only when the selected scope and note selection make it valid.

## Next

- Extend installed smoke coverage to folder move and attachment rendering.
