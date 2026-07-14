# 2026-07-15 iOS Notes-style link editor

## Request

Continue the iPhone Apple Notes parity target by replacing source-placeholder
link insertion with a complete editing workflow while preserving Markdown as the
portable source of truth.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `cf17a6c`
- Scope remained iPhone-only; no iPad or accessibility work was added.

## Changes

- Replaced the `Insert Link` command's raw `[text](https://)` placeholder with a
  native half-sheet containing Name and Link fields.
- Selected text prepopulates the link name. An empty selection starts a new link
  with the name field focused.
- A cursor or selection inside an existing Markdown link opens Edit Link with the
  current label and destination prefilled.
- Existing links can be updated or removed without exposing source mode; removal
  preserves the visible label as ordinary text.
- Link destinations without a scheme receive `https://`; email addresses receive
  `mailto:`; spaces and parentheses are encoded for portable Markdown rendering.
- Added Simplified Chinese copy and retained the existing single-row editor toolbar.

## Verification

- Generic iOS Simulator build and String Catalog validation passed.
- Focused link transformation unit test passed for add, update, remove,
  destination normalization, and invalid empty input.
- Focused real-note UI flow passed for Add Link, Edit Link, and Remove Link.
- Retained visual evidence:
  `/tmp/mudsnote-link-editor-attachments/A91C7C3C-C39E-4876-B426-57D4F486897D.png`.
- Final full App and UI suite: 107 passed, 0 failed, 0 skipped (76
  unit/performance tests and 31 UI tests).
- Only iPhone 17 Pro / iOS 26.5 simulator
  `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5` was used, with parallel testing disabled.
  It was shut down after verification.
- Final result bundle: `/tmp/MudsnoteLinkEditorFullTests.xcresult`.
- Signed Release build passed at
  `/tmp/MudsnoteLinkEditorRelease/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
  Strict code-sign verification passed for the app and embedded widget.
- MudsPhone remained visible but `unavailable` to CoreDevice. Installation failed
  with CoreDevice error 1011 because the device could not be located; no physical
  launch claim was made.

## Decisions

- Link editing remains a Markdown transformation rather than editor-only metadata.
- Link creation and editing use a focused native sheet so the ordinary rich editor
  does not force users into Markdown Source.
- Existing link detection is selection-aware, enabling a single `Insert Link`
  command to cover both creation and editing like Notes.

## Next

- Restore MudsPhone CoreDevice availability, then install and launch the signed
  Release for physical keyboard, link sheet, autosave, and rendered-link checks.
- Continue the next highest-impact Apple Notes parity gap on iPhone.
