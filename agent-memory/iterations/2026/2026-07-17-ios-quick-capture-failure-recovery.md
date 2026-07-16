# 2026-07-17 iOS Quick Capture failure recovery

## Request

Continue the iPhone Apple Notes parity and commercial-readiness goal while preserving Mudsnote's fast Quick Capture and Markdown model. iPhone table expansion remains deferred, so this iteration closes the explicit attachment-error and interrupted-write recovery gap.

## Baseline

- Branch: `main`
- HEAD: `7964f25`
- Dirty files before work: none
- Runtime scope: iPhone only; one iPhone 17 Pro simulator with parallel testing disabled

## Changes

- Audited the real Quick Capture sheet and confirmed the normal attachment, audio, formatting, destination, and submit controls remain in one row.
- Fixed a structural error-visibility bug: submission errors were previously published only into `RootView`, behind the presented Quick Capture sheet.
- Added a compact in-sheet interrupted-write recovery card with the saved draft reason and a direct retry action.
- Preserved the editor, keyboard, destination, attachments, and complete draft after a failed or repeated retry.
- Added a short move-and-fade transition for the recovery card instead of an abrupt command-bar jump.
- Unified Quick Capture attachment failures from Photos, camera, file import, document scanning, and audio preparation into one visible system alert inside the capture sheet.
- Added realistic UI fixtures: an empty image exercises the actual attachment validation path; a full pending queue of invalid interrupted writes exercises actual queue replay and enqueue rejection.
- Added two UI regressions proving attachment-error dismissal restores editing and interrupted writes preserve the draft and expose retry.
- Kept table-related iPhone work deferred.

## Verification

- Current-run visual evidence inspected:
  - `/tmp/MudsnoteIOSRecoveryFinalEvidence/01-normal-single-row.png` — normal one-row capture console.
  - `/tmp/MudsnoteIOSRecoveryFinalEvidence/02-attachment-menu.png` — attachment menu above the same row.
  - `/tmp/MudsnoteIOSRecoveryFinalEvidence/03-attachment-error.png` — attachment failure remains visibly inside Quick Capture.
  - `/tmp/MudsnoteIOSRecoveryFinalEvidence/04-interrupted-write-retry.png` — interrupted-write card, intact draft, keyboard, and retry.
- `jq empty iOS/Localizable.xcstrings`: passed.
- `git diff --check`: passed.
- Focused recovery UI tests: 2 passed.
- The first interrupted-write focused run exposed a test-only element-grouping issue: the recovery container identifier hid the nested retry identifier. Removing the container identifier and fixing the retry button size restored the real child control; the focused rerun passed.
- Clean full single-device regression:
  - Device: iPhone 17 Pro simulator `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5`, iOS 26.5.
  - Parallel testing: disabled.
  - Result: 145 tests, 0 failures, 0 skipped; UI suite 45/45.
- Signed generic iOS Release build with provisioning updates: passed.
- Strict code-sign verification for `MudsnoteCompanion.app` and `MudsnoteCompanionWidget.appex`: passed.
- Physical install attempted on MudsPhone (`2C558043-5D29-531D-878B-F07C4F288D5D`), but CoreDevice still listed it as `unavailable` and rejected installation with error 1011.
- The combined Simulator and Release DerivedData measured 472 MB before cleanup; it was kept only under `/tmp` and removed after verification. The sole simulator was shut down.

## Decisions

- Keep transient attachment problems as system alerts because the user must acknowledge them before continuing with the same picker task.
- Keep submission failures inline and persistent because they require both reassurance that the draft remains safe and an explicit retry action.
- Use actual validation and queue failures in UI fixtures instead of bypassing the production recovery paths.
- No separate durable architecture decision is required.

## Next

- Retry the Release install and the same failure recovery on MudsPhone when CoreDevice exposes it as available.
- Continue the next non-table Notes-parity or commercial-release gap.
