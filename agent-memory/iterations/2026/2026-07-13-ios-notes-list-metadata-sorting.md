# 2026-07-13 iOS Notes-style list metadata and sorting

## Request

Continue the iPhone-only Apple Notes parity target while retaining Mudsnote capture
and local Markdown behavior.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `590cce1`
- Concurrent macOS source changes were preserved and not staged with iOS work.

## Changes

- Added bounded Markdown list metadata extraction for H1 titles, body previews, and
  attachment markers.
- Added actor-owned list metadata caching keyed by relative path, modification date,
  and file size, with exact invalidation after file lifecycle operations.
- Added creation dates to the immutable note inventory.
- Replaced raw-path rows with a Notes-style title, edited/created date, body preview,
  parent folder, attachment marker, and durable pin marker.
- Added persistent sorting by date edited, date created, or title.
- Added optional Notes-style date groups: Today, Yesterday, Previous 7 Days,
  Previous 30 Days, and older month/year groups.
- Added Simplified Chinese localization and an iPhone UI visual regression covering
  list metadata and sort controls.

## Verification

- Generic iOS Simulator SDK build passed without booting a simulator.
- Focused metadata/cache/grouping tests: 3 passed.
- Final full App and UI suite: 55 passed, 0 failed, 0 skipped.
- Notes-style list visual UI test: 1 passed; screenshot exported and inspected.
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled.
- All simulators were shut down after each run.
- Result bundles:
  - `/tmp/MudsnoteListFocused.xcresult`
  - `/tmp/MudsnoteNotesListFull.xcresult`
  - `/tmp/MudsnoteListVisual.xcresult`
  - `/tmp/MudsnoteNotesListFinal.xcresult`

## Decisions

- SwiftUI never reads Markdown directly; file I/O and metadata parsing stay inside
  `MarkdownFileStore`.
- Only the first 64 KiB is needed for list presentation, keeping large libraries and
  attachment-heavy notes responsive.
- Title sorting intentionally suppresses date sections; date grouping follows the
  active edited/created date basis.

## Next

- Continue the Apple Notes editor parity pass: reliable autosave, attachment editing,
  conflict handling, and half-sheet/full-screen continuity.
