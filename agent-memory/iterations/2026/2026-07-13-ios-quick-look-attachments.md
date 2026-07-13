# 2026-07-13 iOS Quick Look attachments

## Request

Continue Notes-style iPhone parity by making rendered note attachments directly
previewable without leaving the note workflow.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `4b1e5ea`
- Concurrent macOS source, tests, documentation, and iteration records were
  preserved and excluded.

## Changes

- Rendered image attachments now open the system Quick Look preview when tapped.
- Rendered generic file attachments now open Quick Look instead of handing the
  file to an external link destination.
- Audio attachments keep their native inline player behavior.
- Preview URLs continue to resolve through the active security-scoped notes
  folder, so Markdown remains portable and stores no device-specific absolute
  paths.
- Added a deterministic text attachment to the UI fixture and a complete UI test
  covering open, correct file title, system close, and return to the note.
- Updated the existing autosave UI test to tap rendered body text rather than the
  center of the whole rendered region, because that region now legitimately
  contains an interactive attachment.

## Verification

- Generic iOS Simulator SDK build passed at `/tmp/MudsnoteQuickLookBuild`.
- Focused Quick Look UI automation passed after aligning the assertion with the
  real iOS 26.5 Quick Look controller identifiers.
- Focused editor autosave automation passed with the body-versus-attachment tap
  paths separated.
- Full App and UI suite: 66 passed, 0 failed, 0 skipped (54 unit + 12 UI).
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled;
  no iPad or additional simulator was used.
- Result bundles:
  - `/tmp/MudsnoteQuickLookFocused4.xcresult`
  - `/tmp/MudsnoteQuickLookAutosaveRetry3.xcresult`
  - `/tmp/MudsnoteQuickLookFull2.xcresult`

## Next

- Add portable Markdown table insertion/editing and document-scan capture while
  keeping the rendered-note-first editing model.
