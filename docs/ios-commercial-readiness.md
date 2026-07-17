# Mudsnote iOS commercial readiness

Last reviewed: 2026-07-17

This checklist tracks the iOS companion only. A checked item requires current source or artifact evidence; unchecked items remain release work.

## Product and interaction

- [x] User-authorized Markdown folder remains the source of truth.
- [x] Inbox, Daily, recent-file targets, text, photo/video, generic file, scanned document, and audio capture exist.
- [x] Quick Capture widget and App Intents build into the app bundle.
- [x] Repeated capture keeps the selected destination and prevents duplicate sends.
- [x] Rendered notes recognize actionable email addresses, phone numbers, and street addresses without modifying the underlying Markdown; explicit Markdown links retain priority.
- [x] Attachments can be browsed by photo, video, audio, and document category; a long press returns to the exact containing note or Inbox memo.
- [x] Open notes let each attachment render as Small, Large, or Plain Link and let the whole note set all attachments to Small or Large; presentation choices persist through note, folder, and attachment lifecycle changes without rewriting Markdown.
- [x] Quick Capture and the full editor can choose or capture a short video, save it as a portable Markdown attachment, and play it inline when the note is opened.
- [x] Scanned and imported PDFs open in native Quick Look markup, save atomically back to the portable attachment, reject stale external edits, and do not rewrite unchanged files.
- [x] Open notes export as print-ready, paginated PDFs through the native share sheet with Preview, Markup, Print, and Save to Files while leaving Markdown source unchanged.
- [x] Audio recorded inside an open note is attached before local transcription begins; successful speech becomes ordinary editable and searchable Markdown, while empty or failed transcription keeps the recording.
- [x] Find in Note optionally includes locally recognized text from referenced images and PDFs, combines text and attachment matches into one navigable sequence, and never modifies Markdown.
- [x] Empty library search presents one-row structured suggestions for pinned notes, attachments, checklists, and notes edited today; suggestions respect All/Notes/Inbox scope and transition cleanly into full-text search.
- [x] Camera Scan Text inserts recognized content at the active caret in Quick Capture and the full Markdown editor as ordinary editable and searchable Markdown.
- [x] Gallery cards preview a note's first image and checklist state from cached Markdown list metadata without view-layer file scans.
- [x] A left swipe on a movable note exposes Move beside Delete and opens a native half-sheet destination picker; moving to the top level or another folder updates the list through the existing atomic lifecycle operation.
- [x] Folder Edit mode exposes a native drag handle; dragging one real folder onto another creates a nested folder through the existing atomic move operation, with cycle rejection, target feedback, refreshed counts, and preserved normal-mode navigation/context menus.
- [x] Removed the reference-only Share Extension placeholder from the release target; v1 explicitly ships App, Widget, and App Intents without claiming system Share Extension support.
- [x] Corrupt, stale, moved, unavailable, or non-folder selections enter an explicit reselect flow; users can clear the old authorization and start over.
- [x] App and Widget ship one reviewed English/Simplified Chinese String Catalog; dynamic status, recovery, attachment, transcription, and accessibility copy use localized runtime strings.

## Stability and data safety

- [x] Pending queue persists ISO-8601 dates and survives process restart.
- [x] Queue replay is automatic and idempotent; a replayed write does not duplicate a memo.
- [x] Failed writes keep the draft visible unless a durable queue item exists.
- [x] Markdown writes use file coordination plus atomic replacement.
- [x] Delete, pin, and tag coordinate against the latest Inbox contents, preserving external/iCloud appends and hidden recovery markers.
- [x] External editor conflicts preserve the local draft until the user keeps editing or reloads the saved version; provider-generated conflict copies have a dedicated review flow that can keep either version as a normal note without overwriting the other.
- [x] Image/video/audio count, per-file size, combined draft size, and encoded pending-queue growth are bounded with user-facing rejection while the draft remains open.
- [x] Image imports derive their extension from ImageIO/UTType content detection, so PNG/HEIC/JPEG data keeps a matching filename.

## Performance

- [x] Build recent files, exact summary counts, and conflict warnings in one file-store actor inventory instead of recursive main-actor scans.
- [x] Performance fixtures record clock and peak-memory metrics for a 1,000-note library, Inbox-only delta refresh, and a maximum 64 MiB attachment draft.
- [x] Plain-text Inbox captures and Inbox card mutations refresh the cached Inbox slice and recent-file entry without recursively rescanning the library; other targets, attachment writes, queue replay, and explicit refresh still run a complete inventory.

## Visual quality and automation

- [x] Current onboarding and primary dark surfaces render correctly on iPhone 17 / iOS 26.5.
- [x] Onboarding switches to a scrollable accessibility layout at Dynamic Type accessibility sizes; AX XXXL keeps complete text and the folder action reachable.
- [x] UI automation covers onboarding-to-system-folder-picker presentation, corrupt-bookmark recovery, continuous capture, draft reset, and destination retention.
- [x] Attachment errors remain inside Quick Capture and restore editing after dismissal; interrupted writes keep the full draft visible with an inline retry action. Both recovery states have UI regression coverage.

Dedicated accessibility and iPad validation are outside the current iPhone-only product scope.

## Privacy and security

- [x] No analytics, accounts, tracking domains, or remote note transmission are present.
- [x] `PrivacyInfo.xcprivacy` declares UserDefaults and user-authorized file timestamp reasons.
- [x] Microphone, Photos, camera, and speech usage descriptions are bundled.
- [x] Review the no-data-collected App Store privacy-label draft against the development-signed `1.0 (1)` archive; reconfirm after distribution export.

## Build and release

- [x] iOS 17 minimum deployment target.
- [x] App, Widget, App Intents metadata, and privacy manifest build and embed on Simulator.
- [x] iPad declares all four supported orientations while iPhone remains portrait-first; generic-device validation no longer emits the orientation warning.
- [x] One hundred fifty-eight tests pass on one iPhone 17 Pro / iOS 26.5 Simulator with parallel testing disabled; PDF markup persistence additionally passes five consecutive stress iterations.
- [x] Development-signed App and Widget install and launch on a physical iPhone Air running iOS 27.0 Beta; both processes were observed alive on-device.
- [ ] Produce a distribution-signed archive and validate it through Organizer/TestFlight.
- [x] A generic-device `1.0 (1)` archive completes App Intents SSU generation for English and Simplified Chinese without the prior `appintentsnltrainingprocessor` warning.
- [ ] Run real-device audio, speech, photo, Widget gallery, App Shortcuts, and interrupted-write smokes.
- [x] Release version `1.0 (1)`, bilingual App Store copy, review notes, and privacy-policy URL are prepared and machine-validated.
- [ ] Replace the provisional GitHub Issues support URL with a public support page containing actual contact information before App Store submission.
- [ ] Capture and validate App Store screenshots at an accepted iPhone size.
