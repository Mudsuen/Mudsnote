# 2026-07-02 Source-list density polish

## Context

The current desktop goal is Apple Notes parity for the macOS library window. iOS real-device installation and validation are explicitly out of scope for this goal; verification should use macOS tests, packaging, and installed-app smoke.

## Change

- Tightened the Notes-like source list by reducing row height from 30 to 28.
- Reduced source stack spacing from 4 to 2.
- Changed source group labels from 12pt bold to 11pt semibold.
- Changed source count labels from 13pt to 12pt.
- Reduced selected source row corner radius from 7 to 6.
- Added row identifiers and regression coverage for the row height and typography contract.

## Verification

- `swift test --filter 'libraryWindowUsesNotesLikeSplitAndLoadsFirstNote|libraryWindowShowsNestedFoldersInSourceList|libraryWindowLoadsTagRowsAfterShellIsVisible'` passed.
- `swift test` passed with 75 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Directly opening `/Applications/Mudsnote.app` showed the `Mudsnote 笔记` library window at 1040x764.
- Screenshot evidence: `/tmp/mudsnote-source-list-density-smoke.png`.
