# 2026-07-11 iOS physical-device install

## Request

Install and test the current Mudsnote iOS build directly on the connected phone.

## Baseline

- Branch: `main`
- HEAD: `d74e640`
- Device: `MudsPhone`, iPhone Air, iOS 27.0 Beta, developer mode enabled, wired and paired.

## Changes

- No product source behavior changed.
- Built the App and embedded Widget for `arm64-apple-ios17.0` with the iPhoneOS 26.5 SDK.
- Registered fresh development provisioning profiles containing the connected device.
- Re-signed the nested Widget and then the host App with the development certificate actually contained by those profiles.

## Verification

- `Mudsnote 0.3 (1)` installed on the physical device.
- `app.mudsnote.companion` launched successfully through CoreDevice.
- The host App and `MudsnoteCompanionWidget` processes were both observed alive on the phone.
- The installed build includes App Intents metadata and English/Simplified Chinese NLU assets.
- Full interaction automation was deferred when the phone automatically locked during the Xcode preflight.

## Decisions

- On this Mac, two same-name Apple Development identities exist. Automatic signing selected certificate `B731...`, while newly generated profiles contained `1D63...`; device artifacts must use the profile-matching identity until the duplicate certificate state is cleaned up deliberately.
- iOS 27.0 Beta provides useful physical-device evidence but does not replace stable-runtime compatibility testing.

## Next

- Keep the phone unlocked to run folder, capture, photo, microphone, speech, Widget gallery, and App Shortcut smokes.
