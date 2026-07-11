# 2026-07-11 iOS folder recovery

## Request

Continue Mudsnote iOS commercial reliability work by making persisted folder authorization recoverable after corruption, movement, removal, or revocation.

## Baseline

- Branch: `main`
- HEAD: `1f26fc9`
- Unrelated macOS editor changes remained excluded.
- Existing iOS baseline: 13 tests passed on the iPhone 17 simulator.

## Changes

- Validates that selected and restored URLs are reachable file-system directories before treating the folder as ready.
- Converts malformed bookmark resolution into a stable user-facing recovery error instead of leaking an opaque Foundation error.
- Clears the in-memory root when restoration fails, preventing later operations from using stale access.
- Distinguishes moved/removed/unavailable folders from selecting an individual file.
- Adds recovery actions to reselect the current folder or clear the saved authorization and return to onboarding.
- Adds isolated UserDefaults regression coverage for corrupted authorization and invalid file selection.

## Verification

- Commands run:
  - `git diff --check`
  - `xcodebuild -project MudsnoteCompanion.xcodeproj -scheme MudsnoteCompanion -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' test`
  - Debug and Release simulator builds, install, and launch.
- Result: 15 tests passed; bookmark corruption and non-folder selection both produce deterministic recovery errors; Debug/Release builds succeeded and the app launched on iPhone 17 / iOS 26.5 Simulator.
- Not verified: revoking a real iCloud Drive security scope or moving an iCloud folder between devices while the app is suspended.

## Decisions

- Keep the failed bookmark until the user either reselects or explicitly clears it, so the error screen can explain the state instead of silently looking like first launch.
- Validate reachability on restoration, but keep the normal security-scoped access wrapper around every later filesystem operation.

## Next

- Complete or remove the Share Extension reference before release.
- Localize mixed-language capture, recovery, and status strings with a String Catalog.
