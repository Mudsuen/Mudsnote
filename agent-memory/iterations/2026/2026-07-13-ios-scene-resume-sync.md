# 2026-07-13 iOS scene resume sync

## Request

Continue bringing the iPhone app to Notes-grade daily reliability while
preserving Mudsnote quick capture, Shortcuts, widgets, and portable Markdown.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `976fa85`
- Concurrent macOS source and tests were preserved and excluded.

## Changes

- Returning the app to the foreground now reloads the selected folder's durable
  queue from disk instead of relying on a stale in-memory copy.
- Captures queued by Shortcuts, widgets, or another process while the main app is
  inactive are automatically replayed when the app becomes active.
- The same resume pass reloads the complete Markdown snapshot, so iCloud Drive or
  Files changes made outside Mudsnote appear without requiring a manual pull to
  refresh.
- An active search is recomputed after the refreshed snapshot is published.
- Queue quarantine behavior is shared with initial library configuration, so a
  queue damaged while the app was inactive is preserved and reported rather than
  blocking foreground recovery.
- Scene recovery separates queue failures from library-refresh failures and keeps
  pending state visible when replay cannot finish.

## Verification

- Generic iOS Simulator SDK build passed at `/tmp/MudsnoteSceneBuild`.
- Integration automation configured a real temporary Markdown library, simulated
  an extension writing a pending capture plus an external Markdown file while
  the main app was inactive, resumed the model, and verified automatic replay,
  external-note discovery, idle sync state, revision publication, and an empty
  durable queue.
- Full App and UI suite: 75 passed, 0 failed, 0 skipped (60 unit/integration and
  15 UI tests).
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled;
  no iPad or additional simulator was used, and it was shut down afterward.
- Full result bundle:
  `/tmp/MudsnoteSceneTests/Logs/Test/Test-MudsnoteCompanion-2026.07.13_17-21-06-+0800.xcresult`.
- Signed Release build passed and strict code-sign verification succeeded at
  `/tmp/MudsnoteSceneDevice/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
- Physical installation was attempted again, but CoreDevice still could not
  locate the `unavailable` MudsPhone; installation and launch are not claimed as
  complete.

## Next

- Refresh the signed Release build and install/launch on `MudsPhone` as soon as
  CoreDevice reports it available.
- Continue Notes parity with the next high-value iPhone lifecycle or editing gap.
