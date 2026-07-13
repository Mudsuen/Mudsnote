# 2026-07-13 iOS local note sharing

## Request

Continue the iPhone Apple Notes parity by adding whole-note sharing while keeping
Mudsnote local-first and excluding collaboration, accounts, and public share links.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `19614fa`

## Changes

- Rendered Markdown notes now expose the native iOS system share action in the
  reading toolbar.
- File-backed notes share their actual local Markdown file, preserving the portable
  `.md` artifact instead of flattening it into a proprietary representation.
- Memo-backed notes share their Markdown text directly.
- Sharing is intentionally available only in rendered reading mode. It is hidden
  while editing so an unsaved draft cannot be mistaken for the saved export.
- The action has a Simplified Chinese localization (`分享笔记`).
- This remains local system sharing only; no collaboration identity, cloud account,
  or public-link feature was introduced.

## Verification

- Focused UI automation opened a real fixture note and verified the native share
  control in rendered reading mode.
- Directly driving the system share sheet was excluded from the automated assertion
  because XCUITest hands control to SpringBoard across the process boundary. The
  implementation itself uses SwiftUI `ShareLink`, and the test remains deterministic
  inside Mudsnote.
- Final full App and UI suite: 88 passed, 0 failed, 0 skipped (65 unit/integration
  and 23 UI tests).
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled;
  no iPad or additional simulator was used, and it was shut down afterward.
- Full result bundle:
  `/tmp/MudsnoteNoteShareFullTests/Logs/Test/Test-MudsnoteCompanion-2026.07.13_19-19-51-+0800.xcresult`.
- Signed Release build passed and strict code-sign verification succeeded at
  `/tmp/MudsnoteNoteShareDevice/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
- Physical installation was attempted, but CoreDevice still reports MudsPhone as
  `unavailable`; install and launch therefore remain unverified.

## Next

- Install the validated Release artifact when the physical iPhone data connection
  becomes available.
- Continue the next Notes-parity note action, list behavior, or editor gap.
