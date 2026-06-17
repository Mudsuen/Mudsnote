# 2026-06-14 iOS companion icon

## Request

Create and apply an icon for the second iOS app, matching the user's dark native professional style.

## Baseline

- Repo had pre-existing dirty files before this icon pass:
  - `.gitignore`
  - `agent-memory/iterations/2026/2026-06-08-ios-companion-v03.md`
  - `iOS/MudsnoteCompanion.xcodeproj/project.xcworkspace/xcuserdata/Donald.xcuserdatad/UserInterfaceState.xcuserstate`
  - `scripts/device_smoke.sh`

## Changes

- Added `MudsnoteCompanion/Assets.xcassets/AppIcon.appiconset`.
- Generated a dark glass-style `M NOTES` icon set in all standard iOS app icon sizes.
- Added the asset catalog to the MudsnoteCompanion app target resources.
- Set `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` for the app target.

## Verification

- `xcodebuild -project /Users/Donald/Code/Mudsnote/iOS/MudsnoteCompanion.xcodeproj -scheme MudsnoteCompanion -destination 'generic/platform=iOS' build`
- Installed the built app on connected `MudsPhone` with `xcrun devicectl device install app`.

## Decisions

- Kept the existing Mudsnote app display name unchanged.
- Did not touch pre-existing dirty files unrelated to the icon hookup.
