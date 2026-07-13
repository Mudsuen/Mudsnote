# 2026-07-13 iOS quick-capture recovery

## Request

Harden the distinctive iPhone quick-capture flow to commercial-grade data-loss
behavior while continuing the Notes-style product direction.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `0d64642`
- Concurrent macOS source and tests were preserved and excluded.

## Changes

- Added an app-private recovery store for a quick-capture draft that has not yet
  been submitted to the Markdown library or durable pending-write queue.
- Recovery preserves body text, tags, Inbox/Daily/recent-file target, creation
  date, and image/audio/generic-file attachments across process termination.
- Attachment bytes are stored as individual protected files rather than large
  Base64 values in `UserDefaults`; unchanged attachments are reused when only
  text changes, avoiding repeated large writes.
- Metadata and attachment writes use atomic output and iOS complete-until-first-
  unlock file protection. Stale attachment files are removed after a successful
  metadata commit.
- Draft changes debounce in the foreground and flush immediately when the app
  leaves the active scene. Empty or successfully submitted drafts remove the
  recovery directory.
- Recovery never overwrites text already entered in the current process. The
  restored message is delayed until the library is ready so it remains visible.
- Added Simplified Chinese recovery and failure copy, and UI-test reset now clears
  app-private draft state for deterministic isolation.

## Verification

- Generic iOS Simulator SDK build passed at `/tmp/MudsnoteDraftRecoveryBuild`.
- Focused storage test proved body/target/all attachment kinds round-trip across a
  new store instance, unchanged binary files are reused, and empty draft cleanup.
- Focused UI automation proved type, process termination, relaunch, recovery
  announcement, and continued editing through the real composer.
- Full App and UI suite: 70 passed, 0 failed, 0 skipped.
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled,
  then shut down; no iPad or additional simulator was used.
- Result bundles:
  - `/tmp/MudsnoteDraftRecoveryFocused3.xcresult`
  - `/tmp/MudsnoteDraftRecoveryFull.xcresult`

## Next

- Add explicit damaged-draft recovery management and privacy/backup diagnostics,
  then install the current signed Release build when `MudsPhone` is online.
