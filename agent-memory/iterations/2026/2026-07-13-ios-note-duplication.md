# 2026-07-13 iOS note duplication

## Request

Continue the iPhone Apple Notes parity by closing a common note-list lifecycle gap
without compromising local Markdown or attachment safety.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `25a96af`
- Concurrent macOS work was preserved and excluded.

## Changes

- Mutable note rows now expose Duplicate Note in their long-press menu.
- A duplicate is created beside the source as a normal portable Markdown file.
- The first copy uses `Name Copy.md`; later collisions use the existing safe
  numbered-name policy without overwriting user files.
- Markdown content and attachment references remain byte-for-byte portable.
- Creation and modification dates are refreshed so the duplicate behaves as a new
  note in date-sorted lists.
- Pin state is deliberately not copied, matching the duplicate's independent note
  lifecycle.
- Inbox and Daily system notes remain protected from duplication.
- Shared attachment references work with the existing cross-note rename guard, so
  a duplicate cannot later break the source note's attachment.

## Verification

- Storage coverage created two copies, verified collision naming, exact Markdown,
  unchanged attachment payload, and independent pin state.
- UI automation long-pressed `Projects/UI Lifecycle.md`, selected Duplicate Note,
  and found `Projects/UI Lifecycle Copy.md` plus the completion state.
- Final full App and UI suite: 87 passed, 0 failed, 0 skipped (65 unit/integration
  and 22 UI tests).
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled;
  no iPad or additional simulator was used, and it was shut down afterward.
- Full result bundle:
  `/tmp/MudsnoteDuplicateFullTests/Logs/Test/Test-MudsnoteCompanion-2026.07.13_18-55-39-+0800.xcresult`.
- Signed Release build passed and strict code-sign verification succeeded at
  `/tmp/MudsnoteDuplicateDevice/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
- Physical installation was attempted, but CoreDevice still reports MudsPhone as
  `unavailable`; install and launch therefore remain unverified.

## Next

- Install the validated Release artifact when the physical iPhone data connection
  becomes available.
- Continue the next Notes-parity list, note-action, or editing gap.
