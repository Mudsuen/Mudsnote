# 2026-07-02 device smoke unavailable state

## Request

Continue toward the active goal that includes iOS real-device install and launch verification.

## Baseline

- Branch: main
- HEAD: 84bec4d
- Dirty files before work: existing Recently Deleted lifecycle work from this iteration.

## Changes

- Improved `scripts/device_smoke.sh` when a paired iPhone is visible but unavailable to CoreDevice.
- The script now prints:
  - the unavailable device name and CoreDevice identifier
  - the `devicectl list devices` table
  - the local Xcode version
  - the local iPhoneOS SDK version
  - a concrete next action to use matching DeviceSupport/DDI

## Verification

- `xcrun devicectl list devices` sees `MudsPhone`, but state is `unavailable`.
- Device JSON reports:
  - `developerModeStatus=enabled`
  - `ddiServicesAvailable=false`
  - `tunnelState=unavailable`
  - device OS `27.0` beta
- `xcodebuild -showdestinations` lists only the generic physical-device placeholder, not `MudsPhone`.
- `xcodebuild -version` is Xcode 26.5 / build 17F42.
- `xcrun --sdk iphoneos --show-sdk-version` is 26.5.
- `./scripts/device_smoke.sh` now exits with a specific unavailable-device diagnostic instead of the generic connect/unlock message.
- `xcodebuild -project iOS/MudsnoteCompanion.xcodeproj -scheme MudsnoteCompanion -configuration Debug -destination 'platform=iOS Simulator,name=iPhone Air,OS=26.5' -derivedDataPath /tmp/mudsnote-ios-sim-derived build` passed.

## Decisions

- Do not mark iOS real-device install complete while CoreDevice reports the phone as unavailable.
- Treat this as an external Xcode/DeviceSupport/DDI compatibility blocker until the device appears as an available destination.

## Next

- Retry `./scripts/device_smoke.sh` after installing or selecting an Xcode build that supports the phone OS.
- Once the phone is available, run the script end to end to build, install, launch, and verify the companion app on device.
