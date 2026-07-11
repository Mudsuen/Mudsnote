# 2026-07-11 iOS critical UI automation

## Request

Continue moving Mudsnote iOS toward commercial release quality with automated coverage of its critical capture journeys.

## Baseline

- Branch: `main`
- HEAD: `ae94db1`
- Dirty files before work: none
- The iOS project had sixteen hosted unit tests but no UI test target.

## Changes

- Added `MudsnoteCompanionUITests` to the project and shared app scheme.
- Added stable accessibility identifiers for folder selection, new-note entry, capture editor, destination menu, and save action.
- Added explicit Debug-only launch configuration for a clean onboarding state or an isolated sandbox Markdown library.
- Added an onboarding test that proves the folder action presents the system document picker.
- Added an end-to-end continuous-capture test that saves to Inbox, verifies draft reset without closing the sheet, switches to Daily, saves again, and proves the selected target remains Daily.

## Verification

- `plutil -lint iOS/MudsnoteCompanion.xcodeproj/project.pbxproj` succeeds.
- `xcodebuild build-for-testing` succeeds with App, Widget, unit-test, and UI-test targets.
- Full iPhone 17 Pro / iOS 26.5 Simulator suite passes: sixteen unit tests and two UI tests, zero failures.
- Release Simulator build succeeds with `CODE_SIGNING_ALLOWED=NO`.
- Inspected the real Simulator app data container after the UI flow:
  - `Inbox.md` contains `First UI memo`.
  - `Daily/2026-07-11.md` contains `Second UI memo`.
  - `.mudsnote/queue.json` remains present with the initialized durable queue.
- Full result bundle: `~/Library/Developer/Xcode/DerivedData/MudsnoteCompanion-cpwblhytrzptqkfhhqifkvtypuol/Logs/Test/Test-MudsnoteCompanion-2026.07.11_16-57-27-+0800.xcresult`

## Decisions

- UI tests use an app-sandbox Markdown folder and the production initializer/write path rather than an in-memory mock.
- Fixture creation and destructive reset require explicit launch arguments and perform work only in Debug builds.
- UI selectors use stable accessibility identifiers so localization does not change the automation contract.
- Concurrent macOS library-monitor changes appeared during verification and were deliberately excluded from this iOS commit.

## Next

- Cover invalid bookmark recovery, attachment rejection, and interrupted-write UI states.
- Continue VoiceOver, contrast, Reduce Motion, landscape, and iPad checks.
