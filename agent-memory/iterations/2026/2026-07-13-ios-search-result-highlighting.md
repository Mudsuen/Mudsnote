# 2026-07-13 iOS search result highlighting

## Request

Continue the iPhone Apple Notes parity and repair the remaining search-result
readability gap without changing Mudsnote's local Markdown search boundary.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `4a77221`
- Concurrent macOS work was preserved and excluded.

## Changes

- Search result titles, context excerpts, and file locations now highlight every
  visible query match.
- Multi-term queries highlight each term independently.
- Matching follows the search engine's case-, diacritic-, and width-insensitive
  behavior, so visible highlights do not disagree with result inclusion.
- Overlapping terms do not stack duplicate highlight attributes.
- Highlights use a restrained Notes-style yellow surface and preserve readable
  foreground contrast in the dark interface.
- Rows use the last completed query rather than in-flight field text, preventing
  stale results from being decorated with a newer unfinished query.

## Verification

- Unit coverage verifies multi-term, case-insensitive, and diacritic-insensitive
  highlight ranges.
- Focused UI automation verified the existing All/Notes/Inbox scope transitions
  and captured the highlighted result at iPhone dimensions.
- Final visual evidence:
  `/tmp/MudsnoteSearchHighlightVisualAttachments/586F7B1B-5DA3-4066-9E02-AAC7C9AA5124.png`.
- Final full App and UI suite: 83 passed, 0 failed, 0 skipped (63 unit/integration
  and 20 UI tests).
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled;
  no iPad or additional simulator was used, and it was shut down afterward.
- Full result bundle:
  `/tmp/MudsnoteSearchHighlightFullTests/Logs/Test/Test-MudsnoteCompanion-2026.07.13_18-33-13-+0800.xcresult`.
- Signed Release build passed and strict code-sign verification succeeded at
  `/tmp/MudsnoteSearchHighlightDevice/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
- Physical installation was attempted, but CoreDevice still reports MudsPhone as
  `unavailable`; install and launch therefore remain unverified.

## Next

- Install the validated Release artifact when the physical iPhone data connection
  becomes available.
- Continue the next Notes-parity organization or editing gap.
