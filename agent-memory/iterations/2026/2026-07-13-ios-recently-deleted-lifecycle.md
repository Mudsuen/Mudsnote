# 2026-07-13 iOS Recently Deleted lifecycle

## Request

Continue the Notes-style iPhone lifecycle while preserving Mudsnote capture and
Markdown behavior.

## Baseline

- Branch: `main`
- Starting implementation checkpoint: `7e90c4c`
- Concurrent macOS changes were left untouched.

## Changes

- Added a hidden, library-local `.mudsnote/Trash` with per-note recovery metadata.
- Added coordinated move to Recently Deleted, restore to the original folder,
  collision-safe restore naming, and permanent deletion.
- Protected `Inbox.md`, `Daily`, attachments, and internal paths from destructive
  note lifecycle operations.
- Published Recently Deleted inventory and counts with the immutable library
  snapshot.
- Added Notes-style home navigation, swipe/context actions, empty state, restore,
  and confirmed permanent deletion.
- Added Simplified Chinese localization for every new lifecycle state and action.
- Added a real UI fixture and end-to-end delete/restore UI test.

## Verification

- Generic iOS Simulator SDK build passed without booting a simulator.
- Store lifecycle tests: 2 passed on one iPhone 17 Pro / iOS 26.5 simulator.
- Full suite after the lifecycle implementation: 44 passed, 0 failed, 0 skipped.
- End-to-end delete/restore UI flow: 1 passed.
- Result bundles:
  - `/tmp/MudsnoteTrashFull.xcresult`
  - `/tmp/MudsnoteTrashUI.xcresult`
- Parallel testing was disabled and all simulators were shut down afterward.

## Decisions

- Trash state travels with the Markdown library rather than living only in app
  preferences.
- Recovery metadata uses authorized relative paths; UUID payload names prevent path
  injection and filename leakage.
- Permanent deletion always requires explicit confirmation in the UI.

## Next

- Implement atomic folder create/rename/delete and note move operations.
- Add pin state without writing proprietary data into Markdown bodies.
- Continue the Notes-style list and editor parity phases.
