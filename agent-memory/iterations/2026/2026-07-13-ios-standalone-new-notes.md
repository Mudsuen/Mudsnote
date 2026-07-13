# 2026-07-13 iOS standalone new notes

## Request

Continue matching Apple Notes' iPhone interaction model while preserving
Mudsnote's quick-capture and portable Markdown strengths.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `f4921f1`
- Concurrent macOS source and tests were preserved and excluded.

## Changes

- The yellow black `square.and.pencil` action now performs Apple Notes-style new
  note creation instead of appending another block to Inbox.
- A new note is an independent, immediately durable Markdown file named
  `Untitled Note.md`, with collision-safe `Untitled Note 2.md` naming.
- New notes open directly in the complete large editor with the keyboard focused,
  rich/source modes, formatting, attachments, scanning, autosave, and Done.
- Folder actions can create a standalone note directly inside the current nested
  folder.
- Quick Note remains a separate single-tap lightning action and retains the
  existing fast sheet, draft recovery, Inbox/Daily targets, image/audio capture,
  and submit-to-collapse behavior.
- Search, microphone, Quick Note, and New Note remain in one bottom command row;
  no second row was introduced.
- Added Simplified Chinese copy for new-note creation and failure states.

## Verification

- Generic iOS Simulator SDK build passed at `/tmp/MudsnoteStandaloneBuild`.
- Storage automation created unique root and nested-folder Markdown notes,
  verified their empty portable files, then saved through optimistic concurrency.
- UI automation tapped New Note, verified immediate full editing, entered and
  saved Markdown, dismissed the sheet, and found the independent file under All
  Notes with its content-derived title.
- Existing quick-capture UI automation verified the formatting/attachment/target/
  submit controls still occupy one row.
- Full App and UI suite: 77 passed, 0 failed, 0 skipped (61 unit/integration and
  16 UI tests).
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled;
  no iPad or additional simulator was used, and it was shut down afterward.
- Full result bundle:
  `/tmp/MudsnoteStandaloneTests/Logs/Test/Test-MudsnoteCompanion-2026.07.13_17-33-41-+0800.xcresult`.
- Signed Release build passed and strict code-sign verification succeeded at
  `/tmp/MudsnoteStandaloneDevice/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
- Physical installation was attempted, but CoreDevice still reported MudsPhone
  as `unavailable` and could not locate it; install/launch is not claimed.

## Next

- Refresh and verify the signed Release build, then install/launch it when
  `MudsPhone` returns to the CoreDevice online state.
- Continue Notes parity with note creation cleanup/renaming and remaining
  lifecycle polish.
