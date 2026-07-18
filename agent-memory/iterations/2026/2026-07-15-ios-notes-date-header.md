# 2026-07-15 iOS Notes-style edited date header

## Request

Continue the iPhone Apple Notes parity target while preserving Mudsnote's Markdown,
new-note, and quick-note behaviors. Replace the file-browser feel in the note sheet
with a Notes-style reading and editing surface.

## Baseline

- Branch: `main`
- Prior iOS checkpoint: `30663e2`
- The concurrent `scripts/visual_notes_qa.sh` edit was preserved and excluded.

## Changes

- Markdown documents now carry their real filesystem content-modification date
  through creation, load, save, generated-title finalization, and attachment flows.
- The half-sheet and full-screen editor replace the leading raw relative path with
  a quiet, centered, localized edited date.
- Save, recording, and unattached-audio states remain independently visible on the
  trailing edge without displacing the centered date.
- The existing tap-to-edit rendered Markdown, full-screen expansion, autosave, and
  one-row editing toolbar remain unchanged.
- Storage and UI regression coverage now verifies modification-date propagation and
  prevents the raw Markdown filename from returning to the note header.

## Verification

- Generic iOS Simulator build passed.
- Focused storage and UI tests: 3 passed, 0 failed, 0 skipped.
- Visual inspection of the retained UI-test screenshot confirmed the centered date,
  trailing Saved state, rendered Markdown title, and single-row toolbar.
- Final full App and UI suite: 98 passed, 0 failed, 0 skipped.
- Only iPhone 17 Pro / iOS 26.5 simulator
  `BA9A4203-C694-492A-9CD0-6B80E3BC6ED5` was booted, parallel testing was disabled,
  and the simulator was shut down afterward.
- Final result bundle:
  `/tmp/MudsnoteDerivedData/Logs/Test/Test-MudsnoteCompanion-2026.07.15_00-57-02-+0800.xcresult`.
- Signed Release build passed at
  `/tmp/MudsnoteReleaseDerivedData/Build/Products/Release-iphoneos/MudsnoteCompanion.app`.
  Strict code-sign verification passed for both the app and widget extension.
- MudsPhone remained physically visible over USB, but CoreDevice reported it
  unavailable and rejected installation because it could not locate the device.
  Device install and launch therefore remain pending for this build.

## Decisions

- The user-visible note title continues to come from rendered Markdown content;
  the underlying filename remains stable so external links do not break.
- File timestamps, not view-local clocks, are the source of truth for existing
  document dates. Successful saves return the newly observed timestamp.
- Status text stays separate from the centered date so autosave truth remains
  visible without making the note sheet resemble a file inspector.

## Next

- Restore MudsPhone availability, then install and launch the already signed Release
  for the remaining physical-device smoke check.
- Continue the next Notes-parity editor, retrieval, or organization gap.
