# 2026-07-17 iOS camera Scan Text

## Request

Continue the iPhone Apple Notes parity goal while preserving Mudsnote's quick-note and Markdown strengths. The user explicitly deferred further iPhone table work, so this iteration adds camera-recognized text insertion without adding table authoring.

## Baseline and audit

- Branch: `main`
- HEAD: `8339f82`
- Dirty files before work: none
- Runtime scope: iPhone only; one iPhone 17 Pro simulator with parallel testing disabled
- Apple Notes' current attachment flow includes Scan Text, while Mudsnote's Quick Capture menu already offered document scan, file import, camera, and Photos but no direct text capture.
- Baseline screenshot: `/tmp/MudsnoteIOSScanTextAudit-20260717/baseline/E8C2F75C-CCCD-4C57-A0A4-E319AF9B0597.png` (temporary evidence removed after verification).

## Changes

- Added `Scan Text` to the existing single-column attachment menu in Quick Capture and the full Markdown editor.
- Restored the active editor as first responder before invoking UIKit's native `captureTextFromCamera(_:)` action, so recognized text is inserted at the current caret instead of entering a separate import flow.
- Gated the action with VisionKit hardware and runtime availability.
- Kept the inserted result as ordinary Markdown text, preserving editing, search, local-file portability, autosave, and conflict behavior.
- Added Simplified Chinese localization and deterministic UI-test coverage for both editor surfaces.
- Kept iPhone table expansion outside this iteration, as requested.

Apple documents Scan Text as an attachment action that inserts recognized camera text into a note, and UIKit exposes the same responder action for `UIKeyInput` / `UITextInput` editors:

- <https://support.apple.com/en-gb/guide/iphone/iph653f28965/26/ios/26>
- <https://developer.apple.com/documentation/uikit/uiaction/capturetextfromcamera%28responder%3Aidentifier%3A%29>
- <https://developer.apple.com/documentation/uikit/uiresponder/capturetextfromcamera%28_%3A%29>

## Verification

- `git diff --check`: passed before release verification.
- `jq empty iOS/Localizable.xcstrings`: passed.
- Focused Quick Capture Scan Text UI test: passed.
- Focused full Markdown editor Scan Text UI test: passed.
- Visual comparison: the five attachment actions remain in one stable single-column menu, the keyboard remains visible, and the command bar does not wrap. Combined evidence: `/tmp/MudsnoteIOSScanTextAudit-20260717/before-after.png` (temporary evidence removed after verification).
- Full single-device regression:
  - Device: iPhone 17 Pro simulator `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5`, iOS 26.5.
  - Parallel testing: disabled.
  - Result: 148 tests, 0 failures, 0 skipped.
- Development-signed generic iOS Release archive `1.0 (1)`: passed with no warnings or errors.
- Strict code-sign verification for `MudsnoteCompanion.app` and `MudsnoteCompanionWidget.appex`: passed.
- Root app privacy manifest: present. App Intents metadata completed without the prior SSU warning.
- Physical install was attempted once on MudsPhone (`2C558043-5D29-531D-878B-F07C4F288D5D`), but CoreDevice listed the phone as `unavailable` and rejected the install with error 1011. Actual camera recognition therefore remains pending until the device reconnects.
- Peak temporary storage before cleanup was approximately 515 MB: 297 MB Simulator DerivedData, 189 MB Release DerivedData, 21 MB archive, 7.1 MB visual evidence, and under 1 MB logs. All artifacts were confined to `/tmp` for deletion after verification.

## Decisions

- Use UIKit's system Scan Text pipeline rather than maintaining a custom OCR camera UI.
- Keep Scan Text inside the attachment menu rather than adding a command-bar button, preserving the single-row editing layout.
- Use the existing first-responder insertion contract so both editors receive text at their current selection.
- Keep table-related iPhone work deferred.

## Next

- Retry installation and actual camera recognition on MudsPhone when CoreDevice exposes it.
- Continue the next non-table iPhone Notes-parity or commercial-readiness gap.
