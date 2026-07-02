# 2026-07-02 nested folder source rows

## Request

Drop iOS real-device verification from the active goal and continue the remaining macOS Apple Notes parity work.

## Baseline

- Branch: main
- HEAD: f927fed
- Dirty files before work: none
- Goal adjustment: iOS real-device install/smoke is no longer part of the active working scope.

## Changes

- Added a `LibraryFolderRow` model for source-list folder rows.
- Expanded preferred folder roots into bounded local subfolder rows with indentation.
- Kept selection on the existing `.folder(URL)` scope, so nested folders reuse current note loading, search, and save behavior.
- Updated folder counts to include descendant notes, matching the recursive folder scope behavior.
- Included nested folders in the move-note menu with visible indentation.
- Added regression coverage for:
  - nested folder rows appearing in the source list
  - selecting a nested folder
  - note list results matching the nested folder
  - move-note menu including the nested destination

## Verification

- `swift test` passed with 66 tests.
- `git diff --check` passed.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app smoke launched `/Applications/Mudsnote.app` with no arguments and showed `Mudsnote 笔记` at `1040x764`.
- Visual smoke screenshot: `/tmp/mudsnote-nested-folder-source-list.png`.

## Decisions

- This slice reads the filesystem directly and does not add a database or metadata cache.
- Disclosure/collapse state is deferred; this pass focuses on making nested folders visible and selectable.
- iOS real-device verification is explicitly excluded from this scope after the user's instruction.

## Next

- Add collapsible disclosure controls for folder rows.
- Continue with editor title/date spacing, toolbar disabled states, and keyboard navigation.
