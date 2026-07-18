# 2026-07-15 iOS quick-capture document scanning

## Request

Continue the iPhone Apple Notes parity target while preserving Mudsnote's faster
new-note and quick-note workflow and portable Markdown storage.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `b302800`
- Dirty files before work: none
- Scope remained iPhone-only; no iPad or accessibility work was added.

## Gap

- The full saved-note editor already exposed the native VisionKit document
  scanner, but the primary quick-capture/new-note flow did not.
- This made scanning require creating or opening a conventional note first and
  broke capability parity between Mudsnote's two editing entry points.

## Changes

- Added Scan Document to the quick-capture attachment menu beside the existing
  Photos action without creating a second toolbar row.
- Replaced the dedicated photo circle with a Notes-style paperclip menu while
  retaining direct image-mode system entry behavior for widgets, deep links, and
  App Intents.
- Reused the native VisionKit multi-page scanner already used by full-note editing.
- Extracted the scanner bridge and PDF renderer from the large reader source into
  a shared feature component used by both quick capture and full editing.
- Converts all captured pages into one aspect-fit US Letter PDF with safe margins.
  Empty and invalid pages fail explicitly rather than producing a blank attachment.
- Sends the PDF through the existing `CaptureAttachment.file` validation, protected
  draft recovery, pending-write queue, collision-safe timestamp naming, and relative
  Markdown attachment pipeline.
- Disables submit and attachment actions while the scan is being prepared. Scanner
  cancellation returns cleanly; conversion and size failures keep the draft open and
  present recoverable error copy.
- Restores editor focus only after the full-screen scanner has dismissed so keyboard
  and capture-sheet animations do not compete.
- Added English and Simplified Chinese scan status and recovery copy.

## Verification

- Generic iOS Simulator build, String Catalog JSON validation, and `git diff --check`
  passed.
- Focused unit coverage passed for valid two-page PDF creation, empty/invalid-page
  rejection, quick-capture attachment creation, and the final Inbox pending-write
  Markdown/attachment transaction.
- Focused UI coverage verified all five command controls remain on one row and that
  the paperclip menu exposes both Photos and Scan Document.
- Visual inspection confirmed the one-row capture geometry and Notes-like attachment
  menu. Retained evidence:
  - `/tmp/mudsnote-quick-scan-ui/87EC9A70-73BF-4CBD-8497-495192C16E8A.png`
  - `/tmp/mudsnote-quick-scan-ui/758B6962-8D4C-4415-921D-03938FC0F7EC.png`
- Final full App and UI suite: 117 passed, 0 failed, 0 skipped.
- Only iPhone 17 Pro / iOS 26.5 simulator
  `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5` was used, with parallel testing disabled.
  It was shut down after verification, leaving no booted simulators.
- Final result bundle: `/tmp/MudsnoteQuickScanFullFinal.xcresult`.
- Signed Release build passed from the final source at
  `/tmp/MudsnoteQuickScanRelease/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
  Strict code-sign verification passed for the app and embedded widget.
- MudsPhone remained visible but `unavailable` to CoreDevice on iOS 27.0 beta.
  Installation failed with CoreDevice error 1011 because the device could not be
  located; no physical scan or launch claim was made.

## Decisions

- Scans are ordinary PDFs rather than proprietary scan objects. They remain readable
  in other Markdown editors and file browsers, and the OCR search index from the prior
  iteration can recognize their text.
- Quick capture and full editing share one scanner/PDF implementation but retain their
  existing transactional save boundaries.
- The compact command row gains capability through a menu instead of adding another
  button, preserving the user's one-row interaction contract.

## Next

- Restore MudsPhone CoreDevice availability, then install and launch the signed
  Release for real camera capture, page correction, PDF creation, submission, and OCR
  retrieval checks.
- Continue the next highest-impact Apple Notes parity gap on iPhone.
