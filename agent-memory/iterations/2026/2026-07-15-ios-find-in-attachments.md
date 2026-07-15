# 2026-07-15 iOS find in attachments

## Request

Continue the full iPhone Apple Notes parity goal while retaining Mudsnote's
local-first Markdown library, quick capture, and default rendered reading surface.
This iteration closes the gap where global search could recognize attachment text
but Find in Note could search only the visible Markdown body.

## Baseline

- Branch: `main`
- HEAD: `2cab653`
- Dirty files before work: none
- Runtime scope: iPhone only; one iPhone 17 Pro simulator with parallel testing disabled

## Changes

- Added a Notes-style `Include Attachments` option to the existing single-row Find
  in Note bar.
- Combined rendered-text and attachment-text matches into one document-ordered result
  sequence with one count and cyclic previous/next navigation.
- Reused the existing bounded, disk-cached local Vision/PDF OCR index rather than
  creating a second recognition path or sending content to a service.
- Loads only attachments referenced by the current Markdown body. The task is
  cancellable when the note, Markdown, find mode, or option changes.
- Attachment matches scroll into view, open any collapsed containing section, and
  show a yellow Notes-like boundary with a short recognized-text excerpt.
- Unsupported, missing, damaged, and oversized attachments remain nonfatal; ordinary
  body search continues to work.
- Added English/Simplified Chinese copy, a pure result-ordering regression, and an
  iPhone UI flow using a real locally generated OCR fixture.

Apple's current iPhone Notes guide says Find in Note can enable `Include Attachments`
to search PDFs and other attachments. Mudsnote implements the locally supportable
image/PDF subset without changing the portable Markdown source:
<https://support.apple.com/guide/iphone/search-notes-iphb8628c6b8/ios>.

## Verification

- `git diff --check`: passed.
- String Catalog JSON validation: passed.
- Focused result-ordering test plus existing body/collapsible-section find flows and
  the new attachment find UI flow: passed.
- Runtime screenshot inspected at
  `/tmp/mudsnote-find-attachment-ui/7E409DB8-6DFE-4435-91A7-D9FD9C9A8BA4.png`;
  the keyboard, search field, attachment option, count, navigation, and Done controls
  remain on one row, while the matching image and OCR excerpt are visible above it.
- Full single-device regression:
  - Command: `xcodebuild -project iOS/MudsnoteCompanion.xcodeproj -scheme MudsnoteCompanion -destination 'platform=iOS Simulator,id=BA9A4203-C694-492A-9CD0-6B80E3BC6ED5' -parallel-testing-enabled NO test`
  - Result: 135 tests, 135 passed, 0 failed, 0 skipped.
  - Result bundle: `/Users/Donald/Library/Developer/Xcode/DerivedData/MudsnoteCompanion-cpwblhytrzptqkfhhqifkvtypuol/Logs/Test/Test-MudsnoteCompanion-2026.07.15_10-12-23-+0800.xcresult`
- Shut down all simulators after verification.
- Signed generic iOS Release build with provisioning updates: passed.
- Strict code-sign verification for `MudsnoteCompanion.app` and
  `MudsnoteCompanionWidget.appex`: passed.
- Physical install attempted on MudsPhone
  (`2C558043-5D29-531D-878B-F07C4F288D5D`), but CoreDevice listed the phone as
  `unavailable` and rejected installation with error 1011. The app was therefore not
  installed in this iteration.

## Decisions

- Attachment recognition remains an optional retrieval layer and never writes OCR
  text or generated metadata into the user's Markdown files.
- Find results follow document order across body and attachment content rather than
  grouping attachment matches separately.
- Image and PDF recognition are claimed; generic binary documents and audio are not
  presented as searchable unless a reliable local text representation exists.

## Next

- Continue the current-state iPhone Notes parity audit and implement the next
  high-value everyday workflow gap.
- Retry direct installation and launch verification when MudsPhone becomes available
  to CoreDevice.
