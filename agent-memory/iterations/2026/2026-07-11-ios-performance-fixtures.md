# 2026-07-11 iOS performance fixtures

## Request

Add repeatable commercial-capacity performance evidence for large libraries and attachment-heavy drafts.

## Baseline

- Branch: `main`
- HEAD: `6ddcbca`
- Existing inventory coverage used only thirty extra Markdown files and did not record performance metrics.
- Attachment policy tests checked rejection boundaries but did not exercise maximum accepted draft preparation.

## Changes

- Added a 1,000-note library snapshot fixture with exact inventory and recent-file assertions.
- Added a maximum accepted attachment fixture: eight 4 MiB audio values, totaling the 32 MiB draft limit.
- Recorded monotonic-clock and physical-memory metrics over three iterations while keeping fixture creation outside the measured region.

## Verification

- iPhone 17 Pro / iOS 26.5 Simulator baseline:
  - 1,000-note snapshot: 0.107 s average; 36.5 MB peak physical memory.
  - 32 MiB attachment draft preparation: 0.106 s average; 85.9 MB peak physical memory.
- Full suite passes: eighteen unit/performance tests and three UI tests, zero failures.
- Release Simulator build succeeds with `CODE_SIGNING_ALLOWED=NO`.

## Decisions

- Metrics are recorded baselines, not brittle wall-clock pass/fail thresholds; Xcode can compare regressions against stable CI/device baselines later.
- Exact result assertions remain inside every measured iteration so a faster incorrect implementation cannot appear healthy.
- Concurrent macOS worktree changes were preserved and excluded.

## Next

- Avoid rescanning the entire library after an Inbox-only capture.
- Establish the same metrics on a stable physical-device OS and CI runner before enforcing regression thresholds.
