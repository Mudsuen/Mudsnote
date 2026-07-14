# 2026-07-15 iOS Notes-style collapsible headings

## Request

Continue the iPhone Apple Notes parity target with current Notes-style collapsible
title and heading sections while preserving portable Markdown source.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `3d06ac7`
- Dirty files before work: none
- Scope remained iPhone-only; no iPad or accessibility work was added.

## Changes

- Added a heading parser for portable Markdown H1-H6 sections without treating
  hashtags such as `#tag` as headings.
- Rendered headings with section content now show a compact disclosure chevron.
- Collapsing a heading hides its body, attachments, tables, and nested headings up
  to the next heading of the same or higher level.
- Nested headings remain independently collapsible when their parent is expanded.
- Collapse state stays in the reader UI and never writes proprietary metadata into
  the `.md` file.
- Find in Note still indexes the complete document. Selecting a match inside one or
  more collapsed sections expands the required ancestors before scrolling.
- Editing and saving clears stale block-index state so structural Markdown changes
  cannot reuse an obsolete collapse projection.
- Rendering parses the Markdown blocks once per view projection, avoiding repeated
  whole-document parsing as visible rows are built.

## Verification

- Generic iOS Simulator build passed.
- Focused unit coverage passed for heading recognition, hierarchy boundaries,
  nested collapse visibility, and hidden-match ancestor discovery.
- Focused real-note UI coverage passed for collapse, expansion, and Find in Note
  automatically revealing hidden content.
- Visual inspection confirmed the disclosure and heading share one row in the
  medium-height reader sheet and collapsed content leaves no duplicate surface.
- Retained visual evidence:
  `/tmp/mudsnote-heading-fold-attachments/A92FF750-B1E4-47ED-9C73-842F665D51AE.png`.
- Final full App and UI suite after the rendering-performance cleanup: 110 passed,
  0 failed, 0 skipped (78 unit/performance tests and 32 UI tests).
- Only iPhone 17 Pro / iOS 26.5 simulator
  `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5` was used, with parallel testing disabled.
  It was shut down after verification.
- Final result bundle: `/tmp/MudsnoteHeadingFoldFullFinalTests.xcresult`.
- Signed Release build passed from the final source at
  `/tmp/MudsnoteHeadingFoldRelease/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
  Strict code-sign verification passed for the app and embedded widget.
- MudsPhone remained visible but `unavailable` to CoreDevice. Installation failed
  with CoreDevice error 1011 because the device could not be located; no physical
  launch claim was made.

## Decisions

- Section folding is presentation state derived from semantic Markdown headings;
  files remain interoperable with editors that know nothing about Mudsnote.
- Heading level, not visual size or row position, owns section boundaries.
- Retrieval is authoritative over folding: a find result must reveal its hidden
  content instead of reporting a match the user cannot see.

## Next

- Restore MudsPhone CoreDevice availability, then install and launch the signed
  Release for physical disclosure animation, find, editing, and save checks.
- Continue the next highest-impact Apple Notes parity gap on iPhone.
