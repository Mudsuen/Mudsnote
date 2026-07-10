# 2026-07-11 iOS commercial reliability baseline

## Request

Optimize Mudsnote iOS and ShortcutTiles toward commercial-release completion, preserving their existing core workflows and verifying real app artifacts.

## Baseline

- Branch: `main`
- HEAD: `54bd355`
- Dirty files before work: none.
- iOS baseline: `xcodebuild ... test` passed 4 tests on the iPhone 17 simulator.

## Changes

- Made pending-write queue dates decode with the same ISO-8601 strategy used when persisting them.
- Made Markdown capture writes idempotent with a stable hidden write marker and coordinated atomic file replacement.
- Automatically replays pending captures after restoring folder access, while keeping failed drafts visible when nothing reached the durable queue.
- Keeps hidden idempotency markers out of memo bodies/previews while preserving them through delete, pin, and tag rewrites.
- Added queue round-trip and duplicate-replay regression tests.
- Added an app privacy manifest for user-defaults and user-authorized file timestamp access; the app continues to declare no collection or tracking.

## Verification

- Commands run:
  - `plutil -lint iOS/MudsnoteCompanion/PrivacyInfo.xcprivacy`
  - `xcodebuild -project iOS/MudsnoteCompanion.xcodeproj -scheme MudsnoteCompanion -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO test`
  - signed Debug and unsigned Release simulator builds, `simctl install`, `simctl launch`, bundle inspection, and strict signature verification
- App/page/package actually opened: installed `app.mudsnote.companion` on iPhone 17 / iOS 26.5 Simulator; onboarding screenshot `/tmp/mudsnote-ios-commercial-final-20260711.png`.
- Result: 7 tests passed; app and embedded Widget built; privacy manifest exists at the app-bundle root; minimum OS is 17.0; onboarding launched with consistent queue copy.
- Not verified: real-device iCloud conflict behavior, audio/speech/widget behavior, interruption during the underlying filesystem atomic replacement, and the non-fatal Simulator SSU archive warning under `appintentsnltrainingprocessor`.

## Decisions

- A queued capture must survive restart and be safe to replay more than once.
- Keep recovery metadata as Markdown HTML comments so files remain portable and the marker stays invisible in rendered notes.

## Next

- Follow `docs/ios-commercial-readiness.md`, starting with coordinated Inbox rewrites and moving recursive library scans off the main actor.
