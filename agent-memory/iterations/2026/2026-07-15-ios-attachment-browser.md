# 2026-07-15 iOS categorized attachment browser

## Request

Continue the iPhone Apple Notes parity goal while preserving Mudsnote's local-first
Markdown source of truth, quick capture, and complete editor. This iteration closes
the attachment-library gap by making stored files browsable by category and linking
each item back to the note that contains it.

## Baseline

- Branch: `main`
- HEAD: `a57b11d`
- Dirty files before work: none
- Runtime scope: iPhone only; one iPhone 17 Pro simulator with parallel testing disabled

## Changes

- Replaced the flat attachment list with one horizontally scrolling category row for
  All, Photos, Audio, and Documents.
- Photos use a two-column thumbnail grid; audio and documents use compact file cards.
- Image thumbnail reads are bounded by the existing attachment size policy and
  downsampled with ImageIO before display, avoiding full-resolution grid decoding.
- A long press exposes `Show in Note`. One owner opens directly; shared attachments
  present the available note titles.
- Attachment ownership is derived during the existing cached Markdown inventory, not
  through a second view-layer filesystem scan.
- Inbox attachment owners are mapped to exact memo identifiers and refreshed by the
  Inbox delta path, so deleted or externally changed memos do not leave stale links.
- Added Simplified Chinese strings plus focused unit and iPhone UI coverage.

Apple documents an attachment browser in Notes and a `Show in Note` action from an
attachment thumbnail. The implementation follows that interaction while limiting the
categories to the file kinds Mudsnote currently stores:

- <https://support.apple.com/en-ie/guide/iphone/iph65637affe/ios>
- <https://support.apple.com/en-ca/118442>
- <https://support.apple.com/en-ae/guide/iphone/iph23f4d9aa9/ios>

## Verification

- `git diff --check`: passed.
- String Catalog JSON validation: passed.
- Focused attachment inventory unit test and attachment-browser UI test: passed.
- Runtime screenshot inspected at
  `/tmp/mudsnote-attachment-browser-ui/EF10EB75-FF7B-45C2-8E40-CB2DC8389A5C.png`;
  the single-row categories, photo grid, and document card render correctly on iPhone.
- Full single-device regression:
  - Command: `xcodebuild -project iOS/MudsnoteCompanion.xcodeproj -scheme MudsnoteCompanion -destination 'platform=iOS Simulator,id=BA9A4203-C694-492A-9CD0-6B80E3BC6ED5' -parallel-testing-enabled NO test`
  - Result: 133 tests, 133 passed, 0 failed, 0 skipped.
  - Result bundle: `/Users/Donald/Library/Developer/Xcode/DerivedData/MudsnoteCompanion-cpwblhytrzptqkfhhqifkvtypuol/Logs/Test/Test-MudsnoteCompanion-2026.07.15_09-49-37-+0800.xcresult`
- Shut down all simulators after verification.
- Signed generic iOS Release build with provisioning updates: passed.
- Strict code-sign verification for `MudsnoteCompanion.app` and
  `MudsnoteCompanionWidget.appex`: passed.
- Physical install attempted on MudsPhone
  (`2C558043-5D29-531D-878B-F07C4F288D5D`), but CoreDevice listed the phone as
  `unavailable` and rejected installation with error 1011. The app was therefore not
  installed in this iteration.

## Decisions

- Attachment ownership belongs in the store snapshot so every consumer sees one
  consistent mapping and the UI never performs recursive filesystem work.
- `Inbox.md` is represented by exact memo owners rather than one coarse file owner.
- Thumbnail loading remains bounded even for user-controlled libraries.
- Web links, map locations, video, and scanned-document-specific grouping are not
  claimed until their corresponding native data types exist in Mudsnote.

## Next

- Continue the current-state iPhone Notes parity audit and implement the next
  high-value everyday workflow gap.
- Retry direct installation and launch verification when MudsPhone becomes available
  to CoreDevice.
