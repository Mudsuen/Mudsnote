# 2026-07-15 iOS Notes-style underline formatting

## Request

Continue the iPhone Apple Notes parity target with reversible underline formatting
while preserving portable Markdown source, rendered reading, search, and note-list
metadata.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `ec85dff`
- Scope remained iPhone-only; no iPad or accessibility work was added.

## Changes

- Added `Underline` to the existing single-row Aa formatting menu beside Bold,
  Italic, and Strikethrough.
- Applying underline wraps the current selection in portable `<u>...</u>` markup;
  applying it again removes the wrapper instead of nesting duplicate markers.
- The rich editor hides the source markers and displays native underlined text.
- Added a shared inline renderer so saved notes display underline together with
  ordinary Markdown emphasis and links without exposing HTML tags.
- Search indexing and highlighted search text now use rendered visible text, so
  `<u>` markers cannot leak into results.
- Note-list title and preview extraction strips underline tags while retaining the
  user-visible text.
- Added Simplified Chinese copy for Underline.

## Verification

- Generic iOS Simulator build and String Catalog validation passed.
- Focused unit coverage passed for reversible underline transforms, combined
  Markdown rendering, visible search text, and list metadata extraction.
- Focused real-note UI coverage passed for applying underline, saving the note,
  and confirming the rendered result contains the text without `<u>` markers.
- Retained visual evidence:
  `/tmp/mudsnote-underline-rendered-attachments/84F53D01-F3B1-43D9-9315-A4CD5602F821.png`
  and
  `/tmp/mudsnote-underline-rendered-attachments/9132B13C-A68D-458E-B1B2-4BC02A4177C2.png`.
- Final full App and UI suite: 108 passed, 0 failed, 0 skipped (77
  unit/performance tests and 31 UI tests).
- Only iPhone 17 Pro / iOS 26.5 simulator
  `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5` was used, with parallel testing disabled.
  It was shut down after verification.
- Final result bundle: `/tmp/MudsnoteUnderlineFullTests.xcresult`.
- Signed Release build passed at
  `/tmp/MudsnoteUnderlineRelease/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
  Strict code-sign verification passed for the app and embedded widget.
- MudsPhone remained visible but `unavailable` to CoreDevice. Installation failed
  with CoreDevice error 1011 because the device could not be located; no physical
  launch claim was made.

## Decisions

- Underline uses the widely understood inline HTML form supported by Markdown
  ecosystems rather than editor-only metadata or a proprietary file format.
- A sentinel-based rendering pass preserves Foundation's ordinary Markdown parsing
  while converting underline spans to native attributed-text styling.
- Reading, searching, and list previews share visible-text semantics so source tags
  remain an implementation detail throughout the iPhone experience.

## Next

- Restore MudsPhone CoreDevice availability, then install and launch the signed
  Release for physical keyboard, formatting, autosave, and rendered-note checks.
- Continue the next highest-impact Apple Notes parity gap on iPhone.
