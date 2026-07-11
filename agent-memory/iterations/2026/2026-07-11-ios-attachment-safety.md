# 2026-07-11 iOS attachment safety

## Request

Continue Mudsnote iOS commercial-release hardening by bounding attachment memory/persistence risk and preserving correct file types.

## Baseline

- Branch: `main`
- HEAD: `d102031`
- Unrelated macOS editor changes were already present and remained excluded.
- Existing iOS baseline: 9 tests passed on the iPhone 17 simulator.

## Changes

- Uses ImageIO and UTType to validate image bytes and derive a matching PNG, HEIC, JPEG, or other supported image extension.
- Rejects empty or unsupported image data instead of persisting misleading files.
- Limits a memo to eight attachments, 15 MB per image, 25 MB per audio recording, and 32 MB combined attachments.
- Preflights file-import size before reading it into memory and revalidates the complete draft before preparing a write.
- Limits the pending queue to 50 captures and 96 MB of encoded attachment payload.
- Distinguishes rejection before durable enqueue from a write that is safely pending, keeping the draft open with an accurate message.
- Cleans up a temporary recording if attachment validation rejects it.

## Verification

- Commands run:
  - `git diff --check`
  - `xcodebuild -project MudsnoteCompanion.xcodeproj -scheme MudsnoteCompanion -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' test`
  - Debug and Release simulator builds, signed install, and launch.
- Result: 13 tests passed, including real PNG type detection, corrupt image rejection, attachment bounds, and pending-queue bounds; Debug/Release builds succeeded and the app launched on iPhone 17 / iOS 26.5 Simulator.
- Not verified: large HEIC selection and long audio capture on a physical device under memory pressure.

## Decisions

- Keep original compressed image bytes rather than transcoding; portability requires a correct extension, not a second lossy encode.
- Bound both raw draft data and encoded recovery data because base64 amplification affects queue memory and disk usage separately.
- Reject before clearing the draft whenever current-capture durability cannot be proven.

## Next

- Add real-device attachment stress tests and visible size information in the capture strip.
- Implement folder-bookmark recovery and remove or complete the reference-only Share Extension surface.
