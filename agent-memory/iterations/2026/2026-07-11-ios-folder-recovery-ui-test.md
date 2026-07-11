# 2026-07-11 iOS folder recovery UI test

## Request

Continue closing commercial iOS recovery-path gaps after the first critical UI automation pass.

## Baseline

- Branch: `main`
- HEAD: `8bcc7ee`
- Pre-existing dirty files: concurrent macOS library-monitor work outside `iOS/`.

## Changes

- Added a Debug-only corrupt-bookmark fixture to the existing UI-test launch configuration.
- Added stable selectors for reselecting a folder and clearing an invalid permission.
- Added an end-to-end test that enters the real `Folder Unavailable` state from malformed bookmark data, clears the old permission, and verifies the app returns to onboarding.

## Verification

- Full iPhone 17 Pro / iOS 26.5 Simulator suite passes: sixteen unit tests and three UI tests, zero failures.
- Release Simulator build succeeds with `CODE_SIGNING_ALLOWED=NO`.
- The new UI test drove the installed app through error recovery rather than calling `AppModel` directly.

## Decisions

- Recovery tests inject only persisted input corruption; production bookmark resolution and UI state transitions remain authoritative.
- Concurrent macOS changes were preserved and excluded from this iOS commit.

## Next

- Cover attachment rejection and interrupted-write UI states.
- Complete the real-device launch and interaction pass after developer trust is granted on the connected iPhone.
