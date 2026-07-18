# 2026-07-15 iOS Find in Note

## Request

Continue the iPhone Apple Notes parity target by closing the retrieval gap inside
an already opened long Markdown note.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `3ea2570`
- Worktree was clean before this iteration.

## Changes

- Added Find in Note to the saved-note options menu without requiring Markdown
  Source mode or entering the editor.
- Added a keyboard-synchronized single-row find bar with a search field, current and
  total match count, previous/next navigation, clear, and Done.
- Highlighted every rendered match in yellow and the active match in orange while
  preserving Markdown typography and links.
- Added cyclic previous/next navigation and animated scrolling to the active rendered
  block.
- Indexed visible rendered text rather than raw Markdown markers, including headings,
  emphasis, quotes, and table cells while excluding attachment paths from false hits.
- Kept content taps from entering edit mode while Find in Note is active.
- Added English and Simplified Chinese find-bar copy.
- Stabilized the existing duplicate-note UI regression without weakening it: the
  short-lived success toast is awaited before the slower list refresh assertion.

## Verification

- Generic iOS Simulator build, String Catalog validation, and `git diff --check`
  passed.
- Focused index and UI tests passed, and the duplicate-note regression passed three
  consecutive iterations after its assertion-order repair.
- Retained visual evidence of rendered highlighting and the keyboard find bar:
  `/tmp/mudsnote-find-in-note-attachments/1538BCAE-F389-4139-A947-4A866D5D6642.png`.
- An initial full run found only the duplicate-toast test timing issue; the repaired
  final full App and UI suite passed 105 tests with 0 failures and 0 skipped (74
  unit/performance tests and 31 UI tests), confirmed from the xcresult summary.
- Only iPhone 17 Pro / iOS 26.5 simulator
  `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5` was used, with parallel testing disabled.
  It was shut down after verification.
- Final result bundle:
  `/tmp/MudsnoteFindInNoteFullTestsRetry/Logs/Test/Test-MudsnoteCompanion-2026.07.15_02-47-42-+0800.xcresult`.
- Signed Release build passed at
  `/tmp/MudsnoteFindInNoteRelease/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
  Strict code-sign verification passed for the app and embedded widget.
- MudsPhone remained visible over USB but unavailable to CoreDevice. `xcdevice`
  reported local-network browsing with `available: false`; installation failed with
  CoreDevice error 1011 because the device could not be located.

## Decisions

- Find operates on the rendered reading model, not raw Markdown syntax, matching the
  product contract that rendered Markdown is the default surface.
- Match identity records block and table-cell positions so navigation remains stable
  without views performing search or filesystem work.
- Search focus begins only from the explicit Find in Note action and ends on Done.

## Next

- Restore MudsPhone CoreDevice availability, then install and launch the signed
  Release for physical keyboard, highlight, and next/previous navigation checks.
- Continue the next Notes-parity inspection or editor interaction gap.
