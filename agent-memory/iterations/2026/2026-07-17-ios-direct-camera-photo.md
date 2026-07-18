# 2026-07-17 iOS direct camera photo attachment

## Request

Continue the iPhone Apple Notes parity goal while preserving Mudsnote's quick-note and Markdown strengths. The user explicitly deferred further iPhone table work, so this iteration adds direct photo capture to both note creation surfaces.

## Baseline

- Branch: `main`
- HEAD: `570770d`
- Dirty files before work: none
- Runtime scope: iPhone only; one iPhone 17 Pro simulator with parallel testing disabled

## Changes

- Added a reusable native camera capture controller that produces validated JPEG data and reports preparation failures without losing the current draft.
- Added `Take Photo` to the existing attachment menus in Quick Capture and the full Markdown note editor; the compact command surfaces remain one row.
- Routed camera output through the same image validation, 15 MiB attachment policy, portable relative Markdown link storage, refresh, and conflict-safe save path already used by the Photos picker.
- Restored editor focus after camera cancellation or successful attachment and added localized recovery alerts for capture preparation failures.
- Added Simplified Chinese strings and regression coverage for camera JPEG preparation, invalid images, and both attachment menus.
- Kept iPhone table expansion outside this iteration, as requested.

Apple Notes exposes both `Take Photo or Video` and `Choose Photo or Video` from its attachment flow. This iteration adopts the direct photo portion while retaining Mudsnote's local Markdown storage model: <https://support.apple.com/en-us/118442>.

## Verification

- `git diff --check`: passed.
- `jq empty iOS/Localizable.xcstrings`: passed.
- Focused camera unit tests: 2 passed.
- Focused Quick Capture and full-editor attachment-menu UI tests: 2 passed.
- Full single-device regression:
  - Device: iPhone 17 Pro simulator `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5`, iOS 26.5.
  - Parallel testing: disabled.
  - Result: 141 tests, 0 failures, 0 skipped.
- Signed generic iOS Release build with provisioning updates: passed.
- Strict code-sign verification for `MudsnoteCompanion.app` and `MudsnoteCompanionWidget.appex`: passed.
- Physical install attempted on MudsPhone (`2C558043-5D29-531D-878B-F07C4F288D5D`), but CoreDevice reported the USB device as `unavailable` and rejected installation with error 1011. Xcode's device preparation layer requested an unlocked, cabled device or an available Developer Mode network connection. Direct camera hardware capture therefore remains pending until the device is available.
- The combined Simulator and Release DerivedData measured 482 MB before cleanup; it was kept only under `/tmp` and removed after verification. All simulators were shut down.

## Decisions

- Keep `Take Photo` inside the attachment menu rather than adding another command-bar button, preserving the user's single-row layout requirement.
- Use the system camera controller and existing camera usage description instead of a custom camera stack.
- Normalize captured photos to JPEG before applying the existing attachment policy so Photos picker and camera attachments share one storage contract.
- Keep table-related iPhone work deferred.

## Next

- Retry installation, launch, permission handling, actual capture, and Markdown rendering on MudsPhone when CoreDevice exposes it.
- Continue the next non-table iPhone Notes-parity or commercial-readiness gap.
