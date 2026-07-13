# 2026-07-13 iOS pending queue recovery

## Request

Continue closing commercial reliability gaps in the iPhone Notes-style app,
especially around quick capture and local failure recovery.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `d5a6c4f`
- Concurrent macOS source, tests, documentation, and iteration records were
  preserved and excluded.

## Changes

- Loading a malformed, unreadable, or unreasonably large pending-capture queue no
  longer prevents the selected Markdown library from opening.
- The original queue is moved to a unique timestamped
  `.mudsnote/queue-damaged-*.json` file before an empty valid queue is created.
- If queue replacement itself fails, the original file is restored when possible
  and the configuration error remains visible instead of silently losing data.
- The library stays usable after quarantine, including submitting new quick
  notes through the rebuilt queue.
- Settings presents an English or Simplified Chinese recovery warning with the
  preserved filename and explicitly states that existing notes were unchanged.
- Added deterministic storage and end-to-end UI fixtures for the damaged-queue
  path.

## Verification

- Generic iOS Simulator SDK build passed at `/tmp/MudsnoteQueueBuild`.
- Focused storage automation preserved the exact malformed bytes, rebuilt an
  empty queue, enqueued a new capture, and reloaded it successfully.
- Focused UI automation opened the library with a malformed queue, submitted a
  new quick note, confirmed the composer dismissed, and found the quarantine
  warning in Settings.
- Full App and UI suite: 74 passed, 0 failed, 0 skipped (59 unit/integration and
  15 UI tests).
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled;
  no iPad or additional simulator was used, and it was shut down afterward.
- Signed Release build passed and strict code-sign verification succeeded at
  `/tmp/MudsnoteQueueDevice/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
- Physical installation was attempted, but CoreDevice still reported `MudsPhone`
  as `unavailable` and could not locate it; installation and launch are therefore
  not claimed as complete.
- Full result bundle:
  `/tmp/MudsnoteQueueTests/Logs/Test/Test-MudsnoteCompanion-2026.07.13_17-12-44-+0800.xcresult`.

## Next

- Install and launch the signed Release build on `MudsPhone` as soon as CoreDevice
  reports the connected phone available, then verify queue recovery and a new
  capture on the physical iPhone.
