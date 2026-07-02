# 2026-07-02 note-list empty states

## Request

Continue iterating Mudsnote toward Apple Notes UI, functionality, interaction, and performance parity, with iOS real-device validation removed from the active goal.

## Baseline

- Branch: main
- Dirty files before work: none
- Active scope: macOS Apple Notes-style library/editor parity.
- Current roadmap gap: richer note-list empty and no-result states.

## Changes

- Added a centered `LibraryNoteListEmptyLabel` overlay to the note-list column.
- Shows `未找到结果` when an active search returns no rows.
- Shows `最近删除为空` when the trash scope is empty.
- Shows `没有笔记` for empty normal scopes.
- Keeps the label hidden for non-empty lists.
- Uses the current `listRows` state after reload, so the empty-state UI does not add indexing, directory traversal, or note-body scanning.
- Added regression coverage for normal hidden state, empty search results, and empty trash after permanent delete.

## Verification

- `swift test` passed with 68 tests.
- `git diff --check` passed.
- Packaged-app smoke launched `/Applications/Mudsnote.app` directly and showed the `Mudsnote 笔记` main window at `1040x764`.
- Visual smoke screenshot: `/tmp/mudsnote-note-list-empty-state-smoke.png`.

## Decisions

- Keep empty-state copy short and Notes-like instead of explaining the feature.
- Do not introduce a search index or extra filesystem scan for this edge state.
- Keep iOS real-device validation out of the active verification path.

## Next

- Continue with exact note-list row spacing, thumbnail previews, source-list spacing, toolbar disabled states, and side-by-side visual QA.
