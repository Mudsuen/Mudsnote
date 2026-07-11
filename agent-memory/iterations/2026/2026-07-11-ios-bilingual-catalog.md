# 2026-07-11 iOS bilingual String Catalog

## Request

Continue Mudsnote iOS commercial-release work by removing mixed-language UI and shipping reviewed localization for the app and widget.

## Baseline

- Branch: `main`
- HEAD: `c617638`
- App and Widget had no localization resources; SwiftUI literals mixed English and Chinese, and model/status strings were always verbatim.

## Changes

- Added one `Localizable.xcstrings` resource to both App and Widget targets with English as the development language and reviewed Simplified Chinese translations.
- Standardized source-facing UI strings on English while preserving Chinese Markdown tags as user data.
- Routed status toasts, folder errors, attachment limits, queue limits, transcription messages, and destination accessibility labels through localized runtime lookup.
- Uses stable format keys for dynamic counts, dates, tags, destinations, and recovery reasons.
- Localized fixed titles passed through `String`-backed view components instead of relying on SwiftUI literal extraction.
- Added an embedded-bundle test for Simplified Chinese lookup and formatted attachment limits.

## Verification

- Commands run:
  - `xcstringstool extract`, key comparison, `xcstringstool compile`, and `plutil -lint`
  - `xcodebuild ... test` on iPhone 17 / iOS 26.5 Simulator
  - unsigned Release build and App/Widget bundle inspection for `en.lproj` and `zh-Hans.lproj`
  - clean install and forced English/Simplified Chinese launches with screenshots
- App/page/package actually opened:
  - `/tmp/mudsnote-onboarding-en-20260711.png`
  - `/tmp/mudsnote-onboarding-zh-20260711.png`
- Result: 16 tests passed; both language bundles are embedded in App and Widget; onboarding rendered without clipping in both languages after widening requirement rows.

## Decisions

- Keep `#图片` and `#语音` unchanged because they are persisted user-data tags, not interface copy.
- Use stable catalog identifiers for formatted strings so compiler placeholder inference cannot drift translations.

## Next

- Run Dynamic Type, VoiceOver, Reduce Motion, landscape, and iPad audits.
- Add UI automation for onboarding, recovery, capture, and destination switching.
