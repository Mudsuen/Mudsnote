# 2026-07-13 iOS generic file attachments

## Request

Continue Notes-style iPhone editor parity by expanding the photo-only editor
attachment flow into a portable local file workflow.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `1c0f04a`
- Concurrent macOS source, tests, documentation, and iteration records were
  preserved and excluded.

## Changes

- Added a dedicated paperclip action beside the photo action in the existing
  single-row Markdown editor toolbar.
- The system file importer accepts one regular file at a time and uses security-
  scoped access only for the duration of the copy.
- File size is checked before loading; generic files share the established 25 MB
  individual and 32 MB draft safety boundaries.
- Imported names are sanitized and bounded, while file extensions are preserved.
- Files are copied into `Attachments/yyyy/mm` with collision-safe timestamped names
  and referenced through ordinary relative Markdown links.
- A failed note update rolls back the copied file through the existing attachment
  transaction.
- Generic Markdown links are now classified as files unless their extension is a
  supported audio type; ordinary PDFs/documents no longer render as audio.
- Capture attachment switches understand the generic-file model even though this
  iteration exposes file importing from the full note editor only.

## Verification

- Generic iOS Simulator SDK build passed.
- Focused storage test proved exact portable bytes, relative Markdown, sanitized
  naming, and generic-file classification.
- Focused UI automation proved the file action is present in the real full editor.
- Full App and UI suite: 65 passed, 0 failed, 0 skipped.
- One iPhone 17 Pro / iOS 26.5 simulator was explicitly booted, used with parallel
  testing disabled, and shut down afterward.
- Result bundles:
  - `/tmp/MudsnoteFileAttachmentFocused.xcresult`
  - `/tmp/MudsnoteFileAttachmentFull.xcresult`

## Next

- Add Quick Look presentation for generic files inside the note sheet, then add
  portable Markdown table insertion/editing and document-scan capture.
