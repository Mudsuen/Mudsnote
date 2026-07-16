# 2026-07-17 iOS App Store 1.0 metadata

## Request

Continue the iPhone-only Apple Notes parity and commercial-readiness goal without expanding iPhone table authoring. Close the next truthful release gap while preserving Mudsnote's Quick Capture and Markdown features.

## Baseline

- Branch: `main`
- HEAD: `1cf8448`
- Dirty files before work: none
- Runtime scope: iPhone only; one iPhone 17 Pro simulator with parallel testing disabled

## Changes

- Unified App, Widget, unit-test, and UI-test Debug/Release configurations on marketing version `1.0` and build `1`.
- Changed the App Info.plist to inherit `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, matching the Widget and preventing future project/plist drift.
- Added bilingual `en-US` and `zh-Hans` App Store metadata for Mudsnote: name, subtitle, promotional copy, description, keywords, review notes, category, provisional support URL, and privacy-policy URL.
- Added a machine validator for Apple's field limits, HTTPS URLs, required localizations, all eight target configurations, and Info.plist version inheritance.
- Kept App Store screenshots explicitly `pending` with the required iPhone scenes instead of claiming an unproduced deliverable.
- Marked the GitHub Issues support URL as provisional after confirming Apple's current support-URL rule requires a page with actual contact information; no personal contact detail was published without user approval.
- Reviewed the no-data-collected privacy-label draft against the signed archive. The app embeds no third-party frameworks; its privacy manifest declares no collected data, tracking, or tracking domains.
- Updated the commercial-readiness checklist with the exact completed and remaining release work.
- Kept iPhone table functionality unchanged.

## Verification

- Public support and privacy URLs returned HTTP 200:
  - `https://github.com/Mudsuen/Mudsnote/issues`
  - `https://github.com/Mudsuen/Mudsnote/blob/main/PRIVACY.md`
- `python3 scripts/validate_ios_app_store_metadata.py`: passed for `1.0 (1)`.
- `plutil -lint` for App and Widget Info.plists: passed.
- `jq empty iOS/AppStore/metadata.json`: passed.
- `git diff --check`: passed.
- Generic iOS Release archive: succeeded at `/tmp/MudsnoteIOS1.0.xcarchive`.
- Archived App and Widget both report `CFBundleShortVersionString = 1.0` and `CFBundleVersion = 1`.
- Strict deep code-sign verification: passed for the development-signed App and embedded Widget.
- App Intents SSU generation archived English and Simplified Chinese successfully and emitted no archive warning.
- Signed-archive privacy review found only Apple system frameworks, no embedded third-party frameworks, and an embedded `PrivacyInfo.xcprivacy` with empty collected-data/tracking declarations.
- Clean full single-device regression:
  - Device: iPhone 17 Pro simulator `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5`, iOS 26.5.
  - Parallel testing: disabled.
  - Result: 145 tests, 0 failures; unit suite 100/100 and UI suite 45/45.
- Physical install was retried on MudsPhone (`2C558043-5D29-531D-878B-F07C4F288D5D`). CoreDevice still listed it as `unavailable` and rejected installation with error 1011.
- Peak temporary artifacts before cleanup: 476 MB DerivedData, 20 MB archive, and 716 KB combined logs. All stayed under `/tmp`; the sole simulator was shut down.

## Decisions

- Treat `1.0 (1)` as the first commercial-release version across every iOS target configuration.
- Keep App Store metadata as reviewable JSON plus a local validator rather than unvalidated prose spread across documents.
- A development-signed archive is sufficient for code, privacy-manifest, version, and SSU inspection, but it does not satisfy the distribution-signed Organizer/TestFlight requirement.
- Screenshot capture, distribution signing, App Store Connect entry, and TestFlight validation remain explicit release tasks.
- The final support page must contain user-approved contact information; a reachable GitHub Issues page alone is not treated as submission-ready.
- No separate durable architecture decision is required.

## Next

- Capture and validate the five planned App Store scenes at an accepted iPhone size.
- Publish a support page with user-approved actual contact information and replace the provisional URL.
- Produce and validate a distribution-signed archive through Organizer/TestFlight.
- Reconfirm the privacy-label draft after distribution export.
- Retry physical installation and real-device media/Widget/App Shortcuts smokes when MudsPhone becomes available to CoreDevice.
