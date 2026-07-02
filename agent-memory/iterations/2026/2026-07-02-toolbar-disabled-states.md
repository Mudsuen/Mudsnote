# 2026-07-02 toolbar disabled states

## Request

Continue iterating Mudsnote toward Apple Notes UI, functionality, interaction, and performance parity, with iOS real-device validation removed from the active goal.

## Baseline

- Branch: main
- Dirty files before work: none.
- Active scope: macOS Apple Notes-style library/editor parity.
- Current roadmap gap: toolbar disabled states still felt less Notes-like.

## Changes

- Added shared state helpers for:
  - selected-note availability
  - editable-document availability
  - move availability
  - trash restore availability
  - more-actions availability
- Updated toolbar validation to use those helpers.
- Updated the more-actions menu and note context menu to use the same state.
- Added defensive guards to formatting, checklist, table, link, attachment, more-actions, and move actions.
- Empty libraries now disable editing and note actions until a new note is started.
- New blank notes enable editing/save actions.
- Recently Deleted disables editing/save actions while leaving restore and permanent delete available for selected trash notes.

## Verification

- Focused regression: `swift test --filter libraryToolbarUsesNotesLikeDisabledStates` passed.
- `swift test` passed with 70 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app smoke launched `/Applications/Mudsnote.app` directly and showed the `Mudsnote 笔记` main window at `1040x764`.
- Visual smoke screenshot: `/tmp/mudsnote-toolbar-disabled-states-smoke.png`.

## Decisions

- Keep disabled-state logic local to the library controller for now because it is tied to selected scope, editor dirtiness, and visible note lifecycle state.
- Do not introduce a broader command bus until action state is needed across multiple windows.

## Next

- Continue with share/export polish, side-by-side visual QA, note-list row spacing, and attachment previews.
