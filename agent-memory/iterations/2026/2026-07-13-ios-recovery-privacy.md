# 2026-07-13 iOS recovery and privacy controls

## Request

Close the commercial failure-state and privacy gaps around the new protected
quick-capture recovery path.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `8d2bb0f`
- Concurrent macOS source, tests, documentation, and iteration records were
  preserved and excluded.

## Changes

- Recovery decode, missing attachment, invalid path, invalid payload, and policy
  failures now converge on a stable user-facing damaged-draft state instead of
  leaking implementation errors.
- Settings exposes a conditional Quick Note Recovery section with retry and an
  explicit destructive discard flow. The confirmation states that saved library
  notes are untouched.
- Discard removes only app-private recovery data, clears the issue state, and
  resumes protecting any new in-memory draft.
- The recovery directory is explicitly excluded from device backups in addition
  to using iOS file protection.
- Settings now documents the actual local-first boundary: Mudsnote has no account
  or upload service; selected-folder providers control note sync/backup, while an
  unfinished quick draft remains protected and backup-excluded app data.
- Added Simplified Chinese copy for all new recovery, privacy, retry, and discard
  states.

## Verification

- Generic iOS Simulator SDK build passed at `/tmp/MudsnoteRecoveryManagementBuild`.
- Focused storage automation proved damaged data maps to the stable recovery error
  and can be cleared.
- Focused UI automation injected a damaged recovery, opened Settings, confirmed
  retry/discard controls, performed the destructive confirmation, and verified
  the recovery section cleared without changing the library.
- Full App and UI suite: 72 passed, 0 failed, 0 skipped.
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled,
  then shut down; no iPad or additional simulator was used.
- Result bundles:
  - `/tmp/MudsnoteRecoveryManagementFocused.xcresult`
  - `/tmp/MudsnoteRecoveryManagementFull.xcresult`

## Next

- Refresh the signed Release build and install/launch on `MudsPhone` when it is
  online, then exercise scanner, recovery, and privacy Settings on device.
