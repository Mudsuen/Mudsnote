# 2026-07-11 iOS integration scope

## Request

Close the Mudsnote iOS Share Extension readiness item without exposing an unimplemented capability in the commercial build.

## Baseline

- Branch: `main`
- HEAD: `fe4041a`
- The app target compiled a dead `ShareExtensionReference` note but no Share Extension target existed.

## Changes

- Removed the placeholder source from the app target and Xcode project.
- Defined v1 integration scope as the app, Quick Capture widget, deep links, and App Intents.
- Kept a future Share Extension out of the production binary until it has a real target, app-group queue design, tests, and device verification.

## Verification

- Commands run:
  - `plutil -lint iOS/MudsnoteCompanion.xcodeproj/project.pbxproj`
  - `xcodebuild ... test` on the iPhone 17 simulator
  - unsigned Release simulator build and bundle source/reference inspection
- Result: the app and widget build, all 15 tests pass, and no `ShareExtensionReference` symbol or source remains in the project.

## Decisions

- Do not market or imply system share-sheet capture in v1.
- Reintroduce a Share Extension only as an independently testable target with durable cross-process recovery.

## Next

- Move mixed-language copy into a reviewed String Catalog.
- Continue accessibility and UI-flow verification before distribution archive work.
