# 2026-07-13 iOS search scopes and race safety

## Request

Repair the iPhone search behavior as part of the Apple Notes parity work instead
of treating search as a cosmetic result list.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `91b0754`
- Concurrent macOS source, tests, documentation, and iteration records were
  preserved and excluded.

## Changes

- Added All, Notes, and Inbox search scopes through a compact segmented control
  displayed only while searching.
- The file store filters before reading and ranking content, so a scoped search
  does not waste work on excluded note types.
- Added a monotonically increasing search generation in `AppModel`; cancelled or
  slower earlier requests can no longer publish over a newer query or scope.
- Search completion records the normalized query and scope that produced the
  visible results.
- The view treats a query as pending until that exact normalized query/scope has
  completed, eliminating the brief false “No Results” state during debounce.
- Clearing search and changing the authorized library invalidate in-flight search
  generations and reset the completion identity.
- Search results and the bottom search controls expose stable UI-test identifiers.

## Verification

- Generic iOS Simulator SDK build passed.
- Focused store/model tests passed for scope isolation and completed-search state.
- Focused UI automation passed the All result, Inbox no-result, Notes result, and
  clear-search sequence without stale results.
- Full App and UI suite: 64 passed, 0 failed, 0 skipped.
- One iPhone 17 Pro / iOS 26.5 simulator was explicitly booted, used with parallel
  testing disabled, and shut down afterward.
- Result bundles:
  - `/tmp/MudsnoteSearchFocused.xcresult`
  - `/tmp/MudsnoteSearchFull.xcresult`

## Next

- Add visible query highlighting in result title/context, then continue with
  Notes-style editor tables/file attachments and the quick-capture completion pass.
