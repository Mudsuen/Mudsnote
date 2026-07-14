# 2026-07-15 iOS toggleable strikethrough formatting

## Request

Continue the iPhone Apple Notes parity target while preserving Mudsnote's
Markdown-native editing model and single-row editor toolbar.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `240326c`
- Scope remained iPhone-only; no iPad or accessibility work was added.

## Changes

- Added Strikethrough to the Notes-style `Aa` formatting menu, grouped with Bold
  and Italic and backed by portable `~~text~~` Markdown.
- Replaced the old one-way marker wrapping used by Bold, Italic, Inline Code, and
  Strikethrough with a shared inline-format toggle.
- Applying a format to plain selected text adds markers; applying it again to the
  selected content or to a selection containing its markers removes them instead
  of nesting duplicate markers.
- Empty selections still insert a selected placeholder so typing immediately
  replaces the placeholder inside the requested formatting.
- Added English and Simplified Chinese menu copy, unit coverage for all toggle
  shapes, and a real editor UI assertion for Strikethrough input.

## Verification

- Generic iOS Simulator build and String Catalog validation passed.
- Focused inline-format unit test passed.
- Focused real-note editor UI test passed and produced `~~Archived~~` through the
  visible Strikethrough menu command.
- Retained visual evidence:
  `/tmp/mudsnote-strikethrough-attachments/D2C49A11-ECBE-42A6-BEFE-1F46289C0049.png`.
- Final full App and UI suite: 106 passed, 0 failed, 0 skipped (75
  unit/performance tests and 31 UI tests).
- Only iPhone 17 Pro / iOS 26.5 simulator
  `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5` was used, with parallel testing disabled.
  It was shut down after verification.
- Final result bundle: `/tmp/MudsnoteStrikethroughFullTests.xcresult`.
- Signed Release build passed at
  `/tmp/MudsnoteStrikethroughRelease/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
  Strict code-sign verification passed for the app and embedded widget.
- MudsPhone remained visible but `unavailable` to CoreDevice. Installation failed
  with CoreDevice error 1011 because the device could not be located; no physical
  launch claim was made.

## Decisions

- Inline formatting remains Markdown source-of-truth rather than editor-only
  state, preserving local-first portability and round trips.
- Repeated format commands must behave like native rich-text toggles rather than
  accumulating syntax markers.
- Strikethrough belongs in the existing `Aa` menu, not in a second toolbar row.

## Next

- Restore MudsPhone CoreDevice availability, then install and launch the signed
  Release for a physical keyboard, menu, save, and rendered-text smoke check.
- Continue the next highest-impact Apple Notes parity gap on iPhone.
