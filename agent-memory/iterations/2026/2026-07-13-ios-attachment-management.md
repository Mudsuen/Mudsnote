# 2026-07-13 iOS attachment management

## Request

Continue complete Notes-style iPhone editing by making rendered attachments
manageable without exposing raw Markdown or adding collaboration/share-link
features.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `aaf4e2e`
- Concurrent macOS work was preserved and excluded.

## Changes

- Long-pressing a rendered image, audio item, or file now exposes Rename
  Attachment, Share Attachment, and Remove from Note.
- Share Attachment uses the system file share sheet; it does not create a Mudsnote
  account, collaboration session, or public share link.
- Rename preserves the file extension, validates the user-facing base name, and
  resolves destination collisions without overwriting another file.
- The physical attachment move and Markdown reference rewrite form one transaction;
  a note-save conflict rolls the file move back.
- All references to the attachment inside the current note move together.
- If another Markdown note references the same attachment, rename is refused rather
  than silently breaking that note.
- Added complete Simplified Chinese copy for the new commands and safety errors.

## Verification

- Storage coverage verifies the file move, portable Markdown reference, payload
  preservation, and shared-reference refusal.
- UI automation opened the fixture note, long-pressed its generic attachment,
  verified the system-share action, renamed `ui-test.txt` to
  `ui-test-renamed.txt`, and found the new rendered attachment.
- Final full App and UI suite: 85 passed, 0 failed, 0 skipped (64 unit/integration
  and 21 UI tests).
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled;
  no iPad or additional simulator was used, and it was shut down afterward.
- Full result bundle:
  `/tmp/MudsnoteAttachmentManagementFullTests/Logs/Test/Test-MudsnoteCompanion-2026.07.13_18-45-22-+0800.xcresult`.
- Signed Release build passed and strict code-sign verification succeeded at
  `/tmp/MudsnoteAttachmentManagementDevice/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
- Physical installation was attempted, but CoreDevice still reports MudsPhone as
  `unavailable`; install and launch therefore remain unverified.

## Next

- Install the validated Release artifact when the physical iPhone data connection
  becomes available.
- Continue the next Notes-parity editing or organization gap.
