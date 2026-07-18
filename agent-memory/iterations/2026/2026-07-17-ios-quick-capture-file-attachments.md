# 2026-07-17 iOS Quick Capture file attachments

## Request

Continue the iPhone Apple Notes parity goal while preserving Mudsnote's quick-note and Markdown strengths. The user explicitly deferred further iPhone table work, so this iteration closes the remaining generic-file gap in Quick Capture without adding table UI.

## Baseline

- Branch: `main`
- HEAD: `1f92f92`
- Dirty files before work: none
- Runtime scope: iPhone only; one iPhone 17 Pro simulator with parallel testing disabled

## Changes

- Added generic document selection to Quick Capture through the existing attachment menu, keeping the compact command surface on one row.
- Shared the security-scoped file importer between Quick Capture and the full Markdown editor.
- Applied the existing 25 MiB per-file validation, 32 MiB complete-draft limit, portable file naming, attachment persistence, and Markdown storage pipeline to Quick Capture files.
- Preserved the current draft when an imported file is oversized or otherwise invalid and restored editor focus after picker cancellation or completion.
- Added Simplified Chinese attachment success and error strings.
- Added integration coverage for successful generic-file import and oversized-file rejection without draft mutation.
- Hardened the duplicate-note UI regression to validate the durable copied note instead of depending on a transient toast animation.
- Kept iPhone table expansion outside this iteration, as requested.

## Verification

- `git diff --check`: passed.
- `jq empty iOS/Localizable.xcstrings`: passed.
- Focused generic-file integration tests: 2 passed.
- Focused Quick Capture attachment-menu UI test: passed.
- The first full run exposed one timing-only failure in an existing duplicate-note test: the durable copied note existed, but its short-lived success toast was missed. The test was narrowed to the persistent product result and passed independently.
- Clean full single-device rerun:
  - Device: iPhone 17 Pro simulator `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5`, iOS 26.5.
  - Parallel testing: disabled.
  - Result: 143 tests, 0 failures, 0 skipped.
- Signed generic iOS Release build with provisioning updates: passed.
- Strict code-sign verification for `MudsnoteCompanion.app` and `MudsnoteCompanionWidget.appex`: passed.
- Physical install attempted on MudsPhone (`2C558043-5D29-531D-878B-F07C4F288D5D`), but CoreDevice still listed it as `unavailable` and rejected installation with error 1011.
- The combined Simulator and Release DerivedData measured 484 MB before cleanup; it was kept only under `/tmp` and removed after verification. The sole simulator was shut down.

## Decisions

- Keep `Add File` inside the attachment menu rather than adding another command-bar button, preserving the user's single-row layout requirement.
- Reuse one importer and one validation/storage contract for both note-creation surfaces.
- Validate file metadata before loading bytes so clearly oversized files fail early.
- Keep table-related iPhone work deferred.

## Next

- Retry installation and real file-provider import on MudsPhone when CoreDevice exposes it as available.
- Continue the next non-table iPhone Notes-parity or commercial-readiness gap.
