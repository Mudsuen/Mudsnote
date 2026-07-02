# 2026-07-01 Apple Notes source counts

## Request

Continue iterating the Mudsnote desktop interface toward Apple Notes parity while keeping the app lightweight.

## Baseline

- Previous slice added Apple Notes-style date grouping and a golden selected note row in the middle list.
- The left source list still showed only labels and icons, without note counts.

## Changes

- Added count labels to the source list rows:
  - all notes
  - recent notes
  - Inbox matches
  - visible tag rows
- Kept the existing `NSButton` source rows as the click targets so selection and filtering behavior stayed unchanged.
- Refreshed counts after library reloads so saves, scope changes, and tag filters keep the sidebar current.
- Fixed the row layout after visual QA showed the first width-alignment pass pushed source text to the right.

## Verification

- `swift test` passed with 58 tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.
- Packaged smoke launched `/Applications/Mudsnote.app` with no arguments and showed the `Mudsnote 笔记` library window directly.
- Visual QA screenshot: `/tmp/mudsnote-window-apple-notes-source-counts-fixed.png`
  - direct launch shows the library
  - source-list counts are visible
  - note list still has the `2026` date group
  - selected note still uses the golden Notes-like highlight

## Next

- Continue source-list parity with real folder hierarchy and collapsed groups.
- Move editor date/status closer to Apple Notes' centered metadata treatment.
- Replace text-heavy editor actions with compact toolbar icons once the main workflow is stable.
