# 2026-07-15 iOS attachment OCR search

## Request

Continue the iPhone Apple Notes parity target, with particular attention to the
broken search experience and commercial-grade architecture and reliability.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `66aedf9`
- Dirty files before work: none
- Scope remained iPhone-only; no iPad or accessibility work was added.

## Changes

- Extended library search to find text inside image and PDF attachments that are
  actually referenced by Markdown notes or Inbox memos.
- Added an on-device Vision recognizer for PNG, JPEG, HEIC, GIF, WebP, TIFF, and
  the first 12 pages of PDFs. Recognition is local and does not require a server.
- Kept ordinary Markdown search on its existing fast path. Attachment OCR only
  runs when note title, path, body, tags, and date do not already satisfy the
  query.
- Combined note metadata and recognized attachment text for multi-term queries,
  so a title term and an image term can match the same note.
- Search results now show the recognized context and source attachment filename,
  then open the owning note with its rendered attachment.
- Added a persistent, disposable OCR cache under the app Caches directory. No
  recognized text or index metadata is written to the Markdown/iCloud library.
- Cache entries invalidate when attachment byte count or modification date
  changes and are trimmed to the 512 most recently accessed entries.
- Constrained OCR to authorized `Attachments/` paths, ignored fenced Markdown
  examples, decoded percent-escaped paths, and rejected traversal outside the
  attachment directory.
- Limited individual files to 32 MB, PDF rendering to 2048 points per dimension,
  PDF recognition to 12 pages, and stored recognized text to 32 KB per attachment.
- Damaged, missing, and unsupported attachments are skipped without failing the
  entire search; cancellation still stops obsolete searches.

## Verification

- Generic iOS Simulator build passed.
- Focused tests passed for safe Markdown attachment parsing, combined metadata
  and OCR matching, cache reuse across store recreation, cache invalidation, and
  real Vision recognition of generated image and PDF content.
- Focused UI coverage searched for text that existed only inside a PNG, verified
  recognized context plus attachment attribution, opened the result, and found
  the rendered attachment.
- Visual inspection confirmed the result displayed highlighted OCR text and
  `Projects/OCR Attachment.md · ocr-search.png` without adding a second command
  row. Retained evidence:
  `/tmp/mudsnote-attachment-ocr-visual/0B47FFA1-1F77-41AF-8486-AF72CEC5BC55.png`.
- Final full App and UI suite: 116 passed, 0 failed, 0 skipped.
- Only iPhone 17 Pro / iOS 26.5 simulator
  `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5` was used, with parallel testing disabled.
  It was shut down after verification, leaving no booted simulators.
- Final result bundle: `/tmp/MudsnoteAttachmentOCRFullFinalTests.xcresult`.
- Signed Release build passed from the final source at
  `/tmp/MudsnoteAttachmentOCRRelease/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
  Strict code-sign verification passed for the app and embedded widget.
- MudsPhone remained visible but `unavailable` to CoreDevice on iOS 27.0 beta.
  Installation failed with CoreDevice error 1011 because the device could not be
  located; no physical install or launch claim was made.

## Decisions

- OCR is on demand instead of an eager full-library migration. This preserves
  fast normal searches, avoids background churn, and builds a reusable index as
  the user searches.
- The OCR cache is derived local state, not note data. It can be deleted safely
  and never pollutes the portable Markdown library or iCloud Drive.
- Search remains note-centric: attachment matches open the owning editable note
  rather than introducing a separate proprietary attachment database UI.

## Next

- Restore MudsPhone CoreDevice availability, then install and launch the signed
  Release for physical OCR latency and search-to-editor checks.
- Continue the next highest-impact Apple Notes parity gap on iPhone, with
  in-note attachment/object search as the likely follow-up.
