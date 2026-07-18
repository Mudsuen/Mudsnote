# 2026-07-15 iOS Notes-style paragraph formats

## Request

Continue the iPhone Apple Notes parity target after compacting the editor toolbar,
while keeping Markdown as the portable source of truth.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `0f66827`
- Concurrent macOS toolbar edits were preserved and excluded from this iteration.

## Changes

- Expanded the editor `Aa` menu with the four common Notes paragraph formats:
  Title, Heading, Subheading, and Body.
- Mapped the formats directly to portable Markdown: `#`, `##`, `###`, and plain
  paragraph text.
- Added a dedicated paragraph transformation layer that first normalizes existing
  ATX H1-H6 markers before applying the requested format.
- Made paragraph style selection idempotent, so repeated taps do not accumulate
  Markdown markers.
- Multi-paragraph selections preserve empty lines and indentation, while hashtag
  text such as `#tag` is not mistaken for a heading.
- Added English and Simplified Chinese menu copy and retained a screenshot of the
  menu while the keyboard and single-row editor toolbar are visible.

## Verification

- Generic iOS Simulator build and String Catalog compilation passed.
- Focused paragraph transformation unit test passed.
- Focused real-note editor UI test passed and verified all four paragraph commands.
- Retained visual evidence:
  `/tmp/mudsnote-paragraph-styles-attachments/BDE7430E-5B46-4F19-86E5-58458992E8F2.png`.
- Final full App and UI suite: 99 passed, 0 failed, 0 skipped (72 unit/performance
  tests and 27 UI tests).
- Only iPhone 17 Pro / iOS 26.5 simulator
  `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5` was used, with parallel testing disabled.
  It was shut down after verification.
- Final result bundle:
  `/tmp/MudsnoteParagraphStylesFullTests/Logs/Test/Test-MudsnoteCompanion-2026.07.15_01-33-47-+0800.xcresult`.
- Signed Release build passed at
  `/tmp/MudsnoteParagraphStylesRelease/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
  Strict code-sign verification passed for the app and embedded widget.
- MudsPhone remained unavailable to CoreDevice. `xcdevice` reported LAN browsing
  rather than an available device, and installation failed with CoreDevice error
  1011 because the device could not be located. The signed artifact itself passed.

## Decisions

- Paragraph formats are semantic Markdown transformations rather than visual-only
  editor state, preserving local-first portability and round trips.
- `#tag` requires no special user mode: only a hash run followed by whitespace is
  treated as an ATX heading.
- The ordinary rendered editor remains the default; these commands do not require
  switching to Markdown Source.

## Next

- Restore MudsPhone CoreDevice availability, then install and launch the signed
  Release for physical keyboard, paragraph menu, and save smoke checks.
- Continue the next Notes-parity gap in editor retrieval/navigation or note actions.
