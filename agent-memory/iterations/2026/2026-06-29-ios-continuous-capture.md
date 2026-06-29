# 2026-06-29 iOS continuous quick capture

## Request

Continue the lightweight iteration goal after the macOS Notes-like library slice: optimize the iOS companion for faster capture rather than turning it into a full editor.

## Changes

- Changed `AppModel.sendDraft` to keep capture open by default after a successful send.
- Added `isSendingDraft` to prevent duplicate sends while a write is in flight.
- Preserved the selected capture target after sending and reset the route back to text for the next memo.
- Removed the explicit sheet dismiss from the send button path.
- Changed `TargetMenuView` from a bare folder icon into a compact pill that shows the current target.
- Added iOS companion tests for target relative paths and attachment-only send eligibility.
- Added the real `MudsnoteCompanionTests` unit-test target to the Xcode project and wired it into the shared `MudsnoteCompanion` scheme.

## Verification

- `xcodebuild -list -project iOS/MudsnoteCompanion.xcodeproj` lists `MudsnoteCompanionTests`.
- XcodeBuildMCP `test_sim` passed 4 iOS tests for `MudsnoteCompanion` on `iPhone 17` simulator with `CODE_SIGNING_ALLOWED=NO`.
- XcodeBuildMCP `build_sim` passed for `MudsnoteCompanion` on `iPhone 17` simulator with `CODE_SIGNING_ALLOWED=NO`.
- XcodeBuildMCP `build_run_sim` passed, installed, and launched `app.mudsnote.companion` on simulator `361B349B-C485-4F27-8980-2977ADC35C58`.
- XcodeBuildMCP `stop_app_sim` passed after setting bundle id `app.mudsnote.companion`.
- `swift test` passed with 57 macOS SwiftPM tests.
- `./scripts/package_app.sh` passed and installed `/Applications/Mudsnote.app`.

## Not Verified

- Manual simulator interaction with repeated send/focus behavior was not performed in this slice.
- Real-device voice transcription, widget gallery, and Shortcuts execution remain open.

## Next

- Add an undo/recent-sent affordance if repeated capture needs recovery.
- Verify continuous text, image, and audio capture manually on simulator, then on device.
