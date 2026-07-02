# 2026-07-02 search scope highlights

## Request

Continue toward full Apple Notes parity for the macOS library while keeping Mudsnote local-first and lightweight.

## Baseline

- Branch: main
- HEAD: c87269a
- Dirty files before work: none

## Changes

- Added a compact `当前 / 所有` search scope control to the note-list header.
- Changed active library searches to use `NoteStore.searchNotes`, so matching body lines appear as snippets.
- Kept empty-query loading on the existing recent-backed fast path.
- Added match highlighting in note-list title and snippet labels.
- Added lightweight trash-scope search support so deleted notes can still be searched without leaving Recently Deleted.

## Verification

- `swift test` passed with 65 tests.
- `git diff --check` passed.
- XcodeBuildMCP `build_sim` passed for `iOS/MudsnoteCompanion.xcodeproj`, scheme `MudsnoteCompanion`, simulator `iPhone 17`.
- `./scripts/device_smoke.sh` is still blocked by CoreDevice/DDI state: paired device `MudsPhone` is visible, but Xcode/CoreDevice reports `State unavailable` and `ddiServicesAvailable: false`.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app smoke launched `/Applications/Mudsnote.app` and showed the `Mudsnote 笔记` window at `1040x764`.
- Visual smoke screenshot: `/tmp/mudsnote-window-search-scope-highlights-final.png`.
- Regression coverage now verifies:
  - current-folder search returns only the selected folder's matching note
  - all-notes search returns matches across folders
  - snippets come from the matching body line
  - title and snippet matches receive highlight attributes

## Decisions

- Search scope is a note-list concern, so the compact scope control lives in the middle column header rather than adding more toolbar width pressure.
- Full indexing remains future P3 work; this slice improves result quality without adding a cache or database.

## Next

- Run the remaining verification ladder.
- Continue with search empty states/result navigation or source-list folder hierarchy.
