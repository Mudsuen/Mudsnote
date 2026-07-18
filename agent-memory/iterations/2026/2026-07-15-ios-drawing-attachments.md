# 2026-07-15 iOS Notes-style drawing attachments

## Request

Continue the iPhone Apple Notes parity target with native finger drawing and
handwriting tools while preserving Mudsnote's portable Markdown library.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `21cef25`
- Dirty files before work: none
- Scope remained iPhone-only; no iPad or accessibility work was added.

## Changes

- Added a full-screen PencilKit drawing editor for Markdown documents.
- Reused the existing single-row editor toolbar: Drawing lives inside the
  attachment menu and does not add a second toolbar row.
- Added native pen, pencil, marker, eraser, lasso, ruler, and color controls via
  the system PencilKit tool picker.
- Added explicit undo and redo controls, disabled empty saves, and a discard
  confirmation for unfinished drawings.
- New canvases always begin with visible black ink on a white surface, including
  when the app is in dark mode.
- Flattened each drawing to a cropped, padded, white-background PNG with a 4096
  pixel maximum dimension. Light rendering traits prevent semantic PencilKit ink
  from becoming white and disappearing during dark-mode export.
- Saved drawing files through the existing coordinated attachment transaction,
  then appended a standard `![Image](Attachments/...)` Markdown reference.
- Preserved the current draft before attachment writes and retained optimistic
  conflict checks so drawing cannot overwrite an external Markdown edit.
- Added Simplified Chinese copy for the drawing flow.

## Verification

- Generic iOS Simulator build passed.
- Focused unit coverage passed for PNG signature, visible ink, maximum dimensions,
  and empty-drawing rejection.
- Focused UI coverage drew on the real PencilKit canvas, confirmed Add is disabled
  while empty, saved the drawing, and verified the portable PNG Markdown reference.
- Visual inspection confirmed black ink is visible on the white canvas in dark
  mode and the generated PNG contains the same visible stroke.
- Retained visual evidence:
  `/tmp/mudsnote-drawing-final-attachments/9AEC051F-F914-4450-A771-6870D1259745.png`.
- Final full App and UI suite: 112 passed, 0 failed, 0 skipped (79 unit/performance
  tests and 33 UI tests).
- Only iPhone 17 Pro / iOS 26.5 simulator
  `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5` was used, with parallel testing disabled.
  It was shut down after verification.
- Final result bundle: `/tmp/MudsnoteDrawingFullFinalTests.xcresult`.
- Signed Release build passed from the final source at
  `/tmp/MudsnoteDrawingRelease/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
  Strict code-sign verification passed for the app and embedded widget.
- MudsPhone remained visible but `unavailable` to CoreDevice. Installation failed
  with CoreDevice error 1011 because the device could not be located; no physical
  launch claim was made.

## Decisions

- Drawing is a portable image attachment rather than proprietary PencilKit data;
  other Markdown editors and file browsers can display it without Mudsnote.
- A deterministic white canvas avoids semantic black/white ink inversion across
  appearance modes and keeps exported notes visually stable.
- The editor crops to actual drawing content rather than saving a full device-sized
  screenshot, reducing file size without losing the user's marks.

## Next

- Restore MudsPhone CoreDevice availability, then install and launch the signed
  Release for physical drawing latency, tool-picker, export, and note-render checks.
- Continue the next highest-impact Apple Notes parity gap on iPhone.
