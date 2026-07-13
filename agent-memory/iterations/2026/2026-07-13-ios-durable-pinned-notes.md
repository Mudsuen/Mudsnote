# 2026-07-13 iOS durable pinned notes

## Request

Close the remaining P0 Notes-style iPhone lifecycle gap with durable pinning while
preserving portable Markdown and Mudsnote capture behavior.

## Baseline

- Branch: `main`
- HEAD: `848891e`
- Concurrent macOS library/editor files were preserved and not staged with iOS work.

## Changes

- Added library-local `.mudsnote/pins.json` metadata without modifying Markdown
  bodies.
- Added pin/unpin swipe and context actions, pin indicators, and Notes-style Pinned
  and Notes sections.
- Pinned notes sort ahead of ordinary notes while retaining modification-date order
  inside each group.
- Pin paths migrate transactionally across note moves and folder renames.
- Moving a pinned note to Recently Deleted removes the active pin; restoring it
  restores its prior pinned state.
- Missing, malformed, or oversized optional pin metadata safely degrades to no pins
  instead of blocking the library.
- Security-scoped access begins before pin file validation for physical-device iCloud
  reliability.
- Added Simplified Chinese pin/unpin and section localization.

## Verification

- Generic iOS Simulator SDK build passed without booting a simulator.
- Focused persistence/recovery tests: 2 passed.
- End-to-end swipe pin/unpin UI test: 1 passed.
- Full App and UI suite: 51 passed, 0 failed, 0 skipped.
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled.
- All simulators were shut down afterward.
- Result bundles:
  - `/tmp/MudsnotePinFocused.xcresult`
  - `/tmp/MudsnotePinUI.xcresult`
  - `/tmp/MudsnotePinFull.xcresult`

## Decisions

- Pin state is portable library metadata rather than proprietary Markdown syntax.
- Optional organization metadata must not make ordinary Markdown unavailable.
- Destructive and structural operations own pin migration as part of their
  transaction, not as a later UI refresh side effect.

## Next

- Begin the next parity phase with richer Notes-style list metadata and sorting.
- Continue editor autosave, attachment, and conflict-recovery polish.
