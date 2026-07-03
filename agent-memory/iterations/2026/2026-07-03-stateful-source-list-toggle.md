# 2026-07-03 - Stateful Source-list Toggle

## Context

The library toolbar already included a sidebar icon, but the action only toggled the source-list view without a durable state contract. Apple Notes-style toolbar controls should make their current action clear and should remain testable as future shortcuts or menu entries are added.

## Change

- Added `isSourceListVisibleForLibrary`, `toggleSourceListForLibrary()`, and `setSourceListVisibleForLibrary(_:)` as the source-list visibility contract.
- Updated the toolbar item's label, tooltip, and accessibility description between `隐藏资料库` and `显示资料库`.
- Added regression coverage that exercises the toolbar target/action path and verifies the source list hides and reappears.
- Kept this iteration macOS-only; iOS real-device validation is excluded from the current goal.

## Verification

- `swift test --filter libraryWindowUsesNotesLikeSplitAndLoadsFirstNote` passed.
- `swift test` passed with 81 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged-app smoke confirmed direct library launch exposes a `Mudsnote 笔记` window.
- Visual QA was skipped after a screen-capture probe returned a pure-black image (`nonBlack=0`) in the current macOS session; the tested toolbar target/action path covers this iteration's behavior.
- `git diff --check` passed.
