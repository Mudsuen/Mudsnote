# 2026-07-13 iOS note audio recording

## Request

Continue the iPhone Apple Notes parity target by closing the gap between quick
audio capture and complete editing of an existing note. Phone-call recording
remains explicitly out of scope.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `f841a0d`
- Pre-existing macOS edits were preserved and excluded.

## Changes

- File-backed Markdown notes now expose an audio recorder in the existing
  single-row horizontal editor toolbar.
- Starting a recording first flushes the current draft, preventing audio from being
  attached against stale note text.
- Stopping writes the recording through the existing coordinated attachment
  transaction and inserts a portable relative `[Audio](Attachments/...m4a)` link.
- Recording and attachment transitions disable Done and interactive sheet dismissal,
  preventing an in-flight recording from being abandoned accidentally.
- If attachment persistence fails, the recording remains available in memory and
  its temporary file remains on disk. The editor offers retry or explicit discard,
  and the toolbar exposes the retained failure state instead of silently losing it.
- All new recovery and status text is localized in English and Simplified Chinese.

## Verification

- Generic iOS Simulator build passed.
- Focused storage coverage verified the exact portable Markdown reference, original
  audio bytes, attachment inventory kind, and note-list attachment metadata.
- Focused iPhone UI automation verified the audio command is present in the complete
  Markdown editor alongside image, file, scan, table, and formatting commands.
- The simulator test deliberately did not activate the host microphone. Real audio
  capture still requires the physical-device microphone smoke.
- Final full App and UI suite: 89 passed, 0 failed, 0 skipped (66 unit/integration
  and 23 UI tests).
- One iPhone 17 Pro / iOS 26.5 simulator was used with parallel testing disabled;
  no iPad or additional simulator was used, and it was shut down afterward.
- Full result bundle:
  `/tmp/MudsnoteNoteAudioFullTests/Logs/Test/Test-MudsnoteCompanion-2026.07.13_19-33-40-+0800.xcresult`.
- Signed Release build passed and strict code-sign verification succeeded at
  `/tmp/MudsnoteNoteAudioDevice/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
- Physical installation was attempted, but CoreDevice still reports MudsPhone as
  `unavailable`; install, launch, microphone permission, and real recording remain
  unverified on the connected iPhone.

## Decisions

- Existing-note voice recording is an ordinary audio attachment, not a call-recording
  subsystem.
- A failed audio attachment remains retained until retry or explicit discard; audio
  failure must not share the generic draft rollback behavior that could lose media.

## Next

- Run the real microphone and audio-playback smoke when MudsPhone becomes available.
- Continue the next Notes-parity retrieval, organization, or conflict-resolution gap.
