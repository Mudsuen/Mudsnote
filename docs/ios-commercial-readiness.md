# Mudsnote iOS commercial readiness

Last reviewed: 2026-07-11

This checklist tracks the iOS companion only. A checked item requires current source or artifact evidence; unchecked items remain release work.

## Product and interaction

- [x] User-authorized Markdown folder remains the source of truth.
- [x] Inbox, Daily, recent-file targets, text, photo, and audio capture exist.
- [x] Quick Capture widget and App Intents build into the app bundle.
- [x] Repeated capture keeps the selected destination and prevents duplicate sends.
- [ ] Complete the Share Extension as a real target or remove the reference-only surface from release scope.
- [ ] Add first-run recovery for stale, revoked, moved, or unavailable folder bookmarks.
- [ ] Replace hard-coded mixed-language strings with reviewed `String Catalog` localization.

## Stability and data safety

- [x] Pending queue persists ISO-8601 dates and survives process restart.
- [x] Queue replay is automatic and idempotent; a replayed write does not duplicate a memo.
- [x] Failed writes keep the draft visible unless a durable queue item exists.
- [x] Markdown writes use file coordination plus atomic replacement.
- [ ] Coordinate the destructive Inbox rewrite actions used by delete, pin, and tag; hidden recovery markers are already preserved across rewrites.
- [ ] Add user-facing iCloud conflict resolution instead of warning-only detection.
- [ ] Bound image/audio attachment sizes and avoid unbounded base64 queue growth.
- [ ] Verify Photos content type so HEIC/PNG data never receives a misleading `.jpg` extension.

## Performance

- [ ] Move recursive recent-file, summary, tag, and conflict scans off the main actor.
- [ ] Add performance fixtures for large libraries and large attachments.
- [ ] Avoid rescanning the whole library after every capture when only Inbox changed.

## Accessibility and visual quality

- [x] Current onboarding and primary dark surfaces render correctly on iPhone 17 / iOS 26.5.
- [ ] Run VoiceOver labels, Dynamic Type, contrast, Reduce Motion, and landscape/iPad audits.
- [ ] Add UI tests for onboarding, folder recovery, continuous capture, target switching, and error states.

## Privacy and security

- [x] No analytics, accounts, tracking domains, or remote note transmission are present.
- [x] `PrivacyInfo.xcprivacy` declares UserDefaults and user-authorized file timestamp reasons.
- [x] Microphone, Photos, camera, and speech usage descriptions are bundled.
- [ ] Review App Store privacy-label answers against the signed archive.

## Build and release

- [x] iOS 17 minimum deployment target.
- [x] App, Widget, App Intents metadata, and privacy manifest build and embed on Simulator.
- [x] Seven current unit tests pass on the iPhone 17 simulator.
- [ ] Produce a distribution-signed archive and validate it through Organizer/TestFlight.
- [ ] Resolve or prove harmless the Simulator-build `appintentsnltrainingprocessor` SSU archive warning before distribution submission.
- [ ] Run real-device audio, speech, photo, Widget gallery, App Shortcuts, and interrupted-write smokes.
- [ ] Set release marketing/build versions and prepare App Store copy, screenshots, support URL, and privacy-policy URL.
