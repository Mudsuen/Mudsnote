# Mudsnote iOS commercial readiness

Last reviewed: 2026-07-11

This checklist tracks the iOS companion only. A checked item requires current source or artifact evidence; unchecked items remain release work.

## Product and interaction

- [x] User-authorized Markdown folder remains the source of truth.
- [x] Inbox, Daily, recent-file targets, text, photo, and audio capture exist.
- [x] Quick Capture widget and App Intents build into the app bundle.
- [x] Repeated capture keeps the selected destination and prevents duplicate sends.
- [x] Removed the reference-only Share Extension placeholder from the release target; v1 explicitly ships App, Widget, and App Intents without claiming system Share Extension support.
- [x] Corrupt, stale, moved, unavailable, or non-folder selections enter an explicit reselect flow; users can clear the old authorization and start over.
- [x] App and Widget ship one reviewed English/Simplified Chinese String Catalog; dynamic status, recovery, attachment, transcription, and accessibility copy use localized runtime strings.

## Stability and data safety

- [x] Pending queue persists ISO-8601 dates and survives process restart.
- [x] Queue replay is automatic and idempotent; a replayed write does not duplicate a memo.
- [x] Failed writes keep the draft visible unless a durable queue item exists.
- [x] Markdown writes use file coordination plus atomic replacement.
- [x] Delete, pin, and tag coordinate against the latest Inbox contents, preserving external/iCloud appends and hidden recovery markers.
- [ ] Add user-facing iCloud conflict resolution instead of warning-only detection.
- [x] Image/audio count, per-file size, combined draft size, and encoded pending-queue growth are bounded with user-facing rejection while the draft remains open.
- [x] Image imports derive their extension from ImageIO/UTType content detection, so PNG/HEIC/JPEG data keeps a matching filename.

## Performance

- [x] Build recent files, exact summary counts, and conflict warnings in one file-store actor inventory instead of recursive main-actor scans.
- [x] Performance fixtures record clock and peak-memory metrics for a 1,000-note library and a maximum 32 MiB attachment draft.
- [ ] Avoid rescanning the whole library after every capture when only Inbox changed.

## Accessibility and visual quality

- [x] Current onboarding and primary dark surfaces render correctly on iPhone 17 / iOS 26.5.
- [x] Onboarding switches to a scrollable accessibility layout at Dynamic Type accessibility sizes; AX XXXL keeps complete text and the folder action reachable.
- [x] UI automation covers onboarding-to-system-folder-picker presentation, corrupt-bookmark recovery, continuous capture, draft reset, and destination retention.
- [ ] Run VoiceOver labels, Dynamic Type, contrast, Reduce Motion, and landscape/iPad audits.
- [ ] Add UI tests for attachment errors and interrupted-write states.

## Privacy and security

- [x] No analytics, accounts, tracking domains, or remote note transmission are present.
- [x] `PrivacyInfo.xcprivacy` declares UserDefaults and user-authorized file timestamp reasons.
- [x] Microphone, Photos, camera, and speech usage descriptions are bundled.
- [ ] Review App Store privacy-label answers against the signed archive.

## Build and release

- [x] iOS 17 minimum deployment target.
- [x] App, Widget, App Intents metadata, and privacy manifest build and embed on Simulator.
- [x] iPad declares all four supported orientations while iPhone remains portrait-first; generic-device validation no longer emits the orientation warning.
- [x] Twenty-one tests pass on the iPhone 17 simulator: eighteen unit/performance tests plus three end-to-end UI tests.
- [x] Development-signed App and Widget install and launch on a physical iPhone Air running iOS 27.0 Beta; both processes were observed alive on-device.
- [ ] Produce a distribution-signed archive and validate it through Organizer/TestFlight.
- [ ] Resolve or prove harmless the Simulator-build `appintentsnltrainingprocessor` SSU archive warning before distribution submission.
- [ ] Run real-device audio, speech, photo, Widget gallery, App Shortcuts, and interrupted-write smokes.
- [ ] Set release marketing/build versions and prepare App Store copy, screenshots, support URL, and privacy-policy URL.
