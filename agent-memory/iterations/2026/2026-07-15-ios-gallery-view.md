# 2026-07-15 iOS Notes-style gallery view

## Request

Continue evolving the iPhone app toward Apple Notes while retaining Mudsnote's quick-note and Markdown strengths. This iteration closes the folder browsing gap by adding a Notes-style gallery view and complete sort direction controls. iPad and accessibility work remain out of scope.

## Baseline

- Branch: `main`
- HEAD: `9315aae`
- Dirty files before work: none
- Runtime scope: iPhone only; one iPhone 17 Pro simulator with parallel testing disabled

## Changes

- Added persistent List/Gallery presentation selection to ordinary note folders, including All Notes, Daily, and nested folders.
- Added a two-column gallery that preserves pinned and date-grouped sections and surfaces title, preview, folder, attachment, pin, and modification time metadata.
- Reused the existing note lifecycle actions in gallery cards, preserving open, pin, duplicate, rename, move, delete, and multi-selection behavior.
- Completed sorting with contextual ascending/descending choices: Newest/Oldest for dates and Ascending/Descending for titles.
- Persisted view style, sort field, sort direction, and grouping independently, and reset them for isolated UI tests.
- Added Simplified Chinese localization for all new menu labels.
- Extended unit and UI coverage for reverse sorting, gallery layout, persistence, context actions, and selection.

Apple's iPhone Notes guide documents List/Gallery views, title/edited/created sorting, reverse order, and date grouping; this iteration follows that information architecture while keeping Mudsnote's own Markdown cards and actions: <https://support.apple.com/en-ie/guide/iphone/ipha61270292/26/ios/26>.

## Verification

- `git diff --check`: passed.
- `jq empty iOS/Localizable.xcstrings`: passed.
- Focused unit and UI tests for note presentation and gallery persistence: passed.
- Runtime screenshot inspected at `/tmp/mudsnote-gallery-ui/BEBF652F-055C-4DD1-B0BD-8C6F4B5258D5.png`; the iPhone layout rendered as a stable two-column gallery with date grouping.
- Full single-device regression:
  - Command: `xcodebuild -project iOS/MudsnoteCompanion.xcodeproj -scheme MudsnoteCompanion -destination 'platform=iOS Simulator,id=BA9A4203-C694-492A-9CD0-6B80E3BC6ED5' -parallel-testing-enabled NO test`
  - Result: 91 unit tests + 39 UI tests = 130 tests, 0 failures.
  - Result bundle: `/Users/Donald/Library/Developer/Xcode/DerivedData/MudsnoteCompanion-cpwblhytrzptqkfhhqifkvtypuol/Logs/Test/Test-MudsnoteCompanion-2026.07.15_09-05-12-+0800.xcresult`
- Shut down all simulators after verification.
- Signed generic iOS Release build with provisioning updates: passed.
- Strict code-sign verification for `MudsnoteCompanion.app` and `MudsnoteCompanionWidget.appex`: passed.
- Physical install attempted on MudsPhone (`2C558043-5D29-531D-878B-F07C4F288D5D`), but CoreDevice reported the phone as `unavailable` and rejected installation with error 1011. The app was therefore not installed in this iteration.

## Decisions

- Gallery is a presentation of the same note model and lifecycle actions, not a parallel workflow.
- Folder view preferences persist across navigation and relaunch, matching a user-level Notes browsing preference.
- Gallery cards remain Markdown-aware text previews; richer attachment thumbnails can be added separately without coupling them to list behavior.

## Next

- Continue the iPhone Notes-parity audit, prioritizing the next high-value workflow gap after gallery browsing.
- Retry direct installation and launch verification when MudsPhone becomes available to CoreDevice.
