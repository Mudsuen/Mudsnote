# 2026-07-13 iOS rendered Markdown editing

## Request

Move the iPhone editor toward Apple Notes-style direct editing without sacrificing
the underlying Markdown source or Mudsnote formatting features.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `6ba38ca`
- Concurrent macOS and script changes were preserved and excluded.

## Changes

- Added a non-destructive rich presentation layer to the existing `UITextView`.
- Rich Text is the default edit mode and visually renders headings, bold, italic,
  strikethrough, inline code, and links while concealing their Markdown delimiters.
- The editable string always remains the original Markdown, so autosave and external
  tools receive byte-for-byte source rather than a lossy rich-text conversion.
- Added an explicit Editor Display menu with Rich Text and Markdown Source choices.
- Retained the existing single-row formatting bar and all Markdown commands.
- Source mode restores monospaced text and every Markdown character.
- Large documents above 512 KiB fall back to lightweight source presentation to
  avoid per-keystroke full-document styling cost.
- Removed the duplicate sheet navigation title so the rendered H1 remains the one
  visible note title, matching Apple Notes more closely.
- Added bilingual display-mode labels.

## Verification

- Generic iOS Simulator SDK build passed.
- Focused presentation test proves the underlying source is unchanged across Rich
  Text and Markdown Source modes and verifies heading, bold, link, and marker styles.
- Full App and UI suite: 58 passed, 0 failed, 0 skipped.
- Focused visual UI flow passed after the duplicate title change; screenshot was
  exported and inspected.
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled and
  shut down afterward.
- Result bundles:
  - `/tmp/MudsnoteRichEditorFocused.xcresult`
  - `/tmp/MudsnoteRichEditorFull.xcresult`
  - `/tmp/MudsnoteRichEditorVisualVerified.xcresult`
- Final screenshot:
  - `/tmp/MudsnoteRichEditorVisualVerifiedAttachments/CFAAC812-C681-45A5-A221-6F67785BEF54.png`

## Decisions

- iOS rich presentation styles source in place instead of porting the AppKit-only
  macOS codec or introducing a lossy HTML/attributed-string round trip.
- Markdown Source remains an advanced escape hatch; users do not need to switch modes
  for normal editing.

## Next

- Improve rendered list/checklist interaction and continue Notes-style selection,
  checklist toggling, and paragraph-format behavior.
